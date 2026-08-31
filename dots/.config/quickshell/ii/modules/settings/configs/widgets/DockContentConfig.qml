import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    property alias activeSubPage: subPageOverlay.activeSubPage

    function cleanDockFolderPath(path: string): string {
        let cleanPath = String(path ?? "").trim().replace(/^file:\/\//, "");
        try {
            cleanPath = decodeURIComponent(cleanPath);
        } catch (error) {
            // Keep the original path if a file manager returns malformed URI data.
        }
        if (cleanPath.length > 1)
            cleanPath = cleanPath.replace(/\/+$/, "");
        return cleanPath;
    }

    function addDockFolder(path: string) {
        const cleanPath = root.cleanDockFolderPath(path);
        if (cleanPath)
            TaskbarApps.addPinnedFile(cleanPath);
    }

    function removeDockFolder(index: int) {
        const folders = Array.from(Config.options.dock.pinnedFiles ?? []);
        if (index >= 0 && index < folders.length)
            TaskbarApps.removePinnedFile(folders[index]);
    }

    function moveDockFolder(index: int, direction: int) {
        const folders = Config.options.dock.pinnedFiles ?? [];
        const targetIndex = index + direction;
        if (targetIndex < 0 || targetIndex >= folders.length)
            return;
        TaskbarApps.reorderPinnedFileByIndex(index, targetIndex);
    }

    FolderDialog {
        id: dockFolderDialog
        title: Translation.tr("Choose a folder for the dock")
        currentFolder: "file://" + Quickshell.env("HOME")
        onAccepted: root.addDockFolder(selectedFolder.toString())
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Dock Content & Buttons")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Widgets & Buttons")
            icon: "widgets"
            tooltip: Translation.tr("Toggle the widgets and utility buttons visible on the dock.")

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: Translation.tr("Toggle the widgets and utility buttons visible on the dock.")
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "memory"
                text: Translation.tr("Adding more widgets to the dock increases CPU usage. Media and Live Preview are the most demanding, so enable only the widgets you need.")
            }

            GridLayout {
                id: dockButtonsGrid
                Layout.fillWidth: true
                columns: width >= Appearance.font.pixelSize.hugeass * 24 ? 3 : (width >= Appearance.font.pixelSize.hugeass * 16 ? 2 : 1)
                columnSpacing: 8
                rowSpacing: 8

                // Media Widget
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.enableMediaWidget
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.enableMediaWidget = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "play_circle"
                            iconSize: 20
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Media Widget")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                // Weather Widget
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.enableWeatherWidget
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.enableWeatherWidget = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "cloud"
                            iconSize: 20
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Weather Widget")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                // Sports Widget
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.enableSportsWidget ?? true
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.enableSportsWidget = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "sports_soccer"
                            iconSize: 20
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Sports Widget")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                // Live Preview Tile (com botão de navegação)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Appearance.rounding.normal
                    color: (Config.options.dock.enableLivePreviewWidget ?? false) ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8

                        RippleButton {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            buttonRadius: Appearance.rounding.normal
                            colBackground: "transparent"
                            colBackgroundHover: "transparent"
                            colRipple: "transparent"
                            onClicked: Config.options.dock.enableLivePreviewWidget = !(Config.options.dock.enableLivePreviewWidget ?? false)

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                MaterialSymbol {
                                    text: "live_tv"
                                    iconSize: 20
                                    fill: (Config.options.dock.enableLivePreviewWidget ?? false) ? 1 : 0
                                    color: (Config.options.dock.enableLivePreviewWidget ?? false) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Live Preview")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: (Config.options.dock.enableLivePreviewWidget ?? false)
                                    color: (Config.options.dock.enableLivePreviewWidget ?? false) ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                }
                            }
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: (Config.options.dock.enableLivePreviewWidget ?? false) ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: root.activeSubPage = Qt.resolvedUrl("DockLivePreviewConfig.qml")

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "settings"
                                iconSize: 16
                                color: (Config.options.dock.enableLivePreviewWidget ?? false) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                            }

                            StyledToolTip {
                                text: Translation.tr("Configure Live Preview settings")
                            }
                        }
                    }
                }

                // Phone Mirror
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.showPhoneButton ?? true
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.showPhoneButton = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "smartphone"
                            iconSize: 20
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Phone Mirror")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                // Notification Badges
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.showNotificationBadges
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.showNotificationBadges = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "notifications"
                            iconSize: 20
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Notification Badges")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                // Dividers
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.showDividers
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.showDividers = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "vertical_split"
                            iconSize: 20
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Dividers")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                // Overview Button
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.showOverviewButton
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.showOverviewButton = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "grid_view"
                            iconSize: 20
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Overview Button")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                // Pin Button
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.showPinButton
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.showPinButton = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "keep"
                            iconSize: 20
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Pin Button")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }

                // Trash Button
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    property bool active: Config.options.dock.showTrashButton
                    colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                    onClicked: Config.options.dock.showTrashButton = !active

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        MaterialSymbol {
                            text: "delete"
                            iconSize: 20
                            fill: parent.parent.active ? 1 : 0
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Trash Button")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: parent.parent.active
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }

                        MaterialSymbol {
                            text: parent.parent.active ? "check_circle" : "radio_button_unchecked"
                            iconSize: 18
                            color: parent.parent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }

        ContentSection {
            title: Translation.tr("Dock folders")
            icon: "folder_special"
            tooltip: Translation.tr("Add directories to the dock for quick access.")

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Add folders to the dock and choose their position.")
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                RippleButtonWithIcon {
                    mainText: Translation.tr("Add folder")
                    materialIcon: "create_new_folder"
                    colText: Appearance.colors.colOnPrimaryContainer
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    onClicked: dockFolderDialog.open()
                }
            }

            Item {
                Layout.fillWidth: true
                visible: (Config.options.dock.pinnedFiles ?? []).length === 0
                implicitHeight: visible ? 110 : 0

                PagePlaceholder {
                    anchors.fill: parent
                    shown: parent.visible
                    icon: "folder_off"
                    title: Translation.tr("No folders in the dock")
                    description: Translation.tr("Use Add folder to place a directory in the dock.")
                    shape: MaterialShape.Shape.Cookie7Sided
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: Config.options.dock.pinnedFiles ?? []

                    delegate: Rectangle {
                        id: dockFolderRow
                        required property string modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 60
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 10

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "folder"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colPrimary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const parts = dockFolderRow.modelData.split("/").filter(part => part.length > 0);
                                        return parts[parts.length - 1] ?? dockFolderRow.modelData;
                                    }
                                    color: Appearance.colors.colOnLayer2
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: dockFolderRow.modelData
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    elide: Text.ElideMiddle
                                }
                            }

                            RippleButtonWithIcon {
                                mainText: ""
                                materialIcon: "arrow_upward"
                                enabled: dockFolderRow.index > 0
                                opacity: enabled ? 1 : 0.4
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colText: Appearance.colors.colOnLayer2
                                colBackground: Appearance.colors.colLayer3
                                colBackgroundHover: Appearance.colors.colLayer3Hover
                                colRipple: Appearance.colors.colLayer3Active
                                onClicked: root.moveDockFolder(dockFolderRow.index, -1)

                                StyledToolTip {
                                    text: Translation.tr("Move folder up")
                                }
                            }

                            RippleButtonWithIcon {
                                mainText: ""
                                materialIcon: "arrow_downward"
                                enabled: dockFolderRow.index < (Config.options.dock.pinnedFiles ?? []).length - 1
                                opacity: enabled ? 1 : 0.4
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colText: Appearance.colors.colOnLayer2
                                colBackground: Appearance.colors.colLayer3
                                colBackgroundHover: Appearance.colors.colLayer3Hover
                                colRipple: Appearance.colors.colLayer3Active
                                onClicked: root.moveDockFolder(dockFolderRow.index, 1)

                                StyledToolTip {
                                    text: Translation.tr("Move folder down")
                                }
                            }

                            RippleButtonWithIcon {
                                mainText: ""
                                materialIcon: "close"
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colText: Appearance.colors.colOnErrorContainer
                                colBackground: Appearance.colors.colErrorContainer
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                colRipple: Appearance.colors.colErrorContainerActive
                                onClicked: root.removeDockFolder(dockFolderRow.index)

                                StyledToolTip {
                                    text: Translation.tr("Remove folder from dock")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
