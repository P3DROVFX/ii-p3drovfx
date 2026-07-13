import QtQuick
import qs.modules.common

QtObject {
    id: root

    property var themes: ({
        "content": {
            "name": "Content",
            "barBackground": Appearance.m3colors["m3primaryContainer"],
            "componentBackground": Appearance.m3colors["m3inverseOnSurface"],
            "highlight": Appearance.colors["colPrimary"]
        },
        "primary": {
            "name": "Primary",
            "barBackground": Appearance.m3colors["m3surfaceTint"],
            "componentBackground": Appearance.m3colors["m3primaryContainer"],
            "highlight": Appearance.colors["colTertiary"]
        },
        "secondary": {
            "name": "Secondary",
            "barBackground": Appearance.m3colors["m3secondaryContainer"],
            "componentBackground": Appearance.m3colors["m3primaryContainer"],
            "highlight": Appearance.colors["colPrimary"]
        },
        "surface": {
            "name": "Surface",
            "barBackground": Appearance.m3colors["m3surfaceContainerHigh"],
            "componentBackground": Appearance.m3colors["m3surfaceBright"],
            "highlight": Appearance.colors["colPrimary"]
        }
    })

    function getTheme(themeName) {
        if (themes[themeName]) return themes[themeName];
        return themes["content"];
    }

    function getThemeNames() {
        return Object.keys(themes);
    }
}
