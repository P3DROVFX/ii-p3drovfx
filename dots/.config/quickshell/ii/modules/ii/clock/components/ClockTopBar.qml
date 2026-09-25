import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** The app bar: where you are, in the expressive title face, and the actions for it. */
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool showBack: false
    default property alias actions: actionRow.data

    signal backRequested()

    implicitHeight: ClockStyle.topBarHeight

    RowLayout {
        anchors {
            fill: parent
            leftMargin: ClockStyle.gapSmall
            rightMargin: ClockStyle.gapSmall
        }
        spacing: ClockStyle.gapSmall

        ClockIconButton {
            visible: root.showBack
            symbol: "arrow_back"
            tooltip: Translation.tr("Back")
            onClicked: root.backRequested()
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.showBack ? 0 : ClockStyle.gapSmall
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textTitle + 4
                color: ClockStyle.colOnBackground
                animateChange: !ClockStyle.reducedMotion
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }

        RowLayout {
            id: actionRow
            spacing: ClockStyle.gapTiny
        }
    }
}
