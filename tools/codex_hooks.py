#!/usr/bin/env python3
"""Chewbacca lifecycle hooks for Codex. No credential reads or automatic pushes."""
import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

import codex_context as context
from work_ledger import context_for

ROOT = Path(__file__).resolve().parents[1]
EVENTS = ('SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop')


from shared_checks import HookDenied, invoke, shared_hook, format_file


def changed_paths(payload):
    """Codex puts an entire patch in command, not Claude's file_path field."""
    tool_input = payload.get('tool_input') or {}
    if not isinstance(tool_input, dict):
        return []
    paths = []
    if isinstance(tool_input.get('file_path'), str):
        paths.append(tool_input['file_path'])
    if payload.get('tool_name') == 'apply_patch':
        command = tool_input.get('command', '')
        if isinstance(command, str):
            paths.extend(re.findall(r'^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$', command, re.M))
    cwd = Path(payload.get('cwd') or os.getcwd())
    return list(dict.fromkeys(str((cwd / path).resolve()) for path in paths))


def proposed_writes(payload):
    """Translate added patch lines for guards that inspect proposed content."""
    tool_input = payload.get('tool_input') or {}
    if not isinstance(tool_input, dict):
        return {}
    if payload.get('tool_name') != 'apply_patch':
        path = tool_input.get('file_path')
        cwd = Path(payload.get('cwd') or os.getcwd())
        return {str((cwd / path).resolve()): tool_input} if path else {}
    result, filename, added = {}, None, []
    cwd = Path(payload.get('cwd') or os.getcwd())
    for line in str(tool_input.get('command', '')).splitlines() + ['*** End Patch']:
        if line.startswith('*** Move to: ') and filename is not None:
            filename = line[len('*** Move to: '):]
            continue
        if line.startswith('*** '):
            if filename is not None:
                result[str((cwd / filename).resolve())] = {'new_string': '\n'.join(added)}
                filename, added = None, []
            match = re.match(r'^\*\*\* (?:Add File|Update File): (.+)$', line)
            if match:
                filename = match.group(1)
        elif filename is not None and line.startswith('+'):
            added.append(line[1:])
    return result


def prompt_context():
    """Read a literal context-only printf hook as data; never run arbitrary settings."""
    shared = Path(os.environ.get('CHEWBACCA_HOME', str(Path.home() / '.chewbacca'))).expanduser() / 'preferences.json'
    if shared.is_file():
        return str(json.loads(shared.read_text()).get('prompt_context', ''))
    settings = Path.home() / '.claude/settings.json'
    if not settings.is_file():
        return ''
    settings_data = json.loads(settings.read_text())
    parts = []
    for group in settings_data.get('hooks', {}).get('UserPromptSubmit', []):
        for handler in group.get('hooks', []):
            try:
                tokens = shlex.split(handler.get('command', ''))
                if len(tokens) != 3 or tokens[:2] != ['printf', '%s']:
                    continue
                output = json.loads(tokens[2]).get('hookSpecificOutput', {})
                if output.get('hookEventName') == 'UserPromptSubmit':
                    parts.append(output.get('additionalContext', ''))
            except ValueError:
                continue
    return '\n'.join(parts)


def git_notice(cwd):
    root = subprocess.run(['git', 'rev-parse', '--show-toplevel'], cwd=cwd,
                          capture_output=True, text=True, timeout=10)
    if root.returncode or Path(root.stdout.strip()) == Path.home():
        return ''
    status = subprocess.run(['git', 'status', '--porcelain'], cwd=cwd,
                            capture_output=True, text=True, timeout=10)
    if status.stdout.strip():
        return ('Working tree has uncommitted changes. Report the changes and checks accurately; '
                'preserve unrelated work. Commit or publish only within the user-authorized scope.')
    return ''


