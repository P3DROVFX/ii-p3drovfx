import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.aiPlanUsage
import qs.services

/** Default style: two compact instruments inside the BarGroup surface. */
MouseArea {
    id: root

    property bool vertical: false

    readonly property bool hasVisibleQuota: AiPlanUsage.selectedItems.some(item => item.available !== false)
    readonly property bool shown: AiPlanUsage.enabled
        && (!(Config.options.bar.aiPlanUsage.hideWhenUnavailable ?? false) || root.hasVisibleQuota)

    visible: root.shown
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    implicitWidth: !root.shown ? 0 : (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : quotaContent.implicitWidth + 12)
    implicitHeight: !root.shown ? 0 : (root.vertical
        ? quotaContent.implicitHeight + 12
        : Appearance.sizes.baseBarHeight)

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        enabled: root.vertical
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    onClicked: AiPlanUsage.cycleProvider()

    AiQuotaTransition {
        id: quotaContent
        anchors.centerIn: parent
        vertical: root.vertical
        contentColor: Appearance.colors.colOnLayer1
    }

    AiPlanUsagePopup {
        hoverTarget: root
    }
}
