pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The mode's colour: one dot per palette key, the theme colour first.
 */
RowLayout {
    id: root

    property string current: ""

    signal picked(string key)

    spacing: 6

    Repeater {
        model: ModeUi.paletteKeys

        delegate: MouseArea {
            id: dot

            required property string modelData
            readonly property bool isCurrent: dot.modelData === root.current

            implicitWidth: 26
            implicitHeight: 26
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.picked(dot.modelData)

            StyledToolTip {
                extraVisibleCondition: dot.containsMouse
                text: ModeUi.paletteLabel(dot.modelData)
            }

            Rectangle {
                anchors.centerIn: parent
                width: dot.isCurrent ? 26 : (dot.containsMouse ? 22 : 18)
                height: width
                radius: Appearance.rounding.full
                color: ModeUi.swatch(dot.modelData)
                border.width: dot.isCurrent ? 2 : 0
                border.color: Appearance.colors.colOnLayer1

                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: dot.isCurrent
                    text: "check"
                    iconSize: 14
                    color: ModeUi.onAccent(dot.modelData)
                }
            }
        }
    }
}
