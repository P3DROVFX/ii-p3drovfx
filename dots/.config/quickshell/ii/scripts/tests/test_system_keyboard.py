"""Read-only XKB tests using the system's actual rules and libxkbcommon."""
import copy
import unittest
from unittest.mock import patch

from scripts.typing import system_keyboard as keyboard


class SystemKeyboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.device = {"name": "at-translated-set-2-keyboard", "main": True,
                      "layout": "us, br", "variant": "intl,", "model": "",
                      "active_layout_index": 1, "active_keymap": "Portuguese (Brazil)"}
        cls.board = keyboard.read_device(cls.device)

    def labels(self, name, board=None):
        board = board or self.board
        index = next(i for i, key in enumerate(board["keys"]) if key["name"] == name)
        return [layer[index]["label"] for layer in board["layers"]]

    def test_active_second_layout_keeps_empty_variant(self):
        self.assertEqual(self.board["layout"], "br")
        self.assertEqual(self.board["variant"], "")
        self.assertEqual(self.board["preset"], "abnt2")
        self.assertEqual(self.labels("AC10")[:2], ["ç", "Ç"])
        self.assertEqual(self.labels("AD11")[:2], ["´", "`"])
        self.assertEqual(self.labels("AC11")[:2], ["~", "^"])

    def test_abnt_extra_keys_and_altgr_symbols(self):
        self.assertEqual(self.labels("LSGT")[:2], ["\\", "|"])
        self.assertEqual(self.labels("AB11"), ["/", "?", "°", "¿"])
        self.assertEqual(self.labels("AD12")[:3], ["[", "{", "ª"])
        self.assertEqual(self.labels("BKSL")[:3], ["]", "}", "º"])
        self.assertEqual(self.labels("RALT"), ["AltGr"] * 4)

    def test_name_fallback_for_older_hyprland(self):
        device = copy.copy(self.device)
        del device["active_layout_index"]
        self.assertEqual(keyboard.read_device(device)["layout"], "br")

    def test_active_english_group_is_not_relabelled_brazilian(self):
        device = {**self.device, "active_layout_index": 0,
                  "active_keymap": "English (US, intl., with dead keys)"}
        board = keyboard.read_device(device)
        self.assertEqual(board["layout"], "us")
        self.assertEqual(board["variant"], "intl")
        self.assertEqual(self.labels("AC10", board)[0], ";")
        self.assertNotEqual(board["deviceUid"], self.board["deviceUid"])

    def test_custom_corne_map_not_mistaken_for_global_us(self):
        custom = {**self.device, "name": "foostan-corne-v4-keyboard",
                  "active_layout_index": 0, "active_keymap": "Corne II - US International + PT-BR"}
        with self.assertRaises(ValueError):
            keyboard.read_device(custom)
        detected = keyboard.detect({"keyboards": [custom, {**self.device, "main": False}]})
        self.assertEqual(detected["layout"], "br")

    def test_primary_device_wins_over_auxiliary_devices(self):
        aux = {**self.device, "name": "video-bus"}
        notebook = {**self.device, "main": False}
        virtual = {**self.device, "name": "keyd-virtual-keyboard"}
        detected = keyboard.detect({"keyboards": [aux, notebook, virtual]})
        self.assertEqual(detected["deviceName"], "keyd-virtual-keyboard")

    def test_repeat_detection_uses_same_identity_across_device_names(self):
        virtual = keyboard.read_device({**self.device, "name": "keyd-virtual-keyboard"})
        self.assertEqual(virtual["deviceUid"], self.board["deviceUid"])

    def test_manual_abnt_preset_does_not_need_hyprland(self):
        with patch.object(keyboard.subprocess, "run", side_effect=AssertionError("no compositor access")):
            board = keyboard.read_device({"layout": "br", "model": "abnt2"}, manual=True)
        self.assertEqual(board["source"], "manual")
        self.assertEqual(board["deviceUid"], "")
        self.assertEqual(self.labels("AC10", board)[0], "ç")

    def test_geometry_and_layers_match_without_overlapping_keys(self):
        board = self.board
        keys = board["keys"]
        self.assertEqual(len({(k["row"], k["col"]) for k in keys}), len(keys))
        for key in keys:
            self.assertLessEqual(key["x"] + key["w"], board["width"])
            self.assertLessEqual(key["y"] + key["h"], board["height"])
        for i, left in enumerate(keys):
            for right in keys[i + 1:]:
                overlap = (left["x"] < right["x"] + right["w"] and right["x"] < left["x"] + left["w"]
                           and left["y"] < right["y"] + right["h"] and right["y"] < left["y"] + left["h"])
                self.assertFalse(overlap, (left["name"], right["name"]))
        for layer in board["layers"]:
            self.assertEqual(len(layer), len(keys))
            self.assertTrue(all(isinstance(k["resolvedCode"], int) for k in layer))

    def test_missing_layout_fails_without_fabricating_us(self):
        for devices in ({}, {"keyboards": []}, {"keyboards": [{"name": "keyboard"}]}):
            with self.assertRaises(ValueError):
                keyboard.detect(devices)


if __name__ == "__main__":
    unittest.main()
