import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.aiPlanUsage
import qs.services

/** Expressive style: a compact quota constellation on its own M3 capsule. */
MouseArea {
    id: root

    property bool vertical: false

    readonly property bool hasVisibleQuota: AiPlanUsage.selectedItems.some(item => item.available !== false)
    readonly property bool shown: AiPlanUsage.enabled
        && (!(Config.options.bar.aiPlanUsage.hideWhenUnavailable ?? false) || root.hasVisibleQuota)
    readonly property var displayProvider: AiPlanUsage.displayProviderById(AiPlanUsage.displayedProviderId)
    readonly property string providerId: String(root.displayProvider?.providerId ?? "")
    readonly property string groupId: String(root.displayProvider?.groupId ?? "")
    readonly property color containerColor: {
        if (root.providerId === "chatgpt")
            return Appearance.colors.colSecondaryContainer;
        if (root.providerId === "claude")
            return Appearance.colors.colTertiaryContainer;
        if (root.providerId === "antigravity" && root.groupId === "other")
            return Appearance.colors.colSecondaryContainer;
        return Appearance.colors.colPrimaryContainer;
    }
    readonly property color onContainerColor: {
        if (root.providerId === "chatgpt")
            return Appearance.colors.colOnSecondaryContainer;
        if (root.providerId === "claude")
            return Appearance.colors.colOnTertiaryContainer;
        if (root.providerId === "antigravity" && root.groupId === "other")
            return Appearance.colors.colOnSecondaryContainer;
        return Appearance.colors.colOnPrimaryContainer;
    }

    visible: root.shown
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    implicitWidth: !root.shown ? 0 : (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : capsule.implicitWidth)
    implicitHeight: !root.shown ? 0 : (root.vertical
        ? capsule.implicitHeight
        : Appearance.sizes.baseBarHeight)

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        enabled: root.vertical
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    onClicked: AiPlanUsage.cycleProvider()

    Rectangle {
        id: capsule
        anchors.centerIn: parent
        implicitWidth: root.vertical
            ? Appearance.sizes.verticalBarWidth - 6
            : constellation.implicitWidth + 14
        implicitHeight: root.vertical
            ? constellation.implicitHeight + 12
            : Appearance.sizes.baseBarHeight - 8
        radius: Config.options.bar.barGroupStyle === 1
            ? Appearance.rounding.windowRounding
            : Appearance.rounding.full
        color: root.containerColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        AiQuotaTransition {
            id: constellation
            anchors.centerIn: parent
            vertical: root.vertical
            useAccentForeground: true
            contentColor: root.onContainerColor
        }
    }

    AiPlanUsagePopup {
        hoverTarget: root
    }
}
