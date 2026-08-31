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
    signal dockToggleRequested(string appId)
    signal lockLayoutResetRequested()

    property string section: "widgets"
    property string barBucket: "right"
    property var dragMetadata: null

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
    readonly property var barOffer: BarComponentRegistry.getAvailableComponents(root.usedBarIds)

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

    // One flat list of section headers and, under each open one, its widgets:
    // a list view can only be given rows, and collapsing by dropping the rows
    // costs nothing - a shut section has no delegates at all.
    readonly property var widgetRows: {
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

    readonly property bool lockTab: GlobalStates.editLockPreview
    onLockTabChanged: {
        if (root.lockTab ? (root.section === "bar" || root.section === "dock") : root.section === "lock")
            root.section = "widgets";
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
                    onClicked: root.section = "widgets"
                }
                SelectionGroupButton {
                    visible: !root.lockTab
                    buttonText: Translation.tr("Bar")
                    toggled: root.section === "bar"
                    onClicked: root.section = "bar"
                }
                SelectionGroupButton {
                    visible: !root.lockTab
                    rightmost: true
                    buttonText: Translation.tr("Dock")
                    toggled: root.section === "dock"
                    onClicked: root.section = "dock"
                }
                SelectionGroupButton {
                    visible: root.lockTab
                    rightmost: true
                    buttonText: Translation.tr("Lock screen")
                    toggled: root.section === "lock"
                    onClicked: root.section = "lock"
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                text: root.section === "widgets"
                    ? (root.lockTab
                        ? Translation.tr("Click a desktop widget to show or hide it on the lock screen. A widget that is not on the desktop is added to the lock screen only.")
                        : Translation.tr("Drag a widget onto the desktop to place it, or click to add or remove it. Drag a desktop widget here to remove it."))
                    : root.section === "lock"
                        ? Translation.tr("What the lock screen shows besides your widgets.")
                    : root.section === "bar"
                        ? Translation.tr("Click a widget to add it to the picked bar section.")
                        : Translation.tr("Click an app to pin or unpin it on the dock.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
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

                        MouseArea {
                            id: header
                            readonly property var group: row.modelData.group
                            readonly property bool open: root.widgetGroupExpanded(header.group.key)
                            readonly property int added: root.widgetGroupAdded(header.group)

                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleWidgetGroup(header.group.key)

                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.large
                                color: header.pressed ? Appearance.colors.colLayer1Active
                                    : header.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
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
                                    text: header.group.icon
                                    iconSize: 22
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: header.group.title
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: header.added > 0
                                        ? `${header.added}/${header.group.items.length}`
                                        : `${header.group.items.length}`
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: header.added > 0 ? Appearance.colors.colPrimary
                                        : Appearance.colors.colOnSurfaceVariant
                                }
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "keyboard_arrow_down"
                                    iconSize: 20
                                    color: Appearance.colors.colOnSurfaceVariant
                                    rotation: header.open ? 0 : -90
                                    Behavior on rotation {
                                        enabled: !Appearance.reducedMotion
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }
                            }
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
                                        && Math.abs(mouse.x - entry.pressX) < drag.threshold
                                        && Math.abs(mouse.y - entry.pressY) < drag.threshold)
                                    return;
                                entry.dragActive = true;
                                root.dragMetadata = entry.widget;
                                const point = entry.mapToItem(root.ghostParent ?? root, mouse.x, mouse.y);
                                ghost.x = point.x - ghost.width / 2;
                                ghost.y = point.y - ghost.height / 2;
                            }
                            onReleased: mouse => {
                                const wasDrag = entry.dragActive;
                                entry.dragActive = false;
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
            ButtonGroup {
                visible: root.section === "bar"
                Layout.leftMargin: 6
                Layout.rightMargin: 6

                SelectionGroupButton {
                    leftmost: true
                    buttonText: Translation.tr("Left")
                    toggled: root.barBucket === "left"
                    onClicked: root.barBucket = "left"
                }
                SelectionGroupButton {
                    buttonText: Translation.tr("Center")
                    toggled: root.barBucket === "center"
                    onClicked: root.barBucket = "center"
                }
                SelectionGroupButton {
                    rightmost: true
                    buttonText: Translation.tr("Right")
                    toggled: root.barBucket === "right"
                    onClicked: root.barBucket = "right"
                }
            }

            StyledListView {
                popin: false
                animateAppearance: false
                id: barList
                visible: root.section === "bar"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.section === "bar" ? root.barOffer : []

                delegate: CatalogueButton {
                    required property var modelData
                    width: barList.width
                    rowSymbol: modelData.icon ?? "widgets"
                    rowTitle: modelData.title ?? modelData.id
                    onClicked: root.barAddRequested(modelData.id, root.barBucket)
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
                model: root.section === "dock" ? TaskbarApps.apps : []

                delegate: CatalogueButton {
                    id: appRow
                    required property var modelData
                    readonly property string appId: modelData.appId ?? ""
                    width: appList.width
                    rowIcon: Quickshell.iconPath(AppSearch.guessIcon(appRow.appId), "image-missing")
                    rowTitle: DesktopEntries.heuristicLookup(appRow.appId)?.name ?? appRow.appId
                    rowChecked: modelData.pinned === true
                    onClicked: root.dockToggleRequested(appRow.appId)
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
