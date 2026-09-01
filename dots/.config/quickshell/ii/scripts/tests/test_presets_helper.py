#!/usr/bin/env python3
"""Tests for preset sanitization and expansion in presets_helper.py."""

import copy
import json
import os
import sys
import tempfile
import unittest

# Add scripts directory to sys.path
SCRIPTS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, SCRIPTS_DIR)

import presets_helper


class TestPresetsHelper(unittest.TestCase):
    def setUp(self):
        self.home_dir = "/home/testuser"

    def test_user_data_removal(self):
        """Teste 1: Confirm that googleDrive and search.aliases are removed, while visual search settings remain."""
        input_data = {
            "search": {
                "enableSystemControls": True,
                "enableMathPreview": True,
                "engineBaseUrl": "https://www.google.com/search?q=",
                "aliases": [
                    {"trigger": "g", "command": "google"},
                    {"trigger": "y", "command": "youtube"}
                ]
            },
            "googleDrive": {
                "enabled": True,
                "backupFolders": ["/home/testuser/Documents"],
                "syncInterval": "1d",
                "lastSyncTime": "2026-08-18T00:00:00Z"
            },
            "bar": {
                "height": 48
            }
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(input_data), self.home_dir)
        self.assertNotIn("googleDrive", sanitized)
        self.assertIn("search", sanitized)
        self.assertNotIn("aliases", sanitized["search"])
        self.assertTrue(sanitized["search"]["enableSystemControls"])
        self.assertTrue(sanitized["search"]["enableMathPreview"])
        self.assertEqual(sanitized["bar"]["height"], 48)

    def test_secrets_removal(self):
        """Teste 2: Verify recursive removal of secrets with varied casing/naming conventions."""
        input_data = {
            "services": {
                "gmail": {
                    "client_id": "test_client_id",
                    "client_secret": "super_secret_client_secret",
                    "refresh_token": "ya29.secret_refresh_token",
                    "accessToken": "secret_access_token"
                },
                "ticktick": {
                    "ticktick_client_id": "tick_id",
                    "ticktick_client_secret": "tick_secret",
                    "ticktick_access_token": "tick_token"
                },
                "ai": {
                    "geminiApiKey": "AIzaSySecretApiKey",
                    "provider": "google",
                    "model": "gemini-2.5-flash"
                }
            },
            "auth": {
                "password": "mypassword123",
                "passwd": "otherpasswd",
                "cookie": "session=abc123xyz"
            },
            "appearance": {
                "palette": "vynx"
            }
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(input_data), self.home_dir)
        # Check that secret keys are removed
        services = sanitized.get("services", {})
        gmail = services.get("gmail", {})
        self.assertNotIn("client_secret", gmail)
        self.assertNotIn("refresh_token", gmail)
        self.assertNotIn("accessToken", gmail)

        ticktick = services.get("ticktick", {})
        self.assertNotIn("ticktick_client_secret", ticktick)
        self.assertNotIn("ticktick_access_token", ticktick)

        ai = services.get("ai", {})
        self.assertNotIn("geminiApiKey", ai)
        self.assertEqual(ai.get("provider"), "google")
        self.assertEqual(ai.get("model"), "gemini-2.5-flash")

        auth = sanitized.get("auth", {})
        self.assertNotIn("password", auth)
        self.assertNotIn("passwd", auth)
        self.assertNotIn("cookie", auth)

        self.assertEqual(sanitized["appearance"]["palette"], "vynx")

    def test_foreign_home_sanitization(self):
        """Teste 3: Confirm foreign /home/otheruser and /var/home/otheruser are transformed to $HOME."""
        input_data = {
            "background": {
                "wallpaperPath": "/home/otheruser/Pictures/wall.jpg"
            },
            "profile": {
                "avatar": "/var/home/silverblueuser/avatar.png"
            },
            "local": {
                "customPath": "/home/testuser/MyFiles/doc.pdf"
            }
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(input_data), self.home_dir)
        self.assertEqual(sanitized["background"]["wallpaperPath"], "$HOME/Pictures/wall.jpg")
        self.assertEqual(sanitized["profile"]["avatar"], "$HOME/avatar.png")
        self.assertEqual(sanitized["local"]["customPath"], "$HOME/MyFiles/doc.pdf")

    def test_known_paths_normalization(self):
        """Teste 4: Normalize Screen Record, Screen Snip, and LocalSend paths."""
        input_data = {
            "screenRecord": {
                "savePath": "/home/otheruser/Videos/CustomRecordings"
            },
            "screenSnip": {
                "savePath": "/home/otheruser/Pictures/Screenshots"
            },
            "localsend": {
                "downloadPath": "/opt/custom/localsend"
            }
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(input_data), self.home_dir)
        self.assertEqual(sanitized["screenRecord"]["savePath"], "$HOME/Videos/CustomRecordings")
        self.assertEqual(sanitized["screenSnip"]["savePath"], "$HOME/Pictures/Screenshots")
        # /opt/custom/localsend is absolute outside /home, so fallback $HOME/Downloads is used
        self.assertEqual(sanitized["localsend"]["downloadPath"], "$HOME/Downloads")

    def test_monitors_reset(self):
        """Teste 5: Ensure machine-specific monitor connector names are reset."""
        input_data = {
            "background": {
                "widgets": {
                    "showOnlyOnSingleMonitor": True,
                    "targetMonitor": "DP-2"
                }
            },
            "bar": {
                "onlyShowOnSingleMonitor": True,
                "singleMonitorName": "HDMI-A-1",
                "screenList": ["DP-1", "DP-2"],
                "floatingNotch": {
                    "onlyShowOnSingleMonitor": True,
                    "singleMonitorName": "eDP-1"
                }
            },
            "interactions": {
                "touchGestures": {
                    "targetMonitor": "DP-3"
                }
            },
            "notifications": {
                "monitor": {
                    "enable": True,
                    "name": "HDMI-A-2"
                }
            }
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(input_data), self.home_dir)
        self.assertFalse(sanitized["background"]["widgets"]["showOnlyOnSingleMonitor"])
        self.assertEqual(sanitized["background"]["widgets"]["targetMonitor"], "")
        self.assertFalse(sanitized["bar"]["onlyShowOnSingleMonitor"])
        self.assertEqual(sanitized["bar"]["singleMonitorName"], "")
        self.assertEqual(sanitized["bar"]["screenList"], [])
        self.assertFalse(sanitized["bar"]["floatingNotch"]["onlyShowOnSingleMonitor"])
        self.assertEqual(sanitized["bar"]["floatingNotch"]["singleMonitorName"], "")
        self.assertEqual(sanitized["interactions"]["touchGestures"]["targetMonitor"], "auto")
        self.assertFalse(sanitized["notifications"]["monitor"]["enable"])
        self.assertEqual(sanitized["notifications"]["monitor"]["name"], "")

    def test_visual_values_preserved(self):
        """Teste 6: Verify legitimate visual styling options are preserved intact."""
        input_data = {
            "appearance": {
                "rounding": {
                    "normal": 17,
                    "large": 23,
                    "windowRounding": 16
                },
                "transparency": {
                    "enable": True,
                    "opacity": 0.85
                },
                "animations": {
                    "enable": True,
                    "speed": 1.0
                }
            },
            "bar": {
                "height": 42,
                "position": "top"
            }
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(input_data), self.home_dir)
        self.assertEqual(sanitized["appearance"]["rounding"]["normal"], 17)
        self.assertEqual(sanitized["appearance"]["rounding"]["windowRounding"], 16)
        self.assertTrue(sanitized["appearance"]["transparency"]["enable"])
        self.assertEqual(sanitized["appearance"]["transparency"]["opacity"], 0.85)
        self.assertEqual(sanitized["bar"]["height"], 42)
        self.assertEqual(sanitized["bar"]["position"], "top")

    def test_dock_blacklist_and_sanitization(self):
        """Teste 7: Verify dock apps and dock widgets are sanitized/blacklisted while visual styles remain."""
        input_data = {
            "dock": {
                "enable": True,
                "dockStyle": "floating",
                "height": 64,
                "dockRadius": 20,
                "enableShapeMask": True,
                "shapeMask": "Circle",
                "enableMagnification": True,
                "magnificationScale": 1.7,
                # Blacklisted dock apps and user items:
                "pinnedApps": ["kitty", "discord", "obsidian"],
                "pinnedFiles": ["/home/testuser/notes.txt"],
                "appGroups": [{"id": "work", "apps": ["slack", "zoom"]}],
                "order": ["pin", "app:kitty", "app:discord", "runningApps", "media", "trash"],
                "ignoredAppRegexes": ["^steam_app_.*"],
                "livePreviewAppId": "org.mozilla.firefox",
                # Blacklisted dock widgets:
                "enableMediaWidget": True,
                "enableWeatherWidget": True,
                "enableSportsWidget": True,
                "enableLivePreviewWidget": True,
                "livePreviewSlots": 3,
                "livePreviewPaintCursor": True,
                "livePreviewCaptureMode": "visible",
                "livePreviewFollowActiveWindow": True,
                "showPhoneButton": True,
                "showTrashButton": True,
                "showOverviewButton": True,
                "showPinButton": True
            }
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(input_data), self.home_dir)
        dock = sanitized.get("dock", {})
        # Visual styling preserved
        self.assertTrue(dock.get("enable"))
        self.assertEqual(dock.get("dockStyle"), "floating")
        self.assertEqual(dock.get("height"), 64)
        self.assertEqual(dock.get("dockRadius"), 20)
        self.assertTrue(dock.get("enableShapeMask"))
        self.assertEqual(dock.get("shapeMask"), "Circle")
        self.assertTrue(dock.get("enableMagnification"))
        self.assertEqual(dock.get("magnificationScale"), 1.7)

        # Blacklisted dock items and widgets stripped
        for key in presets_helper.DOCK_BLACKLIST_KEYS:
            self.assertNotIn(key, dock, f"Key {key} should have been blacklisted and stripped from dock preset")

    def test_dock_preserved_on_expand(self):
        """Teste 8: Verify that expanding a preset preserves the importing user's existing dock configuration."""
        import tempfile
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            preset_file = os.path.join(tmpdir, "MyPreset.json")
            target_config = os.path.join(tmpdir, "config.json")

            # Preset with theme styling but sanitized dock (no pinnedApps or dock widgets)
            preset_data = {
                "appearance": {"palette": "catppuccin"},
                "dock": {
                    "enable": True,
                    "dockStyle": "islands",
                    "height": 50
                }
            }
            with open(preset_file, 'w', encoding='utf-8') as f:
                json.dump(preset_data, f)

            # User B's existing config with their own dock apps and widgets
            user_b_config = {
                "appearance": {"palette": "nord"},
                "dock": {
                    "pinnedApps": ["firefox", "alacritty"],
                    "pinnedFiles": [f"{self.home_dir}/Documents"],
                    "appGroups": [{"id": "dev", "apps": ["code", "nvim"]}],
                    "order": ["pin", "app:firefox", "app:alacritty", "runningApps"],
                    "enableMediaWidget": True,
                    "enableWeatherWidget": False,
                    "showTrashButton": True
                }
            }
            with open(target_config, 'w', encoding='utf-8') as f:
                json.dump(user_b_config, f)

            # Expand preset into target config
            presets_helper.expand(preset_file, target_config, tmpdir, "MyPreset")

            with open(target_config, 'r', encoding='utf-8') as f:
                expanded = json.load(f)

            # Preset visual properties applied
            self.assertEqual(expanded["appearance"]["palette"], "catppuccin")
            self.assertEqual(expanded["dock"]["dockStyle"], "islands")
            self.assertEqual(expanded["dock"]["height"], 50)

            # User B's dock items and widgets preserved
            self.assertEqual(expanded["dock"]["pinnedApps"], ["firefox", "alacritty"])
            self.assertEqual(expanded["dock"]["pinnedFiles"], [f"{self.home_dir}/Documents"])
            self.assertEqual(len(expanded["dock"]["appGroups"]), 1)
            self.assertEqual(expanded["dock"]["order"], ["pin", "app:firefox", "app:alacritty", "runningApps"])
            self.assertTrue(expanded["dock"]["enableMediaWidget"])
            self.assertFalse(expanded["dock"]["enableWeatherWidget"])
            self.assertTrue(expanded["dock"]["showTrashButton"])

    def test_user_profile_and_banner_path_normalization(self):
        """Teste 9: Banner path is normalized to $HOME; profile picture paths are dropped."""
        input_data = {
            "userProfile": {
                "imageStyle": "custom",
                "imagePath": "/home/testuser/Pictures/avatars/user.gif"
            },
            "sidebar": {
                "enableBanner": True,
                "bannerImage": "/var/home/otheruser/Pictures/banner.png",
                "dashboardHeader": {
                    "profileImagePath": "/home/testuser/Pictures/avatars/user.gif"
                }
            }
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(input_data), self.home_dir)
        # The banner ships with the preset, so its path stays portable.
        self.assertEqual(sanitized["sidebar"]["bannerImage"], "$HOME/Pictures/banner.png")
        # The profile picture never does: it is the author's own avatar.
        self.assertNotIn("imagePath", sanitized["userProfile"])
        self.assertNotIn("profileImagePath", sanitized["sidebar"]["dashboardHeader"])
        self.assertEqual(sanitized["userProfile"]["imageStyle"], "custom")

    def test_user_profile_and_banner_fallback_on_expand(self):
        """Teste 10: Verify expand falls back to {name}_profile and {name}_banner when original paths do not exist."""
        import tempfile
        import json

        with tempfile.TemporaryDirectory() as tmpdir:
            preset_file = os.path.join(tmpdir, "NeonTheme.json")
            target_config = os.path.join(tmpdir, "config.json")
            
            # Create companion asset files in preset directory
            profile_asset = os.path.join(tmpdir, "NeonTheme_profile.gif")
            banner_asset = os.path.join(tmpdir, "NeonTheme_banner.jpg")
            wall_asset = os.path.join(tmpdir, "NeonTheme.png")
            open(profile_asset, 'w').close()
            open(banner_asset, 'w').close()
            open(wall_asset, 'w').close()

            # Preset with non-existent foreign paths
            preset_data = {
                "background": {
                    "wallpaperPath": "/home/foreignuser/wallpaper.png"
                },
                "userProfile": {
                    "imageStyle": "custom",
                    "imagePath": "/home/foreignuser/avatar.gif"
                },
                "sidebar": {
                    "enableBanner": True,
                    "bannerImage": "/home/foreignuser/banner.jpg",
                    "dashboardHeader": {
                        "profileImagePath": "/home/foreignuser/avatar.gif"
                    }
                }
            }
            with open(preset_file, 'w', encoding='utf-8') as f:
                json.dump(preset_data, f)

            presets_helper.expand(preset_file, target_config, tmpdir, "NeonTheme")

            with open(target_config, 'r', encoding='utf-8') as f:
                expanded = json.load(f)

            self.assertEqual(expanded["background"]["wallpaperPath"], wall_asset)
            self.assertEqual(expanded["userProfile"]["imagePath"], profile_asset)
            self.assertEqual(expanded["sidebar"]["dashboardHeader"]["profileImagePath"], profile_asset)
            self.assertEqual(expanded["sidebar"]["bannerImage"], banner_asset)


