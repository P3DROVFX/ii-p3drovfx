pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Quick add: a Basic note (front/back) into a deck picked from chips, or into a new
 * deck. Stays open after adding so a run of cards goes in without reopening;
 * Ctrl+Enter adds from anywhere in the sheet.
 */
AnkiSheet {
    id: root

    property var deckId: Anki.studyDeck?.id ?? (Anki.decks.find(d => d.depth === 0)?.id ?? 1)
    property bool newDeck: Anki.decks.length === 0
    property bool busy: false
    property string status: ""

    title: Translation.tr("Add a card")
    subtitle: Translation.tr("A basic card: front, back.")

    function submit() {
        if (root.busy || frontField.text.trim().length === 0)
            return;
        root.busy = true;
        root.status = "";
        const add = (deckId) => Anki.addNote(deckId, [frontField.text, backField.text], (ok, data) => {
            root.busy = false;
            if (!ok) {
                root.status = Translation.tr("Couldn't add: %1").arg(String(data));
                return;
            }
            root.status = Translation.tr("Added to %1").arg(Anki.decks.find(d => d.id === deckId)?.fullName ?? deckNameField.text);
            frontField.text = "";
            backField.text = "";
            frontField.focusInput();
        });
        if (root.newDeck) {
            Anki.createDeck(deckNameField.text.trim() || Translation.tr("My deck"), (ok, data) => {
                if (!ok) {
                    root.busy = false;
                    root.status = String(data);
                    return;
                }
                root.deckId = data.id;
                root.newDeck = false;
                add(data.id);
            });
        } else {
            add(root.deckId);
        }
    }

    Component.onCompleted: frontField.focusInput()
    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.submit();
            event.accepted = true;
        }
    }

    StyledText {
        text: Translation.tr("Deck")
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.gapTiny

        Repeater {
            model: Anki.decks.filter(d => !d.filtered)
            ClockFormChip {
                required property var modelData
                label: modelData.fullName.split("::").join(" › ")
                selected: !root.newDeck && root.deckId === modelData.id
                onTriggered: {
                    root.newDeck = false;
                    root.deckId = modelData.id;
                }
            }
        }
        ClockFormChip {
            symbol: "add"
            label: Translation.tr("New deck")
            selected: root.newDeck
            onTriggered: {
                root.newDeck = true;
                deckNameField.focusInput();
            }
        }
    }

    ClockFormField {
        id: deckNameField
        visible: root.newDeck
        symbol: "folder"
        shapeKind: MaterialShape.Shape.Cookie9Sided
        caption: Translation.tr("New deck name")
        placeholder: Translation.tr("Use :: for subdecks")
        onAccepted: frontField.focusInput()
    }

    ClockFormField {
        id: frontField
        Layout.topMargin: ClockStyle.gapSmall
        symbol: "flip_to_front"
        shapeKind: MaterialShape.Shape.Cookie7Sided
        caption: Translation.tr("Front")
        placeholder: Translation.tr("Question")
        onAccepted: backField.focusInput()
    }

    ClockFormField {
        id: backField
        symbol: "flip_to_back"
        shapeKind: MaterialShape.Shape.Clover4Leaf
        caption: Translation.tr("Back")
        placeholder: Translation.tr("Answer")
        onAccepted: root.submit()
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.status.length > 0
        wrapMode: Text.Wrap
        text: root.status
        font.pixelSize: Appearance.font.pixelSize.small
        color: ClockStyle.colOnSurfaceVariant
    }

    footer: [
        ClockSheetAction {
            label: Translation.tr("Done")
            onClicked: root.dismissed()
        },
        ClockSheetAction {
            primary: true
            enabled: !root.busy && frontField.text.trim().length > 0
            symbol: "add"
            label: Translation.tr("Add card")
            onClicked: root.submit()
        }
    ]
}