def turn_state(payload):
    """Keep the latest request and receipts privately; serialize parallel tools."""
    sid = payload.get('session_id')
    if not sid:
        return {}
    directory = context.codex_home() / 'chewbacca-turn-state'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / 'receipts.sqlite'
    with contextlib.closing(sqlite3.connect(path, timeout=10)) as db, db:
        path.chmod(0o600)
        db.execute('CREATE TABLE IF NOT EXISTS turns (session TEXT PRIMARY KEY, state TEXT NOT NULL)')
        db.execute('BEGIN IMMEDIATE')
        row = db.execute('SELECT state FROM turns WHERE session = ?', (sid,)).fetchone()
        state = json.loads(row[0]) if row else {}
        event = payload.get('hook_event_name')
        if event == 'UserPromptSubmit':
            state = {'prompt': payload.get('prompt', ''), 'prompt_started_at': time.time(), 'sequence': 0,
                     'last_write': 0, 'last_success': -1,
                     'review_required': state.get('review_required', []),
                     'review_before': state.get('review_before', {}),
                     'review_inflight': state.get('review_inflight', {})}
        elif event == 'PreToolUse':
            key = review_tool_key(payload)
            state.setdefault('review_before', {}).setdefault(key, review_snapshots(payload))
            inflight = state.setdefault('review_inflight', {})
            inflight[key] = inflight.get(key, 0) + 1
        elif event == 'PostToolUse':
            sequence = state.get('sequence', 0) + 1
            state['sequence'] = sequence
            response = payload.get('tool_response') or {}
            if payload.get('tool_name') in ('apply_patch', 'Write', 'Edit'):
                state['last_write'] = sequence
            elif isinstance(response, dict) and response.get('exit_code') == 0:
                state['last_success'] = sequence
            required = set(state.get('review_required', []))
            key = review_tool_key(payload)
            before = state.setdefault('review_before', {}).get(key, {})
            for repo, digest in review_snapshots(payload).items():
                if repo not in before and not digest.startswith('unavailable:'):
                    import review_gate
                    if review_gate.repo_root(repo) is not None:
                        try:
                            if review_gate.scope_path(repo).exists():
                                review_gate.current_scope(repo)
                            else:
                                review_gate.capture_scope(repo, base='UNBORN')
                        except (OSError, ValueError, subprocess.TimeoutExpired):
                            try:
                                review_gate.mark_scope_failure(repo)
                            except OSError:
                                pass
                            required.add(repo)
                if digest.startswith('unavailable:') or repo not in before or digest != before[repo]:
                    required.add(repo)
            state['review_required'] = sorted(required)
            finish_review_observation(state, key)
        elif event == 'ReviewScopeFailed':
            state['review_required'] = sorted(set(state.get('review_required', [])) | {payload['review_repo']})
        elif event == 'ToolDenied':
            finish_review_observation(state, review_tool_key(payload))
        else:
            return state
        db.execute('INSERT OR REPLACE INTO turns VALUES (?, ?)', (sid, json.dumps(state)))
        return state



def finish_review_observation(state, key):
    inflight = state.setdefault('review_inflight', {})
    remaining = inflight.get(key, 1) - 1
    if remaining > 0:
        inflight[key] = remaining
    else:
        inflight.pop(key, None)
        state.setdefault('review_before', {}).pop(key, None)


def review_tool_key(payload):
    identity = payload.get('tool_use_id') or payload.get('tool_call_id')
    if identity:
        return str(identity)
    raw = json.dumps([payload.get('tool_name'), payload.get('tool_input')], sort_keys=True)
    return hashlib.sha256(raw.encode()).hexdigest()


