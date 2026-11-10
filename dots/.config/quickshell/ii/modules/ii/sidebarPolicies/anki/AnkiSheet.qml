import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A page over the tab (the sidebar is too narrow for a side sheet beside it, so the
 * sheet takes the full width, as the compact Clock does): title row with close, a
 * scrolling body of form rows, and the footer actions. Enters with a fade and a short
 * rise; Esc closes.
 */
Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    default property alias content: bodyColumn.data
    property alias footer: footerColumn.data

    signal dismissed()

    color: ClockStyle.colSheet
    radius: ClockStyle.radiusCard

    opacity: 0
    transform: Translate {
        id: rise
        y: ClockStyle.enterOffset
    }
    ParallelAnimation {
        id: entrance
        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: ClockStyle.motionEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        NumberAnimation {
            target: rise
            property: "y"
            to: 0
            duration: ClockStyle.motionEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
    Component.onCompleted: {
        if (ClockStyle.reducedMotion) {
            root.opacity = 1;
            rise.y = 0;
        } else {
            entrance.start();
        }
    }

    Keys.onEscapePressed: root.dismissed()

    // The sheet swallows clicks that land between its controls.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.gapLarge
        }
        spacing: ClockStyle.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textTitle
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    wrapMode: Text.Wrap
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colSubtext
                }
            }

            AnkiIconButton {
                Layout.alignment: Qt.AlignTop
                symbol: "close"
                tooltip: Translation.tr("Close (Esc)")
                onClicked: root.dismissed()
            }
        }

        StyledFlickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: bodyColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: bodyColumn
                width: flick.width
                spacing: ClockStyle.gapSmall
            }
        }

        ColumnLayout {
            id: footerColumn
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall
        }
    }
}
