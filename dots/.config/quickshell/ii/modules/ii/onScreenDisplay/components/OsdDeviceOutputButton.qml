import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../popups"

RippleButton {
    id: button

    property real buttonHeight: 56
    property var rootOsd // Reference to OSD root to call triggerOsd()

    Layout.fillWidth: true
    Layout.preferredHeight: buttonHeight
    buttonRadius: Appearance.rounding.normal
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colSecondaryContainerActive

    // Clip the painted button face to its allocated layout height during the OSD
    // expand/collapse animation (when the parent layout reserves less than the
    // natural buttonHeight). Without this, the full-size button overflows the
    // neighbouring elements below it in the column during the transition.
    clip: true

    contentItem: RowLayout {
        spacing: 12
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        MaterialSymbol {
            text: "media_output"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSecondaryContainer
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            StyledText {
                text: Translation.tr("Output device")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSecondaryContainer
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            StyledText {
                text: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.description) ? Pipewire.defaultAudioSink.description : ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3outline
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }

    onClicked: {
        deviceOutputPopup._clickActive = !deviceOutputPopup._clickActive;
        if (rootOsd) {
            rootOsd.triggerOsd();
        }
    }

    OsdDeviceOutputPopup {
        id: deviceOutputPopup
        hoverTarget: button
        keyboardFocus: WlrKeyboardFocus.Click
    }

    StyledToolTip {
        text: Translation.tr("Choose output device")
        extraVisibleCondition: button.hovered
    }
}