def review_snapshots(payload):
    """Observe candidate repositories without interpreting shell programs."""
    import review_gate
    tool_input = payload.get('tool_input') or {}
    if not isinstance(tool_input, dict):
        tool_input = {}
    cwd = Path(payload.get('cwd') or os.getcwd())
    candidates = [cwd]
    workdir = tool_input.get('workdir')
    if isinstance(workdir, str):
        candidates.append(cwd / workdir)
    candidates.extend(Path(path).parent for path in changed_paths(payload))
    # Literal paths cover shell edits and outer orchestration payloads. Dynamic
    # programs can construct other paths; this is observation, not a sandbox.
    for value in tool_input.values():
        if not isinstance(value, str):
            continue
        for match in re.finditer(r'''(["'])(/[^\n"']{1,4096})\1''', value):
            candidates.append(Path(match.group(2)))
        try:
            candidates.extend(Path(token) for token in shlex.split(value)
                              if token.startswith('/') and len(token) <= 4096)
        except ValueError:
            pass
    snapshots = {}
    for candidate in candidates:
        while not candidate.is_dir() and candidate != candidate.parent:
            candidate = candidate.parent
        try:
            result = subprocess.run(['git', '-C', str(candidate), 'rev-parse', '--show-toplevel'],
                                    capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            snapshots[str(candidate.resolve())] = 'unavailable: repository discovery failed'
            continue
        if result.returncode:
            continue
        repo = Path(result.stdout.strip()).resolve()
        if repo == Path.home() or str(repo) in snapshots:
            continue
        try:
            snapshots[str(repo)] = review_gate.snapshot(repo)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            snapshots[str(repo)] = 'unavailable: repository snapshot failed'
    return snapshots


def review_stop(state):
    import review_gate
    failures = []
    for repo in state.get('review_required', []):
        valid, reason = review_gate.check(Path(repo))
        if not valid:
            command = shlex.join([str(ROOT / 'bin/review-gate'), 'run', '--repo', repo])
            failures.append(f'{repo}: {reason}. Run {command}, resolve findings, and rerun '
                            'relevant tests and review. Do this yourself; do not ask the user '
                            'to review the diff. If review cannot run, report it as incomplete.')
    return '\n'.join(failures)


def dispatch(payload):
    try:
        return dispatch_event(payload)
    except HookDenied as error:
        denied = dict(payload, hook_event_name='ToolDenied')
        turn_state(denied)
        reason = str(error)
        try:
            shared_hook('write-log.sh', denied, payload.get('cwd') or os.getcwd())
        except (HookDenied, OSError, RuntimeError, subprocess.TimeoutExpired):
            reason += ' Write observation cleanup was unavailable; the operation remains denied.'
        return {'hookSpecificOutput': {'hookEventName': 'PreToolUse',
                'permissionDecision': 'deny', 'permissionDecisionReason': reason}}


def dispatch_event(payload):
    try:
        return dispatch_event_body(payload)
    finally:
        if payload.get('hook_event_name') == 'PostToolUse':
            turn_state(payload)


def dispatch_event_body(payload):
    event = payload.get('hook_event_name')
    cwd = payload.get('cwd') or os.getcwd()
    state = turn_state(dict(payload, hook_event_name='Stop')) if event == 'PostToolUse' else turn_state(payload)
    parts = []
    if event == 'PreToolUse':
        import review_gate
        for repo in state.get('review_before', {}).get(review_tool_key(payload), {}):
            if review_gate.repo_root(repo) is not None:
                try:
                    review_gate.capture_scope(repo)
                except (OSError, ValueError, subprocess.TimeoutExpired):
                    try:
                        review_gate.mark_scope_failure(repo)
                    except OSError:
                        pass
                    state = turn_state(dict(payload, hook_event_name='ReviewScopeFailed', review_repo=repo))
                    parts.append('Review scope could not be frozen. Review remains required; repair the scope with an explicit base before claiming completion.')
    if event in ('SessionStart', 'UserPromptSubmit'):
        parts.append(context_for(cwd))
    if event == 'SessionStart':
        root = context.brain_root(context.codex_home())
        with contextlib.redirect_stdout(io.StringIO()) as output:
            print('Chewbacca startup briefing loaded by a native Codex hook. '
                  'Use this briefing without running the fallback reader again.\n')
            print((ROOT / 'instructions/agent-neutral.md').read_text())
            context.read_sources(root)
        parts.append(output.getvalue())
        checker = root / 'brain-check.sh'
        if checker.is_file():
            try:
                parts.append(invoke(['bash', str(checker)], payload, cwd))
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                parts.append('Second-brain health check failed; the startup briefing above still loaded.')
    elif event == 'UserPromptSubmit':
        parts.append(prompt_context())
        # These are independent local reads. Preserve their order in the
        # output without paying for each subprocess sequentially.
        with ThreadPoolExecutor(max_workers=4) as pool:
            parts.extend(pool.map(lambda name: shared_hook(name, payload, cwd),
                                  ('coursework-context.sh', 'kit-route.sh',
                                   'skill-route.sh', 'method-guard.sh')))
    elif event in ('PreToolUse', 'PostToolUse'):
        if event == 'PreToolUse':
            if payload.get('session_id'):
                parts.append(shared_hook('write-log.sh', payload, cwd))
            tool = payload.get('tool_name', '')
            if tool in ('Bash', 'exec_command', 'functions.exec', 'functions.exec_command'):
                translated = dict(payload, tool_name='Bash')
                parts.append(shared_hook('submit-guard.sh', translated, cwd))
                parts.append(shared_hook('browser-ux-guard.sh', translated, cwd))
        elif payload.get('session_id'):
            parts.append(shared_hook('write-log.sh', payload, cwd))
        writes = proposed_writes(payload) if event == 'PreToolUse' else {}
        for filename in changed_paths(payload):
            translated = dict(payload, tool_input={'file_path': filename})
            if event == 'PreToolUse':
                parts.append(shared_hook('env-guard.sh', translated, cwd))
                if filename in writes:
                    translated = dict(payload, tool_name='Edit', tool_input={
                        **writes[filename], 'file_path': filename})
                    parts.append(shared_hook('fusion-guard.sh', translated, cwd))
                    parts.append(shared_hook('ux-guard.sh', translated, cwd))
            elif Path(filename).is_file():
                format_file(filename, cwd)
                optional = Path.home() / '.claude/hooks/application-gate.sh'
                if optional.is_file():
                    parts.append(invoke(['bash', str(optional)], translated, cwd))
                parts.append(shared_hook('prose-guard.sh', translated, cwd))
    elif event == 'Stop':
        review_feedback = review_stop(state)
        if review_feedback:
            import review_gate
            if not review_gate.allows_incomplete(state, payload):
                command = shlex.join([str(ROOT / 'bin/review-gate'), 'report-incomplete',
                                      '--session-id', str(payload.get('session_id', '')),
                                      '--turn-id', str(payload.get('turn_id', ''))])
                report = ''
                try:
                    incomplete = review_gate.prepare_incomplete(
                        state.get('review_required', []), payload.get('session_id'),
                        payload.get('turn_id'), state.get('sequence', 0))
                    report = '\nIf further repair cannot proceed, the exact incomplete report is:\n' + incomplete['report']
                except (OSError, ValueError, TypeError, KeyError, subprocess.TimeoutExpired):
                    pass
                return {'decision': 'block', 'reason': review_feedback +
                        '\nAfter a recorded failed review, ' + command +
                        ' prepares an incomplete report. This never clears review obligations.' + report}
        # Codex provides turn_id; session_id alone suppresses every later turn.
        if not payload.get('stop_hook_active'):
            identity = str(payload.get('session_id', '')) + ':' + str(payload.get('turn_id', ''))
            translated = dict(payload, prompt_id=hashlib.sha256(identity.encode()).hexdigest(),
                              user_message=payload.get('user_message', state.get('prompt', '')),
                              agent='codex', durable_since=state.get('prompt_started_at'), codex_evidence_after_write=(
                                  state.get('last_success', -1) > state.get('last_write', 0)))
            feedback = '\n\n'.join(filter(None, (
                shared_hook(name, translated, cwd)
                for name in ('slop-guard.sh', 'handoff-guard.sh',
                             'durable-guard.sh', 'vibe-guard.sh'))))
            if feedback:
                return {'decision': 'block', 'reason': feedback}
        notice = git_notice(cwd)
        return {'systemMessage': notice} if notice else {}
    text = '\n\n'.join(part for part in parts if part)
    return {'hookSpecificOutput': {'hookEventName': event, 'additionalContext': text}} if text else {}


def install(home):
    path = home / 'hooks.json'
    target = path.resolve() if path.is_symlink() else path
    data = json.loads(target.read_text()) if target.exists() else {}
    hooks = data.setdefault('hooks', {})
    command = shlex.join([sys.executable, str(Path(__file__).resolve()), 'run'])
    for event in EVENTS:
        groups = hooks.setdefault(event, [])
        # Own only the adapter, including an older installation path.
        kept = []
        for group in groups:
            handlers = [h for h in group.get('hooks', [])
                        if 'codex_hooks.py' not in h.get('command', '')]
            if handlers:
                kept.append(dict(group, hooks=handlers))
        handler = {'type': 'command', 'command': command, 'timeout': 60,
                   'statusMessage': 'Chewbacca: ' + event}
        if event != 'Stop':
            # Personal briefings can exceed the default 2.5k context limit.
            # Leave room for the shared guidance and memory index.
            handler['additionalContextLimit'] = 32000 if event == 'SessionStart' else 5000
        group = {'hooks': [handler]}
        hooks[event] = kept + [group]
    if target.exists() and not target.with_name(target.name + '.before-chewbacca').exists():
        context.atomic_write(target.with_name(target.name + '.before-chewbacca'), target.read_text())
    context.atomic_write(target, json.dumps(data, indent=2) + '\n')
    return path


def registered_for_event(home, event):
    """A cached native handler must respect removal from the live configuration."""
    config = home / 'hooks.json'
    if not config.exists():
        return False
    data = json.loads(config.read_text())
    for group in data.get('hooks', {}).get(event, []):
        for handler in group.get('hooks', []):
            if handler.get('type') != 'command':
                continue
            try:
                words = shlex.split(handler.get('command', ''))
            except ValueError:
                continue
            if any(Path(word).resolve() == Path(__file__).resolve() for word in words):
                return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('install', 'run'))
    args = parser.parse_args()
    if args.command == 'install':
        print(f'Installed Chewbacca hooks in {install(context.codex_home())}')
        print('Review and trust these hook definitions in Codex before they can run.')
        return
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict) or payload.get('hook_event_name') not in EVENTS:
        raise ValueError('unsupported hook event')
    if not registered_for_event(context.codex_home(), payload['hook_event_name']):
        return
    output = dispatch(payload)
    # Only event metadata is persisted; never prompts, replies, paths, or the briefing.
    audit = context.codex_home() / 'chewbacca-hook-status.json'
    context.atomic_write(audit, json.dumps({'event': payload['hook_event_name'],
                         'time': time.time(), 'status': 'ok'}) + '\n')
    if output:
        print(json.dumps(output))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, sqlite3.Error, subprocess.TimeoutExpired):
        # Don't include subprocess payloads or private source contents in errors.
        print('Chewbacca hook failed; inspect its configuration and local dependencies.', file=sys.stderr)
        raise SystemExit(1)
