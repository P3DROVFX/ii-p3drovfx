import QtQuick
import QtQuick.Controls
import QtTest
import qs.modules.common
import "."

Item {
    id: scene
    width: 1000
    height: 800
    BlurController { id: controller }
    WindowsConfig { id: page; width: 1000 }
    Component { id: pageFactory; WindowsConfig { width: 1000 } }

    function row(label, item) {
        if (item.text === label && (typeof item.moved === "function" || typeof item.checked === "boolean"))
            return item;
        for (const child of item.children) {
            const result = row(label, child);
            if (result) return result;
        }
        return null;
    }

    TestCase {
        name: "WindowsBlur"
        when: windowShown

        function settled() {
            tryCompare(Recorder, "active", 0);
            wait(160);
            tryCompare(Recorder, "active", 0);
        }

        function test_01_initialization_and_burst() {
            compare(Config.ready, false);
            Config.options.appearance.blur.noise = 0.0637;
            wait(170);
            compare(Recorder.commands.length, 0);
            compare(Config.options.appearance.blur.noise, 0.0637);
            Config.ready = true;
            controller.scheduleBlurUpdate();
            controller.pushHyprlandLayerRules();
            for (let i = 0; i < 30; ++i)
                Config.options.appearance.blur.noise = i / 100;
            tryCompare(Recorder, "active", 1);
            compare(Recorder.commands.length, 1);
            verify(Recorder.commands[0][2].includes("noise = 0.29"));
            verify(Recorder.commands[0][2].includes("hl.layer_rule"));
            settled();
        }

        function test_02_changes_while_process_is_running() {
            const count = Recorder.commands.length;
            Config.options.appearance.blur.vibrancy = 0.321;
            tryCompare(Recorder, "active", 1);
            Config.options.appearance.blur.vibrancy = 0.678;
            Config.options.appearance.ignoreAlpha = 0.237;
            settled();
            compare(Recorder.commands.length, count + 2);
            const last = Recorder.commands[Recorder.commands.length - 1][2];
            verify(last.includes("vibrancy = 0.678"));
            verify(last.includes("ignore_alpha = 0.237"));
            compare(Recorder.maxActive, 1);
        }

        function test_03_advanced_visibility_preserves_effect() {
            settled();
            const toggle = scene.row("Advanced blur options", page);
            const labels = ["Blur Passes", "Blur noise", "Blur contrast", "Blur brightness",
                "Blur vibrancy", "Vibrancy in dark areas", "Keep blur strength when windows fade",
                "Optimize blur rendering", "X-ray blur for floating windows",
                "Blur behind special workspaces", "Blur application menus",
                "Application menu alpha threshold", "Blur input method popups", "Input method alpha threshold"];
            compare(toggle.checked, false);
            for (const label of labels)
                compare(scene.row(label, page).visible, false, label);
            compare(scene.row("Blur Size", page).visible, true);
            compare(scene.row("Ignore Alpha", page).visible, true);
            const script = controller.blurConfigScript;
            const count = Recorder.commands.length;
            toggle.clicked();
            compare(Config.options.appearance.blur.advancedOptions, true);
            for (const label of labels)
                compare(scene.row(label, page).visible, true, label);
            toggle.clicked();
            for (const label of labels)
                compare(scene.row(label, page).visible, false, label);
            compare(controller.blurConfigScript, script);
            settled();
            compare(Recorder.commands.length, count);
            const secondPage = createTemporaryObject(pageFactory, scene);
            compare(scene.row("Advanced blur options", secondPage).checked, false);
            compare(scene.row("Blur noise", secondPage).visible, false);
            scene.row("Advanced blur options", secondPage).clicked();
            compare(toggle.checked, true);
            compare(scene.row("Blur noise", page).visible, true);
            compare(Config.options.appearance.blur.noise, 0.29);
            compare(controller.blurConfigScript, script);
        }

        function test_03_slider_ranges_precision_and_persistence() {
            const size = scene.row("Blur Size", page);
            verify(size !== null);
            compare(size.from, 0);
            compare(size.to, 100);
            compare(size.snapMode, Slider.NoSnap);
            compare(size.stopIndicatorValues.length, 0);
            size.value = 17.2;
            size.moved();
            compare(Config.options.appearance.blurSize, 17);
            const contrast = scene.row("Blur contrast", page);
            contrast.value = 1.347;
            contrast.moved();
            compare(Config.options.appearance.blur.contrast, 1.347);
            compare(contrast.badgeText, "134.7%");
            const secondPage = createTemporaryObject(pageFactory, scene);
            verify(secondPage !== null);
            compare(scene.row("Blur Size", secondPage).value, 17);
            compare(scene.row("Blur contrast", secondPage).value, 1.347);
            settled();
        }

        function test_04_disabled_dependencies_preserve_preferences() {
            Config.options.appearance.blur.xray = true;
            Config.options.appearance.blur.newOptimizations = false;
            compare(scene.row("X-ray blur for floating windows", page).enabled, false);
            compare(Config.options.appearance.blur.xray, true);
            verify(controller.blurConfigScript.includes("xray = false"));
            Config.options.appearance.blur.newOptimizations = true;
            verify(controller.blurConfigScript.includes("xray = true"));
            Config.options.appearance.blur.popups = false;
            compare(scene.row("Application menu alpha threshold", page).enabled, false);
            Config.options.appearance.blur.popups = true;
            compare(scene.row("Application menu alpha threshold", page).enabled, true);
            settled();
        }

        function test_05_popup_rules_reset_and_reapply() {
            Config.options.appearance.transparency.enable = true;
            Config.options.appearance.transparency.popups = true;
            const enabledScript = controller.getLayerRulesScript();
            Config.options.appearance.transparency.popups = false;
            const disabledScript = controller.getLayerRulesScript();
            for (const name of ["ii:appearance:popup", "ii:appearance:popup-family"]) {
                verify(enabledScript.includes("name = '" + name + "'"));
                verify(disabledScript.includes("name = '" + name + "'"));
            }
            compare((disabledScript.match(/blur = false, blur_popups = false/g) || []).length, 2);
            verify(!disabledScript.includes("ignorealpha ="));
            verify(!disabledScript.includes("noanim ="));
            settled();
            const count = Recorder.commands.length;
            controller.scheduleBlurUpdate(); // Same path used after compositor reload.
            controller.pushHyprlandLayerRules();
            settled();
            compare(Recorder.commands.length, count + 1);
            verify(Recorder.commands[count][2].includes("contrast = 1.347"));
            compare(Recorder.maxActive, 1);
        }
    }
}
