pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * The mode's colour: one swatch per palette key, the theme colour first. The chosen one
 * squares off and carries a check — the clock's day chips answer the same way — so the
 * pick reads by shape, not only by a ring that disappears on a dark swatch.
 *
 * The swatches wrap when the row is narrower than all of them; `oneLineWidth` is the
 * width that keeps them on one line.
 */
Flow {
    id: root

    property string current: ""
    /// Ring colour around the chosen swatch; the surface the dots sit on decides it.
    property color colRing: ClockStyle.colOnSurface
    readonly property real oneLineWidth: ModeUi.paletteKeys.length * 30 + (ModeUi.paletteKeys.length - 1) * root.spacing

    signal picked(string key)

    Layout.preferredWidth: root.oneLineWidth
    spacing: ClockStyle.gapTiny + 2

    Repeater {
        model: ModeUi.paletteKeys

        delegate: MouseArea {
            id: dot

            required property string modelData
            readonly property bool isCurrent: dot.modelData === root.current

            implicitWidth: 30
            implicitHeight: 30
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.picked(dot.modelData)

            StyledToolTip {
                extraVisibleCondition: dot.containsMouse
                text: ModeUi.paletteLabel(dot.modelData)
            }

            Rectangle {
                anchors.centerIn: parent
                width: dot.isCurrent ? 30 : (dot.containsMouse ? 26 : 22)
                height: width
                radius: dot.isCurrent ? ClockStyle.radiusSmall - 2 : width / 2
                color: ModeUi.swatch(dot.modelData)
                border.width: dot.isCurrent ? 2 : 0
                border.color: root.colRing

                Behavior on width {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
                Behavior on radius {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: dot.isCurrent
                    text: "check"
                    iconSize: 16
                    color: ModeUi.onAccent(dot.modelData)
                }
            }
        }
    }
}
