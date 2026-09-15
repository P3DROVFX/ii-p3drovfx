import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/**
 * One place in the rail.
 *
 * Built to match the Cheatsheet's mail sidebar row: 56 high, an icon and a label at the
 * same size, a count as a round badge on the right, and the group shaped only at its ends.
 *
 * Two departures, both because this list is not that one. The pill radius is capped at the
 * `large` token instead of being a raw half-height — the Settings design system's rule,
 * and what stops a tall row from eating its own corners. And the rows facing the selected
 * one round as well, so the selection presses a notch into the group rather than floating
 * in a hole cut out of it.
 */
RippleButton {
    id: root

    property bool expanded: true
    property string symbol: "circle"
    property string label: ""
    property int count: 0
    property bool current: false

    property bool isFirst: false
    property bool isLast: false
    property bool prevIsCurrent: false
    property bool nextIsCurrent: false

    signal triggered()

    implicitHeight: NotesMetrics.rowHeight
    padding: 0
    toggled: root.current

    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundActive: Appearance.colors.colSecondaryContainerActive
    colBackgroundToggled: Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: Appearance.colors.colPrimaryActive

    onClicked: root.triggered()

    scale: root.down ? 0.95 : (root.hovered ? 1.02 : 1.0)
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    readonly property real pillRadius: NotesMetrics.pillRadius(root.implicitHeight)
    readonly property bool topIsPill: root.current || root.down || root.prevIsCurrent
    readonly property bool bottomIsPill: root.current || root.down || root.nextIsCurrent

    topLeftRadius: root.topIsPill ? root.pillRadius : (root.isFirst ? NotesMetrics.groupEndRadius : NotesMetrics.groupJoinRadius)
    topRightRadius: root.topLeftRadius
    bottomLeftRadius: root.bottomIsPill ? root.pillRadius : (root.isLast ? NotesMetrics.groupEndRadius : NotesMetrics.groupJoinRadius)
    bottomRightRadius: root.bottomLeftRadius

    Behavior on topLeftRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on bottomLeftRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    readonly property color colText: root.current
        ? Appearance.colors.colOnPrimary
        : Appearance.colors.colOnSurfaceVariant

    contentItem: Item {
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.expanded ? 20 : 0
            anchors.rightMargin: root.expanded ? 14 : 0
            spacing: 14

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: !root.expanded
                horizontalAlignment: Text.AlignHCenter
                text: root.symbol
                iconSize: Appearance.font.pixelSize.huge
                fill: root.current ? 1 : 0
                color: root.colText

                Behavior on fill {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.label
                visible: root.expanded
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: root.current ? Font.DemiBold : Font.Normal
                color: root.colText
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 26
                implicitHeight: 26
                radius: Appearance.rounding.full
                visible: root.expanded && root.count > 0
                color: root.current
                    ? Qt.rgba(1, 1, 1, 0.18)
                    : Appearance.colors.colSecondaryContainer
                antialiasing: true

                StyledText {
                    anchors.centerIn: parent
                    text: root.count
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: root.current
                        ? Appearance.colors.colOnPrimary
                        : Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }
    }

    StyledToolTip {
        text: root.label
        extraVisibleCondition: !root.expanded
    }
}
