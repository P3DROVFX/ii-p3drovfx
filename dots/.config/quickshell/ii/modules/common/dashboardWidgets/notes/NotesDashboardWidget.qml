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
    property bool keyboardEnabled: false
    property bool showShortcutHints: false
    property bool ctrlPressed: false
    readonly property bool hintVisible: root.keyboardEnabled
        && (root.showShortcutHints || root.ctrlPressed) && (root.Window.window?.active ?? false)

    onKeyboardEnabledChanged: { if (!root.keyboardEnabled) root.ctrlPressed = false; }
    Connections {
        target: root.Window.window
        function onActiveChanged() { root.ctrlPressed = false; }
    }

    function releaseKey(event) {
        if (event.key === Qt.Key_Control || !(event.modifiers & Qt.ControlModifier))
            root.ctrlPressed = false;
    }

    function createNote() {
        if (!NotesService.ready) return;
        const noteId = NotesService.createNote({ title: "" });
        GlobalStates.openNotes(noteId);
        GlobalStates.sidebarRightOpen = false;
    }

    function captureNote() {
        const text = quickInput.text.trim();
        if (!text.length) return;
        // Keep the draft if the service cannot save it yet.
        const result = NotesService.create(text.split("\n")[0].slice(0, 80), text, null);
        if (result.ok) quickInput.text = "";
    }

    function openNote(index) {
        const note = root.recentNotes[index];
        if (note) GlobalStates.openNotes(note.id);
    }

    function selectNote(index) {
        if (!listView.count) return;
        listView.currentIndex = Math.max(0, Math.min(listView.count - 1, index));
        listView.positionViewAtIndex(listView.currentIndex, ListView.Contain);
        const item = listView.itemAtIndex(listView.currentIndex);
        if (item && item.y + item.height > listView.contentY + listView.height - listView.bottomMargin)
            listView.contentY = Math.min(listView.contentHeight + listView.bottomMargin - listView.height,
                item.y + item.height - listView.height + listView.bottomMargin);
        root.forceActiveFocus();
    }

    function handleKey(event) {
        if (!root.keyboardEnabled) return false;
        root.ctrlPressed = event.key === Qt.Key_Control || !!(event.modifiers & Qt.ControlModifier);
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_N) {
                if (!event.isAutoRepeat) root.createNote();
                return true;
            }
            if (event.key === Qt.Key_F) {
                if (!event.isAutoRepeat) quickInput.forceActiveFocus();
                return true;
            }
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
                if (!event.isAutoRepeat) root.openNote(event.key - Qt.Key_1);
                return true;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!event.isAutoRepeat) root.captureNote();
                return true;
            }
        }
        if (event.modifiers !== Qt.NoModifier) return false;
        if (quickInput.activeFocus) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!event.isAutoRepeat) root.captureNote();
                return true;
            }
            if (event.key === Qt.Key_Escape) {
                root.forceActiveFocus();
                return true;
            }
            // Home/End, Space and text-editing chords belong to the input.
            if (event.key !== Qt.Key_Down && event.key !== Qt.Key_Up) return false;
        }
        if (event.key === Qt.Key_Down) root.selectNote(listView.currentIndex + 1);
        else if (event.key === Qt.Key_Up) root.selectNote(Math.max(0, listView.currentIndex - 1));
        else if (event.key === Qt.Key_Home) root.selectNote(0);
        else if (event.key === Qt.Key_End) root.selectNote(listView.count - 1);
        else if (root.activeFocus && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            if (!event.isAutoRepeat) root.openNote(listView.currentIndex);
        } else return false;
        return true;
    }

    Keys.onPressed: event => { event.accepted = root.handleKey(event); }
    Keys.onReleased: event => root.releaseKey(event)
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

                TaskShortcutContent {
                    Layout.preferredWidth: Appearance.font.pixelSize.smallest * 3
                    Layout.preferredHeight: Appearance.font.pixelSize.larger
                    symbol: "search"
                    shortcut: "Ctrl\n+ F"
                    showHint: root.hintVisible
                    iconSize: Appearance.font.pixelSize.normal
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
                    activeFocusOnTab: true
                    Accessible.name: Translation.tr("Quick note")
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => { event.accepted = root.handleKey(event); }
                    Keys.onReleased: event => root.releaseKey(event)

                    Text {
                        anchors.fill: parent
                        text: Translation.tr("Search notes…")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        visible: quickInput.text.length === 0
                    }

                    onAccepted: root.captureNote()
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 26
                    visible: quickInput.text.trim().length > 0
                    enabled: NotesService.ready
                    Accessible.name: Translation.tr("Save note")
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover

                    contentItem: TaskShortcutContent {
                        symbol: "arrow_forward"
                        shortcut: "↵"
                        showHint: root.hintVisible
                        iconSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimary
                    }

                    onClicked: root.captureNote()
                    StyledToolTip { text: Translation.tr("Save note") + " (Ctrl+Enter)" }
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
                currentIndex: -1
                keyNavigationEnabled: false
                boundsBehavior: Flickable.StopAtBounds
                bottomMargin: noteFab.baseSize + noteFab.anchors.bottomMargin

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index

                    width: listView.width
                    implicitHeight: root.compact ? 44 : 52
                    radius: Appearance.rounding.small
                    color: cardArea.containsMouse || (root.activeFocus && listView.currentIndex === card.index)
                        ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                    Behavior on color {
                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }

                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openNote(card.index)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        TaskShortcutContent {
                            symbol: card.modelData.icon && card.modelData.icon.length > 0 ? card.modelData.icon : "description"
                            shortcut: String(card.index + 1)
                            showHint: root.hintVisible
                            circle: true
                            iconSize: Appearance.font.pixelSize.larger
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

        StyledText {
            Layout.fillWidth: true
            text: quickInput.activeFocus ? "Ctrl + ↵  ·  Esc" : "↑ / ↓  ·  Home / End  ·  ↵"
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            opacity: root.hintVisible ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
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
        enabled: NotesService.ready
        Accessible.name: Translation.tr("New note")
        contentItem: TaskShortcutContent {
            symbol: noteFab.iconText
            shortcut: "Ctrl\n+ N"
            showHint: root.hintVisible
            iconSize: noteFab.iconSize
            color: noteFab.colOnBackground
        }
        onClicked: root.createNote()

        StyledToolTip {
            text: Translation.tr("New note") + " (Ctrl+N)"
        }
    }
}
