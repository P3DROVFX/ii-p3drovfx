pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.services.notes
import qs.modules.common
import qs.modules.common.widgets

/**
 * The app's own settings, as a page.
 *
 * A page and not a sheet. A modal over the notes says "answer me and get back to what you
 * were doing", which is what a confirmation is for; settings is somewhere you go, read,
 * change one thing and leave. So it opens where the notes are, the rail stays put so
 * leaving is one click, and the bar across the top says where you are.
 *
 * It carries no slab of its own: the sections are the slabs, floating on the window's
 * ground with air between them, exactly as the three panes do. One surface wrapped around
 * another of the same colour is a rectangle nobody can see the edge of.
 *
 * Every row here changes something. The first version of this file had four tabs over five
 * hundred lines and, behind them, five controls — the rest was prose describing the app to
 * itself, including a list of paper styles that do not exist. A settings page whose
 * switches configure nothing is worse than none, because it sends somebody looking for a
 * setting that was never there.
 */
Item {
    id: root

    /// Asked for from the data section; the pane owns the export sheet.
    signal exportRequested()

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

    readonly property var paperStyles: [
        { id: "plain", name: Translation.tr("Plain") },
        { id: "grid", name: Translation.tr("Grid") },
        { id: "dots", name: Translation.tr("Dots") },
        { id: "ruled", name: Translation.tr("Ruled") },
        { id: "ruled-margin", name: Translation.tr("Ruled with margin") },
        { id: "isometric", name: Translation.tr("Isometric") },
        { id: "graph", name: Translation.tr("Graph") }
    ]

    readonly property int trashCount: Array.from(NotesService.index.notes ?? [])
        .filter(note => note.trashedAt > 0).length

    /// What the last Keep import said, so the row can answer rather than the log.
    property string importStatus: ""

    NotesTakeoutPicker {
        id: takeout
        onPicked: path => {
            root.importStatus = Translation.tr("Reading %1…").arg(path);
            NotesSync.importTakeout(path);
        }
    }

    Connections {
        target: NotesSync
        function onImportFinished(success, message, importedCount) {
            root.importStatus = success
                ? (importedCount === 1
                    ? Translation.tr("One note came in.")
                    : Translation.tr("%1 notes came in.").arg(importedCount))
                : message;
        }
    }

    StyledFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: sections.implicitHeight + NotesMetrics.readingPadding * 2
        clip: true

        ColumnLayout {
            id: sections
            // A measure, centred. Settings rows are read left to right like prose, and a
            // row three thousand pixels wide puts its control on another continent from
            // the label that names it.
            width: Math.min(root.width - NotesMetrics.paneGap * 2, NotesMetrics.readingWidth)
            x: Math.round((root.width - width) / 2)
            y: NotesMetrics.readingPadding
            spacing: 18

            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("The page")

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "grid_on"
                    title: Translation.tr("Default page style")
                    description: Translation.tr("What a new note starts on. Any note can be changed on its own from the header.")

                    StyledComboBox {
                        implicitWidth: 170
                        model: root.paperStyles.map(style => style.name)
                        currentIndex: Math.max(0, root.paperStyles.findIndex(style =>
                            style.id === (Config.options.notes.defaultPaper ?? "plain")))
                        onActivated: index => {
                            if (Config.ready)
                                Config.options.notes.defaultPaper = root.paperStyles[index].id;
                        }
                    }
                }

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "opacity"
                    title: Translation.tr("How strongly the page shows")

                    RowLayout {
                        spacing: 8

                        StyledSlider {
                            implicitWidth: 140
                            from: 0
                            to: 100
                            stepSize: 5
                            value: Config.options.notes.paperStrength ?? 50
                            onMoved: {
                                if (Config.ready)
                                    Config.options.notes.paperStrength = Math.round(value);
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: 40
                            text: `${Config.options.notes.paperStrength ?? 50}%`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Saving")

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "timer"
                    title: Translation.tr("Save after you stop typing")
                    description: Translation.tr("Shorter writes more often; longer keeps more of a sentence in one revision.")

                    RowLayout {
                        spacing: 8

                        StyledSlider {
                            implicitWidth: 140
                            from: 150
                            to: 1500
                            stepSize: 50
                            value: Config.options.notes.autosaveDelay ?? 400
                            onMoved: {
                                if (Config.ready)
                                    Config.options.notes.autosaveDelay = Math.round(value);
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: 56
                            text: Translation.tr("%1 ms").arg(Config.options.notes.autosaveDelay ?? 400)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Links and the cloud")

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "link"
                    title: Translation.tr("Fetch link previews")
                    description: Translation.tr("Asks the site for its title and picture. With this off, a link shows only its address and nothing leaves this machine.")

                    StyledSwitch {
                        checked: Persistent.states.notes.linkPreviews
                        onToggled: Persistent.states.notes.linkPreviews = checked
                    }
                }

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "cloud_upload"
                    title: Translation.tr("Keep a copy in Google Drive")
                    description: Translation.tr("Adds the notes folder to the backup rclone already runs on its own schedule. This is a backup, not a two-way sync.")

                    StyledSwitch {
                        checked: NotesSync.autoDrive
                        onToggled: NotesSync.toggleDriveBackup()
                    }
                }

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "sync"
                    title: Translation.tr("Sync now")
                    description: NotesSync.driveEnabled
                        ? Translation.tr("Runs the backup this moment instead of waiting for the schedule.")
                        : Translation.tr("Google Drive is not set up yet — turn it on in the shell's own settings first.")

                    RippleButton {
                        implicitHeight: 40
                        buttonRadius: NotesMetrics.pillRadius(40)
                        enabled: NotesSync.driveEnabled
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: NotesSync.syncDriveNow()

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            leftPadding: 16
                            rightPadding: 16
                            text: Translation.tr("Sync")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                    }
                }
            }

            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Your notes")

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "cloud_download"
                    title: Translation.tr("Import from Google Keep")
                    description: root.importStatus.length > 0
                        ? root.importStatus
                        : Translation.tr("Point this at a Google Takeout folder. The official Keep API is for Workspace accounts only, so an export is the way in for a personal one.")

                    RippleButton {
                        implicitHeight: 40
                        buttonRadius: NotesMetrics.pillRadius(40)
                        enabled: !takeout.choosing
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: takeout.pick()

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            leftPadding: 16
                            rightPadding: 16
                            text: takeout.choosing
                                ? Translation.tr("Choosing…")
                                : Translation.tr("Choose a folder…")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                    }
                }

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "download"
                    title: Translation.tr("Export")
                    description: Translation.tr("This note or the whole store, as Markdown, HTML, PDF or a zip.")

                    RippleButton {
                        implicitHeight: 40
                        buttonRadius: NotesMetrics.pillRadius(40)
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.exportRequested()

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            leftPadding: 16
                            rightPadding: 16
                            text: Translation.tr("Export…")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                    }
                }
            }

            /// Only once there is a PIN to talk about. A section explaining a feature
            /// nobody has used is the kind of thing this page was full of.
            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Locked notes")
                visible: Persistent.states.notes.lockDigest.length > 0

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "lock_open"
                    title: Translation.tr("Forget the PIN")
                    description: Translation.tr("Every locked note opens again, and the next one you lock asks for a new PIN.")

                    RippleButton {
                        implicitHeight: 40
                        buttonRadius: NotesMetrics.pillRadius(40)
                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainer
                        onClicked: {
                            Persistent.states.notes.lockDigest = "";
                            Persistent.states.notes.lockSalt = "";
                            // The flags go with it. Left behind, they would lock these
                            // notes again the moment somebody chose a new PIN — for
                            // reasons nobody would be able to reconstruct.
                            for (const note of Array.from(NotesService.index.notes ?? [])) {
                                if (note.locked)
                                    NotesService.updateMeta(note.id, { locked: false });
                            }
                        }

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            leftPadding: 16
                            rightPadding: 16
                            text: Translation.tr("Forget")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onErrorContainer
                        }
                    }
                }
            }

            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("The trash")

                NotesSettingsRow {
                    Layout.fillWidth: true
                    symbol: "delete_forever"
                    title: Translation.tr("Empty the trash")
                    description: root.trashCount === 0
                        ? Translation.tr("Nothing is waiting there.")
                        : (root.trashCount === 1
                            ? Translation.tr("One note is waiting there. This cannot be undone.")
                            : Translation.tr("%1 notes are waiting there. This cannot be undone.").arg(root.trashCount))

                    RippleButton {
                        implicitHeight: 40
                        buttonRadius: NotesMetrics.pillRadius(40)
                        enabled: root.trashCount > 0
                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainer
                        onClicked: {
                            for (const note of Array.from(NotesService.index.notes ?? [])) {
                                if (note.trashedAt > 0)
                                    NotesService.purgeNote(note.id);
                            }
                        }

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            leftPadding: 16
                            rightPadding: 16
                            text: Translation.tr("Empty")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onErrorContainer
                        }
                    }
                }
            }

            NotesSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Keyboard")

                // Key caps, not a bullet list inside a paragraph. The project has a widget
                // for exactly this, and it is what the Cheatsheet uses.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: NotesMetrics.cardPadding
                    spacing: 6

                    KeyboardShortcutBox {
                        Layout.fillWidth: true
                        text: Translation.tr("Open notes from anywhere")
                        // Super+Shift+N is the shell's "next track"; the notes took the
                        // same letter with the other modifier rather than a stranger key.
                        keys: ["Super", "Alt", "N"]
                    }

                    KeyboardShortcutBox {
                        Layout.fillWidth: true
                        text: Translation.tr("New note")
                        keys: ["Ctrl", "N"]
                    }

                    KeyboardShortcutBox {
                        Layout.fillWidth: true
                        text: Translation.tr("Search notes")
                        keys: ["Ctrl", "F"]
                    }

                    KeyboardShortcutBox {
                        Layout.fillWidth: true
                        text: Translation.tr("Back, or close")
                        keys: ["Esc"]
                    }
                }
            }
        }
    }
}
