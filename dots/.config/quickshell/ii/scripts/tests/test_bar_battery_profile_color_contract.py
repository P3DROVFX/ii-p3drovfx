from pathlib import Path
import json
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BarBatteryProfileColorContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_config_declares_color_by_power_profile(self):
        config_text = self.read("modules/common/Config.qml")
        self.assertIn("property bool colorByPowerProfile: true", config_text)

    def test_battery_config_exposes_toggle(self):
        battery_config = self.read("modules/settings/configs/widgets/BatteryConfig.qml")
        self.assertIn("ConfigSwitch", battery_config)
        self.assertIn('text: Translation.tr("Color battery by power profile")', battery_config)
        self.assertIn("Config.options.bar.battery.colorByPowerProfile", battery_config)

    def test_battery_indicator_respects_option(self):
        indicator = self.read("modules/ii/bar/widgets/battery/BatteryIndicator.qml")
        self.assertIn("property bool colorByPowerProfile: Config.options.bar.battery.colorByPowerProfile ?? true", indicator)
        self.assertIn("isPowerSaving: root.colorByPowerProfile && (PowerProfiles.profile === PowerProfile.PowerSaver)", indicator)
        self.assertIn("isPerformance: root.colorByPowerProfile && (PowerProfiles.profile === PowerProfile.Performance)", indicator)

    def test_vertical_battery_indicator_respects_option(self):
        v_indicator = self.read("modules/ii/verticalBar/BatteryIndicator.qml")
        self.assertIn("property bool colorByPowerProfile: Config.options.bar.battery.colorByPowerProfile ?? true", v_indicator)
        self.assertIn("isPowerSaving: root.colorByPowerProfile && (PowerProfiles.profile === PowerProfile.PowerSaver)", v_indicator)
        self.assertIn("isPerformance: root.colorByPowerProfile && (PowerProfiles.profile === PowerProfile.Performance)", v_indicator)

    def test_translations_contain_keys(self):
        en_json = json.loads(self.read("translations/en_US.json"))
        pt_json = json.loads(self.read("translations/pt_BR.json"))

        key_title = "Color battery by power profile"
        key_desc = "Change battery icon color when power saver or performance mode is active"

        self.assertIn(key_title, en_json)
        self.assertIn(key_desc, en_json)

        self.assertIn(key_title, pt_json)
        self.assertIn(key_desc, pt_json)
        self.assertEqual(pt_json[key_title], "Colorir bateria pelo perfil de energia")


if __name__ == "__main__":
    unittest.main()
