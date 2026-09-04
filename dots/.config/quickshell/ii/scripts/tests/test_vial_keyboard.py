"""Offline contract for the Vial keyboard reader.

Everything here runs without a keyboard: the parsing, the geometry and the
keycode naming are pure functions on purpose, so a board that is not on this
desk can still be covered.
"""

import importlib.util
import math
from pathlib import Path
import unittest

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "typing" / "vial_keyboard.py"
SPEC = importlib.util.spec_from_file_location("vial_keyboard", SCRIPT_PATH)
vial = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(vial)


class KeycodeTests(unittest.TestCase):
    def test_letters_carry_the_character_they_type(self):
        self.assertEqual(vial.describe(0x0004), ("a", "a"))
        self.assertEqual(vial.describe(0x001D), ("z", "z"))

    def test_digits_wrap_zero_round_to_the_end(self):
        self.assertEqual(vial.describe(0x001E), ("1", "1"))
        self.assertEqual(vial.describe(0x0027), ("0", "0"))

    def test_space_types_a_space_so_the_test_can_point_at_it(self):
        self.assertEqual(vial.describe(0x002C), ("Space", " "))

    def test_function_rows_are_named_not_numbered_from_zero(self):
        self.assertEqual(vial.describe(0x003A)[0], "F1")
        self.assertEqual(vial.describe(0x0045)[0], "F12")
        self.assertEqual(vial.describe(0x0068)[0], "F13")

    def test_shifted_symbols_read_as_the_symbol_they_produce(self):
        # LSFT(KC_1) is what a symbol layer actually stores for "!".
        self.assertEqual(vial.describe(0x021E), ("!", "!"))
        self.assertEqual(vial.describe(0x0235), ("~", "~"))

    def test_shifted_letters_are_capitals(self):
        self.assertEqual(vial.describe(0x0204), ("A", "A"))

    def test_other_modified_keys_name_the_modifier(self):
        label, char = vial.describe(0x0104 | 0x0000)  # Ctrl + A
        self.assertEqual(label, "Ctrl\na")
        self.assertEqual(char, "")

    def test_layer_switches_are_named_with_their_layer(self):
        self.assertEqual(vial.describe(0x5221)[0], "MO(1)")
        self.assertEqual(vial.describe(0x5202)[0], "TO(2)")
        self.assertEqual(vial.describe(0x5263)[0], "TG(3)")

    def test_tri_layer_keys_read_the_way_vial_shows_them(self):
        self.assertEqual(vial.describe(0x7C77)[0], "Fn1\n(Fn3)")
        self.assertEqual(vial.describe(0x7C78)[0], "Fn2\n(Fn3)")

    def test_nothing_and_transparent_are_blank_rather_than_invented(self):
        self.assertEqual(vial.describe(vial.KC_NO), ("", ""))
        self.assertEqual(vial.describe(vial.KC_TRANSPARENT), ("", ""))

    def test_an_unknown_keycode_keeps_its_hex_instead_of_lying(self):
        self.assertEqual(vial.describe(0x6001)[0], "0x6001")


class KleGeometryTests(unittest.TestCase):
    def test_a_plain_row_advances_one_unit_per_key(self):
        keys = vial.parse_kle([["0,0", "0,1", "0,2"]], 0, [])
        self.assertEqual([k["x"] for k in keys], [0.0, 1.0, 2.0])
        self.assertEqual([k["y"] for k in keys], [0.0, 0.0, 0.0])

    def test_rows_stack_downwards(self):
        keys = vial.parse_kle([["0,0"], ["1,0"]], 0, [])
        self.assertEqual([k["y"] for k in keys], [0.0, 1.0])

    def test_offsets_accumulate_and_width_applies_once(self):
        keys = vial.parse_kle([[{"x": 2, "w": 2}, "0,0", "0,1"]], 0, [])
        self.assertEqual((keys[0]["x"], keys[0]["w"]), (2.0, 2.0))
        # The next key starts past the wide one and is back to a single unit.
        self.assertEqual((keys[1]["x"], keys[1]["w"]), (4.0, 1.0))

    def test_a_rotation_origin_moves_the_cursor_to_itself(self):
        keys = vial.parse_kle([[{"r": 30, "rx": 5, "ry": 9, "x": -1}, "3,5"]], 0, [])
        self.assertEqual(keys[0]["r"], 30.0)
        self.assertEqual((keys[0]["rx"], keys[0]["ry"]), (5.0, 9.0))
        self.assertEqual((keys[0]["x"], keys[0]["y"]), (4.0, 9.0))

    def test_a_row_returns_to_the_rotation_origin_not_to_zero(self):
        keys = vial.parse_kle([[{"rx": 4}, "0,0"], ["1,0"]], 0, [])
        self.assertEqual(keys[1]["x"], 4.0)

    def test_matrix_position_comes_from_the_first_label(self):
        keys = vial.parse_kle([["3,5"]], 0, [])
        self.assertEqual((keys[0]["row"], keys[0]["col"]), (3, 5))

    def test_an_encoder_is_flagged_by_the_tenth_label(self):
        keys = vial.parse_kle([["0,0\n\n\n\n\n\n\n\n\ne"]], 0, [])
        self.assertTrue(keys[0]["encoder"])


