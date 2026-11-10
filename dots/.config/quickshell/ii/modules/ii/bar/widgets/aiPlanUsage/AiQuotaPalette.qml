import QtQuick
import qs.modules.common
import qs.services

/** Provider accent pair for one quota window; switches to the error pair when it runs low. */
QtObject {
    id: root

    property var quota: null

    readonly property bool available: root.quota !== null && root.quota !== undefined
        && root.quota.available !== false
    readonly property bool low: AiPlanUsage.isLow(root.quota)
    readonly property string providerId: String(root.quota?.providerId ?? "")
    readonly property string groupId: String(root.quota?.groupId ?? "")
    // 0 = primary, 1 = secondary, 2 = tertiary (same mapping as AiQuotaIndicator)
    readonly property int family: {
        if (root.providerId === "chatgpt")
            return 1;
        if (root.providerId === "claude")
            return 2;
        if (root.providerId === "antigravity" && root.groupId === "other")
            return 1;
        return 0;
    }

    readonly property color accent: !root.available ? Appearance.colors.colOnSurfaceVariant
        : root.low ? Appearance.colors.colError
        : [Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary][root.family]
    // "*Ink", not "on*": QML would read an `onX:` binding as a signal handler.
    readonly property color accentInk:!root.available ? Appearance.colors.colSurfaceContainer
        : root.low ? Appearance.colors.colOnError
        : [Appearance.colors.colOnPrimary, Appearance.colors.colOnSecondary, Appearance.colors.colOnTertiary][root.family]
    readonly property color container: !root.available ? Appearance.colors.colSurfaceContainerHighest
        : root.low ? Appearance.colors.colErrorContainer
        : [Appearance.colors.colPrimaryContainer, Appearance.colors.colSecondaryContainer,
            Appearance.colors.colTertiaryContainer][root.family]
    readonly property color containerInk:!root.available ? Appearance.colors.colOnSurfaceVariant
        : root.low ? Appearance.colors.colOnErrorContainer
        : [Appearance.colors.colOnPrimaryContainer, Appearance.colors.colOnSecondaryContainer,
            Appearance.colors.colOnTertiaryContainer][root.family]
}
