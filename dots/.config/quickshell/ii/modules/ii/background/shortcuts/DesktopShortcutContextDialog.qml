pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.editMode

ItemContextDialog {
    id: root
    required property var entry
    required property string screenName
    property string page: ""
    property string memberId: ""
    property string pendingAction: ""
    // >1 when the menu was opened on an icon inside a multi-selection: the
    // destructive action then speaks for the whole set, the rest for the
    // clicked entry alone.
    property int selectionCount: 1
    readonly property bool writable: Persistent.ready && !Persistent.blockWrites
    readonly property var member: (entry.apps ?? []).find(app => app.id === memberId) ?? null
    // Dock pinning. An app imported from a .desktop file carries the id
    // "desktop:<path>", which is nobody's desktop-entry id: the pin key is
    // then the filename itself, which normalizes to the same string the dock
    // uses for the installed entry. Folders pin by path. Everything else —
    // groups, plain files — has no dock identity and shows no row.
    readonly property string pinKey: entry.type === "app"
        ? (entry.path ? entry.path.substring(entry.path.lastIndexOf("/") + 1) : entry.id)
        : entry.type === "directory" ? entry.path : ""
    readonly property bool dockPinned: entry.type === "directory"
        ? TaskbarApps.isPinnedFile(entry.path)
        : entry.type === "app" ? TaskbarApps.isPinned(pinKey) : false

    title: entry.name || entry.id || ""
    subtitle: root.selectionCount > 1 ? Translation.tr("%1 items selected").arg(String(root.selectionCount))
        : entry.path || (entry.type === "group" ? Translation.tr("App group") : Translation.tr("Application"))
    iconSource: Quickshell.iconPath(entry.icon || (entry.type === "group" ? "folder-applications"
        : entry.type === "directory" ? "folder" : "text-x-generic"), "image-missing")

    // Windows-like contextual actions. The source stays untouched: the
    // clipboard receives data via wl-copy with single-quote escaping.
    function copyText(text) {
        if (!text)
            return;
        Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(text)}' | wl-copy`]);
    }
    function revealInFolder() {
        const target = root.entry.path;
        if (!target)
            return;
        if (root.entry.type === "directory")
            Quickshell.execDetached(["xdg-open", target]);
        else
            Quickshell.execDetached(["xdg-open", target.substring(0, target.lastIndexOf("/") + 1) || "/"]);
        root.dismiss();
    }
    // A paste into a file manager expects a URI list, matching how the dock
    // exports a file shortcut: encoded path.
    function copyItemReference() {
        const target = root.entry.path;
        if (!target)
            return;
        root.copyText("file://" + encodeURI(target).replace(/#/g, "%23").replace(/\?/g, "%3F"));
    }
    actions: [
        { id: "open", text: entry.type === "group" ? Translation.tr("Open group") : Translation.tr("Open"),
            icon: entry.type === "group" ? "apps" : "open_in_new", submenu: entry.type === "group" },
        { id: "pinDock", text: root.dockPinned ? Translation.tr("Unpin from dock")
            : Translation.tr("Pin to dock"), icon: "push_pin", filled: root.dockPinned,
            visible: root.pinKey !== "" },
        { id: "rename", text: Translation.tr("Rename shortcut"), icon: "edit", submenu: true, enabled: root.writable },
        { id: "details", text: Translation.tr("Details"), icon: "info", submenu: true },
        { id: "reveal", text: Translation.tr("Show in folder"), icon: "folder_open", visible: entry.path !== "" },
        { id: "copyName", text: Translation.tr("Copy name"), icon: "content_copy", visible: entry.name !== "" },
        { id: "copyPath", text: Translation.tr("Copy path"), icon: "content_paste", visible: entry.path !== "" },
        { id: "copyItem", text: Translation.tr("Copy"), icon: "file_copy", visible: entry.path !== "" },
        { id: "remove", text: root.selectionCount > 1 ? Translation.tr("Remove selected items")
            : Translation.tr("Remove from desktop"), icon: "remove_circle_outline",
            destructive: true, enabled: root.writable }
    ].filter(action => action.visible !== false)
    pageComponent: page === "rename" ? renamePage : page === "members" ? membersPage
        : page === "add" ? addPage : page === "member" ? memberPage : page === "details" ? detailsPage : null
    onBackRequested: root.back()
    function back() {
        root.page = root.page === "add" || root.page === "member" ? "members" : "";
    }
    function launch(item) {
        if (item.type === "file")
            Quickshell.execDetached(["xdg-open", item.path]);
        else
            DesktopShortcuts.launch(item);
        root.dismiss();
    }
    onActionTriggered: actionId => {
        if (actionId === "open") {
            if (root.entry.type === "group")
                root.page = "members";
            else
                root.launch(root.entry);
        } else if (actionId === "pinDock") {
            // The menu stays open: the row flips in place and the dock moves
            // behind it, so the toggle reads as live state, not a fired item.
            if (root.entry.type === "directory")
                TaskbarApps.togglePinnedFile(root.entry.path);
            else
                TaskbarApps.togglePin(root.pinKey);
        } else if (actionId === "remove") {
            root.pendingAction = "remove";
            root.dismiss();
        } else if (actionId === "reveal") {
            root.revealInFolder();
        } else if (actionId === "copyName") {
            root.copyText(root.entry.name || "");
            root.dismiss();
        } else if (actionId === "copyPath") {
            root.copyText(root.entry.path || "");
            root.dismiss();
        } else if (actionId === "copyItem") {
            root.copyItemReference();
            root.dismiss();
        } else {
            root.page = actionId;
        }
    }

    component BackButton: ContextActionButton {
        textLabel: Translation.tr("Back")
        symbol: "arrow_back"
        onClicked: root.back()
    }
    Component {
        id: renamePage
        ColumnLayout {
            spacing: 3
            BackButton {}
            // A title, not a row: section headings are plain large text
            // (EditPanelSectionLabel pattern), never clickable rows.
            EditPanelSectionLabel { text: Translation.tr("Name") }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: Translation.tr("Only the shortcut label changes")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: Math.max(Appearance.rounding.verysmall, Appearance.rounding.windowRounding - 6)
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: renameInput.activeFocus ? 2 : 1
                border.color: renameInput.activeFocus ? Appearance.m3colors.m3primary : Appearance.colors.colLayer0Border
                Behavior on border.color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                StyledTextInput {
                    id: renameInput
                    anchors.fill: parent
                    anchors.margins: 12
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.entry.name || ""
                    selectByMouse: true
                    clip: true
                    enabled: root.writable
                    Component.onCompleted: { forceActiveFocus(); selectAll(); }
                    onAccepted: saveName.clicked()
                }
            }
            ContextActionButton {
                id: saveName
                textLabel: Translation.tr("Save")
                symbol: "check"
                enabled: root.writable && renameInput.text.trim().length > 0
                onClicked: {
                    if (!enabled)
                        return;
                    DesktopShortcuts.rename(root.screenName, root.entry.id, renameInput.text);
                    root.page = "";
                }
            }
        }
    }
    Component {
        id: membersPage
        ColumnLayout {
            spacing: 3
            BackButton {}
            ContextActionButton {
                textLabel: Translation.tr("Add application")
                symbol: "add"
                submenu: true
                enabled: root.writable
                onClicked: root.page = "add"
            }
            StyledText {
                Layout.fillWidth: true
                Layout.margins: 12
                visible: (root.entry.apps ?? []).length === 0
                text: Translation.tr("No applications in this group")
                wrapMode: Text.Wrap
            }
            Repeater {
                model: root.entry.apps ?? []
                delegate: ContextActionButton {
                    required property var modelData
                    textLabel: modelData.name
                    iconSource: Quickshell.iconPath(modelData.icon, "image-missing")
                    submenu: true
                    onClicked: { root.memberId = modelData.id; root.page = "member"; }
                }
            }
        }
    }
    Component {
        id: memberPage
        ColumnLayout {
            spacing: 3
            BackButton {}
            ContextActionButton {
                textLabel: root.member?.name ?? ""
                symbol: "open_in_new"
                enabled: root.member !== null
                onClicked: root.launch(root.member)
            }
            ContextActionButton {
                textLabel: Translation.tr("Remove from group")
                symbol: "remove_circle_outline"
                destructive: true
                enabled: root.writable && root.member !== null
                onClicked: {
                    DesktopShortcuts.removeMember(root.screenName, root.entry.id, root.memberId);
                    root.page = "members";
                }
            }
        }
    }
    Component {
        id: addPage
        ColumnLayout {
            id: picker
            spacing: 6
            property string query: ""
            readonly property var applications: {
                const search = query.trim().toLowerCase();
                const existing = new Set((root.entry.apps ?? []).map(app => app.id));
                return Array.from(DesktopEntries.applications.values).filter(app => !app.noDisplay
                    && !existing.has(app.id) && (!search || app.name.toLowerCase().includes(search)));
            }
            BackButton {}
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
                StyledTextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.margins: 12
                    selectByMouse: true
                    clip: true
                    onTextEdited: picker.query = text
                    Component.onCompleted: forceActiveFocus()
                }
                StyledText {
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: !searchInput.text && !searchInput.activeFocus
                    text: Translation.tr("Search applications")
                    color: Appearance.colors.colSubtext
                }
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(260, contentHeight)
                clip: true
                reuseItems: true
                spacing: 3
                model: picker.applications
                delegate: ContextActionButton {
                    required property var modelData
                    width: ListView.view.width
                    textLabel: modelData.name
                    iconSource: Quickshell.iconPath(modelData.icon, "image-missing")
                    enabled: root.writable
                    onClicked: {
                        const app = DesktopShortcuts.application(modelData.id);
                        if (app) {
                            DesktopShortcuts.add(root.screenName, [app], root.entry.x, root.entry.y, root.entry.id);
                            root.page = "members";
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: picker.applications.length === 0
                text: Translation.tr("No applications found")
                wrapMode: Text.Wrap
            }
        }
    }
    Component {
        id: detailsPage
        ColumnLayout {
            spacing: 3
            BackButton { id: backRow; runContinues: true }
            // The item's identity as a static row of the same run: identical
            // geometry to a menu row (circle + two lines, 3px pitch) and the
            // run's own corners — top seam under the Back row, concentric end
            // corner at the bottom, both read from the row above so theme
            // rounding moves them together.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(52, detailsLayout.implicitHeight + 14)
                topLeftRadius: backRow.rSeam
                topRightRadius: backRow.rSeam
                bottomLeftRadius: backRow.rEnd
                bottomRightRadius: backRow.rEnd
                color: Appearance.m3colors.m3surfaceContainerHigh
                RowLayout {
                    id: detailsLayout
                    anchors.fill: parent
                    anchors.leftMargin: 7
                    anchors.rightMargin: 12
                    anchors.topMargin: 7
                    anchors.bottomMargin: 7
                    spacing: 12
                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: width / 2
                        color: Appearance.colors.colSurfaceContainerHighest
                        Image {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            sourceSize: Qt.size(26, 26)
                            source: root.iconSource
                            visible: source.toString().length > 0
                            fillMode: Image.PreserveAspectFit
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: root.iconSource.toString().length === 0
                            text: root.entry.type === "directory" ? "folder"
                                : root.entry.type === "file" ? "description" : "apps"
                            iconSize: 22
                            color: Appearance.m3colors.m3onSurface
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: root.entry.type === "group" ? Translation.tr("App group")
                                : root.entry.type === "directory" ? Translation.tr("Folder")
                                : root.entry.type === "file" ? Translation.tr("File") : Translation.tr("Application")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.entry.path || root.entry.id || ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }
        }
    }
}
