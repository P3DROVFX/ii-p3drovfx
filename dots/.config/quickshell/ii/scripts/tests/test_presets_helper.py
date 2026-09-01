#!/usr/bin/env python3
"""Tests for preset sanitization and expansion in presets_helper.py."""

import copy
import os
import sys
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
        """Teste 9: Verify userProfile and sidebar banner paths are normalized to $HOME."""
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
        self.assertEqual(sanitized["userProfile"]["imagePath"], "$HOME/Pictures/avatars/user.gif")
        self.assertEqual(sanitized["sidebar"]["bannerImage"], "$HOME/Pictures/banner.png")
        self.assertEqual(sanitized["sidebar"]["dashboardHeader"]["profileImagePath"], "$HOME/Pictures/avatars/user.gif")

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


if __name__ == "__main__":
    unittest.main()

