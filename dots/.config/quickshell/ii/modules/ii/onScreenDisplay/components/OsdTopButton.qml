import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

RippleButton {
    id: button

    property string currentIndicator: "volume"
    property real expandedProgress: 0.0
    property real buttonHeight: 56

    property bool _muted: (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false

    rippleEnabled: true

    toggled: {
        if (currentIndicator === "brightness" || currentIndicator === "gamma")
            return Appearance.m3colors.darkmode;
        if (currentIndicator === "keyboardBrightness")
            return GlobalStates.oskOpen;
        return _muted;
    }

    buttonRadius: buttonHeight / 2

    // Color tokens standardized per Task C.1
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggled: Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
    colRipple: Appearance.colors.colSecondaryContainerActive
    colRippleToggled: Appearance.colors.colPrimaryActive

    readonly property string currentIcon: {
        if (currentIndicator === "brightness" || currentIndicator === "gamma") {
            return Appearance.m3colors.darkmode ? "dark_mode" : "light_mode";
        }
        if (currentIndicator === "keyboardBrightness") {
            return "keyboard";
        }
        return _muted ? "volume_off" : "volume_up";
    }

    readonly property string currentText: {
        if (currentIndicator === "brightness" || currentIndicator === "gamma") {
            return Appearance.m3colors.darkmode ? Translation.tr("Light mode") : Translation.tr("Dark mode");
        }
        if (currentIndicator === "keyboardBrightness") {
            return GlobalStates.oskOpen ? Translation.tr("Close keyboard") : Translation.tr("Open keyboard");
        }
        return _muted ? Translation.tr("Unmute output") : Translation.tr("Mute output");
    }

    readonly property color iconColor: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

    contentItem: RowLayout {
        spacing: 8 * button.expandedProgress
        anchors.fill: parent
        anchors.leftMargin: button.expandedProgress > 0.01 ? 16 : 0
        anchors.rightMargin: button.expandedProgress > 0.01 ? 16 : 0

        MaterialSymbol {
            id: buttonIcon
            text: button.currentIcon
            color: button.iconColor
            iconSize: Appearance.font.pixelSize.normal
            Layout.alignment: Qt.AlignVCenter | (button.expandedProgress > 0.01 ? Qt.AlignLeft : Qt.AlignHCenter)
        }

        StyledText {
            id: buttonText
            text: button.currentText
            color: button.iconColor
            font.pixelSize: Appearance.font.pixelSize.small
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            visible: button.expandedProgress > 0.5
            opacity: (button.expandedProgress - 0.5) * 2
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    onClicked: {
        if (currentIndicator === "brightness" || currentIndicator === "gamma") {
            if (Appearance.m3colors.darkmode) {
                DarkModeService.disableDarkMode();
            } else {
                DarkModeService.enableDarkMode();
            }
        } else if (currentIndicator === "keyboardBrightness") {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        } else {
            Audio.toggleMute();
        }
    }

    StyledToolTip {
        text: button.currentText
        extraVisibleCondition: button.hovered
    }
}
