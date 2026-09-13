pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.services.notes
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * Taking the notes out, in a shape something else can read.
 *
 * Four formats, and the sentence under each one says what it is *for* rather than what it
 * is made of: somebody choosing here is deciding where the file is going, not which
 * library rendered it. The first version named two PDF engines by name and had half its
 * options in Portuguese.
 */
Item {
    id: root

    property string noteId: ""
    property var note: null
    property int allNotesCount: NotesService.notes ? NotesService.notes.length : 0

    signal closed()

    property string selectedFormat: "markdown" // "markdown" | "html" | "pdf" | "zip"
    property string scope: "current" // "current" | "all"
    /// A path, not a URL. `Directories.documents` is `file:///…`, and the exporter is a
    /// python script that would have made a directory literally called `file:`.
    property string destDirectory: FileUtils.trimFileProtocol(`${Directories.documents}/NotesExport`)
    property bool exporting: false
    property string statusMessage: ""
    property bool exportSuccess: false
    property string lastExportPath: ""

    function runExport(): void {
        root.exporting = true;
        root.statusMessage = Translation.tr("Exporting…");
        root.exportSuccess = false;
        NotesSync.exportNotes(root.selectedFormat, root.destDirectory, root.noteId, root.scope === "all");
    }

    Connections {
        target: NotesSync
        function onExportFinished(success, message, outputPath) {
            root.exporting = false;
            root.exportSuccess = success;
            root.statusMessage = message;
            if (success)
                root.lastExportPath = outputPath || root.destDirectory;
        }
    }

    // ── Scrim ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }
    }

    // ── Dialog Card ───────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 600)
        // As tall as what is in it. A fixed 540 left a hand's width of empty surface
        // between the formats and the buttons, which reads as something failing to load.
        height: Math.min(parent.height - 32, cardLayout.implicitHeight + 40)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHighest
        clip: true

        StyledRectangularShadow {
            target: card
        }

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: "file_export"
                    iconSize: 24
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Export")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

            }

            // ── Scope Selector ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButton {
                    id: scopeCurrent
                    Layout.fillWidth: true
                    implicitHeight: 44
                    buttonRadius: NotesMetrics.pillRadius(scopeCurrent.implicitHeight)
                    toggled: root.scope === "current"
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    enabled: root.note !== null
                    onClicked: root.scope = "current"

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: root.note
                            ? Translation.tr("This note (%1)").arg(root.note.title.length > 0 ? root.note.title : Translation.tr("untitled"))
                            : Translation.tr("No note is open")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: root.scope === "current" ? Font.DemiBold : Font.Normal
                        color: root.scope === "current" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    id: scopeAll
                    Layout.fillWidth: true
                    implicitHeight: 44
                    buttonRadius: NotesMetrics.pillRadius(scopeAll.implicitHeight)
                    toggled: root.scope === "all"
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.scope = "all"

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("All of them (%1)").arg(root.allNotesCount)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: root.scope === "all" ? Font.DemiBold : Font.Normal
                        color: root.scope === "all" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }
            }

            // ── Format Options ────────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: [
                        { id: "markdown", title: Translation.tr("Markdown"), icon: "description", desc: Translation.tr("Text files with the pictures beside them. Obsidian and Logseq read these.") },
                        { id: "html", title: Translation.tr("Web page"), icon: "language", desc: Translation.tr("One file with the pictures inside it. Opens in any browser.") },
                        { id: "pdf", title: Translation.tr("PDF"), icon: "picture_as_pdf", desc: Translation.tr("For printing, or for sending to somebody who will not edit it.") },
                        { id: "zip", title: Translation.tr("Everything, zipped"), icon: "folder_zip", desc: Translation.tr("The whole store as one archive: notes, pictures and drawings.") }
                    ]

                    delegate: RippleButton {
                        id: fmtBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 74
                        buttonRadius: Appearance.rounding.normal
                        toggled: root.selectedFormat === fmtBtn.modelData.id
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.selectedFormat = fmtBtn.modelData.id

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            MaterialSymbol {
                                text: fmtBtn.modelData.icon
                                iconSize: 26
                                color: fmtBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    text: fmtBtn.modelData.title
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: fmtBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                                }

                                StyledText {
                                    text: fmtBtn.modelData.desc
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: fmtBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }

            // ── Destination Folder ────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    MaterialSymbol {
                        text: "folder"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Into %1").arg(root.destDirectory)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideMiddle
                    }
                }
            }

            // ── Status & Feedback Banner ──────────────────────────────────
            Rectangle {
                visible: root.statusMessage.length > 0
                Layout.fillWidth: true
                implicitHeight: statusRow.implicitHeight + 16
                radius: Appearance.rounding.small
                color: root.exportSuccess
                    ? Appearance.m3colors.m3primaryContainer
                    : Appearance.m3colors.m3errorContainer

                RowLayout {
                    id: statusRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    MaterialSymbol {
                        text: root.exportSuccess ? "check_circle" : (root.exporting ? "hourglass_top" : "error")
                        iconSize: 20
                        color: root.exportSuccess
                            ? Appearance.m3colors.m3onPrimaryContainer
                            : Appearance.m3colors.m3onErrorContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.statusMessage
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.exportSuccess
                            ? Appearance.m3colors.m3onPrimaryContainer
                            : Appearance.m3colors.m3onErrorContainer
                        wrapMode: Text.Wrap
                    }

                    RippleButton {
                        visible: root.exportSuccess && root.lastExportPath.length > 0
                        implicitHeight: 28
                        implicitWidth: 90
                        buttonRadius: Appearance.rounding.verysmall
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        onClicked: Quickshell.execDetached(["xdg-open", root.lastExportPath])

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Open the folder")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            // ── Footer Action Buttons ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButton {
                    id: cancelButton
                    implicitHeight: 44
                    implicitWidth: 110
                    buttonRadius: NotesMetrics.pillRadius(cancelButton.implicitHeight)
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.closed()

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Cancel")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    id: exportButton
                    implicitHeight: 44
                    implicitWidth: 140
                    buttonRadius: NotesMetrics.pillRadius(exportButton.implicitHeight)
                    colBackground: Appearance.m3colors.m3primary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    enabled: !root.exporting
                    onClicked: root.runExport()

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "download"
                            iconSize: 18
                            color: Appearance.m3colors.m3onPrimary
                        }

                        StyledText {
                            text: root.exporting ? Translation.tr("Exporting…") : Translation.tr("Export")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                }
            }
        }
    }
}
