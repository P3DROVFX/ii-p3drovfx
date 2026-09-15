pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root

    readonly property real squircleSmoothing: Config?.options.akebono.squircle.smoothing ?? 4.0

    readonly property bool shelfPills: Config?.options.akebono.shelf.pills ?? true

    // Kept identical to modules/ii/bar/shared/BarThemes.qml so the shelf shares the
    // bar's expressive colour themes. (Inlined: cross-module relative imports of a
    // registered bar directory are dropped by the qs: module resolver.)
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
        if (root.themes[themeName]) return root.themes[themeName];
        return root.themes["content"];
    }

    readonly property var activeTheme: getTheme(Config.options.bar.expressiveColorTheme)

    // Shelf module pills follow the exact colour logic the bar's BarGroupTheme uses
    // (modules/ii/bar/groups/BarGroupTheme.qml), driven by the same bar settings,
    // so the bar appearance page controls the shelf pills too.
    readonly property color shelfPillColor: {
        if (!shelfPills) return "transparent";
        if (Config.options.bar.expressiveColors) return activeTheme.componentBackground;
        if (Config.options.bar.expressiveGroupColor) return Appearance.colors.colPrimaryContainer;
        if (Config.options.bar.barGroupStyle === 0) return Appearance.colors.colLayer1;
        if (Config.options.bar.barGroupStyle === 1)
            return Config.options.bar.barBackgroundStyle === 1
                ? Appearance.colors.colLayer1
                : Appearance.m3colors.m3surfaceContainerLow;
        return "transparent";
    }

    // The dock surface follows the same colour logic as the bar's background
    // (modules/ii/bar/styles/FloatStyle.qml: actualColor). It stays opaque: the
    // dock shader fills the popups with this same colour, so a transparent
    // surface would hide the launcher/quick settings/media panels too.
    readonly property color shelfSurfaceColor:
        Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0

    readonly property color shelfPillHoverColor: {
        if (!shelfPills) return Appearance.colors.colLayer1;
        if (Config.options.bar.expressiveColors) return activeTheme.highlight;
        if (Config.options.bar.expressiveGroupColor) return Appearance.colors.colPrimaryContainerHover;
        return Appearance.colors.colLayer1Hover;
    }

    // The bar's pills/backgrounds resolve to Appearance.rounding.full (a capsule when
    // rounding is on, sharp when the user sets shell rounding to 0). Pills use this so
    // their rounding follows the shell rounding control like the bar's do.
    readonly property real shelfPillRadius: Appearance.rounding.full
}