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
 * Edit Mode's panel: the surface that slides in from the right of the card.
 *
 * Five catalogues - the desktop's widgets, the bar, the dock, the lock
 * screen's own switches and the style (wallpaper, theme, palette) - and each
 * of them is a ROOT with sub-pages rather
 * than a list of accordions. That is the change: sections that expanded in
 * place put eighty rows in one scroll and left no room for anything a section
 * might want to say about itself, which is why the bar's style variants and
 * the dock's own appearance had nowhere to live and stayed in Settings. A page
 * per destination gives each one the whole panel.
 *
 * The address is `GlobalStates.editDrawerSection` plus `editDrawerPage`, held
 * shell-wide because a right-click on the desktop or the bar asks for a
 * catalogue before the panel that shows it exists, and the toolbar's Bar
 * button asks for one page in particular.
 *
 * The panel reports gestures and writes only preferences: every LAYOUT write
 * is made by the surface that owns the geometry, so a drop can be turned into
 * a canvas point and a history entry recorded in one place.
 */
Item {
    id: root

    property string screenName: ""
    // Where the drag ghost lives: an ancestor that is not clipped by the
    // panel's reveal, so the ghost can follow the pointer out over the card.
    property Item ghostParent: null

    signal addRequested(string widgetId, real dropX, real dropY)
    // A catalogue row's click: one more of this widget. Not a toggle - a
    // widget can be placed more than once, so a row has no on/off state to
    // flip; removal belongs to the copy, through its own menu or by dragging
    // it back into the panel.
    signal addInstanceRequested(string widgetId)
    signal barRemoveRequested(string componentId)
    // A component sent to a named list from its own page: unlike the add
    // above, it moves one that is already placed.
    signal barPlaceRequested(string componentId, string bucket)
    // A bar component carried out of the catalogue: where the pointer is, in
    // the chrome's coordinates, for the surface to hand to that screen's bar.
    signal barDragMoved(string componentId, real x, real y)
    signal barDropRequested(string componentId, real x, real y)
    signal barDragCancelled()
    signal dockToggleRequested(string appId)
    signal lockLayoutResetRequested()
    // A whole surface back to the shell's defaults: "widgets" (every desktop
    // widget removed), "bar", "dock" or "lockIslands". The surface answers
    // with one history entry, so the reset is one Ctrl+Z.
    signal resetRequested(string what)

    readonly property string section: GlobalStates.editDrawerSection
    // The address, validated against the catalogue showing it: a page belongs
    // to the section that minted it, and one left over from another section is
    // simply that section's root. Checked here rather than cleared on every
    // section change, so "open the bar's appearance page" is one intent
    // instead of two assignments whose order decides the answer.
    readonly property string page: root.pageValidFor(root.section, GlobalStates.editDrawerPage)
        ? GlobalStates.editDrawerPage : ""
    property var dragMetadata: null

    function pageValidFor(section, page) {
        if (page === "")
            return true;
        if (section === "widgets")
            return page.startsWith("category:");
        if (section === "bar")
            return page === "appearance" || page.startsWith("component:");
        if (section === "dock")
            return page === "appearance" || page === "widgets" || page.startsWith("apps:");
        if (section === "style")
            return page === "wallpapers" || page === "colours";
        return false;
    }

    // ── Navigation ───────────────────────────────────────────────────────────
    // Which way the next page arrives from: 1 going deeper, -1 coming back.
    // The same two-value scalar ChatControlBar's canvas uses, for the same
    // reason - one Loader swapping its content has no other way to say which
    // direction the step was.
    property int navDirection: 1
    readonly property bool atRoot: root.page === "" || root.searching

    // Milliseconds between one row of a page entering and the next. The panel
    // is 380px wide and a page is a short run of rows, so this is smaller than
    // the transcript's: enough to read as filling, not as a queue.
    readonly property int staggerStep: 22

    // 0 while a page is arriving, 1 once it has. The Behavior would animate
    // the way BACK to 0 as well, which would fade the outgoing page out before
    // fading the incoming one in - two half-second beats for one step - so the
    // reset is made with the Behavior held off and only the rise is animated.
    property real pageReveal: 1
    property bool pageRevealSnapping: false
    Behavior on pageReveal {
        enabled: !Appearance.reducedMotion && !root.pageRevealSnapping
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    onContentKeyChanged: {
        root.pageRevealSnapping = true;
        root.pageReveal = 0;
        root.pageRevealSnapping = false;
        root.pageReveal = 1;
    }

    function openPage(page) {
        root.navDirection = 1;
        GlobalStates.editDrawerPage = page;
    }

    function goBack() {
        root.navDirection = -1;
        GlobalStates.editDrawerPage = "";
    }

    function setSection(section) {
        if (GlobalStates.editDrawerSection === section)
            return;
        root.navDirection = 1;
        GlobalStates.editDrawerPage = "";
        GlobalStates.editDrawerSection = section;
    }

    // ── The query ────────────────────────────────────────────────────────────
    // The dock's catalogue alone runs to two hundred rows. A query FLATTENS the
    // catalogue it filters, pages and all: someone typing is after one row, not
    // after where it lives. The lock screen's switches are not worth a box.
    readonly property bool searchable: root.section !== "lock" && root.section !== "style"
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
    // A second field that wants the keyboard the same way - the Style
    // catalogue's preset name. One at a time: asking for it lets the search
    // go, and the other way round.
    property bool fieldWanted: false
    property Item fieldItem: null
    readonly property bool searchFocused: root.searchWanted || root.fieldWanted

    function requestFieldFocus(item) {
        if (!item)
            return;
        root.searchWanted = false;
        root.searchHeld = false;
        searchField.focus = false;
        root.fieldItem = item;
        root.fieldWanted = true;
        item.forceActiveFocus();
    }

    function releaseFieldFocus() {
        root.fieldWanted = false;
        if (root.fieldItem)
            root.fieldItem.focus = false;
        root.fieldItem = null;
    }

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
        root.releaseFieldFocus();
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
        if (p.x >= 0 && p.y >= 0 && p.x <= searchRow.width && p.y <= searchRow.height)
            return true;
        if (!root.fieldWanted || !root.fieldItem)
            return false;
        const q = from.mapToItem(root.fieldItem, x, y);
        return q.x >= 0 && q.y >= 0 && q.x <= root.fieldItem.width && q.y <= root.fieldItem.height;
    }

    onSectionChanged: root.clearSearch()

    // Ctrl+F, from the canvas. Only the screen being edited answers: every
    // screen draws a panel, and the keyboard is on one of them.
    function focusSearch() {
        if (!root.searchable || root.screenName !== GlobalStates.editModeMonitor)
            return;
        root.searchWanted = true;
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    Connections {
        target: GlobalStates
        // Leaving takes the query with it: a panel reopened on last week's
        // half-typed word is a panel that looks broken.
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

    // A desktop widget carried back over this panel: the release removes it.
    readonly property bool dropWouldRemove: root.screenName !== ""
        && GlobalStates.editDrawerDropScreen === root.screenName

    // ── Catalogues ───────────────────────────────────────────────────────────
    readonly property var activeWidgets: Config.options.background.activeWidgets ?? []
    readonly property var usedBarIds: {
        const layouts = Config.options.bar.layouts;
        const ids = [];
        for (const bucket of ["left", "center", "right"])
            for (const entry of (layouts[bucket] ?? []))
                if (entry && entry.id) ids.push(entry.id);
        return ids;
    }
    readonly property bool barCentreBlocked: ShellModePolicy.barCenterActive
    // Every bar component, not only the ones going spare: one already on the
    // bar is named as such and its row still opens its page.
    //
    // Whether a component is PLACED is deliberately not in here. Folding it in
    // made the model a function of `bar.layouts`, so adding or removing one
    // component built a fresh array, reset the view, and replayed the whole
    // list's entrance - a cascade every time you placed a widget. The rows ask
    // `usedBarIds` for themselves instead, which re-evaluates one binding.
    readonly property var barCatalogue: (BarComponentRegistry.allComponents ?? []).map(component => ({
        "component": component,
        "hay": root.prepared(component.title, component.id)
    }))
    readonly property var barRows: root.searching ? root.fuzzyPick(root.barCatalogue) : root.barCatalogue

    // How many copies of a widget the desktop holds - and, on the Lockscreen
    // tab, how many of them the lock actually shows (any behaviour but hide).
    // A count rather than a boolean because a widget can be placed more than
    // once, which is also why the rows carry a number instead of a checkmark.
    function widgetCount(widgetId) {
        let count = 0;
        for (const entry of root.activeWidgets) {
            if (!entry || entry.widgetId !== widgetId)
                continue;
            if (root.lockTab && (entry.lockBehavior || "hide") === "hide")
                continue;
            count++;
        }
        return count;
    }

    // The catalogue's categories, named and ordered as Settings names and
    // orders them. A category the registry hands out that is not listed here -
    // an extension's own - gets one of its own at the end, so a widget can
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

    function widgetGroupByKey(key) {
        return root.widgetGroups.find(group => group.key === key) ?? null;
    }

    // How many KINDS in this category are placed, not how many copies: the
    // header reads "3/20", which is about the catalogue, and a copy count
    // there could exceed the number of rows below it.
    function widgetGroupAdded(group) {
        let count = 0;
        for (const widget of group.items)
            if (root.widgetCount(widget.widgetId) > 0)
                count++;
        return count;
    }

    // The flattened list a query searches, prepared once per catalogue rather
    // than per keystroke.
    readonly property var widgetSearchRows: {
        const rows = [];
        for (const group of root.widgetGroups)
            for (const widget of group.items)
                rows.push({ "widget": widget, "hay": root.prepared(widget.name, widget.widgetId) });
        return rows;
    }

    // What the widget list is showing: a query's answer, or the open category.
    readonly property var widgetItems: {
        if (root.searching)
            return root.fuzzyPick(root.widgetSearchRows).map(row => row.widget);
        if (!root.page.startsWith("category:"))
            return [];
        const group = root.widgetGroupByKey(root.page.substring(9));
        return group ? group.items : [];
    }

    // The dock's catalogue, in three groups for the three answers to "why is
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
        ];
    }

    function appName(appId) {
        return DesktopEntries.heuristicLookup(appId)?.name ?? appId;
    }

    function dockGroupByKey(key) {
        return root.dockGroups.find(group => group.key === key) ?? null;
    }

    readonly property var dockSearchRows: {
        const rows = [];
        for (const group of root.dockGroups)
            for (const app of group.items)
                rows.push({ "app": app, "hay": root.prepared(app.name, app.appId) });
        return rows;
    }

    readonly property var dockItems: {
        if (root.searching)
            return root.fuzzyPick(root.dockSearchRows).map(row => row.app);
        if (!root.page.startsWith("apps:"))
            return [];
        const group = root.dockGroupByKey(root.page.substring(5));
        return group ? group.items : [];
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

    // Everything the lock screen's toolbars can hide, so a remove badge there
    // has a way back. LockIslands' vocabulary; the password field is not on it
    // because a lock screen with no way to type into it is not a lock screen.
    readonly property var lockIslandNames: ({
        "battery": Translation.tr("Battery"),
        "capsLock": Translation.tr("Caps Lock"),
        "alarm": Translation.tr("Next alarm"),
        "weather": Translation.tr("Weather"),
        "keyboardLayout": Translation.tr("Keyboard layout"),
        "keepAwake": Translation.tr("Keep awake"),
        "mode": Translation.tr("Active mode"),
        "sleep": Translation.tr("Sleep"),
        "power": Translation.tr("Shut down"),
        "reboot": Translation.tr("Restart")
    })
    readonly property var lockIslandSymbols: ({
        "battery": "battery_full", "capsLock": "keyboard_capslock", "alarm": "alarm",
        "weather": "partly_cloudy_day", "keyboardLayout": "keyboard", "keepAwake": "coffee",
        "mode": "target", "sleep": "dark_mode", "power": "power_settings_new",
        "reboot": "restart_alt"
    })
    readonly property var hiddenLockIslands: Array.from(Config.options.lock.islands.hidden ?? [])

    function showLockIsland(id) {
        Config.setLockIslandHidden(id, false);
    }

    // ── The page the panel is showing ────────────────────────────────────────
    readonly property string contentKey: root.searching
        ? ("search:" + root.section)
        : (root.section + "/" + root.page)

    readonly property string headerTitle: {
        if (root.searching)
            return Translation.tr("Results");
        if (root.page === "") {
            if (root.section === "bar")
                return Translation.tr("Bar");
            if (root.section === "dock")
                return Translation.tr("Dock");
            if (root.section === "lock")
                return Translation.tr("Lock screen");
            if (root.section === "style")
                return Translation.tr("Style");
            return Translation.tr("Widgets");
        }
        if (root.page === "wallpapers")
            return GlobalStates.editLockPreview && (Config.options.background.useSeparateLockscreenWallpaper ?? false)
                ? Translation.tr("Lock screen wallpaper") : Translation.tr("Wallpaper");
        if (root.page === "colours")
            return Translation.tr("Colour scheme");
        if (root.page.startsWith("category:"))
            return root.widgetGroupByKey(root.page.substring(9))?.title ?? Translation.tr("Widgets");
        if (root.page.startsWith("apps:"))
            return root.dockGroupByKey(root.page.substring(5))?.title ?? Translation.tr("Apps");
        if (root.page.startsWith("component:"))
            return BarComponentRegistry.getComponent(root.page.substring(10))?.title ?? Translation.tr("Widget");
        if (root.page === "appearance")
            return root.section === "dock" ? Translation.tr("Dock appearance") : Translation.tr("Bar appearance");
        if (root.page === "widgets")
            return Translation.tr("Dock widgets");
        return Translation.tr("Edit");
    }

    readonly property string headerSymbol: {
        if (root.section === "bar")
            return "dock_to_bottom";
        if (root.section === "dock")
            return "dock";
        if (root.section === "lock")
            return "lock";
        if (root.section === "style")
            return "palette";
        return "widgets";
    }

    function toGhost(sceneX, sceneY) {
        const host = root.ghostParent ?? root;
        return host.mapFromItem(null, sceneX, sceneY);
    }

    function beginGhost(metadata, sceneX, sceneY) {
        root.dragMetadata = metadata;
        root.moveGhost(sceneX, sceneY);
    }

    function moveGhost(sceneX, sceneY) {
        const p = root.toGhost(sceneX, sceneY);
        ghost.x = p.x - ghost.width / 2;
        ghost.y = p.y - ghost.height / 2;
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
            spacing: 8
            // The contents arrive after the panel: faded on the panel's own scalar.
            opacity: Math.max(0, Math.min(1, (GlobalStates.editDrawerProgress - 0.4) / 0.6))

            // ── Header ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 4
                spacing: 10

                // One control does both jobs: an icon at a root, the way back
                // on a page. Same circle either way, so the header does not
                // change shape as the panel navigates.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: width / 2
                    color: root.atRoot ? "transparent"
                        : backMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                        : backMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighest
                        : Appearance.colors.colSurfaceContainerHigh

                    Behavior on color {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.atRoot ? root.headerSymbol : "arrow_back"
                        iconSize: 22
                        color: Appearance.colors.colOnSurface
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        enabled: !root.atRoot
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.goBack()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.headerTitle
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
            }

            // ── Catalogue picker ─────────────────────────────────────────────
            ButtonGroup {
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                visible: root.atRoot

                SelectionGroupButton {
                    leftmost: true
                    buttonText: Translation.tr("Widgets")
                    toggled: root.section === "widgets"
                    onClicked: root.setSection("widgets")
                }
                SelectionGroupButton {
                    visible: !root.lockTab
                    buttonText: Translation.tr("Bar")
                    toggled: root.section === "bar"
                    onClicked: root.setSection("bar")
                }
                SelectionGroupButton {
                    visible: !root.lockTab
                    buttonText: Translation.tr("Dock")
                    toggled: root.section === "dock"
                    onClicked: root.setSection("dock")
                }
                SelectionGroupButton {
                    visible: root.lockTab
                    buttonText: Translation.tr("Lock screen")
                    toggled: root.section === "lock"
                    onClicked: root.setSection("lock")
                }
                SelectionGroupButton {
                    rightmost: true
                    buttonText: Translation.tr("Style")
                    toggled: root.section === "style"
                    onClicked: root.setSection("style")
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                visible: root.atRoot && !root.searching
                text: root.section === "widgets"
                    ? (root.lockTab
                        ? Translation.tr("Drag a widget onto the lock screen to place it, or click to add one. Drag one back here to remove it.")
                        : Translation.tr("Drag a widget onto the desktop to place it, or click to add one. Drag one back here to remove it."))
                    : root.section === "lock"
                        ? Translation.tr("What the lock screen shows besides your widgets.")
                    : root.section === "style"
                        ? Translation.tr("The wallpaper and the colours everything is drawn in. Changes apply at once; undo takes them back.")
                    : root.section === "bar"
                        ? Translation.tr("Drag a widget onto the bar to drop it where you want it, or open one to change how it looks.")
                        : Translation.tr("Pin apps, and choose how the dock itself is drawn.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            // ── Search ───────────────────────────────────────────────────────
            // One field for all three catalogues: it filters whichever is
            // showing, and the surface only takes the keyboard while it holds
            // focus.
            Item {
                id: searchRow
                // A root-level affordance: a query flattens the catalogue, so
                // it belongs to the catalogue rather than to a page inside it.
                // Typing on a page still works - the results take the panel
                // over and clearing the field puts the page back.
                visible: root.searchable && root.atRoot
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
                    // Focus moved on inside the panel - a row, a section
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

            // ── The page ─────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    // The page changes under one Loader, so the arrival is
                    // animated here rather than by each page: they would all
                    // have to carry the same block and could not agree on the
                    // direction, which only the navigation knows.
                    //
                    // One scalar, one Behavior, no one-shot animation: the
                    // mode's motion audit allows a duration and a curve only
                    // through an Appearance tier, and a hand-built
                    // `ParallelAnimation` cannot get one. `root.pageReveal`
                    // carries both the fade and the slide.
                    opacity: root.pageReveal
                    transform: Translate {
                        x: (1 - root.pageReveal) * 28 * root.navDirection
                    }

                    sourceComponent: {
                        if (root.searching)
                            return root.section === "bar" ? barListPage
                                : root.section === "dock" ? dockAppListPage : widgetListPage;
                        if (root.section === "widgets")
                            return root.page.startsWith("category:") ? widgetListPage : widgetCategoriesPage;
                        if (root.section === "lock")
                            return lockPage;
                        if (root.section === "style") {
                            if (root.page === "wallpapers")
                                return wallpaperPage;
                            if (root.page === "colours")
                                return colourPage;
                            return stylePage;
                        }
                        if (root.section === "bar") {
                            if (root.page === "appearance")
                                return barAppearancePage;
                            if (root.page.startsWith("component:"))
                                return barComponentPage;
                            return barRootPage;
                        }
                        if (root.page === "appearance")
                            return dockAppearancePage;
                        if (root.page === "widgets")
                            return dockWidgetsPage;
                        if (root.page.startsWith("apps:"))
                            return dockAppListPage;
                        return dockRootPage;
                    }
                }
            }
        }
    }

    // ── Pages ────────────────────────────────────────────────────────────────

    // The widget catalogue's root: one row per category, opening a page of its
    // own. The count says how many of it are already placed.
    Component {
        id: widgetCategoriesPage

        StyledListView {
            id: categoryList
            // The page fills top-down. Only the views whose MODEL is stable
            // get this: a view whose array is rebuilt on every placement
            // change would replay the whole cascade each time.
            staggerStep: root.staggerStep
            clip: true
            spacing: 3
            model: root.widgetGroups

            delegate: EditPanelRow {
                required property var modelData
                required property int index
                readonly property int added: root.widgetGroupAdded(modelData)
                width: categoryList.width
                first: index === 0
                last: index === root.widgetGroups.length - 1
                symbol: modelData.icon
                title: modelData.title
                valueText: added > 0 ? `${added}/${modelData.items.length}` : `${modelData.items.length}`
                trailingKind: "chevron"
                onActivated: root.openPage("category:" + modelData.key)
            }

            // A clean slate, one Ctrl+Z away. Shown only while there is
            // something to clear, so the catalogue's root is not a place
            // that offers to delete nothing.
            footer: Item {
                width: categoryList.width
                height: root.activeWidgets.length > 0 ? clearRow.height + 13 : 0
                visible: root.activeWidgets.length > 0

                EditPanelRow {
                    id: clearRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    first: true
                    last: true
                    destructive: true
                    symbol: "delete_sweep"
                    title: Translation.tr("Remove every widget")
                    valueText: `${root.activeWidgets.length}`
                    trailingKind: "none"
                    onActivated: root.resetRequested("widgets")
                }
            }
        }
    }

    // A category's widgets, or a query's answer: a click adds or removes,
    // a drag places the widget where the pointer is let go.
    Component {
        id: widgetListPage

        // The empty line is a SIBLING of the list, never a child of it: a
        // plain child of a ListView is parented into its content item, which
        // scrolls and is zero-sized when the model is empty - exactly the case
        // the line exists for.
        Item {
            StyledListView {
                id: widgetList
                anchors.fill: parent
                staggerStep: root.staggerStep
                clip: true
                spacing: 3
                model: root.widgetItems

                delegate: EditPanelRow {
                    id: widgetRow
                    required property var modelData
                    required property int index
                    readonly property int placed: root.widgetCount(modelData.widgetId)

                    width: widgetList.width
                    first: index === 0
                    last: index === root.widgetItems.length - 1
                    symbol: modelData.icon ?? "widgets"
                    title: modelData.name ?? modelData.widgetId
                    subtitle: modelData.description ?? ""
                    // The row always offers ANOTHER one, and says how many are
                    // out there. A checkmark would be claiming the row is a
                    // switch, and it is not one any more.
                    valueText: widgetRow.placed > 0 ? `×${widgetRow.placed}` : ""
                    trailingKind: "add"
                    draggable: true
                    dragOwner: widgetList

                    onActivated: root.addInstanceRequested(modelData.widgetId)
                    onDragBegan: root.dragMetadata = modelData
                    onDragMovedTo: (x, y) => root.moveGhost(x, y)
                    onDragFinished: (x, y) => {
                        root.dragMetadata = null;
                        const p = root.toGhost(x, y);
                        root.addRequested(modelData.widgetId, p.x, p.y);
                    }
                    onDragCancelled: root.dragMetadata = null
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: widgetList.count === 0
                text: Translation.tr("No matches")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    // The bar's root: what the bar looks like, then every component it can
    // hold. One list, dropped where you want it - the three buckets this
    // replaced asked for the destination before the widget was even picked.
    Component {
        id: barRootPage

        ColumnLayout {
            spacing: 3

            EditPanelRow {
                Layout.fillWidth: true
                first: true
                last: true
                symbol: "palette"
                title: Translation.tr("Bar appearance")
                subtitle: Translation.tr("Position, size, corners and background")
                onActivated: root.openPage("appearance")
            }

            EditPanelRow {
                Layout.fillWidth: true
                Layout.topMargin: 3
                first: true
                last: true
                destructive: true
                symbol: "reset_wrench"
                title: Translation.tr("Reset the bar's layout")
                subtitle: Translation.tr("The widgets and groups the shell ships with")
                trailingKind: "none"
                onActivated: root.resetRequested("bar")
            }

            EditPanelNotice {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: root.barCentreBlocked
                text: Translation.tr("The bar's centre group is unavailable: the Dynamic Island is drawn over it. Widgets that were there have been moved to the right group.")
            }

            EditPanelSectionLabel {
                text: Translation.tr("Widgets")
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledListView {
                    id: barList
                    anchors.fill: parent
                    staggerStep: root.staggerStep
                    clip: true
                    spacing: 3
                    model: root.barRows

                    delegate: EditPanelRow {
                        id: barRow
                        required property var modelData
                        required property int index
                        readonly property var entry: modelData.component
                        readonly property bool used: root.usedBarIds.indexOf(barRow.entry.id) !== -1

                        width: barList.width
                        first: index === 0
                        last: index === root.barRows.length - 1
                        symbol: entry.icon ?? "widgets"
                        title: entry.title ?? entry.id
                        subtitle: barRow.used ? Translation.tr("On the bar") : ""
                        trailingKind: "chevron"
                        draggable: !barRow.used
                        dragOwner: barList

                        // The row opens the widget's page, which is where its
                        // looks and its group live. Adding is the drag - or
                        // the page's own placement chips, which is the answer
                        // for a pointer that would rather not carry anything
                        // across the screen.
                        onActivated: root.openPage("component:" + barRow.entry.id)
                        onDragBegan: root.dragMetadata = {
                            "icon": barRow.entry.icon ?? "widgets",
                            "name": barRow.entry.title ?? barRow.entry.id
                        }
                        onDragMovedTo: (x, y) => {
                            root.moveGhost(x, y);
                            const p = root.toGhost(x, y);
                            root.barDragMoved(barRow.entry.id, p.x, p.y);
                        }
                        onDragFinished: (x, y) => {
                            root.dragMetadata = null;
                            const p = root.toGhost(x, y);
                            root.barDropRequested(barRow.entry.id, p.x, p.y);
                        }
                        onDragCancelled: {
                            root.dragMetadata = null;
                            root.barDragCancelled();
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: barList.count === 0
                    text: Translation.tr("No matches")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    // The same list on its own, for a query: the appearance row above belongs
    // to the root, not to a set of results.
    Component {
        id: barListPage

        Item {
            StyledListView {
                id: barSearchList
                anchors.fill: parent
                staggerStep: root.staggerStep
                clip: true
                spacing: 3
                model: root.barRows

                delegate: EditPanelRow {
                    id: barSearchRow
                    required property var modelData
                    required property int index
                    readonly property var entry: modelData.component

                    width: barSearchList.width
                    first: index === 0
                    last: index === root.barRows.length - 1
                    symbol: entry.icon ?? "widgets"
                    title: entry.title ?? entry.id
                    subtitle: root.usedBarIds.indexOf(barSearchRow.entry.id) !== -1
                        ? Translation.tr("On the bar") : ""
                    trailingKind: "chevron"
                    onActivated: root.openPage("component:" + barSearchRow.entry.id)
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: barSearchList.count === 0
                text: Translation.tr("No matches")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    Component {
        id: barAppearancePage
        EditBarAppearancePage {}
    }

    Component {
        id: barComponentPage

        EditBarComponentPage {
            id: componentPage
            componentId: root.page.startsWith("component:") ? root.page.substring(10) : ""
            onPlaceRequested: bucket => root.barPlaceRequested(componentPage.componentId, bucket)
            onRemoveRequested: root.barRemoveRequested(componentPage.componentId)
        }
    }

    // The dock's root: how it is drawn, what it carries, and the three answers
    // to "why is this app in the list".
    Component {
        id: dockRootPage

        StyledFlickable {
            id: dockRoot
            contentHeight: dockColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: dockColumn
                width: dockRoot.width
                spacing: 3

                EditPanelRow {
                    Layout.fillWidth: true
                    first: true
                    last: false
                    symbol: "palette"
                    title: Translation.tr("Dock appearance")
                    subtitle: Translation.tr("Position, size, style and icons")
                    onActivated: root.openPage("appearance")
                }

                EditPanelRow {
                    Layout.fillWidth: true
                    first: false
                    last: true
                    symbol: "widgets"
                    title: Translation.tr("Dock widgets")
                    subtitle: Translation.tr("Media, weather, sports and the buttons")
                    onActivated: root.openPage("widgets")
                }

                EditPanelRow {
                    Layout.fillWidth: true
                    Layout.topMargin: 3
                    first: true
                    last: true
                    destructive: true
                    symbol: "reset_wrench"
                    title: Translation.tr("Reset the dock")
                    subtitle: Translation.tr("The pins and the order the shell ships with")
                    trailingKind: "none"
                    onActivated: root.resetRequested("dock")
                }

                EditPanelSectionLabel {
                    text: Translation.tr("Apps")
                }

                Repeater {
                    model: root.dockGroups

                    delegate: EditPanelRow {
                        required property var modelData
                        required property int index
                        staggerIndex: index
                        Layout.fillWidth: true
                        first: index === 0
                        last: index === root.dockGroups.length - 1
                        symbol: modelData.icon
                        title: modelData.title
                        valueText: `${modelData.items.length}`
                        onActivated: root.openPage("apps:" + modelData.key)
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 8
                }
            }
        }
    }

    Component {
        id: dockAppListPage

        Item {
            StyledListView {
                id: appList
                anchors.fill: parent
                // No cascade here, and no row transitions either: pinning an
                // app genuinely moves it between groups, so this model IS a
                // function of `dock.pinnedApps` and is rebuilt on every click.
                // Animated, the whole list would replay its entrance each time.
                popin: false
                animateAppearance: false
                clip: true
                spacing: 3
                model: root.dockItems

                delegate: EditPanelRow {
                    required property var modelData
                    required property int index
                    width: appList.width
                    first: index === 0
                    last: index === root.dockItems.length - 1
                    iconSource: Quickshell.iconPath(AppSearch.guessIcon(modelData.appId ?? ""), "image-missing")
                    title: modelData.name ?? modelData.appId
                    trailingKind: modelData.pinned === true ? "check" : "add"
                    onActivated: root.dockToggleRequested(modelData.appId ?? "")
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: appList.count === 0
                text: Translation.tr("Nothing here")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    Component {
        id: dockAppearancePage
        EditDockAppearancePage {}
    }

    Component {
        id: dockWidgetsPage
        EditDockWidgetsPage {}
    }

    // The Style catalogue: the wallpaper, the theme and the palette, with the
    // folder and the swatch grid a page down each.
    Component {
        id: stylePage
        EditStylePage {
            onOpenPageRequested: page => root.openPage(page)
            onFieldFocusRequested: field => root.requestFieldFocus(field)
            onFieldFocusReleased: root.releaseFieldFocus()
        }
    }

    Component {
        id: wallpaperPage
        EditWallpaperPage {
            target: GlobalStates.editLockPreview && (Config.options.background.useSeparateLockscreenWallpaper ?? false)
                ? "lockscreen"
                : ((Config.options.background.useSeparateLightModeWallpaper ?? false) && !Appearance.m3colors.darkmode)
                    ? "lightmode" : "desktop"
        }
    }

    Component {
        id: colourPage
        EditColourPage {}
    }

    // The lock screen's own face: the switches, whatever its toolbars have
    // been asked to hide, and the way back to the desktop's layout.
    Component {
        id: lockPage

        StyledFlickable {
            id: lockRoot
            contentHeight: lockColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: lockColumn
                width: lockRoot.width
                spacing: 3

                Repeater {
                    model: root.lockSwitches

                    delegate: EditPanelRow {
                        required property var modelData
                        required property int index
                        readonly property var target: root.lockSwitchTarget(modelData)
                        staggerIndex: index
                        Layout.fillWidth: true
                        first: index === 0
                        last: index === root.lockSwitches.length - 1
                        symbol: modelData.symbol
                        title: modelData.title
                        trailingKind: "switch"
                        switchChecked: target[modelData.key] ?? true
                        onActivated: target[modelData.key] = !(target[modelData.key] ?? true)
                    }
                }

                EditPanelSectionLabel {
                    visible: root.hiddenLockIslands.length > 0
                    text: Translation.tr("Hidden from the toolbars")
                }

                Repeater {
                    model: root.hiddenLockIslands

                    delegate: EditPanelRow {
                        required property string modelData
                        required property int index
                        staggerIndex: index
                        Layout.fillWidth: true
                        first: index === 0
                        last: index === root.hiddenLockIslands.length - 1
                        symbol: root.lockIslandSymbols[modelData] ?? "widgets"
                        title: root.lockIslandNames[modelData] ?? modelData
                        trailingKind: "add"
                        onActivated: root.showLockIsland(modelData)
                    }
                }

                EditPanelRow {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    first: true
                    last: false
                    rowEnabled: root.anyLockFork
                    symbol: "reset_wrench"
                    title: Translation.tr("Use desktop layout")
                    subtitle: Translation.tr("Drop the positions this screen's lock keeps of its own")
                    trailingKind: "none"
                    onActivated: root.lockLayoutResetRequested()
                }

                EditPanelRow {
                    Layout.fillWidth: true
                    first: false
                    last: true
                    destructive: true
                    symbol: "view_agenda"
                    title: Translation.tr("Reset the islands")
                    subtitle: Translation.tr("Their order, and everything hidden from them")
                    trailingKind: "none"
                    onActivated: root.resetRequested("lockIslands")
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 8
                }
            }
        }
    }

    // The drag ghost: the row's name carried under the pointer, parented
    // outside the reveal so it is not clipped at the panel's edge.
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
}
