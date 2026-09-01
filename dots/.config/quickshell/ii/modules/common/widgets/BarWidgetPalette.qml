import QtQuick
import qs.modules.common

/**
 * Colour resolution shared by the styled bar widgets (date, clock, …).
 *
 * Every pair here is a real Material pair — `container`/`onContainer` and
 * `accent`/`onAccent` are never mixed across families, which is the defect this
 * object exists to make impossible. `bare*` are for variants that paint
 * straight onto the bar with no surface of their own, so they pair with the bar
 * group background (`colOnLayer1`) instead.
 */
QtObject {
    id: root

    // "tonal" | "vibrant" | "neutral"
    property string colorMode: "tonal"

    readonly property bool vibrant: root.colorMode === "vibrant"
    readonly property bool neutral: root.colorMode === "neutral"

    readonly property color container: root.vibrant
        ? Appearance.colors.colPrimaryContainer
        : root.neutral
            ? Appearance.colors.colSurfaceContainerHighest
            : Appearance.colors.colTertiaryContainer
    readonly property color onContainer: root.vibrant
        ? Appearance.colors.colOnPrimaryContainer
        : root.neutral
            ? Appearance.colors.colOnSurface
            : Appearance.colors.colOnTertiaryContainer

    // Solid accent: badges, filled plates, progress strokes.
    readonly property color accent: root.vibrant
        ? Appearance.colors.colPrimary
        : root.neutral
            ? Appearance.colors.colSecondary
            : Appearance.colors.colTertiary
    readonly property color onAccent: root.vibrant
        ? Appearance.colors.colOnPrimary
        : root.neutral
            ? Appearance.colors.colOnSecondary
            : Appearance.colors.colOnTertiary

    // Typography painted directly on the bar background.
    readonly property color bare: Appearance.colors.colOnLayer1
    readonly property color bareAccent: root.neutral
        ? Appearance.colors.colOnSurfaceVariant
        : root.accent
}
