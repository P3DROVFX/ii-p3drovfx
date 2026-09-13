import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.modes

/**
 * The island's mode banner: icon in the mode's colour, "Work mode on", and
 * why. Reads the same payload as the popup fallback.
 */
RowLayout {
    id: root
    anchors.fill: parent
    anchors.leftMargin: 12
    anchors.rightMargin: 14
    spacing: 10

    readonly property var payload: GlobalStates.modeFlashPayload
    readonly property string colorKey: root.payload?.color ?? ""

    MaterialShape {
        id: iconShape
        shapeString: "Cookie12Sided"
        color: ModeUi.container(root.colorKey)
        implicitWidth: Math.max(16, Math.min(32, root.height - 4))
        implicitHeight: Math.max(16, Math.min(32, root.height - 4))
        Layout.alignment: Qt.AlignVCenter

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.payload?.icon ?? "tune"
            iconSize: Math.max(10, Math.min(16, iconShape.implicitHeight - 16))
            fill: 1
            color: ModeUi.onContainer(root.colorKey)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: -2

        StyledText {
            Layout.fillWidth: true
            text: root.payload?.title ?? ""
            elide: Text.ElideRight
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }

        StyledText {
            Layout.fillWidth: true
            visible: (root.payload?.subtitle ?? "").length > 0
            text: root.payload?.subtitle ?? ""
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    onPayloadChanged: iconPulse.restart()

    SequentialAnimation {
        id: iconPulse
        NumberAnimation {
            target: iconShape
            property: "scale"
            to: 1.25
            duration: 120
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: iconShape
            property: "scale"
            to: 1.0
            duration: 220
            easing.type: Easing.OutBack
        }
    }
}
