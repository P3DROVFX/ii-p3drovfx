import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Rectangle {
    Layout.fillWidth: true
    implicitHeight: 64
    radius: Appearance.rounding.full
    color: LocalSend.serverRunning ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

    MaterialShape {
        shapeString: "Circle"
        implicitSize: 40
        color: LocalSend.serverRunning ? Appearance.colors.colPrimary : Appearance.colors.colError
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter; }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "devices"
            iconSize: Appearance.font.pixelSize.huge
            color: LocalSend.serverRunning ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary
            fill: 1
        }
    }

    RowLayout {
        anchors { left: parent.left; right: toggleBtn.left; verticalCenter: parent.verticalCenter; leftMargin: 64; rightMargin: 12 }

        StyledText {
            Layout.fillWidth: true
            text: LocalSend.serverRunning ? Translation.tr("LocalSend • Running") : Translation.tr("LocalSend • Stopped")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            font.weight: Font.Bold
            color: LocalSend.serverRunning ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            horizontalAlignment: Text.AlignHCenter
        }
    }

    RippleButton {
        id: toggleBtn
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        colBackground: LocalSend.serverRunning ? Appearance.colors.colPrimary : Appearance.colors.colSecondary
        colBackgroundHover: LocalSend.serverRunning ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryHover
        onClicked: {
            if (LocalSend.serverRunning) LocalSend.stopServer()
            else LocalSend.startServer()
        }
        MaterialSymbol {
            anchors {
                verticalCenter: parent.verticalCenter
                verticalCenterOffset: 1 // QML whyyy, why do you need this
                horizontalCenter: parent.horizontalCenter
            }
            text: LocalSend.serverRunning ? "stop_circle" : "play_circle"
            iconSize: Appearance.font.pixelSize.huge
            color: LocalSend.serverRunning ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary
            fill: 1
        }
    }
}
