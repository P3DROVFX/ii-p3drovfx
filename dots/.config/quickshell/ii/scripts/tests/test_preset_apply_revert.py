#!/usr/bin/env python3
"""Apply/revert against isolated config files; color scripts and notifications are stubs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]


class TestPresetApplyRevert(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='preset-revert-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.user_dir = self.root / 'home'
        self.presets = self.user_dir / '.config/illogical-impulse/presets'
        self.presets.mkdir(parents=True)
        self.config = self.presets.parent / 'config.json'
        self.original = b'{\n  "configVersion": 16, "bar": {"height": 40}, "localOnly": "keep me"\n}\n'
        self.config.write_bytes(self.original)
        self.active = self.presets / '.active'
        self.state = self.root / 'state'
        self.backups = self.state / 'ii/preset-backups'
        self.scripts = self.root / 'scripts'
        self.scripts.mkdir()
        for name in ['presets.sh', 'presets_helper.py', 'preset_store.py']:
            shutil.copyfile(SCRIPTS / name, self.scripts / name)
        script = self.scripts / 'presets.sh'
        script.write_text(script.read_text().replace('/tmp/presets_switchwall.log', str(self.root / 'colors.log')))
        for name in ['colors/switchwall.sh', 'colors/switchwall_vynx.sh', 'notify-send']:
            target = self.scripts / name
            target.parent.mkdir(exist_ok=True)
            target.write_text('#!/bin/sh\nexit 0\n')
            target.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.user_dir), XDG_STATE_HOME=str(self.state),
                        PATH=str(self.scripts) + os.pathsep + os.environ['PATH'])
        for name, height in [('Blue', 64), ('Green', 72)]:
            (self.presets / (name + '.json')).write_text(json.dumps({'configVersion': 16, 'bar': {'height': height}}))

    def command(self, *args):
        return subprocess.run(['bash', str(self.scripts / 'presets.sh'), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def assert_success(self, *args):
        result = self.command(*args)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_apply_backs_up_exact_config_then_revert_restores_it(self):
        self.assert_success('load', 'Blue')
        snapshots = list(self.backups.glob('*-config.json'))
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0].read_bytes(), self.original)
        self.assertEqual(json.loads(self.config.read_bytes())['bar']['height'], 64)
        self.assertEqual(self.active.read_text().strip(), 'Blue')
        self.assert_success('revert')
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertFalse(self.active.exists())
        self.assertFalse(list(self.backups.glob('*-config.json')))

    def test_two_applies_restore_previous_preset_and_then_original_config(self):
        self.assert_success('load', 'Blue')
        blue = self.config.read_bytes()
        self.assert_success('load', 'Green')
        self.assert_success('revert')
        self.assertEqual(self.config.read_bytes(), blue)
        self.assertTrue(self.active.exists(), 'Revert forgot which preset it restored')
        self.assertEqual(self.active.read_text().strip(), 'Blue')
        self.assert_success('revert')
        self.assertEqual(self.config.read_bytes(), self.original)

    def test_restore_replaces_config_atomically_and_backups_are_private(self):
        self.assert_success('load', 'Blue')
        snapshot = next(self.backups.glob('*-config.json'))
        self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
        # Holding the old descriptor proves restore is a rename, not truncation.
        with self.config.open('rb') as old_config:
            installed_bytes = old_config.read()
            old_inode = os.fstat(old_config.fileno()).st_ino
            self.assert_success('revert')
            self.assertNotEqual(self.config.stat().st_ino, old_inode)
            old_config.seek(0)
            self.assertEqual(old_config.read(), installed_bytes)

    def test_backup_failure_prevents_apply(self):
        self.backups.parent.mkdir(parents=True)
        self.backups.write_text('directory is unavailable')
        result = self.command('load', 'Blue')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertFalse(self.active.exists())

    def test_failed_apply_does_not_create_an_undo_step(self):
        (self.presets / 'Broken.json').write_text('[1, 2, 3]')
        self.assertNotEqual(self.command('load', 'Broken').returncode, 0)
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertFalse(list(self.backups.glob('*-config.json')))

    def test_invalid_backup_is_not_restored_or_consumed(self):
        self.assert_success('load', 'Blue')
        installed = self.config.read_bytes()
        snapshot = next(self.backups.glob('*-config.json'))
        snapshot.write_text('{incomplete')
        self.assertNotEqual(self.command('revert').returncode, 0)
        self.assertEqual(self.config.read_bytes(), installed)
        self.assertTrue(snapshot.exists())
        self.assertEqual(self.active.read_text().strip(), 'Blue')

    def test_failed_restore_keeps_snapshot_and_current_config(self):
        self.assert_success('load', 'Blue')
        installed = self.config.read_bytes()
        snapshot = next(self.backups.glob('*-config.json'))
        blocker = self.scripts / 'mv'
        blocker.write_text('#!/bin/sh\nexit 1\n')
        blocker.chmod(0o755)
        self.assertNotEqual(self.command('revert').returncode, 0)
        self.assertEqual(self.config.read_bytes(), installed)
        self.assertEqual(snapshot.read_bytes(), self.original)
        self.assertFalse(list(self.config.parent.glob('config.json.tmp.*')))

    def test_links_reports_revert_availability(self):
        self.assert_success('load', 'Blue')
        result = subprocess.run(['python3', str(self.scripts / 'preset_store.py'), 'links'],
                                env=self.env, capture_output=True, text=True, timeout=5)
        self.assertTrue(json.loads(result.stdout).get('canRevert'))


if __name__ == '__main__':
    unittest.main()
