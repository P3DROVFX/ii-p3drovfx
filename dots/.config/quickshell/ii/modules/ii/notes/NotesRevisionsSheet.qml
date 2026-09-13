pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.services.notes
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * Revisions and version history sheet with block-level visual diff.
 *
 * Shows past snapshots of the active note, highlights changes compared
 * to the current version, and allows one-click restoration.
 */
Item {
    id: root

    property string noteId: ""
    property var note: null
    property var currentBlocks: []

    signal closed()
    signal revisionRestored()

    property int selectedIndex: 0
    property var revisions: NotesRevisions.currentRevisions
    readonly property var activeRevisionMeta: (root.revisions && root.revisions.length > root.selectedIndex)
        ? root.revisions[root.selectedIndex]
        : null

    property var activeRevisionDoc: null
    property var diffItems: []

    onNoteIdChanged: {
        if (root.noteId && root.visible) {
            root.selectedIndex = 0;
            root.activeRevisionDoc = null;
            root.diffItems = [];
            NotesRevisions.listRevisions(root.noteId);
        }
    }

    onVisibleChanged: {
        if (root.visible && root.noteId) {
            root.selectedIndex = 0;
            NotesRevisions.listRevisions(root.noteId);
        }
    }

    Connections {
        target: NotesRevisions
        function onRevisionsLoaded(id, revs) {
            if (id === root.noteId && revs && revs.length > 0) {
                root.loadRevisionAtIndex(0);
            } else {
                root.activeRevisionDoc = null;
                root.diffItems = [];
            }
        }
    }

    function loadRevisionAtIndex(idx: int): void {
        root.selectedIndex = idx;
        if (!root.revisions || root.revisions.length <= idx)
            return;
        const rev = root.revisions[idx];
        NotesRevisions.readRevision(root.noteId, rev.timestamp, function(doc) {
            root.activeRevisionDoc = doc;
            if (doc && Array.isArray(doc.blocks)) {
                root.diffItems = NotesRevisions.computeDiff(root.currentBlocks, doc.blocks);
            } else {
                root.diffItems = [];
            }
        });
    }

    function restoreActiveRevision() {
        if (!root.activeRevisionDoc || !root.noteId)
            return;
        // Save current as a snapshot before restoring
        NotesRevisions.saveSnapshot(root.noteId, root.note?.title || "", root.currentBlocks, "pre-restore");

        // Update note with revision blocks
        if (Array.isArray(root.activeRevisionDoc.blocks)) {
            NotesService.restoreRevision(root.noteId, root.activeRevisionDoc);
        }
        root.revisionRestored();
        root.closed();
    }

    // ── Scrim ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closed()
        }
    }

    // ── Dialog Card ───────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 840)
        height: Math.min(parent.height - 32, 600)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHighest
        clip: true

        StyledRectangularShadow {
            target: card
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: "history"
                    iconSize: 24
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Version history")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

            }

            // ── Body: Two Columns (Revisions List & Diff View) ─────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                // Left Column: Past Revisions
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 280
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Earlier versions")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        ListView {
                            id: revList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 4
                            clip: true
                            model: root.revisions

                            delegate: RippleButton {
                                id: revBtn
                                required property var modelData
                                required property int index

                                width: revList.width
                                implicitHeight: 52
                                buttonRadius: Appearance.rounding.small
                                toggled: root.selectedIndex === revBtn.index
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover

                                onClicked: root.loadRevisionAtIndex(revBtn.index)

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "schedule"
                                        iconSize: 18
                                        color: revBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: revBtn.modelData.date
                                                ? new Date(revBtn.modelData.date).toLocaleString()
                                                : Translation.tr("Snapshot")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: revBtn.toggled ? Font.DemiBold : Font.Normal
                                            color: revBtn.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("%1 blocks • %2").arg(revBtn.modelData.blockCount || 0).arg(revBtn.modelData.author || "local")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                    }

                    StyledText {
                        anchors.centerIn: parent
                        width: parent.width - 32
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: !root.revisions || root.revisions.length === 0
                        text: Translation.tr("Nothing yet. A version is kept when you come back to a note after a while, and whenever you ask for one.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                // Right Column: Diff Visualizer
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        // Diff Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialSymbol {
                                text: "compare_arrows"
                                iconSize: 20
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.activeRevisionMeta
                                    ? Translation.tr("Comparing with %1").arg(new Date(root.activeRevisionMeta.date).toLocaleString())
                                    : Translation.tr("Select a version to compare")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                        }

                        // Diff Block List
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            clip: true

                            ListView {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6
                                clip: true
                                model: root.diffItems

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    width: parent ? parent.width : 300
                                    implicitHeight: diffRow.implicitHeight + 12
                                    radius: Appearance.rounding.small
                                    color: {
                                        const k = modelData.kind;
                                        if (k === "added") return Appearance.colors.colLayer3;
                                        if (k === "deleted") return Appearance.colors.colLayer3;
                                        if (k === "modified") return Appearance.colors.colSecondaryContainer;
                                        return Appearance.colors.colLayer1;
                                    }

                                    RowLayout {
                                        id: diffRow
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 8

                                        MaterialSymbol {
                                            text: {
                                                const k = modelData.kind;
                                                if (k === "added") return "add_circle";
                                                if (k === "deleted") return "remove_circle";
                                                if (k === "modified") return "change_circle";
                                                return "radio_button_unchecked";
                                            }
                                            iconSize: 16
                                            color: {
                                                const k = modelData.kind;
                                                if (k === "added") return Appearance.colors.colPrimary;
                                                if (k === "deleted") return Appearance.colors.colError;
                                                if (k === "modified") return Appearance.colors.colSecondary;
                                                return Appearance.colors.colSubtext;
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.kind === "deleted"
                                                    ? Translation.tr("Removed: %1").arg(modelData.text || "")
                                                    : (modelData.text || Translation.tr("(empty)"))
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                font.strikeout: modelData.kind === "deleted"
                                                color: {
                                                    if (modelData.kind === "deleted") return Appearance.colors.colError;
                                                    if (modelData.kind === "added") return Appearance.colors.colPrimary;
                                                    return Appearance.colors.colOnLayer2;
                                                }
                                                wrapMode: Text.Wrap
                                            }

                                            StyledText {
                                                visible: modelData.kind === "modified"
                                                Layout.fillWidth: true
                                                text: Translation.tr("Previous: %1").arg(modelData.oldText || "")
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colSubtext
                                                font.strikeout: true
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Footer ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RippleButton {
                    implicitHeight: 38
                    implicitWidth: 140
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        NotesRevisions.saveSnapshot(root.noteId, root.note?.title || "", root.currentBlocks, "manual");
                        NotesRevisions.listRevisions(root.noteId);
                    }

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "save"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            text: Translation.tr("Keep this version")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitHeight: 38
                    implicitWidth: 100
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.closed()

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Cancel")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                }

                RippleButton {
                    implicitHeight: 38
                    implicitWidth: 180
                    buttonRadius: Appearance.rounding.small
                    enabled: root.activeRevisionDoc !== null
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: root.restoreActiveRevision()

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "restore"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            text: Translation.tr("Go back to this")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }
}
