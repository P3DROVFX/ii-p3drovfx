pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.modes

/**
 * The Activity tab: what started, ended or ran, with the reason — so a mode that
 * "switched on by itself" can be traced. Days are cards, newest first, each entry a row
 * of its day's card the way the clock groups its settings; an entry whose actions were
 * not all applied unfolds to show which and why.
 *
 * Filter chips narrow it to modes, routines, or the entries with skipped actions; Clear
 * forgets the whole log after a confirm in the side sheet. Left / Right step through the
 * filters.
 */
Item {
    id: root

    // ── Contract ────────────────────────────────────────────────────────
    property bool compact: false

    readonly property string pageSubtitle: {
        const n = Modes.history.length;
        if (n === 0)
            return Translation.tr("Nothing has happened yet");
        const count = n === 1 ? Translation.tr("1 entry") : Translation.tr("%1 entries").arg(n);
        return root.failureCount > 0 ? count + " · " + Translation.tr("%1 with skipped actions").arg(root.failureCount) : count;
    }
    readonly property bool detailOpen: false
    readonly property string detailTitle: ""

    function closeDetail(): void {
    }

    function handleEscape(): bool {
        if (sidePanel.open) {
            sidePanel.close();
            return true;
        }
        if (root.filter !== "all") {
            root.filter = "all";
            return true;
        }
        return false;
    }

    function handleKey(key: int, modifiers: int): bool {
        if (sidePanel.open || modifiers !== Qt.NoModifier)
            return false;
        if (key !== Qt.Key_Left && key !== Qt.Key_Right)
            return false;
        const ids = root.filters.map(f => f.id);
        const index = ids.indexOf(root.filter);
        root.filter = ids[(index + (key === Qt.Key_Right ? 1 : ids.length - 1)) % ids.length];
        return true;
    }

    // ── State ───────────────────────────────────────────────────────────
    property string filter: "all"
    /// Unfolded entries by key, so a fold survives the log growing under it.
    property var unfolded: ({})

    readonly property var history: Modes.history
    readonly property int failureCount: root.history.filter(h => h.failed && h.failed.length).length
    readonly property var filters: [
        { id: "all", symbol: "history", label: Translation.tr("All"), count: root.history.length },
        { id: "modes", symbol: "tune", label: Translation.tr("Modes"), count: root.history.filter(h => h.kind === "mode").length },
        { id: "routines", symbol: "bolt", label: Translation.tr("Routines"), count: root.history.filter(h => h.kind === "routine").length },
        { id: "failures", symbol: "warning", label: Translation.tr("Problems"), count: root.failureCount }
    ]

    readonly property var entries: {
        const all = root.history;
        switch (root.filter) {
        case "modes":
            return all.filter(h => h.kind === "mode");
        case "routines":
            return all.filter(h => h.kind === "routine");
        case "failures":
            return all.filter(h => h.failed && h.failed.length);
        }
        return all;
    }

    // Day headers woven into the entries, newest first (the engine's order); each entry
    // knows whether it opens or closes its day's card.
    readonly property var rows: {
        const out = [];
        const list = root.entries;
        let header = null;
        for (let i = 0; i < list.length; i++) {
            const h = list[i];
            const day = ModeUi.startOfDay(h.t);
            const prev = i > 0 ? ModeUi.startOfDay(list[i - 1].t) : -1;
            const next = i < list.length - 1 ? ModeUi.startOfDay(list[i + 1].t) : -1;
            if (day !== prev) {
                header = { header: true, label: ModeUi.dayLabel(h.t), count: 0 };
                out.push(header);
            }
            header.count += 1;
            out.push({
                header: false,
                entry: h,
                first: day !== prev,
                last: day !== next,
                key: `${h.t}:${h.kind}:${h.id}:${h.event}`
            });
        }
        return out;
    }

    function toggleUnfold(key: string): void {
        const next = Object.assign({}, root.unfolded);
        if (next[key])
            delete next[key];
        else
            next[key] = true;
        root.unfolded = next;
    }

    function askClear(): void {
        const sheet = sidePanel.show(confirmSheet, {
            title: Translation.tr("Clear the activity?"),
            message: Translation.tr("Every entry listed here is forgotten. Modes and routines are not touched."),
            symbol: "delete_sweep",
            confirmLabel: Translation.tr("Clear")
        });
        sheet?.confirmed.connect(() => Modes.clearHistory());
    }

    // ── Layout ──────────────────────────────────────────────────────────
    readonly property real sheetWidth: root.compact
        ? root.width
        : Math.max(ClockStyle.sheetWidthMin, Math.min(ClockStyle.sheetWidth, root.width * 0.3))
    readonly property real padding: root.compact ? ClockStyle.gapTiny : ClockStyle.pagePadding
    readonly property real columnWidth: Math.min(pageArea.width - root.padding * 2, 920)
    readonly property real columnX: (pageArea.width - root.columnWidth) / 2

    Component {
        id: confirmSheet
        ModesConfirmSheet {}
    }

    // The closed sheet took the keyboard with it; hand the keys back to the page. A
    // timer rather than Qt.callLater, so nothing runs if the page is gone by then.
    Timer {
        id: focusTimer
        interval: 0
        onTriggered: root.forceActiveFocus()
    }

    Connections {
        target: sidePanel
        function onClosed() {
            focusTimer.restart();
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: pageArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !(root.compact && sidePanel.open)
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: ClockStyle.gap

                // ── Filters and Clear ───────────────────────────────────
                RowLayout {
                    Layout.fillWidth: false
                    Layout.preferredWidth: root.columnWidth
                    Layout.leftMargin: root.columnX
                    Layout.topMargin: ClockStyle.gapTiny
                    spacing: ClockStyle.gapSmall

                    Flow {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        Repeater {
                            model: root.filters

                            ClockChip {
                                required property var modelData
                                symbol: modelData.symbol
                                label: modelData.count > 0 ? `${modelData.label} · ${modelData.count}` : modelData.label
                                selected: root.filter === modelData.id
                                colIdle: modelData.id === "failures" && modelData.count > 0 ? ClockStyle.colErrorContainer : ClockStyle.colSurfaceHigh
                                colIdleHover: modelData.id === "failures" && modelData.count > 0 ? ClockStyle.colErrorContainerHover : ClockStyle.colSurfaceHover
                                colOnIdle: modelData.id === "failures" && modelData.count > 0 ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSurfaceVariant
                                onClicked: root.filter = modelData.id
                            }
                        }
                    }

                    ClockButton {
                        Layout.alignment: Qt.AlignTop
                        visible: Modes.history.length > 0
                        variant: "tonal"
                        danger: true
                        symbol: "delete_sweep"
                        label: Translation.tr("Clear")
                        iconOnly: root.columnWidth < 560
                        onClicked: root.askClear()
                    }
                }

                // ── Log ─────────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledListView {
                        id: list
                        anchors.fill: parent
                        visible: root.rows.length > 0
                        clip: true
                        spacing: 2
                        popin: false
                        animateAppearance: false
                        animatePopulate: false
                        bottomMargin: ClockStyle.gapHuge
                        model: root.rows

                        delegate: Item {
                            id: row
                            required property var modelData
                            required property int index

                            readonly property bool header: row.modelData.header === true
                            readonly property var entry: row.modelData.entry ?? null
                            readonly property var def: ModeUi.historyDef(row.entry)
                            readonly property string colorKey: row.def?.color ?? ""
                            readonly property var failed: Array.from(row.entry?.failed ?? [])
                            readonly property bool hasFailed: row.failed.length > 0
                            readonly property bool expanded: row.hasFailed && root.unfolded[row.modelData.key] === true
                            readonly property bool started: row.entry?.event === "start" || row.entry?.event === "run"

                            width: list.width
                            implicitHeight: row.header
                                ? dayRow.implicitHeight + (row.index === 0 ? ClockStyle.gapSmall : ClockStyle.gapHuge) + ClockStyle.gapSmall
                                : card.implicitHeight

                            // ── Day header ──────────────────────────────────
                            RowLayout {
                                id: dayRow
                                visible: row.header
                                x: root.columnX + ClockStyle.gapSmall
                                width: root.columnWidth - ClockStyle.gapSmall * 2
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: ClockStyle.gapSmall
                                spacing: ClockStyle.gap

                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.label ?? ""
                                    elide: Text.ElideRight
                                    font.family: ClockStyle.fontTitle
                                    font.variableAxes: ClockStyle.axesTitle
                                    font.pixelSize: ClockStyle.textLarge + 3
                                    color: ClockStyle.colOnBackground
                                }

                                StyledText {
                                    readonly property int n: row.modelData.count ?? 0
                                    text: n === 1 ? Translation.tr("1 entry") : Translation.tr("%1 entries").arg(n)
                                    font.pixelSize: ClockStyle.textSmall
                                    color: ClockStyle.colSubtext
                                }
                            }

                            // ── Entry ───────────────────────────────────────
                            Rectangle {
                                id: card
                                visible: !row.header
                                x: root.columnX
                                width: root.columnWidth
                                implicitHeight: cardColumn.implicitHeight + ClockStyle.gap * 2
                                topLeftRadius: row.modelData.first ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
                                topRightRadius: topLeftRadius
                                bottomLeftRadius: row.modelData.last ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
                                bottomRightRadius: bottomLeftRadius
                                color: cardArea.containsMouse && row.hasFailed ? ClockStyle.colIdleCardHover : ClockStyle.colPane

                                Behavior on implicitHeight {
                                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                                }
                                Behavior on color {
                                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                                }

                                MouseArea {
                                    id: cardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: row.hasFailed
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleUnfold(row.modelData.key)
                                }

                                ColumnLayout {
                                    id: cardColumn
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                        topMargin: ClockStyle.gap
                                        leftMargin: ClockStyle.gap + 2
                                        rightMargin: ClockStyle.gapLarge
                                    }
                                    spacing: ClockStyle.gapSmall

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: ClockStyle.gap

                                        MaterialShapeWrappedMaterialSymbol {
                                            text: row.def?.icon ?? "history"
                                            iconSize: 18
                                            padding: 9
                                            shape: row.entry?.kind === "routine" ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Cookie9Sided
                                            fill: row.started ? 1 : 0
                                            color: row.def ? (row.started ? ModeUi.accent(row.colorKey) : ModeUi.container(row.colorKey)) : ClockStyle.colSurfaceHigh
                                            colSymbol: row.def ? (row.started ? ModeUi.onAccent(row.colorKey) : ModeUi.onContainer(row.colorKey)) : ClockStyle.colOnSurfaceVariant
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: ClockStyle.gapSmall - 2

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    Layout.maximumWidth: Math.ceil(implicitWidth)
                                                    text: ModeUi.historyName(row.entry)
                                                    elide: Text.ElideRight
                                                    font.pixelSize: ClockStyle.textNormal + 1
                                                    font.weight: Font.DemiBold
                                                    color: ClockStyle.colOnSurface
                                                }

                                                StyledText {
                                                    text: ModeUi.historyEventText(row.entry).toLowerCase()
                                                    font.pixelSize: ClockStyle.textNormal
                                                    color: ClockStyle.colOnSurfaceVariant
                                                }

                                                Rectangle {
                                                    visible: row.entry?.kind === "routine"
                                                    implicitWidth: kindText.implicitWidth + ClockStyle.gapSmall * 2
                                                    implicitHeight: 20
                                                    radius: ClockStyle.radiusSmall / 2 + 2
                                                    color: ClockStyle.colSurfaceHigh

                                                    StyledText {
                                                        id: kindText
                                                        anchors.centerIn: parent
                                                        text: Translation.tr("routine")
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        font.weight: Font.DemiBold
                                                        color: ClockStyle.colOnSurfaceVariant
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: ModeUi.historyWhyText(row.entry)
                                                elide: Text.ElideRight
                                                font.pixelSize: ClockStyle.textSmall
                                                color: ClockStyle.colSubtext
                                            }
                                        }

                                        Rectangle {
                                            visible: row.hasFailed
                                            implicitWidth: failedRow.implicitWidth + ClockStyle.gap + 4
                                            implicitHeight: 28
                                            radius: ClockStyle.radiusSmall
                                            color: ClockStyle.colErrorContainer

                                            RowLayout {
                                                id: failedRow
                                                anchors.centerIn: parent
                                                spacing: ClockStyle.gapTiny

                                                MaterialSymbol {
                                                    text: "warning"
                                                    iconSize: ClockStyle.iconSmall - 1
                                                    color: ClockStyle.colOnErrorContainer
                                                }

                                                StyledText {
                                                    text: row.failed.length === 1 ? Translation.tr("1 skipped")
                                                        : Translation.tr("%1 skipped").arg(row.failed.length)
                                                    font.pixelSize: ClockStyle.textSmall
                                                    font.weight: Font.DemiBold
                                                    color: ClockStyle.colOnErrorContainer
                                                }

                                                MaterialSymbol {
                                                    text: "expand_more"
                                                    iconSize: ClockStyle.iconSmall - 1
                                                    rotation: row.expanded ? 180 : 0
                                                    color: ClockStyle.colOnErrorContainer

                                                    Behavior on rotation {
                                                        animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                                                    }
                                                }
                                            }
                                        }

                                        StyledText {
                                            text: ModeUi.clock(row.entry?.t ?? 0)
                                            font.family: ClockStyle.fontMain
                                            font.variableAxes: ClockStyle.axesDigitsBold
                                            font.pixelSize: ClockStyle.textLarge + 3
                                            color: ClockStyle.colOnSurface
                                        }
                                    }

                                    // One line per skipped action: "type: reason".
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 48
                                        Layout.bottomMargin: ClockStyle.gapTiny
                                        visible: row.expanded
                                        spacing: ClockStyle.gapTiny

                                        Repeater {
                                            model: row.expanded ? row.failed : []

                                            delegate: RowLayout {
                                                id: failedLine
                                                required property var modelData
                                                readonly property string text: String(failedLine.modelData)
                                                readonly property int colon: failedLine.text.indexOf(":")
                                                readonly property string type: failedLine.colon === -1 ? failedLine.text : failedLine.text.slice(0, failedLine.colon)
                                                readonly property string why: failedLine.colon === -1 ? "" : failedLine.text.slice(failedLine.colon + 1).trim()

                                                Layout.fillWidth: true
                                                spacing: ClockStyle.gapSmall

                                                MaterialSymbol {
                                                    text: ModeUi.actionIcon(failedLine.type)
                                                    iconSize: ClockStyle.iconSmall
                                                    color: ClockStyle.colError
                                                }

                                                StyledText {
                                                    text: ModeUi.actionLabel(failedLine.type)
                                                    font.pixelSize: ClockStyle.textSmall
                                                    font.weight: Font.DemiBold
                                                    color: ClockStyle.colOnSurface
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: failedLine.why
                                                    elide: Text.ElideRight
                                                    font.pixelSize: ClockStyle.textSmall
                                                    color: ClockStyle.colSubtext
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Empty ───────────────────────────────────────────
                    ColumnLayout {
                        visible: root.rows.length === 0
                        anchors.centerIn: parent
                        width: Math.min(parent.width - ClockStyle.gapHuge * 2, 440)
                        spacing: ClockStyle.gapHuge

                        ClockEmptyState {
                            Layout.alignment: Qt.AlignHCenter
                            symbol: Modes.history.length === 0 ? "history" : (root.filter === "failures" ? "task_alt" : "filter_alt_off")
                            shape: Modes.history.length === 0 ? "Cookie9Sided" : "Cookie7Sided"
                            title: {
                                if (Modes.history.length === 0)
                                    return Translation.tr("Nothing has happened yet");
                                if (root.filter === "failures")
                                    return Translation.tr("No action was skipped");
                                return Translation.tr("Nothing here for this filter");
                            }
                            subtitle: {
                                if (Modes.history.length === 0)
                                    return Translation.tr("Every time a mode starts or ends, or a routine runs, it is listed here with what caused it.");
                                if (root.filter === "failures")
                                    return Translation.tr("Entries whose actions could not all be applied would show up here.");
                                return Translation.tr("Try another filter above.");
                            }
                        }

                        ClockButton {
                            visible: Modes.history.length > 0
                            Layout.alignment: Qt.AlignHCenter
                            variant: "tonal"
                            symbol: "history"
                            label: Translation.tr("Show everything")
                            onClicked: root.filter = "all"
                        }
                    }
                }
            }
        }

        // ── Side sheet ──────────────────────────────────────────────────
        Item {
            id: sheetSlot
            Layout.fillHeight: true
            Layout.preferredWidth: sidePanel.open ? root.sheetWidth + (root.compact ? 0 : ClockStyle.paneGap) : 0
            visible: Layout.preferredWidth > 1
            clip: true

            Behavior on Layout.preferredWidth {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }

            ClockSidePanel {
                id: sidePanel
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                }
                width: root.sheetWidth
            }
        }
    }
}
