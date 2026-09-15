import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono

RowLayout {
    id: header
    required property var panel
    Layout.fillWidth: true
    spacing: 12

    Item {
        implicitWidth: 42
        implicitHeight: 42
        visible: Config.options.sidebar.dashboardHeader.profileImageType !== "none"

        Squircle {
            id: pfpSquircle
            anchors.fill: parent
            radius: 21
            smoothing: AkebonoAppearance.squircleSmoothing
            color: Appearance.colors.colSecondaryContainer
            // UserProfileAvatar already draws its own backing shape, so this
            // squircle only backs the distro icon and the bare person glyph.
            visible: Config.options.sidebar.dashboardHeader.profileImageType !== "user_profile"
        }

        Loader {
            anchors.fill: parent
            active: Config.options.sidebar.dashboardHeader.profileImageType === "distro"
            sourceComponent: CustomIcon {
                anchors.centerIn: parent
                width: parent.width - 8
                height: parent.height - 8
                source: SystemInfo.distroIcon
                colorize: true
                color: Appearance.colors.colOnLayer1
            }
        }

        UserProfileAvatar {
            anchors.fill: parent
            visible: Config.options.sidebar.dashboardHeader.profileImageType === "user_profile"
            avatarShape: Config.options.sidebar.dashboardHeader.avatarShape
            fontPixelSize: 20
            fontWeight: Font.Black
            borderWidth: 0
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "person"
            iconSize: 25
            color: Appearance.colors.colOnSecondaryContainer
            visible: Config.options.sidebar.dashboardHeader.profileImageType === "none"
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: -2
        StyledText {
            Layout.fillWidth: true
            text: SystemInfo.username
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            text: Battery.available
                ? `${Math.round(Battery.percentage * 100)}%${Battery.isCharging ? " ⚡" : ""} · ${DateTime.shortDate}`
                : DateTime.shortDate
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }
    RowLayout {
        spacing: 2

        ActionButton {
            size: 30
            iconSize: 19
            flat: true
            icon: "refresh"
            onClicked: Quickshell.reload(true)
        }
        ActionButton {
            size: 30
            iconSize: 19
            flat: true
            icon: "edit"
            active: header.panel.editMode
            onClicked: header.panel.editMode = !header.panel.editMode
            StyledToolTip {
                text: Translation.tr("Edit quick settings") + (!header.panel.editMode
                    ? ""
                    : (Config.options.akebono.shelf.quickSettings.style === "android"
                        ? Translation.tr("\nLMB to enable / disable\nDrag handles to resize\nDrag icon to swap position")
                        : Translation.tr("\nDrag to reorder")))
            }
        }
        ActionButton {
            size: 30
            iconSize: 19
            flat: true
            icon: "settings"
            onClicked: {
                GlobalStates.toggleSettings();
                header.panel.closeRequested();
            }
        }
        ActionButton {
            size: 30
            iconSize: 19
            flat: true
            icon: "power_settings_new"
            danger: true
            onClicked: {
                header.panel.closeRequested();
                GlobalStates.sessionOpen = true;
            }
        }
    }
}