def populate(patterns, value):
    """Build a config with every dotted pattern present, '*' as a literal key."""
    data = {}
    for pattern in patterns:
        concrete = ["w1" if part == "*" else part for part in pattern.split(".")]
        presets_helper.set_path(data, concrete, value)
    return data


class TestPersonalDataStripping(unittest.TestCase):
    """Nothing in PERSONAL_PATHS may survive into a saved preset."""

    def setUp(self):
        self.home_dir = "/home/testuser"

    def test_every_personal_path_is_stripped(self):
        data = populate(presets_helper.PERSONAL_PATHS, "LEAK")
        sanitized = presets_helper.sanitize_data(data, self.home_dir)
        for pattern in presets_helper.PERSONAL_PATHS:
            self.assertEqual(
                presets_helper.find_paths(sanitized, pattern), [],
                f"{pattern} survived sanitization")

    def test_personal_paths_are_all_restored_on_apply(self):
        """Drift guard: anything stripped on save must be handed back on load."""
        for pattern in presets_helper.PERSONAL_PATHS:
            self.assertIn(pattern, presets_helper.LOCAL_ONLY_PATHS)

    def test_bluetooth_macs_and_contacts_do_not_travel(self):
        data = {
            "bluetoothDeviceImages": [{"mac": "34:E3:FB:8D:1C:AC", "image": "device.png"}],
            "soundcore": {"macAddress": "E8:EE:CC:96:31:3A", "enableEqualizer": True},
            "phone": {"contacts": {"favoriteIds": ["86r812-4D472D3B45"], "showAvatars": True}},
        }
        sanitized = presets_helper.sanitize_data(copy.deepcopy(data), self.home_dir)
        self.assertNotIn("bluetoothDeviceImages", sanitized)
        self.assertNotIn("macAddress", sanitized["soundcore"])
        self.assertNotIn("favoriteIds", sanitized["phone"]["contacts"])
        # Styling next to the stripped keys is untouched.
        self.assertTrue(sanitized["soundcore"]["enableEqualizer"])
        self.assertTrue(sanitized["phone"]["contacts"]["showAvatars"])

    def test_desktop_widget_photos_do_not_travel(self):
        data = {"background": {"widgets": {
            "photo_pill_2x1": {"imagePath": "/home/testuser/Downloads/me.png", "radius": 12},
            "showOnlyOnSingleMonitor": True,
        }}}
        sanitized = presets_helper.sanitize_data(copy.deepcopy(data), self.home_dir)
        widget = sanitized["background"]["widgets"]["photo_pill_2x1"]
        self.assertNotIn("imagePath", widget)
        self.assertEqual(widget["radius"], 12)


