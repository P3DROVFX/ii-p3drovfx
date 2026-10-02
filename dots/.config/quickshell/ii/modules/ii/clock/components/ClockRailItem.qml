import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One destination in the rail, built like the Notes rail row: an icon and a label, a
 * badge on the right, and the group shaped only at its ends. The rows facing the current
 * one round too, so the selection presses a notch into the group.
 */
RippleButton {
    id: root

    property bool expanded: true
    property real rowHeight: ClockStyle.rowHeight
    property real iconSize: Appearance.font.pixelSize.huge
    property real labelSize: Appearance.font.pixelSize.normal
    property string symbol: "circle"
    property string label: ""
    property string badge: ""
    property bool current: false
    property bool isFirst: false
    property bool isLast: false
    property bool prevIsCurrent: false
    property bool nextIsCurrent: false

    signal triggered()

    implicitHeight: root.rowHeight
    padding: 0
    toggled: root.current

    colBackground: ClockStyle.colRailRow
    colBackgroundHover: ClockStyle.colRailRowHover
    colBackgroundActive: ClockStyle.colRailRowActive
    colBackgroundToggled: ClockStyle.colPrimary
    colBackgroundToggledHover: ClockStyle.colPrimaryHover
    colBackgroundToggledActive: ClockStyle.colPrimaryActive

    onClicked: root.triggered()

    scale: root.down ? 0.95 : (root.hovered ? 1.02 : 1)
    Behavior on scale {
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    readonly property real pillRadius: Math.min(root.implicitHeight / 2, ClockStyle.radiusLarge)
    readonly property real endRadius: ClockStyle.radiusLarge
    readonly property real joinRadius: Appearance.rounding.verysmall
    readonly property bool topIsPill: root.current || root.down || root.prevIsCurrent
    readonly property bool bottomIsPill: root.current || root.down || root.nextIsCurrent

    topLeftRadius: root.topIsPill ? root.pillRadius : (root.isFirst ? root.endRadius : root.joinRadius)
    topRightRadius: root.topLeftRadius
    bottomLeftRadius: root.bottomIsPill ? root.pillRadius : (root.isLast ? root.endRadius : root.joinRadius)
    bottomRightRadius: root.bottomLeftRadius

    Behavior on topLeftRadius {
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }
    Behavior on bottomLeftRadius {
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    readonly property color colText: root.current ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.expanded ? 18 : 0
            anchors.rightMargin: root.expanded ? 12 : 0
            spacing: 12

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: !root.expanded
                horizontalAlignment: Text.AlignHCenter
                text: root.symbol
                iconSize: root.iconSize
                fill: root.current ? 1 : 0
                color: root.colText

                Behavior on fill {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                visible: root.expanded
                text: root.label
                elide: Text.ElideRight
                font.pixelSize: root.labelSize
                font.weight: root.current ? Font.DemiBold : Font.Normal
                color: root.colText
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: root.expanded && root.badge.length > 0
                implicitWidth: Math.max(24, badgeText.implicitWidth + 12)
                implicitHeight: 24
                radius: ClockStyle.radiusFull
                color: root.current ? Qt.rgba(1, 1, 1, 0.18) : ClockStyle.colSecondaryContainer

                StyledText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.badge
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: root.current ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                }
            }
        }

        // Collapsed, the badge shrinks to a dot on the icon's corner: the rail still says
        // "something is running here" without the room to say how much.
        Rectangle {
            visible: !root.expanded && root.badge.length > 0
            width: 8
            height: 8
            radius: 4
            x: parent.width / 2 + 10
            y: parent.height / 2 - 14
            color: root.current ? ClockStyle.colOnPrimary : ClockStyle.colPrimary
        }
    }

    StyledToolTip {
        text: root.label
        extraVisibleCondition: !root.expanded
    }
}
