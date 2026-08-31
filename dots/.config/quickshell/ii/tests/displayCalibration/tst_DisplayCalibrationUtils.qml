import QtQuick
import QtTest
import "../../services/displayCalibration/DisplayCalibrationUtils.js" as CalibrationUtils

TestCase {
    name: "DisplayCalibrationUtils"

    function test_detects_only_valid_ddc_displays() {
        const output = "Display 1\n"
            + "   I2C bus:          /dev/i2c-14\n"
            + "   DRM connector:    card2-HDMI-A-1\n\n"
            + "Invalid display\n"
            + "   I2C bus:          /dev/i2c-15\n"
            + "   DRM connector:    card2-eDP-1\n\n"
            + "Display 2\n"
            + "   I2C bus:          /dev/i2c-8\n"
            + "   DRM connector:    card0-DP-2\n";

        const displays = CalibrationUtils.parseDetectedDisplays(output);
        compare(displays.length, 2);
        compare(displays[0].name, "HDMI-A-1");
        compare(displays[0].busNum, "14");
        compare(displays[1].name, "DP-2");
        compare(displays[1].busNum, "8");
    }

    function test_parses_normal_detect_output_and_direct_connector_names() {
        const output = "Display 1\n"
            + "   I2C bus:  /dev/i2c-14\n"
            + "   DRM_connector:           card2-HDMI-A-1\n"
            + "   EDID synopsis:\n"
            + "      Model:                LG ULTRAGEAR\n\n"
            + "Display 2\n"
            + "   I2C bus:  /dev/i2c-7\n"
            + "   DRM_connector:           DP-2\n";

        const displays = CalibrationUtils.parseDetectedDisplays(output);
        compare(displays.length, 2);
        compare(displays[0].name, "HDMI-A-1");
        compare(displays[0].busNum, "14");
        compare(displays[1].name, "DP-2");
        compare(displays[1].busNum, "7");
    }

    function test_rejects_stale_operation_generation_or_bus() {
        verify(CalibrationUtils.operationMatches(4, "14", 4, "14"));
        verify(!CalibrationUtils.operationMatches(3, "14", 4, "14"));
        verify(!CalibrationUtils.operationMatches(4, "14", 4, "15"));
    }

    function test_parses_supported_vcp_values_and_normalizes_percentages() {
        const values = CalibrationUtils.parseVcpValues(
            "VCP 12 C 75 100\n"
            + "VCP 16 C 128 255\n"
            + "VCP 18 ERR\n"
            + "VCP 1A C 40 80\n"
        );

        compare(values["12"].current, 75);
        compare(values["16"].maximum, 255);
        verify(values["18"] === undefined);
        compare(CalibrationUtils.percentForValue(values["16"].current, values["16"].maximum), 50);
        compare(CalibrationUtils.rawValueForPercent(50, 255), 128);
    }

    function test_builds_one_bus_scoped_coalesced_write() {
        const command = CalibrationUtils.buildSetCommand("14", {
            "1A": 42,
            "12": 75,
            "18": 51
        });

        compare(command.join(" "), "ddcutil -b 14 setvcp 12 75 18 51 1A 42");
    }
}
