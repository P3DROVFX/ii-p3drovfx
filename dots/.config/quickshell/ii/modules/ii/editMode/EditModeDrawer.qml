import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/**
 * Edit Mode's catalogue: the panel that slides in from the right of the card.
 *
 * Three sections. Widgets lists every desktop widget the registry knows - a
 * row is a click to add or remove, or a drag whose release places the widget
 * where the pointer is. Bar lists the bar components not already on the bar
 * and adds one to the picked bucket. Dock lists the apps the dock knows and
 * pins or unpins them.
 *
 * The drawer reports gestures and writes nothing: the surface that owns the
 * geometry turns a release into a canvas point, and every store write is made
 * there so the drawer can be laid out and reasoned about without one.
 */
Item {
    id: root

    property string screenName: ""
    // Where the drag ghost lives: an ancestor that is not clipped by the
    // drawer's reveal, so the ghost can follow the pointer out over the card.
    property Item ghostParent: null

    signal addRequested(string widgetId, real dropX, real dropY)
    signal toggleRequested(string widgetId)
    signal barAddRequested(string componentId, string bucket)
    signal barRemoveRequested(string componentId)
    // A bar component carried out of the catalogue: where the pointer is, in
    // the chrome's coordinates, for the surface to hand to that screen's bar.
    signal barDragMoved(string componentId, real x, real y)
    signal barDropRequested(string componentId, real x, real y)
    signal barDragCancelled()
    signal dockToggleRequested(string appId)
    signal lockLayoutResetRequested()

    // Held shell-wide (GlobalStates), not here: a right-click on the desktop or
    // the bar asks for a catalogue before the drawer that shows it exists, and
    // every screen's drawer shows the same one.
    readonly property string section: GlobalStates.editDrawerSection
    property var dragMetadata: null

    // ── The query ────────────────────────────────────────────────────────────
    // The dock's catalogue alone runs to two hundred rows. A query FLATTENS the
    // sections it filters: someone typing is after one row, not after where it
    // lives. The lock screen's six switches are not worth a search box.
    readonly property bool searchable: root.section !== "lock"
    property string query: ""
    readonly property string needle: root.query.trim().toLowerCase()
    readonly property bool searching: root.searchable && root.needle !== ""
    // Whether the chrome's surface has to hold the keyboard. It is None the
    // rest of the time, deliberately: the desktop's canvas answers Escape and
    // the arrows from another surface, and a chrome that takes focus swallows
    // them (see EditModeChromeSurface).
    //
    // Intent, NOT `searchField.activeFocus`: active focus needs an ACTIVE
    // window, a window is only active while the compositor gives its surface
    // the keyboard, and the surface only asks for the keyboard because of this
    // flag - reading activeFocus here is a deadlock that no click can break.
    // The field says when it wants the keyboard and says when it has lost it.
    property bool searchWanted: false
    property bool searchHeld: false
    readonly property bool searchFocused: root.searchWanted

    // Fuzzysort, the matcher the launcher already searches these same apps
    // with: "fx" finds Firefox, which a substring test never will, and the
    // results come back best-first. Targets are prepared where each catalogue
    // is built - preparing two hundred of them per keystroke is the shape that
    // made the launcher slow ([[launcher-perf-optimization]]).
    function prepared(title, id) {
        return Fuzzy.prepare(`${title ?? ""} ${id ?? ""} `);
    }
    function fuzzyPick(rows) {
        return Fuzzy.go(root.needle, rows, {
            "all": false,
            "key": "hay",
            "limit": 80,
            "threshold": 0.3
        }).map(result => result.obj);
    }

    function releaseSearchFocus() {
        root.searchWanted = false;
        root.searchHeld = false;
        searchField.focus = false;
    }

    function clearSearch() {
        searchField.text = "";
        root.releaseSearchFocus();
    }

    // Whether a point in the chrome's coordinates is on the field itself -
    // asked by the click-anywhere-else catcher, which must not fight the
    // field's own press or the clear button beside it.
    function pointInSearchField(x, y) {
        const from = root.ghostParent ?? root;
        const p = from.mapToItem(searchRow, x, y);
        return p.x >= 0 && p.y >= 0 && p.x <= searchRow.width && p.y <= searchRow.height;
    }


    onSectionChanged: root.clearSearch()

    // Ctrl+F, from the canvas. Only the screen being edited answers: every
    // screen draws a drawer, and the keyboard is on one of them.
    function focusSearch() {
        if (!root.searchable || root.screenName !== GlobalStates.editModeMonitor)
            return;
        root.searchWanted = true;
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    Connections {
        target: GlobalStates
        // Leaving takes the query with it: a drawer reopened on last week's
        // half-typed word is a drawer that looks broken.
        function onEditDrawerOpenChanged() {
            if (!GlobalStates.editDrawerOpen)
                root.clearSearch();
        }
        function onEditModeChanged() {
            if (!GlobalStates.editMode)
                root.clearSearch();
        }
        function onEditSearchFocusRequested() {
            root.focusSearch();
        }
        function onEditSearchReleaseRequested() {
            root.releaseSearchFocus();
        }
    }

    // A desktop widget carried back over this drawer: the release removes it.
    readonly property bool dropWouldRemove: root.screenName !== ""
        && GlobalStates.editDrawerDropScreen === root.screenName

    readonly property var activeWidgets: Config.options.background.activeWidgets ?? []
    readonly property var usedBarIds: {
        const layouts = Config.options.bar.layouts;
        const ids = [];
        for (const bucket of ["left", "center", "right"])
            for (const entry of (layouts[bucket] ?? []))
                if (entry && entry.id) ids.push(entry.id);
        return ids;
    }
    // Every bar component, not only the ones going spare: one already on the
    // bar is shown checked and clicks off again. Hiding them made the panel
    // silent about what the bar holds, and left the badge on the bar as the
    // only way to take anything off it.
    readonly property var barCatalogue: {
        const used = root.usedBarIds;
        return (BarComponentRegistry.allComponents ?? []).map(component => ({
            "component": component,
            "used": used.indexOf(component.id) !== -1,
            "hay": root.prepared(component.title, component.id)
        }));
    }
    readonly property var barRows: root.searching ? root.fuzzyPick(root.barCatalogue) : root.barCatalogue

    function widgetOnDesktop(widgetId) {
        return root.activeWidgets.some(entry => entry && entry.widgetId === widgetId);
    }

    // On the Lockscreen tab a row is "checked" when the widget shows on the
    // lock: any behaviour but hide.
    function widgetOnLock(widgetId) {
        return root.activeWidgets.some(entry => entry && entry.widgetId === widgetId
            && (entry.lockBehavior || "hide") !== "hide");
    }

    // The catalogue's sections, named and ordered as Settings names and orders
    // them. A category the registry hands out that is not listed here - an
    // extension's own - gets a section of its own at the end, so a widget can
    // never be added to the registry and then be missing from this list.
    readonly property var widgetCategoryOrder: [
        { "key": "Clock", "title": Translation.tr("Clocks"), "icon": "schedule" },
        { "key": "Media", "title": Translation.tr("Media players"), "icon": "play_circle" },
        { "key": "Weather", "title": Translation.tr("Weather"), "icon": "cloud" },
        { "key": "Date", "title": Translation.tr("Date & calendar"), "icon": "calendar_today" },
        { "key": "Photo", "title": Translation.tr("Photo"), "icon": "image" },
        { "key": "Devices", "title": Translation.tr("Devices & Bluetooth"), "icon": "earbuds", "merge": ["Bluetooth"] },
        { "key": "Utility", "title": Translation.tr("Utility"), "icon": "build" },
        { "key": "System", "title": Translation.tr("System"), "icon": "tune" },
        { "key": "Resources", "title": Translation.tr("Resources"), "icon": "monitor_heart" }
    ]

    readonly property var widgetGroups: {
        const groups = [];
        const byKey = {};
        for (const category of root.widgetCategoryOrder) {
            const group = { "key": category.key, "title": category.title, "icon": category.icon, "items": [] };
            groups.push(group);
            byKey[category.key] = group;
            for (const alias of (category.merge ?? []))
                byKey[alias] = group;
        }
        for (const widget of (WidgetsRegistry.allWidgets ?? [])) {
            const key = widget?.category ?? "";
            let group = byKey[key];
            if (!group) {
                group = {
                    "key": key === "" ? "other" : key,
                    "title": key === "" ? Translation.tr("Other") : key,
                    "icon": "widgets",
                    "items": []
                };
                byKey[key] = group;
                groups.push(group);
            }
            group.items.push(widget);
        }
        return groups.filter(group => group.items.length > 0);
    }

    // Every section shut on arrival, the way Settings opens its own widget
    // catalogue: the flat list runs to eighty-odd rows, and the point of a
    // section is not having to scroll past the ones you are not after.
    property var expandedWidgetGroups: []

    function widgetGroupExpanded(key) {
        return root.expandedWidgetGroups.indexOf(key) !== -1;
    }

    function toggleWidgetGroup(key) {
        // Reassigned rather than mutated: a list changed in place notifies
        // nobody, and the rows below are built from it.
        const next = root.expandedWidgetGroups.slice();
        const at = next.indexOf(key);
        if (at === -1)
            next.push(key);
        else
            next.splice(at, 1);
        root.expandedWidgetGroups = next;
    }

    function widgetGroupAdded(group) {
        let count = 0;
        for (const widget of group.items)
            if (root.lockTab ? root.widgetOnLock(widget.widgetId) : root.widgetOnDesktop(widget.widgetId))
                count++;
        return count;
    }

    // The flattened list a query searches, prepared once per catalogue rather
    // than per keystroke.
    readonly property var widgetSearchRows: {
        const rows = [];
        for (const group of root.widgetGroups)
            for (const widget of group.items)
                rows.push({
                    "kind": "widget",
                    "widget": widget,
                    "hay": root.prepared(widget.name, widget.widgetId)
                });
        return rows;
    }

    // One flat list of section headers and, under each open one, its widgets:
    // a list view can only be given rows, and collapsing by dropping the rows
    // costs nothing - a shut section has no delegates at all.
    readonly property var widgetRows: {
        if (root.searching)
            return root.fuzzyPick(root.widgetSearchRows);
        const rows = [];
        for (const group of root.widgetGroups) {
            rows.push({ "kind": "header", "group": group });
            if (!root.widgetGroupExpanded(group.key))
                continue;
            for (const widget of group.items)
                rows.push({ "kind": "widget", "widget": widget });
        }
        return rows;
    }

    // The dock's catalogue, in three sections for the three answers to "why is
    // this app in the list": it is on the dock, it is open right now, or it is
    // merely installed. Without the last one an app that is neither pinned nor
    // running could not be pinned at all - it had to be launched first.
    readonly property var dockGroups: {
        const pinnedIds = Config.options.dock.pinnedApps ?? [];
        const running = (TaskbarApps.apps ?? []).filter(app => app && !app.pinned && app.appId);
        const taken = {};
        for (const id of pinnedIds)
            taken[TaskbarApps.normalizeAppId(id)] = true;
        for (const app of running)
            taken[TaskbarApps.normalizeAppId(app.appId)] = true;
        const rest = Array.from(AppSearch.list ?? [])
            .filter(entry => entry && entry.id && !entry.noDisplay
                && !taken[TaskbarApps.normalizeAppId(entry.id)]);
        // The name is resolved HERE, once per catalogue, and carried on the
        // item: a heuristic lookup per row per keystroke over two hundred apps
        // is the exact cost the launcher had to have taken out of it.
        const item = (appId, pinned) => ({
            "appId": appId,
            "pinned": pinned,
            "name": root.appName(appId)
        });
        return [
            {
                "key": "pinned",
                "title": Translation.tr("On the dock"),
                "icon": "keep",
                "items": pinnedIds.filter(id => !!id).map(id => item(id, true))
            },
            {
                "key": "running",
                "title": Translation.tr("Open now"),
                "icon": "select_window",
                "items": running.map(app => item(app.appId, false))
            },
            {
                "key": "installed",
                "title": Translation.tr("All apps"),
                "icon": "apps",
                "items": rest.map(entry => item(entry.id, false))
            }
        ].filter(group => group.items.length > 0);
    }

    // What the showing list has in it, for the empty-result line.
    readonly property int visibleRowCount: root.section === "widgets" ? root.widgetRows.length
        : root.section === "bar" ? root.barRows.length
        : root.section === "dock" ? root.dockRows.length
        : root.lockSwitches.length

    function appName(appId) {
        return DesktopEntries.heuristicLookup(appId)?.name ?? appId;
    }

    // The two short ones open, the long one shut: the point of a section is
    // not having to scroll past the ones you are not after.
    property var expandedDockGroups: ["pinned", "running"]

    function dockGroupExpanded(key) {
        return root.expandedDockGroups.indexOf(key) !== -1;
    }

    function toggleDockGroup(key) {
        const next = root.expandedDockGroups.slice();
        const at = next.indexOf(key);
        if (at === -1)
            next.push(key);
        else
            next.splice(at, 1);
        root.expandedDockGroups = next;
    }

    readonly property var dockSearchRows: {
        const rows = [];
        for (const group of root.dockGroups)
            for (const app of group.items)
                rows.push({
                    "kind": "app",
                    "app": app,
                    "hay": root.prepared(app.name, app.appId)
                });
        return rows;
    }

    readonly property var dockRows: {
        if (root.searching)
            return root.fuzzyPick(root.dockSearchRows);
        const rows = [];
        for (const group of root.dockGroups) {
            rows.push({ "kind": "header", "group": group });
            if (!root.dockGroupExpanded(group.key))
                continue;
            for (const app of group.items)
                rows.push({ "kind": "app", "app": app });
        }
        return rows;
    }

    readonly property bool lockTab: GlobalStates.editLockPreview
    onLockTabChanged: {
        if (root.lockTab ? (root.section === "bar" || root.section === "dock") : root.section === "lock")
            GlobalStates.editDrawerSection = "widgets";
    }
    readonly property bool anyLockFork: root.activeWidgets.some(entry =>
        WidgetPlacement.fork(entry, root.screenName, true) !== null)

    // The lock's own switches, written straight to config: preferences, not
    // layout edits, so no history entry - same as their Settings toggles.
    readonly property var lockSwitches: [
        { "key": "nowPlaying", "group": "lock", "symbol": "music_note", "title": Translation.tr("Now playing") },
        { "key": "sports", "group": "lock", "symbol": "sports_soccer", "title": Translation.tr("Sports") },
        { "key": "showAlarm", "group": "lock", "symbol": "alarm", "title": Translation.tr("Next alarm") },
        { "key": "showWeather", "group": "lock", "symbol": "partly_cloudy_day", "title": Translation.tr("Weather") },
        { "key": "showLockedText", "group": "lock", "symbol": "lock", "title": Translation.tr("\"Locked\" text") },
        { "key": "showIndicator", "group": "fingerprint", "symbol": "fingerprint", "title": Translation.tr("Fingerprint indicator") }
    ]
    function lockSwitchTarget(entry) {
        return entry.group === "fingerprint" ? Config.options.lock.security.fingerprint : Config.options.lock;
    }

    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Appearance.sizes.editModeDrawerWidth
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.verylarge
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // The remove tint: lit while a desktop widget is carried over the panel.
        Rectangle {
            anchors.fill: parent
            radius: panel.radius
            color: root.dropWouldRemove ? Appearance.colors.colLayer1Active : "transparent"
            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            // The contents arrive after the panel: faded on the drawer's own scalar.
            opacity: Math.max(0, Math.min(1, (GlobalStates.editDrawerProgress - 0.4) / 0.6))

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                spacing: 10

                MaterialSymbol {
                    text: "add_circle"
                    iconSize: 22
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Add")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurface
                }
            }

            ButtonGroup {
                Layout.leftMargin: 6
                Layout.rightMargin: 6

                SelectionGroupButton {
                    leftmost: true
                    buttonText: Translation.tr("Widgets")
                    toggled: root.section === "widgets"
                    onClicked: GlobalStates.editDrawerSection = "widgets"
                }
                SelectionGroupButton {
                    visible: !root.lockTab
                    buttonText: Translation.tr("Bar")
                    toggled: root.section === "bar"
                    onClicked: GlobalStates.editDrawerSection = "bar"
                }
                SelectionGroupButton {
                    visible: !root.lockTab
                    rightmost: true
                    buttonText: Translation.tr("Dock")
                    toggled: root.section === "dock"
                    onClicked: GlobalStates.editDrawerSection = "dock"
                }
                SelectionGroupButton {
                    visible: root.lockTab
                    rightmost: true
                    buttonText: Translation.tr("Lock screen")
                    toggled: root.section === "lock"
                    onClicked: GlobalStates.editDrawerSection = "lock"
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                text: root.section === "widgets"
                    ? (root.lockTab
                        ? Translation.tr("Drag a widget onto the lock screen to place it there, or click to show or hide it. A widget that is not on the desktop is added to the lock screen only.")
                        : Translation.tr("Drag a widget onto the desktop to place it, or click to add or remove it. Drag a desktop widget here to remove it."))
                    : root.section === "lock"
                        ? Translation.tr("What the lock screen shows besides your widgets.")
                    : root.section === "bar"
                        ? Translation.tr("Drag a widget onto the bar to drop it where you want it. Click one to add it at the end, or to take a placed one off.")
                        : Translation.tr("Click an app to pin or unpin it. Drag the icons on the dock itself to reorder them.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            // The one field for all three catalogues: it filters whichever is
            // showing, and the surface only takes the keyboard while it holds
            // focus.
            Item {
                id: searchRow
                visible: root.searchable
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                implicitHeight: 38

                ToolbarTextField {
                    id: searchField
                    anchors.fill: parent
                    Layout.fillHeight: false
                    leftPadding: 34
                    rightPadding: 34
                    colBackground: Appearance.colors.colLayer1
                    placeholderText: root.section === "dock" ? Translation.tr("Search apps")
                        : root.section === "bar" ? Translation.tr("Search bar widgets")
                        : Translation.tr("Search widgets")
                    onTextChanged: root.query = searchField.text
                    onPressed: root.searchWanted = true
                    // Focus moved on inside the drawer - a row, a section
                    // button - so the keyboard goes back to the desktop.
                    onActiveFocusChanged: {
                        if (searchField.activeFocus) {
                            root.searchHeld = true;
                            return;
                        }
                        if (!root.searchHeld)
                            return;
                        root.searchHeld = false;
                        root.searchWanted = false;
                    }
                    // The first Escape empties the field, the second gives the
                    // keyboard back - and with it the mode's own Escape ladder.
                    Keys.onEscapePressed: event => {
                        if (searchField.text !== "") {
                            searchField.text = "";
                            return;
                        }
                        root.releaseSearchFocus();
                        event.accepted = true;
                    }
                }

                MaterialSymbol {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }

                FadeLoader {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    shown: searchField.text !== ""
                    sourceComponent: RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: {
                            searchField.text = "";
                            searchField.forceActiveFocus();
                        }
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // Nothing matched: said plainly, because an empty panel under a
            // typed word reads as a broken list.
            StyledText {
                visible: root.searching && root.visibleRowCount === 0
                Layout.fillWidth: true
                Layout.topMargin: 20
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("No matches")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
            }

            // ── Widgets ──────────────────────────────────────────────────────
            StyledListView {
                popin: false
                animateAppearance: false
                id: widgetList
                visible: root.section === "widgets"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.section === "widgets" ? root.widgetRows : []

                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool isHeader: row.modelData.kind === "header"

                    width: widgetList.width
                    height: row.isHeader ? 42 : 60

                    Loader {
                        anchors.fill: parent
                        active: row.isHeader
                        sourceComponent: headerFace
                    }

                    // Indented under its section.
                    Loader {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        active: !row.isHeader
                        sourceComponent: widgetFace
                    }

                    // A section: its name, how many of its widgets are already
                    // placed, and the chevron that opens it.
                    Component {
                        id: headerFace

                        CatalogueHeader {
                            readonly property var group: row.modelData.group
                            readonly property int added: root.widgetGroupAdded(group)
                            symbol: group.icon
                            title: group.title
                            countText: added > 0 ? `${added}/${group.items.length}` : `${group.items.length}`
                            countHighlighted: added > 0
                            open: root.widgetGroupExpanded(group.key)
                            onClicked: root.toggleWidgetGroup(group.key)
                        }
                    }

                    // A widget inside an open section: a click adds or removes
                    // it, a drag places it where the pointer is let go.
                    Component {
                        id: widgetFace

                        MouseArea {
                            id: entry
                            readonly property var widget: row.modelData.widget
                            readonly property bool onDesktop: root.widgetOnDesktop(entry.widget.widgetId)

                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true

                            property real pressX: 0
                            property real pressY: 0
                            property bool dragActive: false

                            onPressed: mouse => {
                                entry.pressX = mouse.x;
                                entry.pressY = mouse.y;
                                entry.dragActive = false;
                            }
                            onPositionChanged: mouse => {
                                if (!entry.pressed)
                                    return;
                                if (!entry.dragActive
                                        && Math.abs(mouse.x - entry.pressX) < 5
                                        && Math.abs(mouse.y - entry.pressY) < 5)
                                    return;
                                if (!entry.dragActive)
                                    widgetList.interactive = false;
                                entry.dragActive = true;
                                root.dragMetadata = entry.widget;
                                const point = entry.mapToItem(root.ghostParent ?? root, mouse.x, mouse.y);
                                ghost.x = point.x - ghost.width / 2;
                                ghost.y = point.y - ghost.height / 2;
                            }
                            onReleased: mouse => {
                                const wasDrag = entry.dragActive;
                                entry.dragActive = false;
                                widgetList.interactive = true;
                                root.dragMetadata = null;
                                if (wasDrag) {
                                    const point = entry.mapToItem(root.ghostParent ?? root, mouse.x, mouse.y);
                                    root.addRequested(entry.widget.widgetId, point.x, point.y);
                                } else {
                                    root.toggleRequested(entry.widget.widgetId);
                                }
                            }
                            onCanceled: {
                                entry.dragActive = false;
                                widgetList.interactive = true;
                                root.dragMetadata = null;
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.large
                                color: entry.pressed ? Appearance.colors.colLayer1Active
                                    : entry.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                                Behavior on color {
                                    enabled: !Appearance.reducedMotion
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }

                            CatalogueRow {
                                anchors.fill: parent
                                symbol: entry.widget.icon ?? "widgets"
                                title: entry.widget.name ?? entry.widget.widgetId
                                subtitle: entry.widget.description ?? ""
                                checked: root.lockTab ? root.widgetOnLock(entry.widget.widgetId) : entry.onDesktop
                            }
                        }
                    }
                }
            }

            // Lock screen section: the islands' switches, then the way back to
            // the desktop's layout on this monitor.
            StyledListView {
                popin: false
                animateAppearance: false
                id: lockList
                visible: root.section === "lock"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.section === "lock" ? root.lockSwitches : []

                delegate: CatalogueButton {
                    id: lockRow
                    required property var modelData
                    readonly property var target: root.lockSwitchTarget(lockRow.modelData)
                    width: lockList.width
                    rowSymbol: lockRow.modelData.symbol
                    rowTitle: lockRow.modelData.title
                    rowChecked: lockRow.target[lockRow.modelData.key] ?? true
                    onClicked: lockRow.target[lockRow.modelData.key] = !lockRow.rowChecked
                }

                footer: Item {
                    width: lockList.width
                    height: resetButton.implicitHeight + 12
                    RippleButton {
                        id: resetButton
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        enabled: root.anyLockFork
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: root.lockLayoutResetRequested()
                        contentItem: RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                Layout.leftMargin: 12
                                text: "reset_wrench"
                                iconSize: Appearance.font.pixelSize.larger
                                color: resetButton.enabled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOutline
                            }
                            StyledText {
                                Layout.rightMargin: 12
                                text: Translation.tr("Use desktop layout")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: resetButton.enabled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOutline
                            }
                        }
                    }
                }
            }

            // ── Bar ──────────────────────────────────────────────────────────
            // One list, dropped where you want it. The three buckets this
            // replaced asked for the destination before the widget was even
            // picked, and still only ever put it at the end of that list; the
            // bar itself is the better target, and it previews the landing.
            StyledListView {
                popin: false
                animateAppearance: false
                id: barList
                visible: root.section === "bar"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.section === "bar" ? root.barRows : []

                delegate: MouseArea {
                    id: barRow
                    required property var modelData
                    readonly property var entry: barRow.modelData.component
                    // Already on the bar: a click takes it off, and there is
                    // nothing to carry - it has a place already.
                    readonly property bool used: barRow.modelData.used === true

                    width: barList.width
                    height: 52
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true

                    property real pressX: 0
                    property real pressY: 0
                    property bool dragActive: false

                    function pointOf(mouse) {
                        return barRow.mapToItem(root.ghostParent ?? root, mouse.x, mouse.y);
                    }

                    onPressed: mouse => {
                        barRow.pressX = mouse.x;
                        barRow.pressY = mouse.y;
                        barRow.dragActive = false;
                    }
                    onPositionChanged: mouse => {
                        if (!barRow.pressed || barRow.used)
                            return;
                        // Under the list's own threshold, and the list is shut
                        // off the moment this wins: the bar is straight up from
                        // here, and a drag that way is a flick to a ListView.
                        if (!barRow.dragActive
                                && Math.abs(mouse.x - barRow.pressX) < 5
                                && Math.abs(mouse.y - barRow.pressY) < 5)
                            return;
                        if (!barRow.dragActive)
                            barList.interactive = false;
                        barRow.dragActive = true;
                        root.dragMetadata = {
                            "icon": barRow.entry.icon ?? "widgets",
                            "name": barRow.entry.title ?? barRow.entry.id
                        };
                        const point = barRow.pointOf(mouse);
                        ghost.x = point.x - ghost.width / 2;
                        ghost.y = point.y - ghost.height / 2;
                        root.barDragMoved(barRow.entry.id, point.x, point.y);
                    }
                    onReleased: mouse => {
                        const wasDrag = barRow.dragActive;
                        barRow.dragActive = false;
                        barList.interactive = true;
                        root.dragMetadata = null;
                        // A click is still worth something: it puts the widget
                        // at the end of the right-hand section, where the
                        // picker this replaced started.
                        if (!wasDrag) {
                            if (barRow.used)
                                root.barRemoveRequested(barRow.entry.id);
                            else
                                root.barAddRequested(barRow.entry.id, "right");
                            return;
                        }
                        const point = barRow.pointOf(mouse);
                        root.barDropRequested(barRow.entry.id, point.x, point.y);
                    }
                    onCanceled: {
                        barRow.dragActive = false;
                        barList.interactive = true;
                        root.dragMetadata = null;
                        root.barDragCancelled();
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.large
                        color: barRow.pressed ? Appearance.colors.colLayer1Active
                            : barRow.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                        Behavior on color {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    CatalogueRow {
                        anchors.fill: parent
                        symbol: barRow.entry.icon ?? "widgets"
                        title: barRow.entry.title ?? barRow.entry.id
                        checked: barRow.used
                    }
                }
            }

            // ── Dock ─────────────────────────────────────────────────────────
            StyledListView {
                popin: false
                animateAppearance: false
                id: appList
                visible: root.section === "dock"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.section === "dock" ? root.dockRows : []

                delegate: Item {
                    id: appRow
                    required property var modelData
                    readonly property bool isHeader: appRow.modelData.kind === "header"

                    width: appList.width
                    height: appRow.isHeader ? 42 : 52

                    Loader {
                        anchors.fill: parent
                        active: appRow.isHeader
                        sourceComponent: dockHeaderFace
                    }

                    // Indented under its section.
                    Loader {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        active: !appRow.isHeader
                        sourceComponent: dockAppFace
                    }

                    Component {
                        id: dockHeaderFace

                        CatalogueHeader {
                            readonly property var group: appRow.modelData.group
                            symbol: group.icon
                            title: group.title
                            countText: `${group.items.length}`
                            countHighlighted: group.key === "pinned"
                            open: root.dockGroupExpanded(group.key)
                            onClicked: root.toggleDockGroup(group.key)
                        }
                    }

                    Component {
                        id: dockAppFace

                        CatalogueButton {
                            readonly property string appId: appRow.modelData.app.appId ?? ""
                            rowIcon: Quickshell.iconPath(AppSearch.guessIcon(appId), "image-missing")
                            rowTitle: appRow.modelData.app.name ?? appId
                            rowChecked: appRow.modelData.app.pinned === true
                            onClicked: root.dockToggleRequested(appId)
                        }
                    }
                }
            }
        }
    }

    // The drag ghost: the row's name carried under the pointer, parented
    // outside the reveal so it is not clipped at the drawer's edge.
    Rectangle {
        id: ghost
        parent: root.ghostParent ?? root
        visible: root.dragMetadata !== null
        z: 100
        width: ghostRow.implicitWidth + 24
        height: 40
        radius: Appearance.rounding.full
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        RowLayout {
            id: ghostRow
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                text: root.dragMetadata?.icon ?? "widgets"
                iconSize: 20
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                text: root.dragMetadata?.name ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
            }
        }
    }

    // A catalogue row's face: symbol or app icon, title, optional subtitle,
    // and the trailing added/add mark.
    component CatalogueRow: RowLayout {
        id: face
        property string symbol: ""
        property string iconSource: ""
        property string title: ""
        property string subtitle: ""
        property bool checked: false
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Loader {
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: face.iconSource !== "" ? appIconFace : symbolFace
        }
        Component {
            id: symbolFace
            MaterialSymbol {
                text: face.symbol
                iconSize: 24
                color: Appearance.colors.colOnSurface
            }
        }
        Component {
            id: appIconFace
            IconImage {
                implicitSize: 26
                source: face.iconSource
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: face.title
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: face.subtitle !== ""
                text: face.subtitle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: face.checked ? "check_circle" : "add"
            iconSize: 22
            color: face.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
        }
    }

    // A section header: its name, how many rows are under it, and the chevron
    // that opens it. Shared by the widget catalogue and the dock's.
    component CatalogueHeader: MouseArea {
        id: head
        property string symbol: "widgets"
        property string title: ""
        property string countText: ""
        property bool countHighlighted: false
        property bool open: false

        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: head.pressed ? Appearance.colors.colLayer1Active
                : head.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: head.symbol
                iconSize: 22
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: head.title
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: head.countText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: head.countHighlighted ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnSurfaceVariant
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "keyboard_arrow_down"
                iconSize: 20
                color: Appearance.colors.colOnSurfaceVariant
                rotation: head.open ? 0 : -90
                Behavior on rotation {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    // A click-only catalogue row (bar components, dock apps).
    component CatalogueButton: RippleButton {
        id: button
        property string rowSymbol: ""
        property string rowIcon: ""
        property string rowTitle: ""
        property bool rowChecked: false
        implicitHeight: 52
        buttonRadius: Appearance.rounding.large
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        contentItem: CatalogueRow {
            anchors.fill: parent
            symbol: button.rowSymbol
            iconSource: button.rowIcon
            title: button.rowTitle
            checked: button.rowChecked
        }
    }
}
