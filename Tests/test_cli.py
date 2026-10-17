"""Exercise the actual bds entry point using fake hardware tools."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

FIRST = 'AAAAAAAA-0000-0000-0000-000000000001'
SECOND = 'AAAAAAAA-0000-0000-0000-000000000002'

class CLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='BDMenu CLI ')
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.cfg = self.root / 'profiles'
        self.cfg.mkdir()
        self.log = self.root / 'arguments'
        self.env = dict(os.environ, BDMENU_CONFIG_DIR=str(self.cfg), BDMENU_TEST_LOG=str(self.log))
        shutil.copyfile(Path(__file__).parents[1] / 'cli/bds', self.root / 'bds')
        self.tool('displaypower', f"printf '1\\t1\\t1\\t{FIRST}\\n2\\t0\\t1\\t{SECOND}\\n'")
        fixture = f'''Persistent screen id: {FIRST}
Resolution: 1920x1080
Hertz: N/A
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Enabled: true
Persistent screen id: {SECOND}
Resolution: 1200x1920
Hertz: 60
Color Depth: 8
Scaling: off
Origin: (-1200,240)
Rotation: 90
Enabled: true
'''
        self.tool('displayplacer', 'if [ "$1" = list ]; then\ncat <<\'DATA\'\n' + fixture + 'DATA\nelse\nprintf \'%s\\n\' "$@" > "$BDMENU_TEST_LOG"\nfi')
        self.tool('displayctl', 'printf 50')

    def tearDown(self):
        self.temp.cleanup()

    def tool(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def run_cli(self, *args):
        return subprocess.run(['bash', str(self.root / 'bds'), *args], env=self.env,
                              capture_output=True, text=True, timeout=5)

    def test_main_preserves_relative_coordinates_rotation_and_unknown_hertz(self):
        result = self.run_cli('main', 'external')
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.log.read_text().splitlines()
        self.assertEqual(len(lines), 2)
        self.assertIn('origin:(1200,-240)', lines[0])
        self.assertNotIn('hz:N/A', lines[0])
        self.assertIn('origin:(0,0)', lines[1])
        self.assertIn('degree:90', lines[1])

    def test_restore_rejects_trailing_shell_command(self):
        marker = self.root / 'unexpected'
        (self.cfg / 'bad.profile').write_text(f'displayplacer "id:{FIRST} enabled:true"; touch "{marker}"\n')
        result = self.run_cli('restore', 'bad')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())
        self.assertFalse(self.log.exists())

    def test_restore_does_not_execute_command_substitution(self):
        marker = self.root / 'unexpected'
        argument = f'id:{FIRST} enabled:true res:$(touch {marker})'
        (self.cfg / 'literal.profile').write_text(f'displayplacer "{argument}"\n')
        result = self.run_cli('restore', 'literal')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(self.log.read_text().strip(), argument)

    def test_rejects_profile_path_traversal(self):
        result = self.run_cli('save', '../outside')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'outside.profile').exists())

if __name__ == '__main__':
    unittest.main()
