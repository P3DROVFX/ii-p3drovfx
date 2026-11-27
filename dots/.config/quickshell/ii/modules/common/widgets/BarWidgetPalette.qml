import QtQuick
import qs.modules.common

/**
 * Colour resolution shared by the styled bar widgets (date, clock, record, …).
 * Delegates all Material colour resolution to the shared BarWidgetPaletteStore
 * singleton so each widget pays a single lookup instead of ~160 reactive
 * Appearance.colors dependency captures.
 */
QtObject {
    id: root

    property string colorMode: "tonal"

    readonly property string effectiveMode: BarWidgetPaletteStore.normalizeMode(root.colorMode)
    readonly property var _p: BarWidgetPaletteStore.palettes[root.effectiveMode] || BarWidgetPaletteStore.palettes["primary"]

    readonly property bool isPrimary: root.effectiveMode === "primary"
    readonly property bool isPrimaryContainer: root.effectiveMode === "primaryContainer"
    readonly property bool isSecondary: root.effectiveMode === "secondary"
    readonly property bool isSecondaryContainer: root.effectiveMode === "secondaryContainer"
    readonly property bool isTertiary: root.effectiveMode === "tertiary"
    readonly property bool isTertiaryContainer: root.effectiveMode === "tertiaryContainer"
    readonly property bool isNeutral: root.effectiveMode === "neutral"
    readonly property bool isNeutralContainer: root.effectiveMode === "neutralContainer"
    readonly property bool isAlert: root.effectiveMode === "alert"

    // Backward-compatible taste flags
    readonly property bool vibrant: root.colorMode === "vibrant" || root.isPrimary
    readonly property bool neutral: root.colorMode === "neutral" || root.isNeutral || root.isNeutralContainer
    readonly property bool alert: root.colorMode === "alert" || root.isAlert

    readonly property color colBackground: _p.colBackground
    readonly property color colOnBackground: _p.colOnBackground
    readonly property color colBackgroundHover: _p.colBackgroundHover
    readonly property color colBackgroundActive: _p.colBackgroundActive

    readonly property color colBackgroundVariant: _p.colBackgroundVariant
    readonly property color colOnBackgroundVariant: _p.colOnBackgroundVariant
    readonly property color colBackgroundVariantHover: _p.colBackgroundVariantHover
    readonly property color colBackgroundVariantActive: _p.colBackgroundVariantActive

    readonly property color colContainer: _p.colContainer
    readonly property color colOnContainer: _p.colOnContainer
    readonly property color colContainerHover: _p.colContainerHover
    readonly property color colContainerActive: _p.colContainerActive

    readonly property color colAccent: _p.colAccent
    readonly property color colOnAccent: _p.colOnAccent
    readonly property color colAccentHover: _p.colAccentHover
    readonly property color colAccentActive: _p.colAccentActive

    readonly property color colBare: _p.colBare
    readonly property color colBareAccent: _p.colBareAccent
}
