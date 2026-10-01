pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "../../../../services/reminders/RemindersLogic.js" as Logic

/**
 * Reminders, after Samsung Reminder (One UI 8): the home screen's list cards (Today,
 * Scheduled, Important, No alert, Completed), the user's categories, the "Try these out"
 * templates and recent reminders; each list grouped by day; search with its filters; a
 * recycle bin; and the "Add reminder" bar along the bottom, with the microphone.
 *
 * Editing happens in the side sheet like everywhere else in the app. The page keeps only
 * which list is open, what is selected and what is being searched; the reminders belong
 * to RemindersService.
 */
Item {
    id: root

    property date now: new Date()
    property bool compact: false
    property bool wide: false
    property ClockSidePanel panels: null
    property real layoutWidth: root.width

    signal settingsRequested()

    // ── Settings ────────────────────────────────────────────────────────
    readonly property var settings: Config.options.clockApp.reminders
    readonly property string sortBy: root.settings?.sortBy ?? "alertTime"
    readonly property bool pinImportant: root.settings?.pinImportant ?? true
    readonly property bool showCompleted: root.settings?.showCompleted ?? false
    readonly property string itemView: root.settings?.view ?? "card"

    // ── Where we are ────────────────────────────────────────────────────
    /// "home" | "list" | "search" | "trash"
    property string view: "home"
    /// In "list": a smart list id ("today", …) or "cat:<category id>".
    property string listId: ""
    property var selected: []
    property bool selectMode: false
    property bool menuOpen: false
    property string searchText: ""
    property var searchFilters: ({ checklist: false, images: false, links: false, completed: false })

    readonly property bool selecting: root.selectMode || root.selected.length > 0
    readonly property string categoryId: root.listId.startsWith("cat:") ? root.listId.slice(4) : ""
    readonly property var smart: RemindersStyle.smartList(root.listId)
    readonly property bool inTrash: root.view === "trash"
    readonly property string listTitle: root.view === "search" ? Translation.tr("Search")
        : root.inTrash ? Translation.tr("Recycle bin")
        : root.categoryId.length > 0 ? RemindersService.categoryName(root.categoryId)
        : (root.smart?.label ?? "")

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property real contentWidth: Math.min(root.width - ClockStyle.gapTiny * 2, 1180)
    readonly property real contentLayoutWidth: Math.min(root.layoutWidth - ClockStyle.gapTiny * 2, 1180)
    readonly property int tileColumns: root.contentLayoutWidth >= 860 ? 5 : root.contentLayoutWidth >= 520 ? 3 : 2
    readonly property int listColumns: root.contentLayoutWidth >= 980 && root.itemView === "card" ? 2 : 1
    readonly property int categoryColumns: root.contentLayoutWidth >= 760 ? 2 : 1

    // ── Data ────────────────────────────────────────────────────────────
    readonly property var counts: Logic.smartCounts(RemindersService.reminders, root.now)
    readonly property var categoryCounts: Logic.categoryCounts(RemindersService.reminders)
    readonly property var categoryOrder: RemindersService.categoryOrder()
    property var memo: ({})
    /// What a delegate shows for the frame between its reminder leaving and the list
    /// dropping it: every field present, so nothing reads off undefined.
    readonly property var placeholder: ({ id: "", title: "", notes: "", categoryId: "default", checklist: [], attachments: [],
        schedule: null, completed: false, important: false, early: null, snoozedUntil: 0, alert: "default" })

    /// The open list as groups of ids — ids, so a reminder edited in place keeps its
    /// delegate (and an unchanged list keeps the very same array).
    readonly property var groups: {
        let list;
        let grouped = false;
        const all = RemindersService.reminders;
        if (root.view === "trash") {
            list = Logic.sortReminders(RemindersService.trashed, "modified", false, {}, RemindersService.allDayTime);
        } else if (root.view === "search") {
            const filtered = Logic.search(all, root.searchText, root.searchFilters);
            list = Logic.sortReminders(filtered, root.sortBy, root.pinImportant, root.categoryOrder, RemindersService.allDayTime);
        } else if (root.view === "list" && root.listId === "completed") {
            list = Logic.sortReminders(all.filter(item => Logic.inSmartList(item, "completed", root.now)), "completed", false, {},
                RemindersService.allDayTime);
        } else if (root.view === "list") {
            const open = root.categoryId.length > 0
                ? all.filter(item => Logic.isLive(item) && item.categoryId === root.categoryId)
                : all.filter(item => Logic.inSmartList(item, root.listId, root.now));
            list = Logic.sortReminders(open, root.sortBy, root.pinImportant, root.categoryOrder, RemindersService.allDayTime);
            grouped = root.sortBy === "alertTime" && root.listId !== "noAlert" && root.listId !== "important";
        } else {
            return ObjectUtils.keep(root.memo, "groups", []);
        }
        let groups = grouped
            ? Logic.groupByDay(list, root.now, RemindersService.allDayTime).map(group => ({ key: group.key, ids: group.reminders.map(item => item.id) }))
            : [{ key: "", ids: list.map(item => item.id) }];
        // A category list shows its finished reminders under them, when asked to.
        if (root.view === "list" && root.categoryId.length > 0 && root.showCompleted) {
            const done = Logic.sortReminders(all.filter(item => !item.deletedAt && item.completed && item.categoryId === root.categoryId),
                "completed", false, {}, RemindersService.allDayTime);
            if (done.length > 0)
                groups = groups.concat([{ key: "completed", ids: done.map(item => item.id) }]);
        }
        return ObjectUtils.keep(root.memo, "groups", groups.filter(group => group.ids.length > 0));
    }
    readonly property int shownCount: root.groups.reduce((sum, group) => sum + group.ids.length, 0)

    readonly property var recentIds: ObjectUtils.keep(root.memo, "recent", RemindersService.reminders
        .filter(item => Logic.isLive(item))
        .sort((a, b) => b.modifiedAt - a.modifiedAt)
        .slice(0, 5)
        .map(item => item.id))

    readonly property var templates: [
        { id: "workout", icon: "fitness_center", title: Translation.tr("Workout schedule"), subtitle: Translation.tr("Tuesdays and Thursdays") },
        { id: "payment", icon: "payments", title: Translation.tr("Monthly payment"), subtitle: Translation.tr("The 1st of every month") },
        { id: "pickup", icon: "local_shipping", title: Translation.tr("Pickup reminder"), subtitle: Translation.tr("Tomorrow at 17:00") },
        { id: "home", icon: "home", title: Translation.tr("When you get home"), subtitle: Translation.tr("This evening") },
        { id: "grocery", icon: "shopping_cart", title: Translation.tr("Grocery list"), subtitle: Translation.tr("A checklist to tick off") }
    ]

    readonly property string pageSubtitle: {
        const today = root.counts.today;
        const next = RemindersService.nextAlert;
        const nextItem = next ? RemindersService.reminder(next.id) : null;
        const parts = [];
        if (today > 0)
            parts.push(today === 1 ? Translation.tr("1 for today") : Translation.tr("%1 for today").arg(String(today)));
        if (nextItem)
            parts.push(Translation.tr("Next: %1").arg(nextItem.title || Translation.tr("Reminder")) + " · " + RemindersService.whenText(nextItem, root.now));
        return parts.length > 0 ? parts.join(" · ") : Translation.tr("Nothing coming up");
    }
    readonly property bool actionAvailable: !root.inTrash && !root.selecting
    readonly property string editingId: root.panels?.isShowing(editorSheet) ? (root.panels.current?.reminderId ?? "") : ""

    // ── Actions ─────────────────────────────────────────────────────────
    function primaryAction(): void {
        root.openEditor("", root.draftForList({}));
    }

    function openEditor(id: string, draft): void {
        root.menuOpen = false;
        root.panels?.show(editorSheet, { reminderId: id, initialDraft: draft ?? null });
    }

    function openList(id: string): void {
        root.clearSelection();
        root.menuOpen = false;
        root.listId = id;
        root.view = "list";
        flick.contentY = 0;
    }

    function goHome(): void {
        root.clearSelection();
        root.menuOpen = false;
        root.view = "home";
        root.listId = "";
        root.searchText = "";
        flick.contentY = 0;
    }

    function openSearch(): void {
        root.clearSelection();
        root.menuOpen = false;
        root.view = "search";
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    /** What a new reminder starts with, from the list it is added in. */
    function draftForList(base) {
        const draft = Object.assign({}, base);
        if (root.categoryId.length > 0)
            draft.categoryId = root.categoryId;
        if (root.view === "list" && root.listId === "important")
            draft.important = true;
        if (root.view === "list" && (root.listId === "today" || root.listId === "scheduled") && !draft.schedule) {
            const soon = new Date(Date.now() + 3600000);
            draft.schedule = root.listId === "today"
                ? { date: Qt.formatDate(new Date(), "yyyy-MM-dd"), time: "" }
                : { date: Qt.formatDate(soon, "yyyy-MM-dd"), time: Qt.formatTime(soon, "HH:mm") };
        }
        return draft;
    }

    function quickAdd(text: string): void {
        const title = text.trim();
        if (title.length === 0)
            return;
        RemindersService.create(root.draftForList({ title: title }));
        quickField.text = "";
    }

    function useTemplate(id: string): void {
        const draft = Logic.templateDraft(id, new Date(), {
            workout: Translation.tr("Workout"),
            payment: Translation.tr("Pay the bills"),
            pickup: Translation.tr("Pick up the parcel"),
            home: Translation.tr("When I get home"),
            grocery: Translation.tr("Grocery list"),
            groceryItems: [Translation.tr("Milk"), Translation.tr("Bread"), Translation.tr("Eggs"), Translation.tr("Fruit")]
        });
        root.openEditor("", draft);
    }

    function toggleSelected(id: string): void {
        root.selected = root.selected.includes(id) ? root.selected.filter(item => item !== id) : root.selected.concat([id]);
        if (root.selected.length === 0)
            root.selectMode = false;
    }

    function clearSelection(): void {
        root.selected = [];
        root.selectMode = false;
    }

    function selectAll(): void {
        const all = [];
        root.groups.forEach(group => group.ids.forEach(id => all.push(id)));
        root.selected = all;
    }

    function groupTitle(key: string): string {
        switch (key) {
        case "overdue": return Translation.tr("Overdue");
        case "today": return Translation.tr("Today");
        case "tomorrow": return Translation.tr("Tomorrow");
        case "week": return Translation.tr("Next 7 days");
        case "later": return Translation.tr("Later");
        case "none": return Translation.tr("No alert");
        case "completed": return Translation.tr("Completed");
        }
        return "";
    }

    function setOption(key: string, value): void {
        Config.options.clockApp.reminders[key] = value;
    }

    // A notification's Open, or anything else that asks for one reminder.
    function consumePendingOpen(): void {
        const id = GlobalStates.reminderToOpen;
        if (id.length === 0)
            return;
        GlobalStates.reminderToOpen = "";
        if (RemindersService.reminder(id))
            Qt.callLater(() => root.openEditor(id, null));
    }

    Component.onCompleted: root.consumePendingOpen()

    Connections {
        target: GlobalStates
        function onReminderToOpenChanged() {
            root.consumePendingOpen();
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key === Qt.Key_F) {
            root.openSearch();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.menuOpen) {
            root.menuOpen = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.selecting) {
            root.clearSelection();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.view !== "home") {
            root.goHome();
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete && root.selected.length > 0) {
            if (root.inTrash)
                RemindersService.deleteForever(root.selected);
            else
                RemindersService.trash(root.selected);
            root.clearSelection();
            event.accepted = true;
        }
    }

    Component {
        id: editorSheet
        ReminderEditorSheet {}
    }

    Component {
        id: categorySheet
        ReminderCategorySheet {}
    }

    Component {
        id: categoriesSheet
        ReminderCategoriesSheet {
            onEditRequested: categoryId => root.panels?.show(categorySheet, { categoryId: categoryId })
            onMoved: root.clearSelection()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: ClockStyle.gapSmall

        // ── Toolbar ─────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: 48

            // Selection replaces the toolbar with what can be done to the selection.
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gapTiny
                anchors.rightMargin: ClockStyle.gapTiny
                visible: root.selecting
                spacing: 2

                ClockIconButton {
                    symbol: "close"
                    tooltip: Translation.tr("Cancel")
                    onClicked: root.clearSelection()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.selected.length === 0 ? Translation.tr("Select reminders")
                        : Translation.tr("%1 selected").arg(String(root.selected.length))
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSurface
                    elide: Text.ElideRight
                }

                ClockIconButton {
                    symbol: "select_all"
                    tooltip: Translation.tr("Select all")
                    onClicked: root.selectAll()
                }

                ClockIconButton {
                    visible: !root.inTrash
                    enabled: root.selected.length > 0
                    symbol: "check_circle"
                    tooltip: Translation.tr("Complete")
                    onClicked: {
                        RemindersService.completeMany(root.selected);
                        root.clearSelection();
                    }
                }

                ClockIconButton {
                    visible: !root.inTrash
                    enabled: root.selected.length > 0
                    symbol: "drive_file_move"
                    tooltip: Translation.tr("Move to category")
                    onClicked: root.panels?.show(categoriesSheet, { mode: "move", reminderIds: root.selected })
                }

                ClockIconButton {
                    visible: !root.inTrash
                    enabled: root.selected.length > 0
                    symbol: "content_copy"
                    tooltip: Translation.tr("Duplicate")
                    onClicked: {
                        root.selected.forEach(id => RemindersService.duplicate(id));
                        root.clearSelection();
                    }
                }

                ClockIconButton {
                    visible: root.inTrash
                    enabled: root.selected.length > 0
                    symbol: "restore_from_trash"
                    tooltip: Translation.tr("Restore")
                    onClicked: {
                        RemindersService.restoreFromTrash(root.selected);
                        root.clearSelection();
                    }
                }

                ClockIconButton {
                    enabled: root.selected.length > 0
                    symbol: root.inTrash ? "delete_forever" : "delete"
                    colIcon: ClockStyle.colError
                    tooltip: root.inTrash ? Translation.tr("Delete for good") : Translation.tr("Move to recycle bin")
                    onClicked: {
                        if (root.inTrash)
                            RemindersService.deleteForever(root.selected);
                        else
                            RemindersService.trash(root.selected);
                        root.clearSelection();
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gapTiny
                anchors.rightMargin: ClockStyle.gapTiny
                visible: !root.selecting
                spacing: 2

                ClockIconButton {
                    visible: root.view !== "home"
                    symbol: "arrow_back"
                    tooltip: Translation.tr("Back")
                    onClicked: root.goHome()
                }

                // A list's name, in its category colour.
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.view === "list" || root.view === "trash"
                    spacing: ClockStyle.gapSmall

                    MaterialSymbol {
                        text: root.inTrash ? "delete" : root.categoryId.length > 0 ? RemindersStyle.categoryIcon(root.categoryId) : (root.smart?.icon ?? "")
                        iconSize: ClockStyle.iconNormal
                        fill: 1
                        color: root.categoryId.length > 0 ? RemindersStyle.categoryColor(root.categoryId) : ClockStyle.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.listTitle + (root.shownCount > 0 ? "  " + root.shownCount : "")
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textTitle - 4
                        color: ClockStyle.colOnSurface
                        elide: Text.ElideRight
                    }
                }

                // Search: the field fills the toolbar, filters below it.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.view === "search"
                    implicitHeight: 44
                    radius: height / 2
                    color: ClockStyle.colSurfaceHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 6
                        spacing: 8

                        MaterialSymbol {
                            text: "search"
                            iconSize: ClockStyle.iconSmall + 4
                            color: ClockStyle.colOnSurfaceVariant
                        }

                        StyledTextInput {
                            id: searchField
                            Layout.fillWidth: true
                            clip: true
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: ClockStyle.colOnSurface
                            onTextChanged: root.searchText = searchField.text
                            Keys.onEscapePressed: event => {
                                root.goHome();
                                event.accepted = true;
                            }

                            StyledText {
                                anchors.fill: parent
                                visible: searchField.text.length === 0
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Search reminders")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                        }

                        ClockIconButton {
                            visible: searchField.text.length > 0
                            symbol: "close"
                            size: 32
                            iconSize: ClockStyle.iconSmall + 2
                            tooltip: Translation.tr("Clear")
                            onClicked: searchField.text = ""
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    visible: root.view === "home"
                }

                ClockIconButton {
                    visible: root.view !== "search"
                    symbol: "search"
                    tooltip: Translation.tr("Search") + " (Ctrl+F)"
                    onClicked: root.openSearch()
                }

                ClockIconButton {
                    visible: root.view !== "home"
                    enabled: root.shownCount > 0
                    symbol: "checklist_rtl"
                    tooltip: Translation.tr("Select")
                    onClicked: root.selectMode = true
                }

                ClockIconButton {
                    id: menuButton
                    symbol: "more_vert"
                    toggled: root.menuOpen
                    tooltip: Translation.tr("More options")
                    onClicked: root.menuOpen = !root.menuOpen
                }
            }
        }

        // Search filters (Samsung's Checklists / Images / Links / Complete).
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: ClockStyle.gapTiny
            visible: root.view === "search"
            spacing: 6

            Repeater {
                model: [
                    { id: "checklist", icon: "checklist", label: Translation.tr("Checklists") },
                    { id: "images", icon: "image", label: Translation.tr("Images") },
                    { id: "links", icon: "link", label: Translation.tr("Links") },
                    { id: "completed", icon: "check_circle", label: Translation.tr("Completed") }
                ]

                ClockFormChip {
                    required property var modelData
                    symbol: modelData.icon
                    label: modelData.label
                    selected: root.searchFilters[modelData.id] === true
                    onTriggered: {
                        const next = Object.assign({}, root.searchFilters);
                        next[modelData.id] = !next[modelData.id];
                        root.searchFilters = next;
                    }
                }
            }
        }

        // ── Page ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledFlickable {
                id: flick
                anchors.fill: parent
                contentWidth: width
                contentHeight: page.implicitHeight + ClockStyle.fabClearance
                clip: true

                ColumnLayout {
                    id: page
                    x: (flick.width - width) / 2
                    y: ClockStyle.gapTiny
                    width: root.contentWidth
                    spacing: ClockStyle.gapHuge

                    // ── Home: the list cards ────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.view === "home"
                        spacing: ClockStyle.gap

                        SectionHeader {
                            title: Translation.tr("Lists")
                            collapsible: true
                            collapsed: !(root.settings?.categoriesExpanded ?? true)
                            onToggled: root.setOption("categoriesExpanded", !(root.settings?.categoriesExpanded ?? true))
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: root.tileColumns
                            columnSpacing: ClockStyle.gap
                            rowSpacing: ClockStyle.gap
                            uniformCellWidths: true

                            Repeater {
                                model: RemindersStyle.smartLists

                                SmartTile {
                                    required property var modelData
                                    required property int index
                                    list: modelData
                                    count: root.counts[modelData.id] ?? 0
                                    collapsed: !(root.settings?.categoriesExpanded ?? true)

                                    StaggeredEntrance {
                                        index: parent.index
                                        active: !ClockStyle.reducedMotion
                                    }
                                }
                            }
                        }
                    }

                    // ── Home: My reminders ──────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.view === "home"
                        spacing: ClockStyle.gapSmall

                        SectionHeader {
                            title: Translation.tr("My reminders")

                            ClockButton {
                                variant: "text"
                                symbol: "create_new_folder"
                                label: Translation.tr("Add")
                                onClicked: root.panels?.show(categorySheet, {})
                            }

                            ClockButton {
                                variant: "text"
                                symbol: "tune"
                                label: Translation.tr("Manage")
                                onClicked: root.panels?.show(categoriesSheet, { mode: "manage" })
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: root.categoryColumns
                            columnSpacing: ClockStyle.gapSmall
                            rowSpacing: ClockStyle.gapSmall
                            uniformCellWidths: true

                            Repeater {
                                model: RemindersService.categories

                                CategoryRow {
                                    required property var modelData
                                    category: modelData
                                }
                            }
                        }
                    }

                    // ── Home: templates ─────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.view === "home" && (root.settings?.showTemplates ?? true)
                        spacing: ClockStyle.gapSmall

                        SectionHeader {
                            title: Translation.tr("Try these out")

                            ClockIconButton {
                                symbol: "close"
                                size: 32
                                iconSize: ClockStyle.iconSmall + 2
                                tooltip: Translation.tr("Hide templates")
                                onClicked: root.setOption("showTemplates", false)
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            Repeater {
                                model: root.templates

                                TemplateCard {
                                    required property var modelData
                                    template: modelData
                                }
                            }
                        }
                    }

                    // ── Home: recent ────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.view === "home" && root.recentIds.length > 0
                        spacing: ClockStyle.gapSmall

                        SectionHeader {
                            title: Translation.tr("Recent reminders")
                        }

                        Repeater {
                            model: root.recentIds

                            ReminderItem {
                                required property string modelData
                                reminder: RemindersService.reminder(modelData) ?? root.placeholder
                                visible: RemindersService.reminder(modelData) !== null
                                now: root.now
                                view: root.itemView
                                editing: root.editingId === modelData
                                onOpenRequested: root.openEditor(modelData, null)
                                onSelectToggled: root.openEditor(modelData, null)
                            }
                        }
                    }

                    // ── A list ──────────────────────────────────────────
                    Repeater {
                        model: root.view === "home" ? [] : root.groups

                        ColumnLayout {
                            id: group
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            SectionHeader {
                                visible: group.modelData.key.length > 0
                                title: root.groupTitle(group.modelData.key)
                                count: group.modelData.ids.length
                                alert: group.modelData.key === "overdue"
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: root.listColumns
                                columnSpacing: ClockStyle.gapSmall
                                rowSpacing: root.itemView === "list" ? 4 : ClockStyle.gapSmall
                                uniformCellWidths: true

                                Repeater {
                                    model: group.modelData.ids

                                    ReminderItem {
                                        required property string modelData
                                        Layout.alignment: Qt.AlignTop
                                        reminder: RemindersService.reminder(modelData) ?? root.placeholder
                                        now: root.now
                                        view: root.itemView
                                        selecting: root.selecting
                                        selected: root.selected.includes(modelData)
                                        editing: root.editingId === modelData
                                        showCategory: root.categoryId.length === 0
                                        inTrash: root.inTrash
                                        onOpenRequested: {
                                            if (root.inTrash)
                                                root.toggleSelected(modelData);
                                            else
                                                root.openEditor(modelData, null);
                                        }
                                        onSelectToggled: root.toggleSelected(modelData)
                                    }
                                }
                            }
                        }
                    }

                    // Bin and completed housekeeping, under their lists.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: (root.inTrash || (root.view === "list" && root.listId === "completed")) && root.shownCount > 0
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: root.inTrash
                                ? (RemindersService.trashDays > 0
                                    ? Translation.tr("Reminders in the recycle bin are deleted after %1 days.").arg(String(RemindersService.trashDays))
                                    : Translation.tr("Reminders stay in the recycle bin until you empty it."))
                                : (RemindersService.autoDeleteCompletedDays > 0
                                    ? Translation.tr("Completed reminders move to the recycle bin after %1 days.").arg(String(RemindersService.autoDeleteCompletedDays))
                                    : "")
                            wrapMode: Text.Wrap
                            font.pixelSize: ClockStyle.textSmall
                            color: ClockStyle.colSubtext
                        }

                        ClockButton {
                            variant: "tonal"
                            danger: true
                            symbol: root.inTrash ? "delete_forever" : "delete_sweep"
                            label: root.inTrash ? Translation.tr("Empty recycle bin") : Translation.tr("Clear completed")
                            onClicked: {
                                if (root.inTrash)
                                    RemindersService.emptyTrash();
                                else
                                    RemindersService.clearCompleted();
                            }
                        }
                    }
                }
            }

            // An empty list says what goes in it.
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - ClockStyle.gapHuge * 2, 420)
                visible: root.view !== "home" && root.shownCount === 0
                spacing: ClockStyle.gapHuge

                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: root.inTrash ? "delete" : root.view === "search" ? "search" : (root.smart?.icon ?? "checklist")
                    shape: root.smart?.shape ?? "Cookie9Sided"
                    title: root.inTrash ? Translation.tr("Recycle bin is empty")
                        : root.view === "search" ? (root.searchText.length > 0 ? Translation.tr("No matches") : Translation.tr("Search your reminders"))
                        : root.listId === "completed" ? Translation.tr("Nothing completed yet")
                        : Translation.tr("No reminders")
                    subtitle: root.inTrash ? ""
                        : root.view === "search" ? Translation.tr("Titles, notes, checklists and links are all searched.")
                        : Translation.tr("Add one below, or press Ctrl+N for the full editor.")
                }
            }
        }

        // ── Add reminder ────────────────────────────────────────────────
        // Samsung's bottom bar: type and press Enter, or dictate.
        Rectangle {
            id: quickBar
            Layout.fillWidth: true
            Layout.rightMargin: ClockStyle.fabSizeLarge + ClockStyle.gapLarge * 2 - ClockStyle.paneGap
            Layout.bottomMargin: ClockStyle.gapLarge + (ClockStyle.fabSizeLarge - implicitHeight) / 2
            visible: !root.inTrash && root.view !== "search" && !(root.view === "list" && root.listId === "completed") && !root.selecting
            implicitHeight: 56
            radius: height / 2
            color: quickField.activeFocus ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                ClockIconButton {
                    symbol: "add"
                    size: 40
                    tooltip: Translation.tr("Add reminder")
                    onClicked: quickField.text.trim().length > 0 ? root.quickAdd(quickField.text) : root.primaryAction()
                }

                StyledTextInput {
                    id: quickField
                    Layout.fillWidth: true
                    clip: true
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: ClockStyle.colOnSurface
                    onAccepted: root.quickAdd(quickField.text)
                    Keys.onEscapePressed: event => {
                        quickField.text = "";
                        root.forceActiveFocus();
                        event.accepted = true;
                    }

                    StyledText {
                        anchors.fill: parent
                        visible: quickField.text.length === 0
                        verticalAlignment: Text.AlignVCenter
                        text: root.categoryId.length > 0
                            ? Translation.tr("Add reminder to %1").arg(RemindersService.categoryName(root.categoryId))
                            : Translation.tr("Add reminder")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1Inactive
                    }
                }

                ClockIconButton {
                    visible: quickField.text.trim().length > 0
                    symbol: "open_in_full"
                    size: 40
                    iconSize: ClockStyle.iconSmall + 4
                    tooltip: Translation.tr("More details")
                    onClicked: {
                        root.openEditor("", root.draftForList({ title: quickField.text.trim() }));
                        quickField.text = "";
                    }
                }

                // Dictation types into the focused field, so focus it first.
                ClockIconButton {
                    visible: DictationService.enabled
                    symbol: DictationService.recording ? "graphic_eq" : "mic"
                    size: 40
                    toggled: DictationService.busy
                    tooltip: DictationService.recording ? Translation.tr("Stop dictating") : Translation.tr("Dictate")
                    onClicked: {
                        quickField.forceActiveFocus();
                        DictationService.toggle();
                    }
                }
            }
        }
    }

    // ── More options ────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        visible: root.menuOpen
        z: 20
        onClicked: root.menuOpen = false
    }

    Loader {
        active: root.menuOpen
        z: 21
        anchors.right: parent.right
        anchors.rightMargin: ClockStyle.gapTiny
        y: 50
        sourceComponent: RemindersMenu {
            sortBy: root.sortBy
            pinImportant: root.pinImportant
            showCompleted: root.showCompleted
            itemView: root.itemView
            listId: root.listId
            inTrash: root.inTrash
            onOptionChanged: (key, value) => root.setOption(key, value)
            onManageRequested: {
                root.menuOpen = false;
                root.panels?.show(categoriesSheet, { mode: "manage" });
            }
            onTrashRequested: {
                root.clearSelection();
                root.menuOpen = false;
                root.view = "trash";
                root.listId = "";
            }
            onSettingsRequested: {
                root.menuOpen = false;
                root.settingsRequested();
            }
            onSyncRequested: {
                root.menuOpen = false;
                RemindersSync.syncNow();
            }
            onEditCategoryRequested: {
                root.menuOpen = false;
                root.panels?.show(categorySheet, { categoryId: root.categoryId });
            }
            onClosed: root.menuOpen = false
        }
    }

    // ── Pieces ──────────────────────────────────────────────────────────
    component SectionHeader: RowLayout {
        id: header
        property string title: ""
        property int count: -1
        property bool alert: false
        property bool collapsible: false
        property bool collapsed: false
        default property alias trailing: trailingRow.data

        signal toggled()

        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: ClockStyle.gapSmall

        StyledText {
            text: header.title
            font.pixelSize: ClockStyle.textNormal + 1
            font.weight: Font.Bold
            color: header.alert ? ClockStyle.colError : ClockStyle.colOnSurfaceVariant
        }

        StyledText {
            visible: header.count >= 0
            text: String(header.count)
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }

        Item {
            Layout.fillWidth: true
        }

        RowLayout {
            id: trailingRow
            spacing: 2
        }

        ClockIconButton {
            visible: header.collapsible
            symbol: "expand_less"
            size: 32
            iconSize: ClockStyle.iconSmall + 4
            rotation: header.collapsed ? 180 : 0
            tooltip: header.collapsed ? Translation.tr("Expand") : Translation.tr("Collapse")
            onClicked: header.toggled()

            Behavior on rotation {
                animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
            }
        }
    }

    /// One of the five list cards: icon, name and how many. Collapsed, they shrink to chips.
    component SmartTile: RippleButton {
        id: tile
        property var list
        property int count: 0
        property bool collapsed: false
        readonly property var colors: RemindersStyle.smartColors(tile.list.id)

        Layout.fillWidth: true
        implicitHeight: tile.collapsed ? 52 : 112
        buttonRadius: tile.collapsed ? ClockStyle.radiusFull : ClockStyle.radiusCard
        buttonRadiusPressed: ClockStyle.radiusNormal
        colBackground: ClockStyle.colIdleCard
        colBackgroundHover: ClockStyle.colIdleCardHover
        colRipple: ClockStyle.colSurfaceActive
        onClicked: root.openList(tile.list.id)

        Behavior on implicitHeight {
            animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
        }

        contentItem: Item {
            MaterialShapeWrappedMaterialSymbol {
                id: tileIcon
                anchors.left: parent.left
                anchors.leftMargin: tile.collapsed ? 8 : 16
                anchors.top: tile.collapsed ? undefined : parent.top
                anchors.topMargin: 14
                anchors.verticalCenter: tile.collapsed ? parent.verticalCenter : undefined
                text: tile.list.icon
                iconSize: tile.collapsed ? 16 : 20
                padding: tile.collapsed ? 7 : 10
                shape: tile.list.shapeKind
                color: tile.colors[0]
                colSymbol: tile.colors[1]
                fill: 1
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: tile.collapsed ? 16 : 18
                anchors.top: tile.collapsed ? undefined : parent.top
                anchors.topMargin: 10
                anchors.verticalCenter: tile.collapsed ? parent.verticalCenter : undefined
                text: String(tile.count)
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: tile.collapsed ? ClockStyle.textLarge : 34
                color: ClockStyle.colOnSurface
            }

            StyledText {
                anchors.left: tile.collapsed ? tileIcon.right : parent.left
                anchors.leftMargin: tile.collapsed ? 8 : 18
                anchors.right: parent.right
                anchors.rightMargin: tile.collapsed ? 44 : 12
                anchors.bottom: tile.collapsed ? undefined : parent.bottom
                anchors.bottomMargin: 14
                anchors.verticalCenter: tile.collapsed ? parent.verticalCenter : undefined
                text: tile.list.label
                elide: Text.ElideRight
                font.pixelSize: tile.collapsed ? ClockStyle.textNormal : Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: ClockStyle.colOnSurface
            }
        }
    }

    component CategoryRow: RippleButton {
        id: row
        property var category
        readonly property color colAccent: RemindersStyle.categoryColor(row.category.id)

        Layout.fillWidth: true
        implicitHeight: 60
        buttonRadius: ClockStyle.radiusLarge
        buttonRadiusPressed: ClockStyle.radiusNormal
        colBackground: ClockStyle.colIdleCard
        colBackgroundHover: ClockStyle.colIdleCardHover
        colRipple: ClockStyle.colSurfaceActive
        onClicked: root.openList("cat:" + row.category.id)

        contentItem: RowLayout {
            spacing: 12

            Rectangle {
                Layout.leftMargin: 10
                implicitWidth: 38
                implicitHeight: 38
                radius: 19
                color: row.colAccent

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: row.category.icon
                    iconSize: 19
                    fill: 1
                    color: RemindersStyle.onColor(row.colAccent)
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: RemindersService.categoryName(row.category.id)
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: ClockStyle.colOnSurface
            }

            MaterialSymbol {
                visible: row.category.pinned
                text: "keep"
                fill: 1
                iconSize: ClockStyle.iconSmall
                color: ClockStyle.colOnSurfaceVariant
            }

            MaterialSymbol {
                visible: row.category.remote?.todo?.listId ? true : false
                text: "cloud_done"
                iconSize: ClockStyle.iconSmall
                color: ClockStyle.colOnSurfaceVariant
            }

            StyledText {
                Layout.rightMargin: 16
                text: String(root.categoryCounts[row.category.id] ?? 0)
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: ClockStyle.textLarge
                color: ClockStyle.colOnSurfaceVariant
            }
        }
    }

    component TemplateCard: RippleButton {
        id: card
        property var template

        implicitWidth: 220
        implicitHeight: 72
        buttonRadius: ClockStyle.radiusLarge
        buttonRadiusPressed: ClockStyle.radiusNormal
        colBackground: ClockStyle.colSurfaceHigh
        colBackgroundHover: ClockStyle.colSurfaceHover
        colRipple: ClockStyle.colSurfaceActive
        onClicked: root.useTemplate(card.template.id)

        contentItem: RowLayout {
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                Layout.leftMargin: 10
                text: card.template.icon
                iconSize: 18
                padding: 9
                shape: MaterialShape.Shape.Cookie7Sided
                color: ClockStyle.colTertiaryContainer
                colSymbol: ClockStyle.colOnTertiaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.rightMargin: 10
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: card.template.title
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.template.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }
        }
    }
}
