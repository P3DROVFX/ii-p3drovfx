pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

GridLayout {
    id: root

    columns: 3
    columnSpacing: Appearance.rounding.small
    rowSpacing: Appearance.rounding.small
    Layout.fillWidth: true

    readonly property list<string> builtInColorSchemes: ["angel_light", "amber_crt", "angel", "ayu", "bauhaus", "blueprint", "braun", "cobalt2", "cursor", "dracula", "everforest", "flexoki", "frappe", "game_boy", "github", "gruber_darker", "gruvbox", "gruvbox_hard", "gruvbox_material", "gruvbox_soft", "hazard", "kanagawa", "kodak", "latte", "legal_pad", "macchiato", "material_ocean", "matrix", "melange", "mercury", "mocha", "monokai_pro", "nord", "nothing_os", "one_dark", "open_code", "orng", "osaka_jade", "oxocarbon", "poimandres", "rose_pine", "sakura", "samurai", "solarized", "synthwave84", "teenage_engineering", "thinkpad", "tokyo_night", "vercel", "vesper", "zen_burn", "zen_garden"]
    property list<string> customColorSchemes: Config.options.appearance.customColorSchemes ?? []
    readonly property list<string> wallpaperColorSchemes: ["scheme-auto", "scheme-content", "scheme-tonal-spot", "scheme-fidelity", "scheme-intense", "scheme-vibrant", "scheme-fruit-salad", "scheme-expressive", "scheme-rainbow", "scheme-neutral", "scheme-monochrome"]

    property bool customTheme: false
    property bool builtInTheme: false
    property list<string> colorSchemes: customTheme ? customColorSchemes : builtInTheme ? builtInColorSchemes : wallpaperColorSchemes
    property int loadedCount: 0
    property string hoveredColorSchemeDisplayName: ""

    readonly property string selectedColorSchemeDisplayName: {
        const selectedScheme = normalizeName(Config.options.appearance.palette.type);
        for (let i = 0; i < colorSchemes.length; ++i) {
            if (normalizeName(colorSchemes[i]) === selectedScheme)
                return formatText(colorSchemes[i]);
        }
        return "";
    }

    function normalizeName(text) {
        return String(text).replace(/\.json$/i, "");
    }

    function formatText(text) {
        const normalized = normalizeName(text).replace(/[_-]+/g, " ");
        const withoutSchemePrefix = customTheme || builtInTheme
            ? normalized
            : normalized.replace(/^scheme /, "");
        return withoutSchemePrefix.replace(/\b\w/g, character => character.toUpperCase());
    }

    Repeater {
        model: root.colorSchemes

        delegate: ColorPreviewButton {
            required property int index
            required property string modelData

            Layout.fillWidth: true
            colorScheme: root.normalizeName(modelData)
            colorSchemeDisplayName: ""
            customTheme: root.customTheme
            builtInTheme: root.builtInTheme
            shouldLoad: index < root.loadedCount
            expressiveSelection: true

            onHoveredChanged: {
                const displayName = root.formatText(modelData);
                if (hovered) {
                    root.hoveredColorSchemeDisplayName = displayName;
                } else if (root.hoveredColorSchemeDisplayName === displayName) {
                    root.hoveredColorSchemeDisplayName = "";
                }
            }
        }
    }

    Timer {
        id: loadTimer
        interval: 20
        repeat: true
        running: false

        onTriggered: {
            root.loadedCount += 1;

            if (root.loadedCount >= root.colorSchemes.length)
                loadTimer.stop();
        }
    }

    Component.onCompleted: Qt.callLater(() => loadTimer.start())
}
