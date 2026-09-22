"""Only requested MCP entries move; credentials stay out of reports."""
import json
from pathlib import Path
import sys
import tempfile
import tomllib
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import codex_integrations


class IntegrationTests(unittest.TestCase):
    def test_selected_servers_preserve_existing_settings_and_auth(self):
        with tempfile.TemporaryDirectory() as temp:
            source, target = Path(temp) / 'source.json', Path(temp) / 'config.toml'
            source.write_text(json.dumps({'mcpServers': {
                'remote': {'type': 'http', 'url': 'https://example.invalid/mcp',
                           'headers': {'x-api-key': 'PRIVATE_CANARY'}},
                'local': {'command': 'node', 'args': ['server.js'], 'env': {'TOKEN': 'PRIVATE_CANARY'}},
                'unused': {'command': 'never-run'}}}))
            target.write_text('approval_policy = "never"\n[mcp_servers.personal]\ncommand = "keep"\n')
            result = codex_integrations.import_servers(source, target, ['remote', 'local'], Path('/working/node'))
            self.assertNotIn('PRIVATE_CANARY', json.dumps(result))
            parsed = tomllib.loads(target.read_text())
            self.assertEqual(parsed['approval_policy'], 'never')
            self.assertEqual(parsed['mcp_servers']['personal']['command'], 'keep')
            self.assertEqual(parsed['mcp_servers']['remote']['http_headers']['x-api-key'], 'PRIVATE_CANARY')
            self.assertEqual(parsed['mcp_servers']['local']['command'], '/working/node')
            self.assertNotIn('unused', parsed['mcp_servers'])
            before = target.read_text()
            codex_integrations.import_servers(source, target, ['remote', 'local'])
            self.assertEqual(target.read_text(), before)


if __name__ == '__main__':
    unittest.main()
