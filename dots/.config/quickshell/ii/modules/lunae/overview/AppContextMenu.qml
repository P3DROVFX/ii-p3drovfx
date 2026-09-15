pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland

import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var entry: null
    property bool showing: false
    property real boundsWidth: 0
    property real boundsHeight: 0
    property real clickX: 0
    property real clickY: 0
    property string activeView: ""

    visible: showing
    z: 100

    function show(entry, x, y) {
        root.entry = entry;
        root.activeView = "";
        root.clickX = x;
        root.clickY = y;
        root.showing = true;
        menuBg.forceActiveFocus();
    }

    function dismiss() {
        root.showing = false;
        root.activeView = "";
        root.entry = null;
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.showing
        onClicked: root.dismiss()
    }

    Rectangle {
        id: menuBg
        x: Math.min(Math.max(8, root.clickX), root.boundsWidth - width - 8)
        y: Math.min(Math.max(8, root.clickY), root.boundsHeight - contentLoader.implicitHeight - 8)
        width: 280
        implicitHeight: contentLoader.implicitHeight
        radius: Appearance.rounding.normal
        color: Config?.options.appearance.transparency.enable ?? false
            ? Qt.rgba(
                Appearance.colors.colLayer2Base.r,
                Appearance.colors.colLayer2Base.g,
                Appearance.colors.colLayer2Base.b,
                Math.max(0.8, 1 - Config.options.appearance.transparency.backgroundTransparency)
            )
            : Appearance.colors.colLayer2
        clip: true
        scale: root.showing ? 1 : 0.9
        opacity: root.showing ? 1 : 0
        transformOrigin: Item.TopLeft

        Behavior on x { enabled: root.showing; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: root.showing; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (root.activeView !== "")
                    root.activeView = "";
                else
                    root.dismiss();
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: contentLoader
            width: parent.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.topMargin: 8
                spacing: 10

                IconImage {
                    source: root.entry?.iconName ? Quickshell.iconPath(root.entry.iconName, "image-missing") : ""
                    implicitSize: 24
                    visible: root.entry?.iconType === LauncherSearchResult.IconType.System
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.activeView === "" ? (root.entry?.name ?? "")
                        : root.activeView === "launch" ? Translation.tr("Launch")
                        : root.activeView === "workspace" ? Translation.tr("Open in workspace")
                        : Translation.tr("More options")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
            }

            MenuSeparator {}

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: root.activeView === ""

                ContextMenuItem {
                    iconName: "play_arrow"
                    label: Translation.tr("Launch")
                    onClicked: {
                        const de = root.entry?.id ? DesktopEntries.byId(root.entry.id) : null;
                        Qt.callLater(() => { GlobalStates.overviewOpen = false; });
                        if (de) de.execute();
                        else root.entry?.execute();
                    }
                }

                ContextMenuItem {
                    iconName: "more_horiz"
                    label: Translation.tr("Launch options")
                    hasSubmenu: true
                    onClicked: root.activeView = "launch"
                }

                ContextMenuItem {
                    visible: root.entry?.type === Translation.tr("App") && root.entry?.id
                    iconName: LauncherApps.isPinned(root.entry?.id ?? "") ? "heart_broken" : "favorite"
                    label: Translation.tr("Favourite")
                    onClicked: { LauncherApps.togglePin(root.entry.id); root.dismiss(); }
                }

                ContextMenuItem {
                    visible: root.entry?.type === Translation.tr("App") && root.entry?.id
                    iconName: TaskbarApps.isPinned(root.entry?.id ?? "") ? "keep_off" : "keep"
                    label: TaskbarApps.isPinned(root.entry?.id ?? "") ? Translation.tr("Unpin from dock") : Translation.tr("Pin to dock")
                    onClicked: { TaskbarApps.togglePin(root.entry.id); root.dismiss(); }
                }

                MenuSeparator {}

                ContextMenuItem {
                    visible: root.entry?.type === Translation.tr("App") && root.entry?.id
                    iconName: "visibility_off"
                    label: Translation.tr("Hide from launcher")
                    danger: true
                    onClicked: {
                        const currentHidden = Config.options.search.hiddenApps ?? [];
                        if (!currentHidden.includes(root.entry.id))
                            Config.options.search.hiddenApps = [...currentHidden, root.entry.id];
                        GlobalStates.overviewOpen = false;
                        root.dismiss();
                    }
                }

                ContextMenuItem {
                    visible: root.entry?.type === Translation.tr("App") && root.entry?.id
                    iconName: "desktop_windows"
                    label: Translation.tr("Open in workspace")
                    hasSubmenu: true
                    onClicked: root.activeView = "workspace"
                }

                MenuSeparator {}

                ContextMenuItem {
                    visible: root.entry?.type === Translation.tr("App") && root.entry?.id
                    iconName: "folder_open"
                    label: Translation.tr("Open .desktop file")
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", `/usr/share/applications/`]);
                        GlobalStates.overviewOpen = false;
                        root.dismiss();
                    }
                }

                ContextMenuItem {
                    visible: root.entry?.type === Translation.tr("App") && root.entry?.id
                    iconName: "more_horiz"
                    label: Translation.tr("More options")
                    hasSubmenu: true
                    onClicked: root.activeView = "more"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: root.activeView === "launch"

                ContextMenuItem {
                    iconName: "play_arrow"
                    label: Translation.tr("Launch")
                    onClicked: {
                        const de = root.entry?.id ? DesktopEntries.byId(root.entry.id) : null;
                        Qt.callLater(() => { GlobalStates.overviewOpen = false; });
                        if (de) de.execute();
                        else root.entry?.execute();
                    }
                }

                ContextMenuItem {
                    iconName: "terminal"
                    label: Translation.tr("Run in terminal")
                    onClicked: {
                        const de = DesktopEntries.byId(root.entry?.id ?? "");
                        if (de) Quickshell.execDetached(["bash", "-c", `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(de.command.join(" "))}'`]);
                        GlobalStates.overviewOpen = false;
                        root.dismiss();
                    }
                }

                Repeater {
                    model: (root.entry?.actions ?? []).filter(a => a.name !== Translation.tr("Copy") && a.name !== Translation.tr("Delete"))

                    ContextMenuItem {
                        required property var modelData
                        iconName: modelData.iconName ?? "open_in_new"
                        label: modelData.name ?? ""
                        onClicked: {
                            modelData.execute();
                            GlobalStates.overviewOpen = false;
                            root.dismiss();
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: root.activeView === "workspace"

                Repeater {
                    model: Hyprland.workspaces.values.filter(ws => ws.id > 0).sort((a, b) => a.id - b.id)

                    ContextMenuItem {
                        required property var modelData
                        iconName: "monitor"
                        label: `Workspace ${modelData.id}`
                        onClicked: {
                            const de = DesktopEntries.byId(root.entry?.id ?? "");
                            if (de) Hyprland.dispatch(`hl.dsp.exec("[workspace ${modelData.id} silent] ${de.command.join(" ")}")`);
                            GlobalStates.overviewOpen = false;
                            root.dismiss();
                        }
                    }
                }

                ContextMenuItem {
                    iconName: "add"
                    label: Translation.tr("New workspace")
                    onClicked: {
                        const de = DesktopEntries.byId(root.entry?.id ?? "");
                        if (de) {
                            const occupied = Hyprland.workspaces.values.map(ws => ws.id).filter(id => id > 0);
                            let next = 1;
                            while (occupied.includes(next)) next++;
                            Hyprland.dispatch(`hl.dsp.exec("[workspace ${next} silent] ${de.command.join(" ")}")`);
                        }
                        GlobalStates.overviewOpen = false;
                        root.dismiss();
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: root.activeView === "more"

                ContextMenuItem {
                    iconName: "admin_panel_settings"
                    label: Translation.tr("Run as root")
                    onClicked: {
                        const de = DesktopEntries.byId(root.entry?.id ?? "");
                        if (de) Quickshell.execDetached(["pkexec", ...de.command]);
                        GlobalStates.overviewOpen = false;
                        root.dismiss();
                    }
                }

                ContextMenuItem {
                    iconName: "content_copy"
                    label: Translation.tr("Copy app ID")
                    onClicked: { Quickshell.clipboardText = root.entry?.id ?? ""; root.dismiss(); }
                }

                ContextMenuItem {
                    iconName: "code"
                    label: Translation.tr("Copy exec command")
                    onClicked: {
                        const de = DesktopEntries.byId(root.entry?.id ?? "");
                        if (de) Quickshell.clipboardText = de.command.join(" ");
                        root.dismiss();
                    }
                }
            }

            ContextMenuItem {
                visible: root.activeView !== ""
                iconName: "chevron_left"
                label: Translation.tr("Back")
                isBack: true
                onClicked: root.activeView = ""
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 8 }
        }
    }

    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        color: Appearance.colors.colLayer2Hover
    }

    component ContextMenuItem: Item {
        id: menuItem
        property string iconName: ""
        property string label: ""
        property bool danger: false
        property bool hasSubmenu: false
        property bool isBack: false

        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 40 : 0

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            radius: Appearance.rounding.small
            color: itemMouse.containsMouse
                ? (menuItem.danger ? Qt.alpha(Appearance.colors.colError, 0.1) : Appearance.colors.colLayer2Hover)
                : "transparent"

            MouseArea {
                id: itemMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: menuItem.clicked()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                MaterialSymbol {
                    text: menuItem.iconName
                    iconSize: Appearance.font.pixelSize.large
                    color: menuItem.danger ? Appearance.colors.colError
                        : menuItem.isBack ? Appearance.colors.colSubtext
                        : Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: menuItem.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: menuItem.isBack ? Font.DemiBold : Font.Normal
                    color: menuItem.danger ? Appearance.colors.colError
                        : menuItem.isBack ? Appearance.colors.colSubtext
                        : Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    visible: menuItem.hasSubmenu
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
