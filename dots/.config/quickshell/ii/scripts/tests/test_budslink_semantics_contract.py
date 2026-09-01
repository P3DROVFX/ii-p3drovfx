#!/usr/bin/env python3
"""
Unit tests for BudsLink semantics, normalization, and provider router contracts.
Validates BudsLinkSemantics.js logic and EarbudsControlService routing rules.
"""

import json
import os
import subprocess
import unittest

SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
SEMANTICS_JS = os.path.join(ROOT_DIR, "services", "budslink", "BudsLinkSemantics.js")


def run_js_eval(expr: str):
    """Evaluates JavaScript code importing BudsLinkSemantics.js using gjs."""
    # Convert .pragma library file to module-compatible evaluation
    with open(SEMANTICS_JS, "r", encoding="utf-8") as f:
        code = f.read()

    # Remove .pragma line for gjs evaluation
    code = code.replace(".pragma library", "")

    test_script = f"""
{code}

const __result = ({expr});
print(JSON.stringify(__result));
"""
    proc = subprocess.run(
        ["gjs", "-c", test_script],
        capture_output=True,
        text=True,
        check=True
    )
    return json.loads(proc.stdout.strip())


class TestBudsLinkSemanticsContract(unittest.TestCase):
    """Test suite verifying BudsLinkSemantics.js normalization functions."""

    def test_normalize_mac(self):
        """Test canonical MAC address normalization."""
        self.assertEqual(run_js_eval("normalizeMac('40:35:E6:31:8B:AC')"), "40:35:E6:31:8B:AC")
        self.assertEqual(run_js_eval("normalizeMac('40-35-e6-31-8b-ac')"), "40:35:E6:31:8B:AC")
        self.assertEqual(run_js_eval("normalizeMac('40_35_e6_31_8b_ac')"), "40:35:E6:31:8B:AC")
        self.assertEqual(run_js_eval("normalizeMac('invalid-mac')"), "")
        self.assertEqual(run_js_eval("normalizeMac(null)"), "")

    def test_extract_mac_from_path(self):
        """Test MAC address extraction from D-Bus object paths."""
        path = "/io/github/maniacx/BudsLink/dev_40_35_E6_31_8B_AC"
        self.assertEqual(run_js_eval(f"extractMacFromPath('{path}')"), "40:35:E6:31:8B:AC")
        self.assertEqual(run_js_eval("extractMacFromPath('/invalid/path')"), "")

    def test_battery_normalization_three_components(self):
        """Test normalization of Left, Right, and Case battery telemetry."""
        state = {
            "battery1Level": 85,
            "battery1Status": "discharging",
            "battery2Level": 90,
            "battery2Status": "discharging",
            "battery3Level": 100,
            "battery3Status": "charging",
            "computedBatteryLevel": 87
        }
        config = {
            "battery1Icon": "bbm-left-symbolic",
            "battery2Icon": "bbm-right-symbolic",
            "battery3Icon": "bbm-case-symbolic"
        }
        expr = f"normalizeBattery({json.dumps(state)}, {json.dumps(config)})"
        res = run_js_eval(expr)

        self.assertTrue(res["available"])
        self.assertEqual(res["aggregate"], 87)
        self.assertIsNotNone(res["left"])
        self.assertEqual(res["left"]["level"], 85)
        self.assertFalse(res["left"]["charging"])
        self.assertIsNotNone(res["right"])
        self.assertEqual(res["right"]["level"], 90)
        self.assertIsNotNone(res["case"])
        self.assertEqual(res["case"]["level"], 100)
        self.assertTrue(res["case"]["charging"])

    def test_battery_case_disconnected_omission(self):
        """Test that disconnected Case battery is marked unavailable and not reported as 0%."""
        state = {
            "battery1Level": 80,
            "battery1Status": "discharging",
            "battery2Level": 80,
            "battery2Status": "discharging",
            "battery3Level": None,
            "battery3Status": "disconnected"
        }
        config = {
            "battery1Icon": "bbm-left-symbolic",
            "battery2Icon": "bbm-right-symbolic",
            "battery3Icon": "bbm-case-symbolic",
            "battery3ShowOnDisconnect": False
        }
        expr = f"normalizeBattery({json.dumps(state)}, {json.dumps(config)})"
        res = run_js_eval(expr)

        self.assertTrue(res["available"])
        self.assertEqual(res["aggregate"], 80)
        self.assertIsNotNone(res["case"])
        self.assertFalse(res["case"]["available"])

    def test_noise_controls_normalization(self):
        """Test normalization of 3-state and 4-state noise controls."""
        state = {
            "toggle1Visible": True,
            "toggle1State": 2
        }
        config = {
            "toggle1Title": "Noise Control",
            "toggle1Button1Icon": "bbm-anc-off-symbolic",
            "toggle1Button1Name": "Off",
            "toggle1Button2Icon": "bbm-transperancy-symbolic",
            "toggle1Button2Name": "Ambient Sound",
            "toggle1Button3Icon": "bbm-adaptive-symbolic",
            "toggle1Button3Name": "Adaptive",
            "toggle1Button4Icon": "bbm-anc-on-symbolic",
            "toggle1Button4Name": "Active Noise Cancelling"
        }
        expr = f"normalizeNoiseControls({json.dumps(state)}, {json.dumps(config)})"
        res = run_js_eval(expr)

        self.assertTrue(res["available"])
        self.assertEqual(len(res["modes"]), 4)
        self.assertEqual(res["modes"][0]["key"], "off")
        self.assertEqual(res["modes"][1]["key"], "transparency")
        self.assertEqual(res["modes"][2]["key"], "adaptive")
        self.assertEqual(res["modes"][3]["key"], "anc")
        self.assertEqual(res["currentMode"], "transparency")
        self.assertTrue(res["hasAdaptive"])
        self.assertTrue(res["hasTransparency"])
        self.assertTrue(res["hasAnc"])
        self.assertEqual(res["modeKeyToButtonIndex"]["adaptive"], 3)
        self.assertEqual(res["modeKeyToButtonIndex"]["anc"], 4)

    def test_conversation_awareness_normalization(self):
        """Test normalization of Conversation Awareness toggle."""
        state = {
            "toggle2Visible": True,
            "toggle2State": 2
        }
        config = {
            "toggle2Title": "Conversation Awareness",
            "toggle2Button1Icon": "bbm-ca-off-symbolic",
            "toggle2Button1Name": "Off",
            "toggle2Button2Icon": "bbm-ca-on-symbolic",
            "toggle2Button2Name": "On"
        }
        expr = f"normalizeConversationAwareness({json.dumps(state)}, {json.dumps(config)})"
        res = run_js_eval(expr)

        self.assertTrue(res["available"])
        self.assertTrue(res["enabled"])
        self.assertEqual(res["onButtonIndex"], 2)
        self.assertEqual(res["offButtonIndex"], 1)

    def test_dynamic_option_boxes_normalization(self):
        """Test normalization of slider, checkbox, and radio option boxes."""
        state = {
            "optionsBoxVisible": True,
            "box1SliderValue": 65,
            "box1SliderIsDragging": 0,
            "box2CheckButton1State": 1,
            "box2CheckButton2State": 0,
            "box3RadioButtonState": 2
        }
        config = {
            "optionsBox1": "slider",
            "box1SliderTitle": "Ambient Sound Volume",
            "optionsBox2": "check",
            "box2CheckButton1": "Touch controls",
            "box2CheckButton2": "In-ear detection",
            "optionsBox3": "radio",
            "box3RadioTitle": "Equalizer"
        }
        expr = f"normalizeOptionBoxes({json.dumps(state)}, {json.dumps(config)})"
        res = run_js_eval(expr)

        self.assertEqual(len(res), 3)
        # Box 1: Slider
        self.assertTrue(res[0]["hasSlider"])
        self.assertEqual(res[0]["slider"]["title"], "Ambient Sound Volume")
        self.assertEqual(res[0]["slider"]["value"], 65)

        # Box 2: Check buttons
        self.assertTrue(res[1]["hasCheck"])
        self.assertEqual(len(res[1]["checkButtons"]), 2)
        self.assertEqual(res[1]["checkButtons"][0]["title"], "Touch controls")
        self.assertTrue(res[1]["checkButtons"][0]["state"])
        self.assertFalse(res[1]["checkButtons"][1]["state"])

        # Box 3: Radio
        self.assertTrue(res[2]["hasRadio"])
        self.assertEqual(res[2]["radio"]["state"], 2)

    def test_device_capabilities_flags(self):
        """Test complete device normalization and capability flag compilation."""
        raw_device = {
            "path": "/io/github/maniacx/BudsLink/dev_40_35_E6_31_8B_AC",
            "mac": "40:35:E6:31:8B:AC",
            "alias": "Galaxy Buds FE",
            "config": {
                "showSettingsButton": True,
                "battery1Icon": "bbm-left-symbolic",
                "battery2Icon": "bbm-right-symbolic",
                "toggle1Button1Icon": "bbm-anc-off-symbolic",
                "toggle1Button2Icon": "bbm-transperancy-symbolic",
                "toggle1Button3Icon": "bbm-anc-on-symbolic",
                "toggle2Title": "Voice Detect",
                "toggle2Button1Name": "Off",
                "toggle2Button2Name": "On",
                "optionsBox1": "slider",
                "box1SliderTitle": "Ambient Level"
            },
            "state": {
                "battery1Level": 90,
                "battery1Status": "discharging",
                "battery2Level": 95,
                "battery2Status": "discharging",
                "toggle1State": 3,
                "toggle2State": 1,
                "box1SliderValue": 50
            }
        }
        expr = f"normalizeDevice({json.dumps(raw_device)})"
        res = run_js_eval(expr)

        self.assertIsNotNone(res)
        self.assertEqual(res["mac"], "40:35:E6:31:8B:AC")
        caps = res["capabilities"]
        self.assertTrue(caps["enhanced"])
        self.assertEqual(caps["provider"], "budslink")
        self.assertTrue(caps["batteryBreakdown"])
        self.assertTrue(caps["leftBattery"])
        self.assertTrue(caps["rightBattery"])
        self.assertFalse(caps["caseBattery"])
        self.assertTrue(caps["noiseControl"])
        self.assertFalse(caps["adaptiveNoiseControl"])
        self.assertTrue(caps["transparency"])
        self.assertTrue(caps["anc"])
        self.assertTrue(caps["conversationAwareness"])
        self.assertTrue(caps["dynamicOptions"])
        self.assertTrue(caps["deviceSettings"])


if __name__ == "__main__":
    unittest.main()
