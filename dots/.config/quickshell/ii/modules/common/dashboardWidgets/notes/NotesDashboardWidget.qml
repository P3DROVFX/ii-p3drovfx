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

    property int sizeW: 0
    property int sizeH: 0

    readonly property bool isWide: sizeW >= 4 || (sizeW === 0 && root.width > 320 && root.height < 200)
    readonly property bool isTall: sizeH >= 4 || (sizeH === 0 && root.height > 220 && root.width < 260)
    readonly property bool isCompact: (sizeW === 2 && sizeH === 2) || (sizeW === 0 && root.width < 260 && root.height < 180)

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
    readonly property bool compact: root.isCompact || (root.height > 0 && root.height < 300)
    readonly property bool dense: root.isCompact || root.width < 260
    readonly property var recentNotes: Array.from(NotesService.notes ?? []).slice(0, 6)

    Component {
        id: cardDelegate

        Rectangle {
            id: card
            required property var modelData
            required property int index

            width: ListView.view ? ListView.view.width : parent.width
            implicitHeight: root.isCompact ? 36 : (root.compact ? 44 : 52)
            radius: Appearance.rounding.small
            color: cardArea.containsMouse || (root.activeFocus && ListView.view && ListView.view.currentIndex === card.index)
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
                anchors.margins: root.isCompact ? 4 : 8
                spacing: root.isCompact ? 6 : 10

                TaskShortcutContent {
                    symbol: card.modelData.icon && card.modelData.icon.length > 0 ? card.modelData.icon : "description"
                    shortcut: String(card.index + 1)
                    showHint: root.hintVisible
                    circle: true
                    iconSize: root.isCompact ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                    color: card.modelData.favorite ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.isCompact ? 0 : 2

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.title && card.modelData.title.length > 0
                            ? card.modelData.title
                            : Translation.tr("Untitled note")
                        font.pixelSize: root.isCompact ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.isCompact && card.modelData.preview && card.modelData.preview.length > 0
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

    // ── Wide 4x2 Layout ──────────────────────────────────────────────────
    RowLayout {
        id: wideLayout
        visible: root.isWide
        anchors.fill: parent
        anchors.margins: 6
        spacing: 12

        Item {
            Layout.preferredWidth: Math.round(parent.width * 0.42)
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Appearance.rounding.full
                    color: wideSearchHover.containsMouse || wideQuickInput.activeFocus
                        ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                    MouseArea {
                        id: wideSearchHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.IBeamCursor
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 4

                        MaterialSymbol {
                            text: "search"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }

                        TextInput {
                            id: wideQuickInput
                            Layout.fillWidth: true
                            clip: true
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                            selectByMouse: true
                            cursorVisible: activeFocus
                            activeFocusOnTab: true
                            Accessible.name: Translation.tr("Quick note")

                            Text {
                                anchors.fill: parent
                                text: Translation.tr("Search notes…")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                                visible: wideQuickInput.text.length === 0
                            }

                            onAccepted: {
                                const text = wideQuickInput.text.trim();
                                if (!text.length) return;
                                const result = NotesService.create(text.split("\n")[0].slice(0, 80), text, null);
                                if (result.ok) wideQuickInput.text = "";
                            }
                        }

                        RippleButton {
                            implicitWidth: 26
                            implicitHeight: 22
                            visible: wideQuickInput.text.trim().length > 0
                            enabled: NotesService.ready
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover

                            contentItem: MaterialSymbol {
                                text: "arrow_forward"
                                iconSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimary
                            }

                            onClicked: {
                                const text = wideQuickInput.text.trim();
                                if (!text.length) return;
                                const result = NotesService.create(text.split("\n")[0].slice(0, 80), text, null);
                                if (result.ok) wideQuickInput.text = "";
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 notes").arg(String(NotesService.notes?.length ?? 0))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    RippleButton {
                        implicitHeight: 32
                        implicitWidth: 80
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.createNote()

                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: "add"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: Translation.tr("New")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                anchors.fill: parent
                visible: root.recentNotes.length > 0
                clip: true
                spacing: 4
                model: root.recentNotes
                delegate: cardDelegate
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: root.recentNotes.length === 0
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "note_stack"
                    iconSize: 28
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No notes yet")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Standard / Compact / Tall Layout ─────────────────────────────────
    ColumnLayout {
        id: standardLayout
        visible: !root.isWide
        anchors.fill: parent
        anchors.margins: root.isCompact ? 4 : (root.dense ? 4 : 8)
        spacing: root.isCompact ? 4 : (root.compact ? 6 : 10)

        // ── Quick Capture Row ─────────────────────────────────────────────
        Rectangle {
            id: searchField
            Layout.fillWidth: true
            implicitHeight: root.isCompact ? 28 : (root.compact ? 34 : 38)
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
                anchors.leftMargin: root.isCompact ? 8 : 12
                anchors.rightMargin: 6
                spacing: root.isCompact ? 4 : 6

                TaskShortcutContent {
                    Layout.preferredWidth: Appearance.font.pixelSize.smallest * 3
                    Layout.preferredHeight: Appearance.font.pixelSize.larger
                    symbol: "search"
                    shortcut: "Ctrl\n+ F"
                    showHint: root.hintVisible
                    iconSize: root.isCompact ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
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
                    implicitWidth: root.isCompact ? 26 : 32
                    implicitHeight: root.isCompact ? 22 : 26
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

                RippleButton {
                    implicitWidth: 22
                    implicitHeight: 22
                    visible: root.isCompact && quickInput.text.trim().length === 0
                    enabled: NotesService.ready
                    Accessible.name: Translation.tr("New note")
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colPrimary
                    }
                    onClicked: root.createNote()
                    StyledToolTip { text: Translation.tr("New note") }
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
                    iconSize: root.isCompact ? 28 : 36
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No notes yet")
                    font.pixelSize: root.isCompact ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }

            // List View
            ListView {
                id: listView
                anchors.fill: parent
                visible: root.recentNotes.length > 0
                clip: true
                spacing: root.isCompact ? 4 : 6
                model: root.recentNotes
                currentIndex: -1
                keyNavigationEnabled: false
                boundsBehavior: Flickable.StopAtBounds
                bottomMargin: root.isCompact ? 0 : (noteFab.baseSize + noteFab.anchors.bottomMargin)

                delegate: cardDelegate
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.isCompact
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
        visible: noteFab.visible
    }

    // Same pill as the To-Do create button, in the same corner.
    FloatingActionButton {
        id: noteFab
        visible: !root.isWide && !root.isCompact
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.isCompact ? 4 : (root.dense ? 6 : 14)
        anchors.bottomMargin: root.isCompact ? 4 : (root.dense ? 6 : 14)
        baseSize: root.isCompact ? 32 : (root.dense ? 40 : 52)
        iconSize: root.isCompact ? 16 : (root.compact ? 20 : 24)
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
