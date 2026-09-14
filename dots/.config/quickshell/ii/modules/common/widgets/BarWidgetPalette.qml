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
 * Supports 8 Material 3 expressive palettes:
 * - primary
 * - primaryContainer
 * - secondary
 * - secondaryContainer
 * - tertiary
 * - tertiaryContainer
 * - neutral
 * - neutralContainer
 * As well as legacy/specialized modes: "tonal", "vibrant", "alert".
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

    property string colorMode: "tonal"

    readonly property string effectiveMode: {
        const raw = String(root.colorMode ?? "primary").trim().toLowerCase().replace(/[\s_-]/g, "");
        if (raw === "vibrant") return "primary";
        if (raw === "tonal") return "tertiaryContainer";
        if (raw === "alert") return "alert";
        if (raw === "primary") return "primary";
        if (raw === "primarycontainer") return "primaryContainer";
        if (raw === "secondary") return "secondary";
        if (raw === "secondarycontainer") return "secondaryContainer";
        if (raw === "tertiary" || raw === "teritiary") return "tertiary";
        if (raw === "tertiarycontainer" || raw === "teritiarycontainer") return "tertiaryContainer";
        if (raw === "neutral") return "neutral";
        if (raw === "neutralcontainer") return "neutralContainer";
        return "primary";
    }

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

    // Primary surface background & text/icon pair
    readonly property color colBackground: root.isAlert
        ? Appearance.colors.colErrorContainer
        : root.isPrimary
            ? Appearance.colors.colPrimary
            : root.isPrimaryContainer
                ? Appearance.colors.colPrimaryContainer
                : root.isSecondary
                    ? Appearance.colors.colSecondary
                    : root.isSecondaryContainer
                        ? Appearance.colors.colSecondaryContainer
                        : root.isTertiary
                            ? Appearance.colors.colTertiary
                            : root.isTertiaryContainer
                                ? Appearance.colors.colTertiaryContainer
                                : root.isNeutral
                                    ? Appearance.colors.colSurfaceContainerHighest
                                    : Appearance.colors.colSurfaceContainerHigh

    readonly property color colOnBackground: root.isAlert
        ? Appearance.colors.colOnErrorContainer
        : root.isPrimary
            ? Appearance.colors.colOnPrimary
            : root.isPrimaryContainer
                ? Appearance.colors.colOnPrimaryContainer
                : root.isSecondary
                    ? Appearance.colors.colOnSecondary
                    : root.isSecondaryContainer
                        ? Appearance.colors.colOnSecondaryContainer
                        : root.isTertiary
                            ? Appearance.colors.colOnTertiary
                            : root.isTertiaryContainer
                                ? Appearance.colors.colOnTertiaryContainer
                                : Appearance.colors.colOnSurface

    readonly property color colBackgroundHover: root.isAlert
        ? Appearance.colors.colErrorContainerHover
        : root.isPrimary
            ? Appearance.colors.colPrimaryHover
            : root.isPrimaryContainer
                ? Appearance.colors.colPrimaryContainerHover
                : root.isSecondary
                    ? Appearance.colors.colSecondaryHover
                    : root.isSecondaryContainer
                        ? Appearance.colors.colSecondaryContainerHover
                        : root.isTertiary
                            ? Appearance.colors.colTertiaryHover
                            : root.isTertiaryContainer
                                ? Appearance.colors.colTertiaryContainerHover
                                : Appearance.colors.colSurfaceContainerHighestHover

    readonly property color colBackgroundActive: root.isAlert
        ? Appearance.colors.colErrorContainerActive
        : root.isPrimary
            ? Appearance.colors.colPrimaryActive
            : root.isPrimaryContainer
                ? Appearance.colors.colPrimaryContainerActive
                : root.isSecondary
                    ? Appearance.colors.colSecondaryActive
                    : root.isSecondaryContainer
                        ? Appearance.colors.colSecondaryContainerActive
                        : root.isTertiary
                            ? Appearance.colors.colTertiaryActive
                            : root.isTertiaryContainer
                                ? Appearance.colors.colTertiaryContainerActive
                                : Appearance.colors.colSurfaceContainerHighestActive

    // Secondary / inner variant pair (for nested chips, cookies, badges)
    readonly property color colBackgroundVariant: root.isAlert
        ? Appearance.colors.colError
        : root.isPrimary
            ? Appearance.colors.colPrimaryContainer
            : root.isPrimaryContainer
                ? Appearance.colors.colPrimary
                : root.isSecondary
                    ? Appearance.colors.colSecondaryContainer
                    : root.isSecondaryContainer
                        ? Appearance.colors.colSecondary
                        : root.isTertiary
                            ? Appearance.colors.colTertiaryContainer
                            : root.isTertiaryContainer
                                ? Appearance.colors.colTertiary
                                : root.isNeutral
                                    ? Appearance.colors.colSurfaceContainerHigh
                                    : Appearance.colors.colSurfaceContainerHighest

    readonly property color colOnBackgroundVariant: root.isAlert
        ? Appearance.colors.colOnError
        : root.isPrimary
            ? Appearance.colors.colOnPrimaryContainer
            : root.isPrimaryContainer
                ? Appearance.colors.colOnPrimary
                : root.isSecondary
                    ? Appearance.colors.colOnSecondaryContainer
                    : root.isSecondaryContainer
                        ? Appearance.colors.colOnSecondary
                        : root.isTertiary
                            ? Appearance.colors.colOnTertiaryContainer
                            : root.isTertiaryContainer
                                ? Appearance.colors.colOnTertiary
                                : Appearance.colors.colOnSurface

    readonly property color colBackgroundVariantHover: root.isAlert
        ? Appearance.colors.colErrorHover
        : root.isPrimary
            ? Appearance.colors.colPrimaryContainerHover
            : root.isPrimaryContainer
                ? Appearance.colors.colPrimaryHover
                : root.isSecondary
                    ? Appearance.colors.colSecondaryContainerHover
                    : root.isSecondaryContainer
                        ? Appearance.colors.colSecondaryHover
                        : root.isTertiary
                            ? Appearance.colors.colTertiaryContainerHover
                            : root.isTertiaryContainer
                                ? Appearance.colors.colTertiaryHover
                                : Appearance.colors.colSurfaceContainerHighestHover

    readonly property color colBackgroundVariantActive: root.isAlert
        ? Appearance.colors.colErrorActive
        : root.isPrimary
            ? Appearance.colors.colPrimaryContainerActive
            : root.isPrimaryContainer
                ? Appearance.colors.colPrimaryActive
                : root.isSecondary
                    ? Appearance.colors.colSecondaryContainerActive
                    : root.isSecondaryContainer
                        ? Appearance.colors.colSecondaryActive
                        : root.isTertiary
                            ? Appearance.colors.colTertiaryContainerActive
                            : root.isTertiaryContainer
                                ? Appearance.colors.colTertiaryActive
                                : Appearance.colors.colSurfaceContainerHighestActive

    // Container pair
    readonly property color colContainer: root.alert
        ? Appearance.colors.colErrorContainer
        : (root.isPrimary || root.isPrimaryContainer)
            ? Appearance.colors.colPrimaryContainer
            : (root.isSecondary || root.isSecondaryContainer)
                ? Appearance.colors.colSecondaryContainer
                : root.isNeutral
                    ? Appearance.colors.colSurfaceContainerHighest
                    : root.isNeutralContainer
                        ? Appearance.colors.colSurfaceContainerHigh
                        : Appearance.colors.colTertiaryContainer

    readonly property color colOnContainer: root.isAlert
        ? Appearance.colors.colOnErrorContainer
        : (root.isPrimary || root.isPrimaryContainer)
            ? Appearance.colors.colOnPrimaryContainer
            : (root.isSecondary || root.isSecondaryContainer)
                ? Appearance.colors.colOnSecondaryContainer
                : (root.isNeutral || root.isNeutralContainer)
                    ? Appearance.colors.colOnSurface
                    : Appearance.colors.colOnTertiaryContainer

    readonly property color colContainerHover: root.isAlert
        ? Appearance.colors.colErrorContainerHover
        : (root.isPrimary || root.isPrimaryContainer)
            ? Appearance.colors.colPrimaryContainerHover
            : (root.isSecondary || root.isSecondaryContainer)
                ? Appearance.colors.colSecondaryContainerHover
                : (root.isNeutral || root.isNeutralContainer)
                    ? Appearance.colors.colSurfaceContainerHighestHover
                    : Appearance.colors.colTertiaryContainerHover

    readonly property color colContainerActive: root.isAlert
        ? Appearance.colors.colErrorContainerActive
        : (root.isPrimary || root.isPrimaryContainer)
            ? Appearance.colors.colPrimaryContainerActive
            : (root.isSecondary || root.isSecondaryContainer)
                ? Appearance.colors.colSecondaryContainerActive
                : (root.isNeutral || root.isNeutralContainer)
                    ? Appearance.colors.colSurfaceContainerHighestActive
                    : Appearance.colors.colTertiaryContainerActive

    // Solid accent: badges, filled plates, progress strokes.
    readonly property color colAccent: root.isAlert
        ? Appearance.colors.colError
        : (root.isPrimary || root.isPrimaryContainer)
            ? Appearance.colors.colPrimary
            : (root.isSecondary || root.isSecondaryContainer)
                ? Appearance.colors.colSecondary
                : (root.isNeutral || root.isNeutralContainer)
                    ? Appearance.colors.colSecondary
                    : Appearance.colors.colTertiary

    readonly property color colOnAccent: root.isAlert
        ? Appearance.colors.colOnError
        : (root.isPrimary || root.isPrimaryContainer)
            ? Appearance.colors.colOnPrimary
            : (root.isSecondary || root.isSecondaryContainer)
                ? Appearance.colors.colOnSecondary
                : (root.isNeutral || root.isNeutralContainer)
                    ? Appearance.colors.colOnSecondary
                    : Appearance.colors.colOnTertiary

    readonly property color colAccentHover: root.isAlert
        ? Appearance.colors.colErrorHover
        : (root.isPrimary || root.isPrimaryContainer)
            ? Appearance.colors.colPrimaryHover
            : (root.isSecondary || root.isSecondaryContainer)
                ? Appearance.colors.colSecondaryHover
                : (root.isNeutral || root.isNeutralContainer)
                    ? Appearance.colors.colSecondaryHover
                    : Appearance.colors.colTertiaryHover

    readonly property color colAccentActive: root.isAlert
        ? Appearance.colors.colErrorActive
        : (root.isPrimary || root.isPrimaryContainer)
            ? Appearance.colors.colPrimaryActive
            : (root.isSecondary || root.isSecondaryContainer)
                ? Appearance.colors.colSecondaryActive
                : (root.isNeutral || root.isNeutralContainer)
                    ? Appearance.colors.colSecondaryActive
                    : Appearance.colors.colTertiaryActive

    // Typography painted directly on the bar background.
    readonly property color colBare: Appearance.colors.colOnLayer1
    readonly property color colBareAccent: (root.isNeutral || root.isNeutralContainer)
        ? Appearance.colors.colOnSurfaceVariant
        : root.colAccent
}
