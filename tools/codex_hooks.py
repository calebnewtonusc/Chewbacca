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
import subprocess
import sys
import tempfile
import time

import codex_context as context

ROOT = Path(__file__).resolve().parents[1]
EVENTS = ('SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop')


def invoke(command, payload, cwd, timeout=20, env=None):
    # Existing Claude hooks have 5-20 second watchdogs; bound the adapter too.
    result = subprocess.run(command, input=json.dumps(payload), text=True,
                            capture_output=True, cwd=cwd, timeout=timeout, env=env)
    if result.returncode not in (0, 2):
        raise RuntimeError(f'{Path(command[-1]).name} exited {result.returncode}')
    text = result.stdout.strip()
    if not text:
        return result.stderr.strip() if result.returncode == 2 else ''
    try:
        data = json.loads(text)
    except ValueError:
        return text
    output = data.get('hookSpecificOutput', {})
    return output.get('additionalContext') or output.get('systemMessage') or data.get('reason') or ''


def shared_hook(name, payload, cwd):
    installed = Path.home() / '.claude/hooks' / name
    script = installed if installed.is_file() else ROOT / '.claude/hooks' / name
    if not script.is_file():
        return ''
    # Agent-only setup does not install global scanner launchers. Resolve the
    # bundled Python scanners from this checkout in fresh Codex environments.
    env = dict(os.environ, PATH=str(ROOT / 'bin') + os.pathsep + os.environ.get('PATH', ''))
    # Legacy reply lint writes temporary prose. Keep it in a private directory
    # and remove it after the check, including when the subprocess fails.
    if name == 'slop-guard.sh':
        with tempfile.TemporaryDirectory(prefix='chewbacca-codex-') as temp:
            return invoke(['bash', str(script)], payload, cwd,
                          env=dict(env, TMPDIR=temp))
    return invoke(['bash', str(script)], payload, cwd, env=env)


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


def format_file(filename, cwd):
    path = Path(filename)
    if not path.is_file() or path.suffix not in {
        '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.json', '.css', '.scss',
        '.html', '.md', '.yaml', '.yml',
    }:
        return
    if path.name in ('CLAUDE.md', 'CLAUDE-QUICK.md'):
        return
    if re.search(r'^@[~./]', path.read_text(encoding='utf-8'), re.M):
        return
    prettier = next((str(parent / 'node_modules/.bin/prettier')
                     for parent in path.parents
                     if os.access(parent / 'node_modules/.bin/prettier', os.X_OK)), None)
    prettier = prettier or shutil.which('prettier')
    if prettier:
        result = subprocess.run([prettier, '--write', filename, '--log-level', 'silent'],
                                cwd=cwd, capture_output=True, text=True, timeout=20)
        if result.returncode:
            raise RuntimeError('Prettier failed; inspect the edited file before finishing')


def prompt_context():
    """Read a literal context-only printf hook as data; never run arbitrary settings."""
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


def dispatch(payload):
    event = payload.get('hook_event_name')
    cwd = payload.get('cwd') or os.getcwd()
    parts = []
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
        parts.append(shared_hook('coursework-context.sh', payload, cwd))
        parts.append(shared_hook('kit-route.sh', payload, cwd))
    elif event in ('PreToolUse', 'PostToolUse'):
        for filename in changed_paths(payload):
            translated = dict(payload, tool_input={'file_path': filename})
            if event == 'PreToolUse':
                parts.append(shared_hook('env-guard.sh', translated, cwd))
            elif Path(filename).is_file():
                format_file(filename, cwd)
                parts.append(shared_hook('application-gate.sh', translated, cwd))
                parts.append(shared_hook('prose-guard.sh', translated, cwd))
    elif event == 'Stop':
        # Codex provides turn_id; session_id alone suppresses every later turn.
        if not payload.get('stop_hook_active'):
            identity = str(payload.get('session_id', '')) + ':' + str(payload.get('turn_id', ''))
            translated = dict(payload, prompt_id=hashlib.sha256(identity.encode()).hexdigest())
            feedback = shared_hook('slop-guard.sh', translated, cwd)
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
        if event in ('PreToolUse', 'PostToolUse'):
            group['matcher'] = '^apply_patch$|^Write$|^Edit$'
        hooks[event] = kept + [group]
    if target.exists() and not target.with_name(target.name + '.before-chewbacca').exists():
        context.atomic_write(target.with_name(target.name + '.before-chewbacca'), target.read_text())
    context.atomic_write(target, json.dumps(data, indent=2) + '\n')
    return path


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
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
        # Don't include subprocess payloads or private source contents in errors.
        print('Chewbacca hook failed; inspect its configuration and local dependencies.', file=sys.stderr)
        raise SystemExit(1)
