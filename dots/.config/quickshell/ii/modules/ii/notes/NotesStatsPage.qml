pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.usage
import "../../../services/notes/NotesDocument.js" as Doc

/**
 * What is in the notes, counted.
 *
 * A page, like the settings, and for the same reason: it is somewhere you go and read, not
 * a question to answer and dismiss. It carries no slab of its own — the cards are the
 * slabs, on the window's ground, as the panes are.
 *
 * Every number here is read from the documents themselves. The first version read
 * `note.isFavorite`, `note.words` and `note.characters`, none of which the index has ever
 * had, so it opened on a page of confident zeroes — the worst kind of wrong number,
 * because it looks like an answer.
 */
Item {
    id: root

    clip: true

    /**
     * The page arrives rather than appearing.
     *
     * Nothing else in this app changes a whole column without saying so, and a third of
     * the window swapping its contents between two frames reads as a glitch. The column
     * fades and settles by a few pixels — the shell's own `elementMoveEnter` curve, the
     * one the lists use.
     */
    Component.onCompleted: entrance.restart()

    ParallelAnimation {
        id: entrance

        NumberAnimation {
            target: root
            property: "opacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: sections
            property: "y"
            from: NotesMetrics.readingPadding + 14
            to: NotesMetrics.readingPadding
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    readonly property var liveNotes: Array.from(NotesService.notes ?? [])
    readonly property var notebooks: Array.from(NotesService.notebooks ?? [])
    readonly property int trashCount: Array.from(NotesService.index.notes ?? [])
        .filter(note => note.trashedAt > 0).length

    /**
     * One pass over every document, because each of these numbers costs a document read
     * and there are six of them. `statsOf` is the same function the note header counts
     * with, so the page and the note can never disagree.
     */
    readonly property var totals: {
        const sum = {
            words: 0,
            characters: 0,
            blocks: 0,
            favorites: 0,
            pinned: 0,
            ink: 0,
            images: 0,
            code: 0,
            byNotebook: ({}),
            byDay: ({})
        };
        for (const note of root.liveNotes) {
            if (note.favorite)
                sum.favorites++;
            if (note.pinned)
                sum.pinned++;
            const key = note.notebookId.length > 0 ? note.notebookId : "";
            sum.byNotebook[key] = (sum.byNotebook[key] ?? 0) + 1;
            if (note.modified > 0) {
                const day = root.dayKey(new Date(note.modified));
                sum.byDay[day] = (sum.byDay[day] ?? 0) + 1;
            }
            const document = NotesService.documentOf(note.id);
            if (!document)
                continue;
            const stats = Doc.statsOf(document);
            sum.words += stats.words;
            sum.characters += stats.characters;
            sum.blocks += stats.blockCount;
            if (stats.hasInk)
                sum.ink++;
            if (stats.hasImages)
                sum.images++;
            if (stats.hasCode)
                sum.code++;
        }
        return sum;
    }

    readonly property int readingMinutes: root.totals.words === 0
        ? 0
        : Math.max(1, Math.ceil(root.totals.words / 200))

    /// Local, not UTC. `toISOString` groups by a day that starts somewhere else, so
    /// anything written in the evening landed on tomorrow's square.
    function dayKey(date) {
        return String(date.getFullYear()) + "-"
            + String(date.getMonth() + 1).padStart(2, "0") + "-"
            + String(date.getDate()).padStart(2, "0");
    }

    readonly property int heatmapWeeks: 6

    /// The Monday six weeks back, so the grid ends with this week and reads Mon → Sun like
    /// the calendar does.
    function gridStart() {
        const today = new Date();
        const monday = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12);
        monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7) - (root.heatmapWeeks - 1) * 7);
        return monday;
    }

    readonly property var heatmapCells: {
        const cells = [];
        const start = root.gridStart();
        const now = new Date();
        // Noon, like the cells below. Comparing a cell's noon against the actual clock
        // blanked today's square every morning: at 03:00 today is still "ahead".
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12);
        const byDay = root.totals.byDay;
        for (let week = 0; week < root.heatmapWeeks; week++) {
            for (let day = 0; day < 7; day++) {
                const date = new Date(start.getFullYear(), start.getMonth(),
                    start.getDate() + week * 7 + day, 12);
                const key = root.dayKey(date);
                const count = byDay[key] ?? 0;
                const ahead = date.getTime() > today.getTime();
                cells.push({
                    inRange: !ahead,
                    value: ahead ? 0 : count,
                    tooltip: `${date.toLocaleDateString(Qt.locale(), "d MMM")} · `
                        + (count === 1
                            ? Translation.tr("1 note touched")
                            : Translation.tr("%1 notes touched").arg(count))
                });
            }
        }
        return cells;
    }

    readonly property int activeDays: root.heatmapCells.filter(cell => cell.value > 0).length
    readonly property int touchedInWindow: root.heatmapCells.reduce((total, cell) => total + cell.value, 0)

    readonly property var dayLabels: [
        Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"),
        Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat"), Translation.tr("Sun")
    ]

    /// Notebooks with at least one note, plus whatever sits outside all of them, named
    /// rather than labelled "Notebook" six times over.
    readonly property var notebookRows: {
        const rows = [];
        for (const notebook of root.notebooks) {
            const count = root.totals.byNotebook[notebook.id] ?? 0;
            if (count > 0)
                rows.push({ name: notebook.title, count: count });
        }
        const loose = root.totals.byNotebook[""] ?? 0;
        if (loose > 0)
            rows.push({ name: Translation.tr("Not in a notebook"), count: loose });
        rows.sort((a, b) => b.count - a.count);
        return rows;
    }

    PagePlaceholder {
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 420)
        visible: root.liveNotes.length === 0
        icon: "analytics"
        title: Translation.tr("Nothing to count yet")
        description: Translation.tr("Write a note and this page starts filling in.")
    }

    StyledFlickable {
        anchors.fill: parent
        contentHeight: sections.implicitHeight + NotesMetrics.readingPadding * 2
        visible: root.liveNotes.length > 0
        clip: true

        ColumnLayout {
            id: sections
            width: Math.min(root.width - NotesMetrics.paneGap * 2, NotesMetrics.readingWidth)
            x: Math.round((root.width - width) / 2)
            y: NotesMetrics.readingPadding
            spacing: 18

            // ── The four numbers ──────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                visible: root.liveNotes.length > 0
                columns: sections.width < 560 ? 2 : 4
                columnSpacing: NotesMetrics.paneGap
                rowSpacing: NotesMetrics.paneGap

                Repeater {
                    model: [
                        {
                            symbol: "description",
                            value: String(root.liveNotes.length),
                            label: Translation.tr("Notes")
                        },
                        {
                            symbol: "match_word",
                            value: String(root.totals.words),
                            label: Translation.tr("Words")
                        },
                        {
                            symbol: "schedule",
                            value: root.readingMinutes > 0
                                ? Translation.tr("%1 min").arg(root.readingMinutes)
                                : "—",
                            label: Translation.tr("To read it all")
                        },
                        {
                            symbol: "star",
                            value: String(root.totals.favorites),
                            label: Translation.tr("Favourites")
                        }
                    ]

                    delegate: Rectangle {
                        id: card
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: 104
                        radius: Appearance.rounding.large
                        color: Appearance.m3colors.m3surfaceContainerHigh

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: NotesMetrics.cardPadding
                            anchors.rightMargin: NotesMetrics.cardPadding
                            spacing: 2

                            MaterialSymbol {
                                text: card.modelData.symbol
                                iconSize: 20
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.value
                                font.pixelSize: Appearance.font.pixelSize.hugeass
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // ── Notebooks ─────────────────────────────────────────────────
            //
            // Rows with a bar each, not a column chart. A column chart of one category is
            // a single lonely pillar that says nothing the number beside it did not, and
            // it has nowhere to put a notebook's name once there are six of them.
            //
            // Shown only when there is a division to show: with everything in one
            // notebook this section would restate the count above it.
            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Notes per notebook")
                visible: root.notebookRows.length > 1

                Repeater {
                    model: root.notebookRows

                    delegate: Item {
                        id: notebookRow
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: 52

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: NotesMetrics.cardPadding
                            anchors.rightMargin: NotesMetrics.cardPadding
                            spacing: 12

                            StyledText {
                                Layout.preferredWidth: 160
                                text: notebookRow.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 10
                                radius: NotesMetrics.pillRadius(10)
                                color: Appearance.colors.colLayer2

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(parent.radius * 2, parent.width
                                        * notebookRow.modelData.count / Math.max(1, root.notebookRows[0].count))
                                    height: parent.height
                                    radius: parent.radius
                                    color: Appearance.colors.colPrimary

                                    Behavior on width {
                                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                    }
                                }
                            }

                            StyledText {
                                Layout.preferredWidth: 32
                                horizontalAlignment: Text.AlignRight
                                text: String(notebookRow.modelData.count)
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }

            // ── Activity ──────────────────────────────────────────────────
            NotesStatsSection {
                Layout.fillWidth: true
                title: Translation.tr("The last six weeks")
                subtitle: Translation.tr("A square for every day, darker where more notes were touched.")
                contentHeight: 250

                RowLayout {
                    anchors.fill: parent
                    spacing: NotesMetrics.cardPadding

                    UsageActivityHeatmap {
                        Layout.preferredWidth: 300
                        Layout.fillHeight: true
                        cells: root.heatmapCells
                        dayLabels: root.dayLabels
                        weekCount: root.heatmapWeeks
                        cellSpacing: 4
                        activeColor: Appearance.colors.colPrimary
                        midColor: Appearance.colors.colTertiary
                        // The layered colours are transparency-adjusted, and colLayer2 over
                        // this surface is a square nobody can see: an empty day has to be
                        // visibly a day, or six weeks of nothing looks like a blank slab.
                        emptyColor: Appearance.m3colors.m3surfaceContainerHighest
                    }

                    // What the squares add up to, in words. A grid answers "when"; these
                    // answer "how much", which is the question somebody opening a page
                    // called statistics actually asked.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 14

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: root.activeDays === 1
                                    ? Translation.tr("1 day")
                                    : Translation.tr("%1 days").arg(root.activeDays)
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("you wrote something")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: String(root.touchedInWindow)
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("notes opened and changed")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            // ── What is in them ───────────────────────────────────────────
            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("What is in them")
                visible: root.liveNotes.length > 0

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "draw"
                    title: Translation.tr("Notes with a drawing")

                    StyledText {
                        text: String(root.totals.ink)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "image"
                    title: Translation.tr("Notes with a picture")

                    StyledText {
                        text: String(root.totals.images)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "code"
                    title: Translation.tr("Notes with code")

                    StyledText {
                        text: String(root.totals.code)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "layers"
                    title: Translation.tr("Blocks in total")

                    StyledText {
                        text: String(root.totals.blocks)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "delete"
                    title: Translation.tr("Waiting in the trash")

                    StyledText {
                        text: String(root.trashCount)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
