"""The shared library stays live without overwriting personal skills."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import codex_skills


class SkillInstallTests(unittest.TestCase):
    def test_links_follow_updates_and_preserve_conflicting_skills(self):
        with tempfile.TemporaryDirectory() as temp:
            source, destination = Path(temp) / 'source', Path(temp) / 'destination'
            for name in ('shared', 'personal'):
                (source / name).mkdir(parents=True)
                (source / name / 'SKILL.md').write_text('original')
            (destination / 'personal').mkdir(parents=True)
            (destination / 'personal/SKILL.md').write_text('keep me')
            result = codex_skills.install(source, destination)
            self.assertEqual(result, {'linked': ['shared'], 'conflicts': ['personal']})
            (source / 'shared/SKILL.md').write_text('updated')
            self.assertEqual((destination / 'shared/SKILL.md').read_text(), 'updated')
            self.assertEqual((destination / 'personal/SKILL.md').read_text(), 'keep me')
            self.assertEqual(codex_skills.install(source, destination), result)


if __name__ == '__main__':
    unittest.main()
