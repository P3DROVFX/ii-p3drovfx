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
    // The ids the selection pages act on: the whole selection when the menu
    // opened on a selected icon, else the clicked one alone.
    property var selectedIds: []
    // Other outputs the icons can be sent to.
    readonly property var otherScreens: Quickshell.screens.filter(s => s.name !== root.screenName)
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
        { id: "arrange", text: Translation.tr("Arrange selection"), icon: "align_horizontal_left",
            submenu: true, visible: root.selectionCount > 1, enabled: root.writable },
        { id: "screen", text: root.selectionCount > 1 ? Translation.tr("Move selection to screen")
            : Translation.tr("Move to screen"), icon: "screen_share",
            submenu: true, visible: root.otherScreens.length > 0, enabled: root.writable },
        { id: "remove", text: root.selectionCount > 1 ? Translation.tr("Remove selected items")
            : Translation.tr("Remove from desktop"), icon: "remove_circle_outline",
            destructive: true, enabled: root.writable }
    ].filter(action => action.visible !== false)
    pageComponent: page === "rename" ? renamePage : page === "members" ? membersPage
        : page === "add" ? addPage : page === "member" ? memberPage : page === "details" ? detailsPage
        : page === "arrange" ? arrangePage : page === "screen" ? screenPage : null
    pageDepth: page === "" ? 0 : (page === "add" || page === "member" ? 2 : 1)
    onBackRequested: root.back()
    function back() {
        root.page = root.page === "add" || root.page === "member" ? "members" : "";
    }
    function launch(item) {
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
                visible: !root.entry.stack
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
                    first: index === 0 && !!root.entry.stack
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

    // A square tool button in the card's idiom, for the align strip.
    component ToolButton: Rectangle {
        id: tool
        property string symbol: ""
        property string tip: ""
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 48
        radius: Math.max(Appearance.rounding.verysmall, Appearance.rounding.windowRounding - 12)
        color: toolMouse.pressed ? Appearance.colors.colSurfaceContainerHighestActive
            : toolMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.colors.colSurfaceContainerHigh
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(tool)
        }
        MaterialSymbol {
            id: toolGlyph
            anchors.centerIn: parent
            text: tool.symbol
            iconSize: 22
            color: Appearance.m3colors.m3onSurface
            scale: toolMouse.pressed ? 0.85 : 1
            Behavior on scale {
                NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
            }
        }
        MouseArea {
            id: toolMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tool.clicked()
        }
        StyledToolTip {
            extraVisibleCondition: toolMouse.containsMouse && tool.tip !== ""
            text: tool.tip
        }
    }

    Component {
        id: arrangePage
        ColumnLayout {
            spacing: 3
            readonly property var ids: root.selectedIds
            PageHeader { title: Translation.tr("Arrange %1 items").arg(String(root.selectionCount)) }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.topMargin: 2
                text: Translation.tr("Align")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                columns: 3
                rowSpacing: 3
                columnSpacing: 3
                Repeater {
                    model: [
                        { mode: "left", symbol: "align_horizontal_left", tip: Translation.tr("Align left") },
                        { mode: "hcenter", symbol: "align_horizontal_center", tip: Translation.tr("Align centers horizontally") },
                        { mode: "right", symbol: "align_horizontal_right", tip: Translation.tr("Align right") },
                        { mode: "top", symbol: "align_vertical_top", tip: Translation.tr("Align top") },
                        { mode: "vcenter", symbol: "align_vertical_center", tip: Translation.tr("Align centers vertically") },
                        { mode: "bottom", symbol: "align_vertical_bottom", tip: Translation.tr("Align bottom") }
                    ]
                    delegate: ToolButton {
                        required property var modelData
                        symbol: modelData.symbol
                        tip: modelData.tip
                        onClicked: DesktopShortcuts.alignSelection(root.screenName, root.selectedIds, modelData.mode)
                    }
                }
            }
            MenuRow {
                first: true
                last: false
                symbol: "horizontal_distribute"
                title: Translation.tr("Distribute horizontally")
                onActivated: DesktopShortcuts.distributeSelection(root.screenName, root.selectedIds, "horizontal")
            }
            MenuRow {
                first: false
                last: false
                symbol: "vertical_distribute"
                title: Translation.tr("Distribute vertically")
                onActivated: DesktopShortcuts.distributeSelection(root.screenName, root.selectedIds, "vertical")
            }
            MenuRow {
                first: false
                last: false
                symbol: "view_agenda"
                title: Translation.tr("Stack in a column")
                onActivated: DesktopShortcuts.stackSelection(root.screenName, root.selectedIds, "column")
            }
            MenuRow {
                first: false
                last: !groupRow.visible
                symbol: "view_column"
                title: Translation.tr("Stack in a row")
                onActivated: DesktopShortcuts.stackSelection(root.screenName, root.selectedIds, "row")
            }
            MenuRow {
                id: groupRow
                first: false
                last: true
                visible: DesktopShortcuts.canGroup(root.screenName, root.selectedIds)
                symbol: "create_new_folder"
                title: Translation.tr("Group apps")
                onActivated: {
                    DesktopShortcuts.groupSelection(root.screenName, root.selectedIds);
                    root.dismiss();
                }
            }
        }
    }
    Component {
        id: screenPage
        ColumnLayout {
            spacing: 3
            PageHeader { title: Translation.tr("Move to screen") }
            Repeater {
                model: root.otherScreens
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    first: index === 0
                    last: index === root.otherScreens.length - 1
                    symbol: "monitor"
                    title: modelData.name
                    subtitle: modelData.model ?? ""
                    trailingKind: "chevron"
                    onActivated: {
                        const ids = root.selectedIds.length > 0 ? root.selectedIds : [root.entry.id];
                        const from = root.screenName;
                        const to = modelData.name;
                        root.dismiss();
                        Qt.callLater(() => DesktopShortcuts.moveToScreen(from, to, ids));
                    }
                }
            }
        }
    }
}
