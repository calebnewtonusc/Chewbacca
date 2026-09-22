#!/usr/bin/env python3
"""Import explicitly selected existing MCP connections without printing secrets."""
import argparse
import json
from pathlib import Path
import tomllib


def import_servers(source, target, names, node=None):
    servers = json.loads(source.read_text()).get('mcpServers', {})
    original = target.read_text() if target.exists() else ''
    existing = tomllib.loads(original).get('mcp_servers', {})
    sections, added, skipped = [], [], []
    for name in names:
        if name in existing:
            skipped.append(name)
            continue
        config = servers[name]
        fields = {}
        if config.get('type') == 'http':
            fields['url'] = config['url']
            nested = {'http_headers': config.get('headers', {})}
        else:
            command = config['command']
            fields['command'] = str(node) if node and command == 'node' else command
            fields['args'] = config.get('args', [])
            nested = {'env': config.get('env', {})}
        heading = 'mcp_servers.' + json.dumps(name)
        sections.append('\n[' + heading + ']')
        sections.extend(key + ' = ' + json.dumps(value) for key, value in fields.items())
        for group, values in nested.items():
            if values:
                sections.append('[' + heading + '.' + group + ']')
                sections.extend(json.dumps(key) + ' = ' + json.dumps(value)
                                for key, value in values.items())
        added.append(name)
    if sections:
        updated = original.rstrip() + '\n' + '\n'.join(sections) + '\n'
        tomllib.loads(updated)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(updated)
        target.chmod(0o600)
    return {'added': added, 'preserved': skipped}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', action='append', required=True)
    parser.add_argument('--source', type=Path, default=Path.home() / '.claude.json')
    parser.add_argument('--target', type=Path, default=Path.home() / '.codex/config.toml')
    parser.add_argument('--node', type=Path)
    args = parser.parse_args()
    print(json.dumps(import_servers(args.source, args.target, args.server, args.node)))


if __name__ == '__main__':
    main()