class LayoutOptionTests(unittest.TestCase):
    def test_a_key_without_an_option_label_is_always_shown(self):
        self.assertEqual(len(vial.parse_kle([["0,0"]], 0, [3])), 1)

    def test_only_the_chosen_variant_of_an_option_survives(self):
        rows = [["0,0\n\n\n0,0", "0,1\n\n\n0,1"]]
        chosen = vial.parse_kle(rows, 0, [3])
        self.assertEqual([(k["row"], k["col"]) for k in chosen], [(0, 0)])

    def test_a_different_choice_selects_the_other_variant(self):
        rows = [["0,0\n\n\n0,0", "0,1\n\n\n0,1"]]
        chosen = vial.parse_kle(rows, 1, [3])
        self.assertEqual([(k["row"], k["col"]) for k in chosen], [(0, 1)])

    def test_groups_are_packed_low_bits_first(self):
        # Two 3-choice groups take two bits each; 0b0100 is group 1 on choice 1.
        self.assertEqual(vial.layout_choice(0b0100, 0, [3, 3]), 0)
        self.assertEqual(vial.layout_choice(0b0100, 1, [3, 3]), 1)

    def test_group_sizes_come_from_the_definition_labels(self):
        definition = {"layouts": {"labels": [["Left EX1", "Key", "Encoder", "None"], "Split space"]}}
        self.assertEqual(vial.layout_groups(definition), [3, 2])


class BoundsTests(unittest.TestCase):
    def test_the_board_is_slid_flush_against_the_origin(self):
        keys = vial.parse_kle([[{"y": 1, "x": 2}, "0,0"]], 0, [])
        width, height = vial.normalise(keys)
        self.assertEqual((keys[0]["x"], keys[0]["y"]), (0.0, 0.0))
        self.assertEqual((width, height), (1.0, 1.0))

    def test_a_rotated_key_is_measured_by_the_corners_it_is_drawn_on(self):
        # A 1u key turned 45 degrees about its own top-left sweeps wider than 1u.
        keys = vial.parse_kle([[{"r": 45, "rx": 0, "ry": 0}, "0,0"]], 0, [])
        _, _, width, height = vial.bounds(keys)
        self.assertAlmostEqual(width, math.sqrt(2), places=4)
        self.assertAlmostEqual(height, math.sqrt(2), places=4)

    def test_normalising_leaves_the_angle_each_key_is_drawn_at_alone(self):
        keys = vial.parse_kle([[{"r": 30, "rx": 5, "ry": 9, "x": -1}, "0,0"]], 0, [])
        before = (keys[0]["rx"] - keys[0]["x"], keys[0]["ry"] - keys[0]["y"])
        vial.normalise(keys)
        after = (keys[0]["rx"] - keys[0]["x"], keys[0]["ry"] - keys[0]["y"])
        self.assertEqual(before, after)
        self.assertEqual(keys[0]["r"], 30.0)

    def test_an_empty_board_has_no_size_rather_than_failing(self):
        self.assertEqual(vial.bounds([]), (0.0, 0.0, 0.0, 0.0))


class LayerTests(unittest.TestCase):
    ROWS, COLS = 1, 2

    def _codes(self, *layers):
        flat = []
        for layer in layers:
            flat.extend(layer)
        return flat

    def test_each_layer_is_labelled_from_its_own_keycodes(self):
        keys = [{"row": 0, "col": 0}, {"row": 0, "col": 1}]
        codes = self._codes([0x0004, 0x0005], [0x0006, 0x0007])
        layers = vial.build_layers(codes, keys, self.ROWS, self.COLS, 2)
        self.assertEqual([e["label"] for e in layers[0]], ["a", "b"])
        self.assertEqual([e["label"] for e in layers[1]], ["c", "d"])

    def test_a_transparent_key_shows_what_will_actually_fire(self):
        keys = [{"row": 0, "col": 0}, {"row": 0, "col": 1}]
        codes = self._codes([0x0004, 0x0005], [vial.KC_TRANSPARENT, 0x0007])
        layers = vial.build_layers(codes, keys, self.ROWS, self.COLS, 2)
        self.assertEqual(layers[1][0]["label"], "a")
        self.assertTrue(layers[1][0]["inherited"])
        self.assertFalse(layers[1][1]["inherited"])

    def test_transparency_falls_through_more_than_one_layer(self):
        keys = [{"row": 0, "col": 0}]
        codes = self._codes([0x0004, vial.KC_NO],
                            [vial.KC_TRANSPARENT, vial.KC_NO],
                            [vial.KC_TRANSPARENT, vial.KC_NO])
        layers = vial.build_layers(codes, keys, self.ROWS, self.COLS, 3)
        self.assertEqual(layers[2][0]["label"], "a")
        self.assertTrue(layers[2][0]["inherited"])

    def test_an_unmapped_key_stays_blank_and_is_not_called_inherited(self):
        keys = [{"row": 0, "col": 0}]
        codes = self._codes([vial.KC_NO, vial.KC_NO], [vial.KC_NO, vial.KC_NO])
        layers = vial.build_layers(codes, keys, self.ROWS, self.COLS, 2)
        self.assertEqual(layers[1][0]["label"], "")
        self.assertFalse(layers[1][0]["inherited"])


if __name__ == "__main__":
    unittest.main()
