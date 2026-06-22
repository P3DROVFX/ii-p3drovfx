import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects

import qs.modules.ii.sidebarDashboard.quickToggles
import qs.modules.ii.sidebarDashboard.quickToggles.classicStyle

import qs.modules.ii.sidebarDashboard.bluetoothDevices
import qs.modules.ii.sidebarDashboard.nightLight
import qs.modules.ii.sidebarDashboard.volumeMixer
import qs.modules.ii.sidebarDashboard.wifiNetworks
import qs.modules.ii.sidebarDashboard.darkMode
import qs.modules.ii.sidebarDashboard.localSend

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool showDarkModeDialog: false
    property bool showLocalSendDialog: false
    property bool editMode: false

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
                root.showDarkModeDialog = false;
                root.showLocalSendDialog = false;
            }
        }
    }

    Bar.BarThemes {
        id: barThemes
    }
    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    Loader {
        active: !GlobalStates.connectModeActive
        sourceComponent: Component {
            StyledRectangularShadow {
                target: sidebarRightBackground
            }
        }
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0
        border.width: GlobalStates.connectModeActive ? 0 : 1
        border.color: GlobalStates.connectModeActive ? "transparent" : Appearance.colors.colLayer0Border
        radius: GlobalStates.connectModeActive ? 0 : Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            SystemButtonRow {
                id: headerRow
                Layout.fillHeight: false
                Layout.fillWidth: true
                // Layout.margins: 10
                Layout.topMargin: 5
                Layout.bottomMargin: 0
            }


            LoaderedQuickPanelImplementation {
                id: classicQuickPanelLoader
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            LoaderedQuickPanelImplementation {
                id: androidQuickPanelLoader
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            CenterWidgetGroup {
                id: centerGroup
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
                visible: !root.editMode
            }

            Item {
                Layout.fillHeight: true
                visible: root.editMode
            }

            BottomWidgetGroup {
                id: bottomGroup
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                forceCollapsed: root.editMode
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown)
                return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showDarkModeDialog"
        dialog: DarkModeDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showLocalSendDialog"
        dialog: LocalSendDialog {}
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown)
            toggleDialogLoader.active = true
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false;
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString])
                    toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() {
                root.showAudioOutputDialog = true;
            }
            function onOpenAudioInputDialog() {
                root.showAudioInputDialog = true;
            }
            function onOpenBluetoothDialog() {
                root.showBluetoothDialog = true;
            }
            function onOpenNightLightDialog() {
                root.showNightLightDialog = true;
            }
            function onOpenWifiDialog() {
                root.showWifiDialog = true;
            }
            function onOpenDarkModeDialog() {
                root.showDarkModeDialog = true;
            }
            function onOpenLocalSendDialog() {
                root.showLocalSendDialog = true;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            readonly property int fullRadius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
            radius: fullRadius

            visible: Config.options.sidebar.dashboardHeader.profileImageType !== "none" || Config.options.sidebar.dashboardHeader.textMode !== "none"

            property int rowLeftMargin: Config.options.sidebar.dashboardHeader.profileImageType === "user_profile" ? 6 : 14

            implicitWidth: uptimeRow.implicitWidth + rowLeftMargin + 14
            implicitHeight: Math.max(32, uptimeRow.implicitHeight + (Config.options.sidebar.dashboardHeader.profileImageType === "user_profile" ? 4 : 12))

            Row {
                id: uptimeRow
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: uptimeContainer.rowLeftMargin
                }
                spacing: 8

                // PROFILE PICTURE
                Item {
                    id: profilePicContainer

                    anchors.verticalCenter: parent.verticalCenter
                    width: Config.options.sidebar.dashboardHeader.profileImageType === "distro" ? 24 : 40
                    height: Config.options.sidebar.dashboardHeader.profileImageType === "distro" ? 24 : 40
                    visible: Config.options.sidebar.dashboardHeader.profileImageType !== "none"

                    Loader {
                        anchors.fill: parent
                        active: Config.options.sidebar.dashboardHeader.profileImageType === "distro"
                        sourceComponent: CustomIcon {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            source: SystemInfo.distroIcon
                            colorize: true
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    Item {
                        anchors.fill: parent
                        visible: Config.options.sidebar.dashboardHeader.profileImageType === "user_profile"
                        
                        readonly property string _style: Config.options.userProfile.imageStyle
                        
                        // Custom
                        Item {
                            anchors.fill: parent
                            visible: parent._style === "custom"
                            Image {
                                id: profilePicSource
                                anchors.fill: parent
                                source: parent.visible ? Config.options.userProfile.imagePath : ""
                                sourceSize.width: parent.width
                                sourceSize.height: parent.height
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                            }
                            Rectangle {
                                id: profilePicMask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                            }
                            OpacityMask {
                                anchors.fill: parent
                                source: profilePicSource
                                maskSource: profilePicMask
                            }
                        }

                        // Initial
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            visible: parent._style === "initial" || parent._style === "default"

                            Image {
                                id: initialAvatarSource
                                anchors.fill: parent
                                source: parent.visible ? Directories.userAvatarPathAccountsService : ""
                                sourceSize.width:  parent.width
                                sourceSize.height: parent.height
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                            }
                            Rectangle {
                                id: initialAvatarMask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                            }
                            OpacityMask {
                                id: initialAvatarImage
                                anchors.fill: parent
                                source: initialAvatarSource
                                maskSource: initialAvatarMask
                                visible: initialAvatarSource.status === Image.Ready
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Appearance.colors.colPrimary
                                visible: initialAvatarSource.status !== Image.Ready

                                StyledText {
                                    anchors.centerIn: parent
                                    text: SystemInfo.username.charAt(0).toUpperCase()
                                    color: Appearance.colors.colOnPrimary
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        // Expressive
                        MaterialShape {
                            anchors.fill: parent
                            
                            function resolveShapeInner(s) {
                                switch(s) {
                                    case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided;
                                    case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided;
                                    case "Squircle":      return MaterialShape.Shape.Squircle;
                                    case "Circle":        return MaterialShape.Shape.Circle;
                                    case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf;
                                    case "Burst":         return MaterialShape.Shape.Burst;
                                    case "Heart":         return MaterialShape.Shape.Heart;
                                    case "Bun":           return MaterialShape.Shape.Bun;
                                    default:              return MaterialShape.Shape.Cookie9Sided;
                                }
                            }
                            shape: resolveShapeInner(Config.options.userProfile.avatarShape)
                            
                            property color resolvedColor: {
                                switch(Config.options.userProfile.avatarColor) {
                                    case "primary": return Appearance.colors.colPrimary;
                                    case "secondary": return Appearance.colors.colSecondary;
                                    case "tertiary": return Appearance.colors.colTertiary;
                                    case "error": return Appearance.colors.colError;
                                    default: return Appearance.colors.colPrimary;
                                }
                            }
                            property color resolvedOnColor: {
                                switch(Config.options.userProfile.avatarColor) {
                                    case "primary": return Appearance.colors.colOnPrimary;
                                    case "secondary": return Appearance.colors.colOnSecondary;
                                    case "tertiary": return Appearance.colors.colOnTertiary;
                                    case "error": return Appearance.colors.colOnError;
                                    default: return Appearance.colors.colOnPrimary;
                                }
                            }
                            
                            color: resolvedColor
                            visible: parent._style === "expressive"

                            StyledText {
                                anchors.centerIn: parent
                                text: {
                                    let n = Config.options.userProfile.customName || SystemInfo.username;
                                    return n.charAt(0).toUpperCase();
                                }
                                color: parent.resolvedOnColor
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.family: Appearance.font.family.expressive
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    visible: Config.options.sidebar.dashboardHeader.textMode !== "none"
                    
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colOnLayer0
                        text: {
                            const mode = Config.options.sidebar.dashboardHeader.textMode;
                            if (mode === "username") {
                                const greeting = Config.options.userProfile.customGreeting;
                                return (greeting !== "" ? greeting : Translation.tr("Hello,")) + " " + (Config.options.userProfile.customName !== "" ? Config.options.userProfile.customName : SystemInfo.username);
                            }
                            if (mode === "uptime") return Translation.tr("Uptime") + ": " + DateTime.uptime;
                            if (mode === "custom") return Config.options.sidebar.dashboardHeader.customText;
                            return "";
                        }
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        text: Config.options.userProfile.customBio
                        visible: Config.options.sidebar.dashboardHeader.textMode === "username" && text !== ""
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: 4

            QuickToggleButton {
                toggled: root.editMode
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nDrag handles to resize\nDrag icon to swap position") : "")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "reload"]);
                    Quickshell.reload(true);
                }
                StyledToolTip {
                    text: Translation.tr("Reload Hyprland & Quickshell")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    GlobalStates.toggleSettings();
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }

            QuickToggleButton {
                toggled: false
                buttonIcon: "power_settings_new"
                onClicked: {
                    GlobalStates.sessionOpen = true;
                }
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
