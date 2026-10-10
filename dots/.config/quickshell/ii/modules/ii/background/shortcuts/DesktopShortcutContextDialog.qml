pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
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
    iconSource: DesktopShortcuts.iconSource(entry.icon, entry.type === "group" ? "folder-applications"
        : entry.type === "directory" ? "folder" : "text-x-generic")

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
        { id: "rename", text: Translation.tr("Rename"), icon: "edit", submenu: true, enabled: root.writable },
        { id: "icon", text: Translation.tr("Change icon"), icon: "image", submenu: true,
            visible: entry.type === "directory", enabled: root.writable },
        { id: "details", text: Translation.tr("Details"), icon: "info", submenu: true },
        { id: "reveal", text: Translation.tr("Show in folder"), icon: "folder_open", visible: entry.path !== "" },
        { id: "copy", text: Translation.tr("Copy"), icon: "content_copy", submenu: true,
            visible: entry.name !== "" || entry.path !== "" },
        { id: "arrange", text: Translation.tr("Arrange selection"), icon: "align_horizontal_left",
            submenu: true, visible: root.selectionCount > 1, enabled: root.writable },
        { id: "screen", text: root.selectionCount > 1 ? Translation.tr("Move selection to screen")
            : Translation.tr("Move to screen"), icon: "screen_share",
            submenu: true, visible: root.otherScreens.length > 0, enabled: root.writable },
        { id: "remove", text: root.selectionCount > 1 ? Translation.tr("Move selected to trash")
            : Translation.tr("Move to trash"), icon: "delete",
            destructive: true, enabled: root.writable }
    ].filter(action => action.visible !== false)
    pageComponent: page === "rename" ? renamePage : page === "members" ? membersPage
        : page === "add" ? addPage : page === "member" ? memberPage : page === "details" ? detailsPage
        : page === "icon" ? iconPage : page === "copy" ? copyPage
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
        } else {
            root.page = actionId;
        }
    }

    // The folder's new picture is picked the way this shell picks images
    // everywhere else: the XDG portal helper the banner and profile pickers
    // use, which prints the chosen path - and nothing at all when the person
    // backs out. Its own Process, like theirs; what it prints goes into the
    // shortcut, not into a config key.
    Process {
        id: imagePicker
        function pick(): void {
            if (imagePicker.running)
                return;
            const args = ["python3", Directories.scriptPath + "/image_picker.py",
                "--title", Translation.tr("Choose an image for this folder"),
                "--filters", JSON.stringify([Translation.tr("Images (*.png *.jpg *.jpeg *.webp *.svg *.gif *.bmp *.avif)")])];
            if (root.entry.path)
                args.push("--folder", "file://" + root.entry.path);
            imagePicker.command = args;
            imagePicker.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                DesktopShortcuts.setIcon(root.screenName, root.entry.id, JSON.parse(text));
            }
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
        // The name without its extension, the part a rename is about.
        function focusStem(isFile: bool): void {
            fieldInput.forceActiveFocus();
            const dot = fieldInput.text.lastIndexOf(".");
            if (isFile && dot > 0)
                fieldInput.select(0, dot);
            else
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

    // The three copies behind one row: the name, the path, the file itself.
    // A copy answers in place (the row turns into "Copied") before the menu
    // goes, like the old top-level rows did.
    Component {
        id: copyPage
        ColumnLayout {
            id: copyColumn
            spacing: 3
            readonly property var copies: [
                { id: "copyName", text: Translation.tr("Copy name"), icon: "badge", visible: root.entry.name !== "" },
                { id: "copyPath", text: Translation.tr("Copy path"), icon: "content_paste", visible: root.entry.path !== "" },
                { id: "copyItem", text: Translation.tr("Copy file"), icon: "file_copy", visible: root.entry.path !== "" }
            ].filter(copy => copy.visible)
            PageHeader { title: Translation.tr("Copy") }
            Repeater {
                model: copyColumn.copies
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    readonly property bool done: modelData.id === root.doneId
                    first: index === 0
                    last: index === copyColumn.copies.length - 1
                    symbol: done ? "check" : modelData.icon
                    title: done ? root.doneText : modelData.text
                    selected: done
                    onActivated: {
                        if (root.doneId !== "")
                            return;
                        if (modelData.id === "copyName")
                            root.copyText(root.entry.name || "");
                        else if (modelData.id === "copyPath")
                            root.copyText(root.entry.path || "");
                        else
                            root.copyItemReference();
                        root.confirmCopy(modelData.id);
                    }
                }
            }
        }
    }
    Component {
        id: renamePage
        ColumnLayout {
            spacing: 3
            PageHeader { title: Translation.tr("Rename") }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.bottomMargin: 4
                text: Translation.tr("Renames the item on the desktop")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            MenuField {
                id: renameField
                Layout.bottomMargin: 3
                text: root.entry.name || ""
                inputEnabled: root.writable
                onAccepted: saveName.activated()
                Component.onCompleted: renameField.focusStem(root.entry.type === "file")
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
    // A folder's own picture. The shortcut only remembers the path - the
    // file stays where it is - and the plate above redraws the moment the
    // store moves, so a pick is answered in place and the way back to the
    // theme's icon sits one row under it.
    Component {
        id: iconPage
        ColumnLayout {
            spacing: 3
            readonly property bool picked: DesktopShortcuts.isIconPath(root.entry.icon)
            PageHeader { title: Translation.tr("Folder icon") }
            MenuRow {
                first: true
                last: !iconPage.picked
                symbol: "image_search"
                title: Translation.tr("Choose an image…")
                subtitle: iconPage.picked ? String(root.entry.icon) : ""
                rowEnabled: root.writable
                onActivated: imagePicker.pick()
            }
            MenuRow {
                visible: iconPage.picked
                first: false
                last: true
                symbol: "restart_alt"
                title: Translation.tr("Use the theme's folder icon")
                rowEnabled: root.writable
                onActivated: DesktopShortcuts.setIcon(root.screenName, root.entry.id, "")
            }
            StyledText {
                Layout.fillWidth: true
                Layout.margins: 12
                Layout.topMargin: 4
                text: Translation.tr("Any image file can stand in for this folder's icon")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
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
                    iconSource: DesktopShortcuts.iconSource(modelData.icon, "image-missing")
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

                TouchpadScrollHandler {
                    flickable: appList
                }
                delegate: EditPanelRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    hostRadius: Appearance.rounding.windowRounding
                    hostPadding: 8
                    first: index === 0
                    last: index === appList.count - 1
                    title: modelData.name
                    iconSource: DesktopShortcuts.iconSource(modelData.icon, "image-missing")
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
    // What the filesystem knows about the item, read once when the page opens:
    // one shell pass printing key=value lines (see `info`). Folders also get
    // their total size, bounded by a timeout so a huge tree cannot hold the
    // page; the size row then says it was not measured.
    Component {
        id: detailsPage
        ColumnLayout {
            id: details
            spacing: 3
            property var info: ({})
            property bool loaded: root.entry.path === ""
            readonly property bool isDir: root.entry.type === "directory"
            readonly property bool isGroup: root.entry.type === "group"

            function bytes(n) {
                n = Number(n);
                if (!isFinite(n))
                    return "";
                const units = ["B", "KB", "MB", "GB", "TB"];
                let i = 0;
                while (n >= 1024 && i < units.length - 1) {
                    n /= 1024;
                    i++;
                }
                return (i === 0 ? String(n) : n.toFixed(n >= 100 ? 0 : n >= 10 ? 1 : 2)) + " " + units[i];
            }
            function exact(n) {
                return Translation.tr("%1 bytes").arg(Number(n).toLocaleString(Qt.locale(), "f", 0));
            }
            function count(n) {
                return Number(n).toLocaleString(Qt.locale(), "f", 0);
            }
            function date(seconds) {
                const value = Number(seconds);
                if (!isFinite(value) || value <= 0)
                    return "";
                return new Date(value * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat);
            }
            function duration(seconds) {
                let total = Math.round(Number(seconds));
                if (!isFinite(total) || total <= 0)
                    return "";
                const h = Math.floor(total / 3600);
                const m = Math.floor((total % 3600) / 60);
                const sec = total % 60;
                const two = v => (v < 10 ? "0" : "") + v;
                return h > 0 ? `${h}:${two(m)}:${two(sec)}` : `${m}:${two(sec)}`;
            }
            function frameRate(fraction) {
                const parts = String(fraction ?? "").split("/");
                const rate = Number(parts[0]) / (Number(parts[1]) || 1);
                return isFinite(rate) && rate > 0 ? `${Math.round(rate * 100) / 100} fps` : "";
            }
            function kindName(kind) {
                const k = String(kind ?? "");
                if (k.startsWith("symbolic link"))
                    return Translation.tr("Link");
                if (k === "directory")
                    return Translation.tr("Folder");
                if (k.startsWith("regular"))
                    return Translation.tr("File");
                return k.charAt(0).toUpperCase() + k.slice(1);
            }

            // The rows, as data: sections of { label, value, sub, long }. A
            // long value (a path, a description) goes under its label and may
            // wrap; a short one sits at the row's end.
            readonly property var sections: {
                const i = details.info;
                const out = [];
                const section = (title, rows) => {
                    const kept = rows.filter(row => row && row.value);
                    if (kept.length > 0)
                        out.push({ "title": title, "rows": kept });
                };
                const row = (label, value, sub, long) => ({
                    "label": label, "value": value ? String(value) : "", "sub": sub ?? "", "long": long === true
                });
                const e = root.entry;
                const dock = root.pinKey !== "";

                if (details.isGroup) {
                    section(Translation.tr("Group"), [
                        row(Translation.tr("Applications"), details.count((e.apps ?? []).length)),
                        row(Translation.tr("Layout"), e.stack ? Translation.tr("Stack") : Translation.tr("Group"))
                    ]);
                }

                const size = i.size !== undefined && i.size !== "" ? Number(i.size) : NaN;
                const disk = String(i.disk ?? "").split(" ");
                const onDisk = Number(disk[0]) * Number(disk[1]);
                const fs = String(i.fs ?? "").trim().split(/\s+/);
                const total = i.total !== undefined && i.total !== "" ? Number(i.total) : NaN;
                const desc = String(i.desc ?? "");
                // `file` also prints the print density ("density 72x72") of a JPEG.
                const dims = /(\d{2,6})\s*x\s*(\d{2,6})/.exec(desc.replace(/density \d+x\d+/g, ""));
                const isLink = i.link !== undefined;

                section(Translation.tr("General"), [
                    row(Translation.tr("Kind"), isLink ? Translation.tr("Link") + " · " + details.kindName(i.kind) : details.kindName(i.kind)),
                    row(Translation.tr("Content type"), i.mime),
                    row(details.isDir ? Translation.tr("Size on disk") : Translation.tr("Size"),
                        details.isDir ? (isFinite(total) ? details.bytes(total) : (i.kind ? Translation.tr("Not measured") : ""))
                            : (isFinite(size) ? details.bytes(size) : ""),
                        details.isDir ? (isFinite(total) ? details.exact(total) : "")
                            : (isFinite(size) ? details.exact(size) : "")),
                    row(Translation.tr("Space used"), !details.isDir && isFinite(onDisk) && onDisk > 0 ? details.bytes(onDisk) : ""),
                    row(Translation.tr("Description"), desc, "", true),
                    row(Translation.tr("Location"), e.path ? FileUtils.parentDirectory(e.path) : "", "", true),
                    row(Translation.tr("Link target"), i.link, "", true),
                    row(Translation.tr("Resolves to"), isLink && i.real !== i.link ? i.real : "", "", true)
                ]);

                if (details.isDir) {
                    section(Translation.tr("Contents"), [
                        row(Translation.tr("Folders"), i.folders !== undefined ? details.count(i.folders) : ""),
                        row(Translation.tr("Files"), i.files !== undefined ? details.count(i.files) : ""),
                        row(Translation.tr("Hidden items"), Number(i.hidden) > 0 ? details.count(i.hidden) : "")
                    ]);
                } else {
                    section(Translation.tr("Contents"), [
                        row(Translation.tr("Dimensions"), dims && String(i.mime ?? "").startsWith("image/") ? `${dims[1]} × ${dims[2]} px` : ""),
                        row(Translation.tr("Lines"), i.lines !== undefined ? details.count(i.lines) : ""),
                        row(Translation.tr("Words"), i.words !== undefined ? details.count(i.words) : ""),
                        row(Translation.tr("Characters"), i.chars !== undefined ? details.count(i.chars) : ""),
                        row(Translation.tr("Duration"), details.duration(i.f_duration)),
                        row(Translation.tr("Resolution"), i.v_width ? `${i.v_width} × ${i.v_height} px` : ""),
                        row(Translation.tr("Frame rate"), details.frameRate(i.v_r_frame_rate)),
                        row(Translation.tr("Video codec"), i.v_codec_name),
                        row(Translation.tr("Audio codec"), i.a_codec_name),
                        row(Translation.tr("Sample rate"), i.a_sample_rate ? `${Number(i.a_sample_rate) / 1000} kHz` : ""),
                        row(Translation.tr("Channels"), i.a_channels),
                        row(Translation.tr("Bit rate"), i.f_bit_rate ? `${Math.round(Number(i.f_bit_rate) / 1000)} kb/s` : "")
                    ]);
                }

                section(Translation.tr("Application"), [
                    row(Translation.tr("Description"), i.de_Comment, "", true),
                    row(Translation.tr("Command"), i.de_Exec, "", true),
                    row(Translation.tr("Categories"), String(i.de_Categories ?? "").split(";").filter(c => c).join(", "), "", true),
                    row(Translation.tr("Runs in terminal"), String(i.de_Terminal ?? "").toLowerCase() === "true" ? Translation.tr("Yes") : "")
                ]);

                section(Translation.tr("Dates"), [
                    row(Translation.tr("Modified"), details.date(i.mtime)),
                    row(Translation.tr("Opened"), details.date(i.atime)),
                    row(Translation.tr("Changed"), details.date(i.ctime)),
                    row(Translation.tr("Created"), details.date(i.btime))
                ]);

                section(Translation.tr("Access"), [
                    row(Translation.tr("Permissions"), i.permStr, i.perm ? String(i.perm) : ""),
                    row(Translation.tr("Owner"), i.owner),
                    row(Translation.tr("Group"), i.group)
                ]);

                section(Translation.tr("Storage"), [
                    row(Translation.tr("Filesystem"), fs[0] && fs[0] !== "" ? fs[0] : "", fs[1] ?? ""),
                    row(Translation.tr("Free space"), i.free ? details.bytes(i.free) : ""),
                    row(Translation.tr("Inode"), i.inode),
                    row(Translation.tr("Hard links"), Number(i.links) > 1 ? i.links : "")
                ]);

                section(Translation.tr("On the desktop"), [
                    row(Translation.tr("Screen"), root.screenName),
                    row(Translation.tr("Pinned to dock"), dock ? (root.dockPinned ? Translation.tr("Yes") : Translation.tr("No")) : "")
                ]);
                return out;
            }

            Process {
                id: infoProcess
                running: root.entry.path !== ""
                command: ["bash", "-c", details.script, "_", root.entry.path ?? ""]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const next = {};
                        for (const line of text.split("\n")) {
                            const at = line.indexOf("=");
                            if (at > 0 && next[line.substring(0, at)] === undefined)
                                next[line.substring(0, at)] = line.substring(at + 1).trim();
                        }
                        details.info = next;
                        details.loaded = true;
                    }
                }
            }
            readonly property string script: `p=$1
[ -e "$p" ] || [ -L "$p" ] || exit 0
st() { stat -c "$1" -- "$p" 2>/dev/null; }
echo "kind=$(st %F)"
echo "size=$(stat -L -c %s -- "$p" 2>/dev/null)"
echo "disk=$(stat -L -c '%b %B' -- "$p" 2>/dev/null)"
echo "perm=$(st %a)"; echo "permStr=$(st %A)"
echo "owner=$(st %U)"; echo "group=$(st %G)"
echo "atime=$(st %X)"; echo "mtime=$(st %Y)"; echo "ctime=$(st %Z)"; echo "btime=$(st %W)"
echo "inode=$(st %i)"; echo "links=$(st %h)"
echo "fs=$(df --output=fstype,source -- "$p" 2>/dev/null | tail -n1)"
echo "free=$(df -B1 --output=avail -- "$p" 2>/dev/null | tail -n1 | tr -d ' ')"
if [ -L "$p" ]; then echo "link=$(readlink -- "$p")"; echo "real=$(readlink -f -- "$p")"; fi
mime=$(file -b -L --mime-type -- "$p" 2>/dev/null); echo "mime=$mime"
echo "desc=$(file -b -L -- "$p" 2>/dev/null | cut -c1-200)"
if [ -d "$p" ]; then
  echo "folders=$(find "$p" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  echo "files=$(find "$p" -mindepth 1 -maxdepth 1 ! -type d 2>/dev/null | wc -l)"
  echo "hidden=$(find "$p" -mindepth 1 -maxdepth 1 -name '.*' 2>/dev/null | wc -l)"
  echo "total=$(timeout 3 du -sb -- "$p" 2>/dev/null | cut -f1)"
elif [ -f "$p" ]; then
  bytes=$(stat -L -c %s -- "$p" 2>/dev/null)
  case $mime in
    text/*|application/json|application/xml|application/x-shellscript|application/javascript)
      if [ "\${bytes:-0}" -lt 20000000 ]; then
        echo "lines=$(wc -l < "$p")"; echo "words=$(wc -w < "$p")"; echo "chars=$(wc -m < "$p")"
      fi ;;
  esac
  case $mime in
    video/*|audio/*)
      if command -v ffprobe >/dev/null 2>&1; then
        ffprobe -v error -show_entries format=duration,bit_rate -of default=nw=1 -- "$p" 2>/dev/null | sed 's/^/f_/'
        ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -of default=nw=1 -- "$p" 2>/dev/null | sed 's/^/v_/'
        ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=nw=1 -- "$p" 2>/dev/null | sed 's/^/a_/'
      fi ;;
  esac
fi
case $p in
  *.desktop)
    for k in Comment Exec Categories Terminal; do
      echo "de_$k=$(grep -m1 "^$k=" -- "$p" | cut -d= -f2-)"
    done ;;
esac`

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

            StyledFlickable {
                id: detailsFlick
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.preferredHeight: Math.min(380, detailsColumn.implicitHeight)
                visible: details.sections.length > 0
                contentWidth: width
                contentHeight: detailsColumn.implicitHeight
                clip: true
                ColumnLayout {
                    id: detailsColumn
                    width: detailsFlick.width
                    spacing: 3
                    Repeater {
                        model: details.sections
                        delegate: ColumnLayout {
                            id: sectionColumn
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 3
                            StyledText {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                Layout.leftMargin: 6
                                text: sectionColumn.modelData.title
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: sectionColumn.modelData.rows
                                delegate: MenuRow {
                                    required property var modelData
                                    required property int index
                                    first: index === 0
                                    last: index === sectionColumn.modelData.rows.length - 1
                                    title: modelData.label
                                    subtitle: modelData.long ? modelData.value : modelData.sub
                                    subtitleWrap: true
                                    valueText: modelData.long ? "" : modelData.value
                                }
                            }
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.margins: 12
                Layout.topMargin: 6
                visible: !details.loaded
                text: Translation.tr("Reading details…")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
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