class TestPresetMerge(unittest.TestCase):
    """merge() layers a preset over a config instead of replacing it."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.preset_path = os.path.join(self.tmp.name, "Theme.json")
        self.config_path = os.path.join(self.tmp.name, "config.json")

    def write(self, path, data):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)

    def merge(self, preset, config, preset_name="Theme"):
        self.write(self.preset_path, preset)
        self.write(self.config_path, config)
        presets_helper.merge(self.preset_path, self.config_path, self.config_path,
                             self.tmp.name, preset_name)
        with open(self.config_path, encoding="utf-8") as f:
            return json.load(f)

    def test_secrets_and_user_data_survive(self):
        """The bug this replaces: applying a shared preset wiped these."""
        merged = self.merge(
            preset={"appearance": {"palette": "catppuccin"}},
            config={
                "ai": {"apiKey": "sk-live-secret"},
                "googleDrive": {"enabled": True, "refreshToken": "ya29.token"},
                "search": {"aliases": [{"trigger": "g", "command": "google"}]},
                "dock": {"pinnedApps": ["firefox"]},
                "appearance": {"palette": "nord"},
            })
        self.assertEqual(merged["ai"]["apiKey"], "sk-live-secret")
        self.assertEqual(merged["googleDrive"]["refreshToken"], "ya29.token")
        self.assertEqual(merged["search"]["aliases"][0]["trigger"], "g")
        self.assertEqual(merged["dock"]["pinnedApps"], ["firefox"])
        self.assertEqual(merged["appearance"]["palette"], "catppuccin")

    def test_preset_values_actually_apply(self):
        """Guard against protecting so much that nothing lands."""
        merged = self.merge(
            preset={"bar": {"height": 48, "cornerStyle": 1}, "dock": {"dockStyle": "islands"}},
            config={"bar": {"height": 32, "cornerStyle": 0, "screenList": ["DP-1"]},
                    "dock": {"dockStyle": "floating", "pinnedApps": ["kitty"]}})
        self.assertEqual(merged["bar"]["height"], 48)
        self.assertEqual(merged["bar"]["cornerStyle"], 1)
        self.assertEqual(merged["dock"]["dockStyle"], "islands")
        self.assertEqual(merged["dock"]["pinnedApps"], ["kitty"])

    def test_every_local_only_path_comes_from_the_importer(self):
        merged = self.merge(
            preset=populate(presets_helper.LOCAL_ONLY_PATHS, "THEIRS"),
            config=populate(presets_helper.LOCAL_ONLY_PATHS, "MINE"))
        for pattern in presets_helper.LOCAL_ONLY_PATHS:
            for path in presets_helper.find_paths(merged, pattern):
                self.assertEqual(presets_helper.get_path(merged, path), "MINE",
                                 f"{pattern} came from the preset")

    def test_local_only_path_absent_locally_is_not_inherited(self):
        """A legacy preset carrying a monitor name must not impose it."""
        merged = self.merge(
            preset={"bar": {"singleMonitorName": "DP-3", "height": 40}},
            config={"bar": {"height": 32}})
        self.assertNotIn("singleMonitorName", merged["bar"])
        self.assertEqual(merged["bar"]["height"], 40)

    def test_preset_config_version_survives(self):
        """migrateRaw() only runs if the file still says which version it is."""
        merged = self.merge(preset={"configVersion": 9, "bar": {"height": 40}},
                            config={"configVersion": 16, "bar": {"height": 32}})
        self.assertEqual(merged["configVersion"], 9)

    def test_wallpaper_falls_back_to_bundled_asset(self):
        bundled = os.path.join(self.tmp.name, "Theme.png")
        open(bundled, "w").close()
        merged = self.merge(
            preset={"background": {"wallpaperPath": "/home/author/gone.png"}},
            config={"background": {"wallpaperPath": "/home/testuser/mine.png"}})
        self.assertEqual(merged["background"]["wallpaperPath"], bundled)

    def test_dead_asset_path_falls_back_to_the_local_one(self):
        """No bundled light-mode wallpaper ships, so the importer keeps theirs."""
        existing = os.path.join(self.tmp.name, "local-light.png")
        open(existing, "w").close()
        merged = self.merge(
            preset={"background": {"lightModeWallpaperPath": "/home/author/gone.png"}},
            config={"background": {"lightModeWallpaperPath": existing}})
        self.assertEqual(merged["background"]["lightModeWallpaperPath"], existing)

    def test_home_placeholder_is_expanded(self):
        merged = self.merge(preset={"apps": {"note": "$HOME/notes"}}, config={})
        self.assertEqual(merged["apps"]["note"], presets_helper.user_home() + "/notes")

    def test_malformed_config_is_refused(self):
        """Never merge onto an empty dict: the broken file is the only truth."""
        self.write(self.preset_path, {"bar": {"height": 40}})
        with open(self.config_path, "w", encoding="utf-8") as f:
            f.write("{ not json")
        with self.assertRaises(ValueError):
            presets_helper.merge(self.preset_path, self.config_path, self.config_path)

    def test_missing_config_is_treated_as_empty(self):
        self.write(self.preset_path, {"bar": {"height": 40}})
        presets_helper.merge(self.preset_path, os.path.join(self.tmp.name, "none.json"),
                             self.config_path)
        with open(self.config_path, encoding="utf-8") as f:
            self.assertEqual(json.load(f)["bar"]["height"], 40)


if __name__ == "__main__":
    unittest.main()

