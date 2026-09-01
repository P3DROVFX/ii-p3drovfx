import QtQuick
import QtTest
import "../../services/displayColorFilter/DisplayColorFilterUtils.js" as FilterUtils

TestCase {
    name: "DisplayColorFilterUtils"

    function test_normalizes_and_clamps_profile_values() {
        const profile = FilterUtils.normalizeProfile({
            saturation: 3,
            contrast: 0.2,
            red: 1.25,
            green: "invalid",
            blue: 0
        });

        compare(profile.saturation, 2);
        compare(profile.contrast, 0.5);
        compare(profile.red, 1.25);
        compare(profile.green, 1);
        compare(profile.blue, 0.5);
    }

    function test_identity_profile_is_not_rendered() {
        const shader = FilterUtils.buildShader([
            {
                id: 0,
                name: "HDMI-A-1",
                profile: FilterUtils.defaultProfile()
            }
        ]);

        verify(!shader.includes("wl_output == 0"));
        verify(shader.includes("fragColor = vec4(calibrated, pixColor.a)"));
    }

    function test_shader_is_scoped_by_output_id_and_supports_vibrance() {
        const shader = FilterUtils.buildShader([
            {
                id: 0,
                name: "HDMI-A-1",
                profile: {
                    saturation: 1.75,
                    contrast: 1.2,
                    red: 1.1,
                    green: 1,
                    blue: 0.9
                }
            },
            {
                id: 1,
                name: "eDP-1",
                profile: {
                    saturation: 1.3,
                    contrast: 0.85,
                    red: 1,
                    green: 1.05,
                    blue: 1
                }
            }
        ]);

        verify(shader.includes("uniform int wl_output"));
        verify(shader.includes("if (wl_output == 0)"));
        verify(shader.includes("else if (wl_output == 1)"));
        verify(shader.includes("1.7500, 1.2000, vec3(1.1000, 1.0000, 0.9000)"));
        verify(shader.includes("1.3000, 0.8500, vec3(1.0000, 1.0500, 1.0000)"));
    }

    function test_rejects_invalid_monitor_ids() {
        const shader = FilterUtils.buildShader([
            {
                id: "not-an-id",
                name: "broken",
                profile: {
                    saturation: 2,
                    contrast: 1,
                    red: 1,
                    green: 1,
                    blue: 1
                }
            }
        ]);

        verify(!shader.includes("wl_output =="));
    }
}
