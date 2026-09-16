pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
// The root module, for `GlobalStates` — without it every button here threw
// `ReferenceError: GlobalStates is not defined` and the whole tab did nothing.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property int entranceTrigger: -1
    readonly property bool compact: root.height > 0 && root.height < 300
    readonly property bool dense: root.width < 260
    readonly property var recentNotes: Array.from(NotesService.notes ?? []).slice(0, 6)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.dense ? 4 : 8
        spacing: root.compact ? 6 : 10

        // ── Header Row ────────────────────────────────────────────────────
        // No header title: the search bar below is the anchor of the page.

        // ── Quick Capture Row ─────────────────────────────────────────────
        Rectangle {
            id: searchField
            Layout.fillWidth: true
            implicitHeight: root.compact ? 34 : 38
            radius: Appearance.rounding.full
            color: searchHover.containsMouse || quickInput.activeFocus
                ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

            Behavior on color {
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
            }

            MouseArea {
                id: searchHover
                anchors.fill: parent
                enabled: false
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 6
                spacing: 6

                MaterialSymbol {
                    text: "search"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }

                TextInput {
                    id: quickInput
                    objectName: "notesSearchInput"
                    Layout.fillWidth: true
                    clip: true
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    selectByMouse: true
                    cursorVisible: activeFocus

                    Text {
                        anchors.fill: parent
                        text: Translation.tr("Search notes…")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        visible: quickInput.text.length === 0
                    }

                    onAccepted: {
                        if (quickInput.text.trim().length === 0)
                            return;
                        const text = quickInput.text.trim();
                        // The first line names it. `create` with an empty title falls back
                        // to "AI note", which is right where it is used — the assistant —
                        // and wrong for something jotted down by hand.
                        NotesService.create(text.split("\n")[0].slice(0, 80), text, null);
                        quickInput.text = "";
                    }
                }

                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    visible: quickInput.text.trim().length > 0
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_forward"
                        iconSize: 14
                        color: Appearance.colors.colOnPrimary
                    }

                    onClicked: {
                        if (quickInput.text.trim().length === 0)
                            return;
                        const text = quickInput.text.trim();
                        NotesService.create(text.split("\n")[0].slice(0, 80), text, null);
                        quickInput.text = "";
                    }
                }
            }
        }

        // ── Recent Notes List / Empty State ───────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Empty State
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.recentNotes.length === 0
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "note_stack"
                    iconSize: 36
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No notes yet")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }

            // List View
            ListView {
                id: listView
                anchors.fill: parent
                visible: root.recentNotes.length > 0
                clip: true
                spacing: 6
                model: root.recentNotes

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index

                    width: listView.width
                    implicitHeight: root.compact ? 44 : 52
                    radius: Appearance.rounding.small
                    color: cardArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                    Behavior on color {
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }

                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            GlobalStates.openNotes(card.modelData.id);
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        MaterialSymbol {
                            text: card.modelData.icon && card.modelData.icon.length > 0 ? card.modelData.icon : "description"
                            iconSize: 18
                            color: card.modelData.favorite ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.title && card.modelData.title.length > 0
                                    ? card.modelData.title
                                    : Translation.tr("Untitled note")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData.preview && card.modelData.preview.length > 0
                                    ? card.modelData.preview
                                    : Translation.tr("Empty note")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        MaterialSymbol {
                            visible: card.modelData.pinned
                            text: "keep"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    StyledRectangularShadow {
        target: noteFab
        radius: noteFab.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }

    // Same pill as the To-Do create button, in the same corner.
    FloatingActionButton {
        id: noteFab
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.dense ? 6 : 14
        anchors.bottomMargin: root.dense ? 6 : 14
        baseSize: root.dense ? 40 : 52
        iconSize: root.compact ? 20 : 24
        iconText: "add"
        onClicked: {
            const noteId = NotesService.createNote({ title: "" });
            GlobalStates.openNotes(noteId);
            GlobalStates.sidebarRightOpen = false;
        }

        StyledToolTip {
            text: Translation.tr("New note")
        }
    }
}
