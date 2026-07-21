import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

RippleButton {
    id: itemButton

    required property PwNode node
    readonly property bool isActive: Pipewire.defaultAudioSink ? (node.id === Pipewire.defaultAudioSink.id) : false

    Layout.fillWidth: true
    Layout.preferredHeight: 56
    buttonRadius: Appearance.rounding.normal
    rippleEnabled: true
    toggled: isActive

    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggled: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.35)
    colBackgroundToggledHover: ColorUtils.transparentize(Appearance.colors.colPrimaryHover, 0.35)
    colRipple: Appearance.colors.colSecondaryContainerActive
    colRippleToggled: Appearance.colors.colPrimaryActive

    contentItem: RowLayout {
        spacing: 12
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        MaterialSymbol {
            text: {
                if (itemButton.node && itemButton.node.audio && itemButton.node.audio.muted) {
                    return "volume_off";
                }
                let vol = (itemButton.node && itemButton.node.audio) ? itemButton.node.audio.volume : 0;
                if (vol === 0) return "volume_mute";
                if (vol <= 0.5) return "volume_down";
                return "volume_up";
            }
            iconSize: Appearance.font.pixelSize.normal
            color: itemButton.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            text: Audio.friendlyDeviceName(itemButton.node)
            font.pixelSize: Appearance.font.pixelSize.small
            font.bold: itemButton.isActive
            color: itemButton.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            Layout.fillWidth: true
            elide: Text.ElideRight
            Layout.alignment: Qt.AlignVCenter
        }
    }

    onClicked: {
        Audio.setDefaultSink(node);
    }

    StyledToolTip {
        text: Audio.friendlyDeviceName(itemButton.node)
        extraVisibleCondition: itemButton.hovered
    }
}
