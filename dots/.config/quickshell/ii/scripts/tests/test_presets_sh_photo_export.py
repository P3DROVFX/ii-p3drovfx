#!/usr/bin/env python3
"""Integration tests for presets.sh export and import with desktop photo widgets."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile

SCRIPTS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class TestPresetsShPhotoExport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = self.tmp.name
        self.stubs = os.path.join(self.home, "bin")
        os.makedirs(self.stubs, exist_ok=True)
        # Create a stub notify-send
        stub = os.path.join(self.stubs, "notify-send")
        with open(stub, "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(stub, 0o755)

        # Create pictures directory and a sample photo
        self.pics = os.path.join(self.home, "Pictures")
        os.makedirs(self.pics, exist_ok=True)
        self.cat_img = os.path.join(self.pics, "cat.png")
        with open(self.cat_img, "wb") as f:
            f.write(b"SAMPLE_PHOTO_CONTENT_12345")

        # Create config.json in ~/.config/illogical-impulse/config.json
        self.cfg_dir = os.path.join(self.home, ".config", "illogical-impulse")
        os.makedirs(self.cfg_dir, exist_ok=True)
        self.config_path = os.path.join(self.cfg_dir, "config.json")
        initial_config = {
            "configVersion": 1,
            "background": {
                "wallpaperPath": self.cat_img,
                "activeWidgets": [
                    {
                        "id": "pw_test",
                        "widgetId": "photo_plain_2x1",
                        "imagePath": self.cat_img,
                        "x": 200,
                        "y": 300
                    }
                ],
                "widgets": {
                    "photo": {
                        "imagePath": ""
                    }
                }
            }
        }
        with open(self.config_path, "w", encoding="utf-8") as f:
            json.dump(initial_config, f)

    def run_cmd(self, *args, env_home=None):
        env = dict(os.environ)
        env["HOME"] = env_home or self.home
        env["PATH"] = self.stubs + os.pathsep + env.get("PATH", "")
        cmd = ["bash", os.path.join(SCRIPTS_DIR, "presets.sh")] + list(args)
        return subprocess.run(cmd, capture_output=True, text=True, env=env)

    def test_presets_sh_save_export_import_flow(self):
        # 1. Save preset
        res = self.run_cmd("save", "CatTheme")
        self.assertEqual(res.returncode, 0, f"save failed: {res.stderr}")

        presets_dir = os.path.join(self.home, ".config", "illogical-impulse", "presets")
        bundled_json = os.path.join(presets_dir, "CatTheme.json")
        bundled_photo = os.path.join(presets_dir, "CatTheme_photo0.png")
        self.assertTrue(os.path.isfile(bundled_json), "CatTheme.json should exist")
        self.assertTrue(os.path.isfile(bundled_photo), "CatTheme_photo0.png should exist")
        with open(bundled_photo, "rb") as f:
            self.assertEqual(f.read(), b"SAMPLE_PHOTO_CONTENT_12345")

        # 2. Export preset to a zip file
        export_zip = os.path.join(self.home, "CatTheme_export.zip")
        res = self.run_cmd("export", "CatTheme", export_zip)
        self.assertEqual(res.returncode, 0, f"export failed: {res.stderr}")
        self.assertTrue(os.path.isfile(export_zip), "Exported zip should exist")

        # Verify zip contents: config.json and photo0.png must be inside
        with zipfile.ZipFile(export_zip, "r") as z:
            names = z.namelist()
            self.assertIn("config.json", names)
            self.assertIn("photo0.png", names)
            self.assertEqual(z.read("photo0.png"), b"SAMPLE_PHOTO_CONTENT_12345")

        # 3. Simulate another user importing and loading the preset
        other_home = os.path.join(self.home, "other_user")
        other_cfg_dir = os.path.join(other_home, ".config", "illogical-impulse")
        os.makedirs(other_cfg_dir, exist_ok=True)
        other_config = os.path.join(other_cfg_dir, "config.json")
        with open(other_config, "w", encoding="utf-8") as f:
            json.dump({"configVersion": 1, "background": {"activeWidgets": []}}, f)

        res = self.run_cmd("import", export_zip, env_home=other_home)
        self.assertEqual(res.returncode, 0, f"import failed: {res.stderr}")

        # The imported preset should be in other user's presets directory
        other_presets_dir = os.path.join(other_cfg_dir, "presets")
        imported_preset_name = "CatTheme_export"
        imported_json = os.path.join(other_presets_dir, f"{imported_preset_name}.json")
        imported_photo = os.path.join(other_presets_dir, f"{imported_preset_name}_photo0.png")
        self.assertTrue(os.path.isfile(imported_json), "Imported json should exist")
        self.assertTrue(os.path.isfile(imported_photo), "Imported photo0 should exist")

        # 4. Load the preset on other user's machine
        res = self.run_cmd("load", imported_preset_name, env_home=other_home)
        self.assertEqual(res.returncode, 0, f"load failed: {res.stderr}")

        with open(other_config, "r", encoding="utf-8") as f:
            loaded_cfg = json.load(f)

        loaded_widgets = loaded_cfg["background"]["activeWidgets"]
        self.assertEqual(len(loaded_widgets), 1)
        self.assertEqual(loaded_widgets[0]["widgetId"], "photo_plain_2x1")
        self.assertEqual(loaded_widgets[0]["imagePath"], imported_photo)
        self.assertTrue(os.path.isfile(loaded_widgets[0]["imagePath"]))
        with open(loaded_widgets[0]["imagePath"], "rb") as f:
            self.assertEqual(f.read(), b"SAMPLE_PHOTO_CONTENT_12345")

    def test_presets_sh_localsend_and_phone_toggles_blacklist(self):
        """Verify that presets.sh save, export, import, and load blacklist localsend
        and phone config toggles and preserve the recipient's settings."""
        # 1. Author config with non-default localsend and phone settings
        with open(self.config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        cfg["localsend"] = {
            "autoStart": False,
            "showNotifications": False,
            "preferPopupOverNotification": False,
            "downloadPath": "/opt/custom/downloads",
        }
        cfg["phone"] = {
            "kdeconnectEnabled": False,
            "remoteCommands": False,
            "mirrorNotificationsToDesktop": False,
            "showPeripheralCards": False,
            "scrcpy": {
                "useWireless": True,
                "bitRate": "12M",
            }
        }
        with open(self.config_path, "w", encoding="utf-8") as f:
            json.dump(cfg, f)

        # 2. Save and export preset
        res = self.run_cmd("save", "ServiceTestTheme")
        self.assertEqual(res.returncode, 0, f"save failed: {res.stderr}")

        export_zip = os.path.join(self.home, "ServiceTestTheme.zip")
        res = self.run_cmd("export", "ServiceTestTheme", export_zip)
        self.assertEqual(res.returncode, 0, f"export failed: {res.stderr}")

        # In exported zip config.json, verify toggles are stripped
        with zipfile.ZipFile(export_zip, "r") as z:
            exported_cfg = json.loads(z.read("config.json").decode("utf-8"))
        self.assertNotIn("autoStart", exported_cfg.get("localsend", {}))
        self.assertNotIn("showNotifications", exported_cfg.get("localsend", {}))
        self.assertNotIn("preferPopupOverNotification", exported_cfg.get("localsend", {}))
        self.assertNotIn("kdeconnectEnabled", exported_cfg.get("phone", {}))
        self.assertNotIn("remoteCommands", exported_cfg.get("phone", {}))
        self.assertNotIn("mirrorNotificationsToDesktop", exported_cfg.get("phone", {}))
        self.assertNotIn("showPeripheralCards", exported_cfg.get("phone", {}))
        self.assertNotIn("useWireless", exported_cfg.get("phone", {}).get("scrcpy", {}))
        # Non-blacklisted settings still travel
        self.assertEqual(exported_cfg["phone"]["scrcpy"]["bitRate"], "12M")

        # 3. Recipient has enabled settings
        other_home = os.path.join(self.home, "other_user2")
        other_cfg_dir = os.path.join(other_home, ".config", "illogical-impulse")
        os.makedirs(other_cfg_dir, exist_ok=True)
        other_config = os.path.join(other_cfg_dir, "config.json")
        recipient_initial = {
            "configVersion": 1,
            "localsend": {
                "autoStart": True,
                "showNotifications": True,
                "preferPopupOverNotification": True,
                "downloadPath": "/home/other_user2/Downloads",
            },
            "phone": {
                "kdeconnectEnabled": True,
                "remoteCommands": True,
                "mirrorNotificationsToDesktop": True,
                "showPeripheralCards": True,
                "scrcpy": {
                    "useWireless": False,
                    "bitRate": "8M",
                }
            }
        }
        with open(other_config, "w", encoding="utf-8") as f:
            json.dump(recipient_initial, f)

        res = self.run_cmd("import", export_zip, env_home=other_home)
        self.assertEqual(res.returncode, 0, f"import failed: {res.stderr}")

        res = self.run_cmd("load", "ServiceTestTheme", env_home=other_home)
        self.assertEqual(res.returncode, 0, f"load failed: {res.stderr}")

        # Verify recipient's settings were preserved!
        with open(other_config, "r", encoding="utf-8") as f:
            recipient_after = json.load(f)

        self.assertTrue(recipient_after["localsend"]["autoStart"])
        self.assertTrue(recipient_after["localsend"]["showNotifications"])
        self.assertTrue(recipient_after["localsend"]["preferPopupOverNotification"])
        self.assertEqual(recipient_after["localsend"]["downloadPath"], "/home/other_user2/Downloads")

        self.assertTrue(recipient_after["phone"]["kdeconnectEnabled"])
        self.assertTrue(recipient_after["phone"]["remoteCommands"])
        self.assertTrue(recipient_after["phone"]["mirrorNotificationsToDesktop"])
        self.assertTrue(recipient_after["phone"]["showPeripheralCards"])
        self.assertFalse(recipient_after["phone"]["scrcpy"]["useWireless"])
        # Theme styling did apply
        self.assertEqual(recipient_after["phone"]["scrcpy"]["bitRate"], "12M")


if __name__ == "__main__":
    unittest.main()

