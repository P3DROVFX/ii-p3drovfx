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
    // A copy answers in place before the menu goes: the row fills, its icon
    // turns into a check and its label says so, long enough to be read.
    function confirmCopy(id) {
        root.confirmAction(id, Translation.tr("Copied"));
        copiedDismiss.restart();
    }
    Timer {
        id: copiedDismiss
        interval: 850
        onTriggered: root.dismiss()
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
        { id: "pinDock", text: Translation.tr("Pinned to dock"), icon: "push_pin",
            toggle: true, checked: root.dockPinned, visible: root.pinKey !== "" },
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
    pageDepth: page === "" ? 0 : (page === "add" || page === "member" ? 2 : 1)
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
            root.confirmCopy(actionId);
        } else if (actionId === "copyPath") {
            root.copyText(root.entry.path || "");
            root.confirmCopy(actionId);
        } else if (actionId === "copyItem") {
            root.copyItemReference();
            root.confirmCopy(actionId);
        } else {
            root.page = actionId;
        }
    }

    // Every page opens with the menu's own header: the way back and the
    // page's title.
    component PageHeader: EditMenuPageHeader {
        Layout.bottomMargin: 4
        onBackRequested: root.back()
    }
    // A text field in the card's idiom: the pill a row would be, holding
    // the caret instead of a label.
    component MenuField: Rectangle {
        id: field
        property alias text: fieldInput.text
        property alias placeholder: fieldPlaceholder.text
        property alias inputEnabled: fieldInput.enabled
        signal accepted()
        signal textEdited()
        function focusField(selectAll: bool): void {
            fieldInput.forceActiveFocus();
            if (selectAll)
                fieldInput.selectAll();
        }
        Layout.fillWidth: true
        implicitHeight: 52
        radius: Math.max(Appearance.rounding.verysmall, Appearance.rounding.windowRounding - 8)
        color: Appearance.colors.colSurfaceContainerHigh
        border.width: fieldInput.activeFocus ? 2 : 0
        border.color: Appearance.m3colors.m3primary
        StyledTextInput {
            id: fieldInput
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            clip: true
            onAccepted: field.accepted()
            onTextEdited: field.textEdited()
        }
        StyledText {
            id: fieldPlaceholder
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            verticalAlignment: Text.AlignVCenter
            visible: fieldInput.text.length === 0
            color: Appearance.colors.colSubtext
        }
    }
    component MenuRow: EditPanelRow {
        Layout.fillWidth: true
        hostRadius: Appearance.rounding.windowRounding
        hostPadding: 8
        trailingKind: "none"
    }

    Component {
        id: renamePage
        ColumnLayout {
            spacing: 3
            PageHeader { title: Translation.tr("Rename shortcut") }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.bottomMargin: 4
                text: Translation.tr("Only the shortcut label changes")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            MenuField {
                id: renameField
                Layout.bottomMargin: 3
                text: root.entry.name || ""
                inputEnabled: root.writable
                onAccepted: saveName.activated()
                Component.onCompleted: renameField.focusField(true)
            }
            MenuRow {
                id: saveName
                symbol: "check"
                title: Translation.tr("Save")
                rowEnabled: root.writable && renameField.text.trim().length > 0
                onActivated: {
                    if (!rowEnabled)
                        return;
                    DesktopShortcuts.rename(root.screenName, root.entry.id, renameField.text);
                    root.page = "";
                }
            }
        }
    }
    Component {
        id: membersPage
        ColumnLayout {
            id: membersColumn
            spacing: 3
            readonly property var apps: root.entry.apps ?? []
            PageHeader { title: root.entry.name || Translation.tr("App group") }
            MenuRow {
                symbol: "add"
                title: Translation.tr("Add application")
                trailingKind: "chevron"
                first: true
                last: membersColumn.apps.length === 0
                rowEnabled: root.writable
                onActivated: root.page = "add"
            }
            Repeater {
                model: membersColumn.apps
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    title: modelData.name
                    iconSource: Quickshell.iconPath(modelData.icon, "image-missing")
                    trailingKind: "chevron"
                    first: false
                    last: index === membersColumn.apps.length - 1
                    onActivated: { root.memberId = modelData.id; root.page = "member"; }
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.margins: 12
                visible: membersColumn.apps.length === 0
                text: Translation.tr("No applications in this group")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }
    Component {
        id: memberPage
        ColumnLayout {
            spacing: 3
            PageHeader { title: root.member?.name ?? "" }
            MenuRow {
                first: true
                last: false
                symbol: "open_in_new"
                title: Translation.tr("Open")
                rowEnabled: root.member !== null
                onActivated: root.launch(root.member)
            }
            MenuRow {
                first: false
                last: true
                symbol: "remove_circle_outline"
                title: Translation.tr("Remove from group")
                destructive: true
                rowEnabled: root.writable && root.member !== null
                onActivated: {
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
            spacing: 3
            property string query: ""
            readonly property var applications: {
                const search = query.trim().toLowerCase();
                const existing = new Set((root.entry.apps ?? []).map(app => app.id));
                return Array.from(DesktopEntries.applications.values).filter(app => !app.noDisplay
                    && !existing.has(app.id) && (!search || app.name.toLowerCase().includes(search)));
            }
            PageHeader { title: Translation.tr("Add application") }
            MenuField {
                id: searchField
                Layout.bottomMargin: 3
                placeholder: Translation.tr("Search applications")
                onTextEdited: picker.query = searchField.text
                Component.onCompleted: searchField.focusField(false)
            }
            ListView {
                id: appList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, contentHeight)
                clip: true
                reuseItems: true
                spacing: 3
                model: picker.applications
                delegate: EditPanelRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    hostRadius: Appearance.rounding.windowRounding
                    hostPadding: 8
                    first: index === 0
                    last: index === appList.count - 1
                    title: modelData.name
                    iconSource: Quickshell.iconPath(modelData.icon, "image-missing")
                    trailingKind: "add"
                    rowEnabled: root.writable
                    onActivated: {
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
                Layout.margins: 12
                visible: picker.applications.length === 0
                text: Translation.tr("No applications found")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }
    Component {
        id: detailsPage
        ColumnLayout {
            spacing: 3
            PageHeader { title: Translation.tr("Details") }
            // The item's identity as a static pill of the row's geometry
            // (circle + two lines), a whole run on its own.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(58, detailsLayout.implicitHeight + 16)
                radius: Math.max(Appearance.rounding.verysmall, Appearance.rounding.windowRounding - 8)
                color: Appearance.colors.colSurfaceContainerHigh
                RowLayout {
                    id: detailsLayout
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
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
