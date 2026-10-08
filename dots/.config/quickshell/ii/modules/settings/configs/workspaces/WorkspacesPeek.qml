import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The workspace row kept in sight once the stage has scrolled away: a floating
 * pill that drops in from the top edge and says what is being tried on.
 */
Item {
    id: root

    required property WorkspacesPreviewState preview
    property bool shown: false
    property string caption: ""

    readonly property real pillHeight: 50
    readonly property real topMargin: 12
    readonly property real sidePadding: 10
    readonly property real unit: 24
    readonly property real hiddenLift: 24
    readonly property color colPill: Appearance.colors.colLayer0
    readonly property color colGroup: Appearance.colors.colLayer1

    implicitHeight: root.pillHeight + root.topMargin
    visible: pill.opacity > 0

    StyledRectangularShadow {
        target: pill
        opacity: pill.opacity
    }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.shown ? root.topMargin : -root.hiddenLift
        width: Math.min(parent.width - 32, row.implicitWidth + root.sidePadding * 2)
        height: root.pillHeight
        radius: height / 2
        color: root.colPill
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        opacity: root.shown ? 1 : 0
        Behavior on y {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10

            Rectangle {
                implicitWidth: strip.implicitWidth + 16
                implicitHeight: root.pillHeight - 10
                radius: height / 2
                color: root.colGroup

                WorkspacesLiveStrip {
                    id: strip
                    anchors.centerIn: parent
                    preview: root.preview
                    unit: root.unit
                    barColor: root.colGroup
                    interactive: true
                }
            }

            StyledText {
                visible: root.caption !== ""
                Layout.maximumWidth: 220
                Layout.rightMargin: 8
                text: root.caption
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
                elide: Text.ElideRight
            }
        }
    }
}
