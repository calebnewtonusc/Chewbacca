#!/usr/bin/env python3
"""Runtime-independent execution of the shared checks and formatter."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

class HookDenied(Exception):
    """A shared guard refused the pending operation."""


def invoke(command, payload, cwd, timeout=20, env=None):
    # Existing Claude hooks have 5-20 second watchdogs; bound the adapter too.
    result = subprocess.run(command, input=json.dumps(payload), text=True,
                            capture_output=True, cwd=cwd, timeout=timeout, env=env)
    if result.returncode not in (0, 2):
        raise RuntimeError(f'{Path(command[-1]).name} exited {result.returncode}')
    if result.returncode == 2 and payload.get('hook_event_name') == 'PreToolUse':
        raise HookDenied(result.stderr.strip() or 'Shared guard blocked this operation.')
    text = result.stdout.strip()
    if not text:
        return result.stderr.strip() if result.returncode == 2 else ''
    try:
        data = json.loads(text)
    except ValueError:
        return text
    output = data.get('hookSpecificOutput', {})
    if payload.get('hook_event_name') == 'PreToolUse' and (
            output.get('permissionDecision') == 'deny' or data.get('decision') == 'block'):
        raise HookDenied(output.get('permissionDecisionReason') or data.get('reason')
                         or 'Shared guard blocked this operation.')
    return output.get('additionalContext') or output.get('systemMessage') or data.get('reason') or ''


def shared_hook(name, payload, cwd):
    script = ROOT / '.claude/hooks' / name
    if not script.is_file():
        raise RuntimeError('Shared check is missing: ' + name)
    # Agent-only setup does not install global scanner launchers. Resolve the
    # bundled Python scanners from this checkout in fresh Codex environments.
    env = dict(os.environ, PATH=str(ROOT / 'bin') + os.pathsep + os.environ.get('PATH', ''),
               CHEWBACCA_SKILLS_DIR=str(ROOT / 'skills'))
    # Legacy reply lint writes temporary prose. Keep it in a private directory
    # and remove it after the check, including when the subprocess fails.
    if name == 'slop-guard.sh':
        with tempfile.TemporaryDirectory(prefix='chewbacca-codex-') as temp:
            return invoke(['bash', str(script)], payload, cwd,
                          env=dict(env, TMPDIR=temp))
    return invoke(['bash', str(script)], payload, cwd, env=env)


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
        # A broken Homebrew node existed on PATH after llhttp was upgraded.
        # Probe execution and use a working runtime for the formatter's shebang.
        candidates = [shutil.which('node')]
        candidates.extend(str(p) for p in sorted((Path.home() / '.nvm/versions/node').glob('*/bin/node'), reverse=True))
        node = None
        for candidate in candidates:
            if not candidate:
                continue
            try:
                probe = subprocess.run([candidate, '--version'], capture_output=True, timeout=5)
                if probe.returncode == 0:
                    node = candidate
                    break
            except (OSError, subprocess.TimeoutExpired):
                continue
        if node is None:
            raise RuntimeError('Prettier is installed but no working Node runtime was found')
        env = dict(os.environ, PATH=str(Path(node).parent) + os.pathsep + os.environ.get('PATH', ''))
        result = subprocess.run([prettier, '--write', filename, '--log-level', 'silent'],
                                cwd=cwd, capture_output=True, text=True, timeout=20, env=env)
        if result.returncode:
            raise RuntimeError('Prettier failed; inspect the edited file before finishing')



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('run', 'format'))
    parser.add_argument('script', nargs='?')
    args = parser.parse_args()
    payload = json.load(sys.stdin)
    if args.command == 'format':
        filename = (payload.get('tool_input') or {}).get('file_path')
        if filename:
            format_file(filename, payload.get('cwd') or os.getcwd())
        return 0
    script = ROOT / '.claude/hooks' / str(args.script)
    if script.parent != ROOT / '.claude/hooks' or not script.is_file():
        parser.error('unknown shared check')
    env = dict(os.environ, PATH=str(ROOT / 'bin') + os.pathsep + os.environ.get('PATH', ''),
               CHEWBACCA_SKILLS_DIR=str(ROOT / 'skills'))
    result = subprocess.run(['bash', str(script)], input=json.dumps(payload), text=True, env=env)
    return result.returncode

if __name__ == '__main__':
    raise SystemExit(main())
