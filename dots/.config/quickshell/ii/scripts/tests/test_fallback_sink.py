"""fallback-sink.py: who takes over when the default Bluetooth sink goes away."""
import importlib.util
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "fallback_sink", Path(__file__).resolve().parents[1] / "audio" / "fallback-sink.py")
fs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fs)

DEPARTED = "bluez_output.40_35_E6_31_8B_AC.1"


def sink(name, priority, api="alsa", form=None, ports=(("out", "availability unknown"),)):
    props = {"device.api": api, "priority.session": str(priority)}
    if form:
        props["device.form_factor"] = form
    return {"name": name, "properties": props, "active_port": ports[0][0] if ports else None,
            "ports": [{"name": n, "availability": a} for n, a in ports]}


SPEAKER = sink("alsa_output.speaker", 1000)
MIC_JACK = sink("alsa_output.usb-fifine.analog-stereo", 1109, form="microphone")
HDMI_OFF = sink("alsa_output.hdmi1", 1200, ports=(("hdmi", "not available"),))
EASYEFFECTS = sink("easyeffects_sink", 2000, api=None)


class FallbackSinkTest(unittest.TestCase):
    def test_real_output_beats_microphone_and_unplugged_hdmi(self):
        self.assertEqual(fs.choose([SPEAKER, MIC_JACK, HDMI_OFF, EASYEFFECTS], [], DEPARTED),
                         ("alsa_output.speaker", False))

    def test_another_bluetooth_sink_comes_first(self):
        other = sink("bluez_output.AA_BB_CC_DD_EE_FF.1", 1010, api="bluez5")
        self.assertEqual(fs.choose([SPEAKER, other], [], DEPARTED)[0], other["name"])

    def test_card_still_present_means_ask_again(self):
        cards = [{"name": "bluez_card.40_35_E6_31_8B_AC"}]
        self.assertEqual(fs.choose([SPEAKER], cards, DEPARTED), (None, True))

    def test_nothing_real_leaves_wireplumber_alone(self):
        self.assertEqual(fs.choose([MIC_JACK, HDMI_OFF], [], DEPARTED), (None, False))


if __name__ == "__main__":
    unittest.main()
