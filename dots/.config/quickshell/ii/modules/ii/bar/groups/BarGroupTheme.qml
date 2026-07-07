import QtQuick
import qs
import qs.modules.common
import qs.modules.ii.bar.shared

// Computes radius and color values for a BarGroup.
// Instantiate once per BarComponent; all outputs are read-only bindings.
QtObject {
    id: root

    // Inputs — set by BarComponent
    required property int barSection        // 0:left 1:center 2:right
    required property var list              // section list (for neighbor checks)
    required property int originalIndex     // position in list
    required property bool isExpressive
    required property bool highlighted
    required property bool activated        // from widget item (itemLoader.item?.activated)
    required property var activeTheme       // from BarThemes
    required property string widgetId

    readonly property int barGroupStyle:     Config.options.bar.barGroupStyle
    readonly property int barBackgroundStyle: Config.options.bar.barBackgroundStyle

    // ── Radius ────────────────────────────────────────────────────────────────
    readonly property real startRadius: {
        if (barGroupStyle === 1) return Appearance.rounding.windowRounding;
        if (barSection === 0) {
            return originalIndex === 0
                ? Appearance.rounding.full
                : Appearance.rounding.verysmall;
        } else if (barSection === 2) {
            const hasLeft = list.slice(0, originalIndex).some(i => i.visible !== false);
            return hasLeft ? Appearance.rounding.verysmall : Appearance.rounding.full;
        } else { // center
            if (list.length === 1) return Appearance.rounding.full;
            const hasLeft = list.slice(0, originalIndex).some(i => i.visible !== false);
            return hasLeft ? Appearance.rounding.verysmall : Appearance.rounding.full;
        }
    }

    readonly property real endRadius: {
        if (barGroupStyle === 1) return Appearance.rounding.windowRounding;
        if (barSection === 2) {
            return originalIndex === list.length - 1
                ? Appearance.rounding.full
                : Appearance.rounding.verysmall;
        } else if (barSection === 0) {
            const hasRight = list.slice(originalIndex + 1).some(i => i.visible !== false);
            return hasRight ? Appearance.rounding.verysmall : Appearance.rounding.full;
        } else { // center
            if (list.length === 1) return Appearance.rounding.full;
            const hasRight = list.slice(originalIndex + 1).some(i => i.visible !== false);
            return hasRight ? Appearance.rounding.verysmall : Appearance.rounding.full;
        }
    }

    // ── Colors ────────────────────────────────────────────────────────────────
    readonly property color colBackground: {
        if (Config.options.bar.expressiveColors) return activeTheme.componentBackground;
        if (Config.options.bar.expressiveGroupColor && (barGroupStyle === 0 || barGroupStyle === 1))
            return Appearance.colors.colPrimaryContainer;
        if (barGroupStyle === 0) return Appearance.colors.colLayer1;
        if (barGroupStyle === 1 && barBackgroundStyle === 1) return Appearance.colors.colLayer1;
        if (barGroupStyle === 1) return Appearance.m3colors.m3surfaceContainerLow;
        return "transparent";
    }

    readonly property color colBackgroundHighlight: {
        if (Config.options.bar.expressiveColors) return activeTheme.highlight;
        if (widgetId === "sports") return barGroupStyle === 2
            ? "transparent"
            : Appearance.colors.colPrimaryContainer;
        return Appearance.colors.colPrimary;
    }

    readonly property color colOnBackgroundHighlight: {
        if (Config.options.bar.expressiveColors)
            return ColorUtils.getContrastingTextColor(colBackgroundHighlight);
        if (widgetId === "sports") return barGroupStyle === 2
            ? Appearance.colors.colOnSurface
            : Appearance.colors.colOnPrimaryContainer;
        return Appearance.colors.colOnPrimary;
    }

    // Resolved background for BarGroup (transparent when expressive, highlight when active)
    readonly property color resolvedBackground: ((isExpressive && widgetId !== "workspaces") || (widgetId === "system_monitor" && Config.options.bar.resources.showDocker))
        ? "transparent"
        : ((activated || highlighted) ? colBackgroundHighlight : colBackground)
}
