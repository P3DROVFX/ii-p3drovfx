import QtQuick
import qs.modules.common

/**
 * Colour resolution shared by the styled bar widgets (date, clock, record, …).
 *
 * Every pair here is a real Material pair — `colContainer`/`colOnContainer` and
 * `colAccent`/`colOnAccent` are never mixed across families, which is the defect
 * this object exists to make impossible. `colBare*` are for variants that paint
 * straight onto the bar with no surface of their own, so they pair with the bar
 * group background (`colOnLayer1`) instead.
 *
 * > [!CAUTION]
 * > **Nothing here may be named `on<Something>`.** These used to be `onContainer`
 * > and `onAccent`, and both silently rendered **black**: QML reserves the `on`
 * > prefix for signal handlers, so a property declared that way *with a binding*
 * > never receives it — the property keeps its default, which for a colour is
 * > black. A constant initialiser survives, which is why this looks like it works
 * > until the value becomes conditional. There is no warning in `qs log`; the
 * > only symptom is black text on a coloured surface.
 */
QtObject {
    id: root

    // "tonal" | "vibrant" | "neutral" | "alert"
    //
    // `alert` is the error family, and it is not a fourth taste: it is reserved
    // for a widget whose whole subject is a live capture of the screen, where
    // the colour has to say "this is running" at a glance. Nothing else should
    // ask for it.
    property string colorMode: "tonal"

    readonly property bool vibrant: root.colorMode === "vibrant"
    readonly property bool neutral: root.colorMode === "neutral"
    readonly property bool alert: root.colorMode === "alert"

    readonly property color colContainer: root.alert
        ? Appearance.colors.colErrorContainer
        : root.vibrant
            ? Appearance.colors.colPrimaryContainer
            : root.neutral
                ? Appearance.colors.colSurfaceContainerHighest
                : Appearance.colors.colTertiaryContainer
    readonly property color colOnContainer: root.alert
        ? Appearance.colors.colOnErrorContainer
        : root.vibrant
            ? Appearance.colors.colOnPrimaryContainer
            : root.neutral
                ? Appearance.colors.colOnSurface
                : Appearance.colors.colOnTertiaryContainer

    // Solid accent: badges, filled plates, progress strokes.
    readonly property color colAccent: root.alert
        ? Appearance.colors.colError
        : root.vibrant
            ? Appearance.colors.colPrimary
            : root.neutral
                ? Appearance.colors.colSecondary
                : Appearance.colors.colTertiary
    readonly property color colOnAccent: root.alert
        ? Appearance.colors.colOnError
        : root.vibrant
            ? Appearance.colors.colOnPrimary
            : root.neutral
                ? Appearance.colors.colOnSecondary
                : Appearance.colors.colOnTertiary

    // Typography painted directly on the bar background.
    readonly property color colBare: Appearance.colors.colOnLayer1
    readonly property color colBareAccent: root.neutral
        ? Appearance.colors.colOnSurfaceVariant
        : root.colAccent
}
