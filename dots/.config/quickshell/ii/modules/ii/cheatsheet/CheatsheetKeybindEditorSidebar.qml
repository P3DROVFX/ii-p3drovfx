pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Right rail for creating and editing a personal shortcut.
 *
 * The form follows the Timetable rail pattern: a strong preview/hero, one
 * primary editing path, contextual chips, progressive disclosure, and sticky
 * actions. The parent owns width; this component owns state and transitions.
 */
Item {
    id: root

    required property string pageId
    property Item keyNavTarget: null
    property bool isOpen: false
    property bool isAnimating: false
    property string editingKeybindId: ""
    property bool detailsExpanded: false
    property bool confirmingDelete: false
    property real pageShift: 28
    property real pageOpacity: 1
    property string contextValue: ""
    property string iconValue: ""
    property int sessionAddCount: 0
    property bool keepCategory: false
    property bool keepContext: false
    property bool recordingKeys: false

    readonly property var conflicts: KeybindsService.detectConflicts(root.pageId, keysField.text, root.editingKeybindId)

    readonly property var page: {
        const revision = KeybindsService.revision;
        return KeybindsService.pageById(root.pageId);
    }
    readonly property var categorySuggestions: {
        const seen = {};
        const categories = [];
        for (const entry of root.page?.keybinds ?? []) {
            const category = String(entry.category ?? "").trim();
            if (!category || seen[category])
                continue;
            seen[category] = true;
            categories.push(category);
            if (categories.length >= 6)
                break;
        }
        return categories;
    }
    readonly property var iconChoices: [
        { icon: "auto_awesome", value: "", label: Translation.tr("Automatic") },
        { icon: "search", value: "search", label: Translation.tr("Search") },
        { icon: "edit", value: "edit", label: Translation.tr("Edit") },
        { icon: "code", value: "code", label: Translation.tr("Code") },
        { icon: "terminal", value: "terminal", label: Translation.tr("Terminal") },
        { icon: "folder_open", value: "folder_open", label: Translation.tr("Files") },
        { icon: "play_arrow", value: "play_arrow", label: Translation.tr("Run") },
        { icon: "bug_report", value: "bug_report", label: Translation.tr("Debug") },
        { icon: "visibility", value: "visibility", label: Translation.tr("View") },
        { icon: "commit", value: "commit", label: Translation.tr("Git") },
        { icon: "open_with", value: "open_with", label: Translation.tr("Move") },
        { icon: "select", value: "select", label: Translation.tr("Select") }
    ]
    readonly property string previewIcon: root.iconValue.trim() || root.inferredIcon(categoryField.text, descriptionField.text)
    readonly property string optionalSummary: {
        const pieces = [];
        if (categoryField.text.trim()) pieces.push(categoryField.text.trim());
        if (root.contextValue.trim()) pieces.push(root.contextValue.trim());
        if (root.iconValue.trim()) pieces.push(Translation.tr("custom icon"));
        if (notesField.text.trim()) pieces.push(Translation.tr("notes"));
        return pieces.length ? pieces.join(" · ") : Translation.tr("Category, context, icon and notes");
    }

    signal closeRequested

    visible: root.isOpen || root.isAnimating
    enabled: root.isOpen || root.isAnimating

    function inferredIcon(category, description): string {
        const value = (String(category ?? "") + " " + String(description ?? "")).toLowerCase();
        if (value.includes("search") || value.includes("find")) return "search";
        if (value.includes("file") || value.includes("folder") || value.includes("project")) return "folder_open";
        if (value.includes("edit") || value.includes("change") || value.includes("replace")) return "edit";
        if (value.includes("git") || value.includes("commit")) return "commit";
        if (value.includes("debug") || value.includes("test")) return "bug_report";
        if (value.includes("run") || value.includes("launch")) return "play_arrow";
        if (value.includes("window") || value.includes("split") || value.includes("pane")) return "view_quilt";
        if (value.includes("move") || value.includes("jump") || value.includes("go to")) return "open_with";
        if (value.includes("select") || value.includes("visual")) return "select";
        if (value.includes("terminal") || value.includes("command")) return "terminal";
        return "keyboard_command_key";
    }

    function contextIcon(context): string {
        const value = String(context ?? "").toLowerCase();
        if (value.includes("normal")) return "arrow_selector_tool";
        if (value.includes("insert")) return "edit";
        if (value.includes("visual") || value.includes("select")) return "select";
        if (value.includes("command") || value.includes("terminal")) return "terminal";
        return "adjust";
    }

    function resetFields(): void {
        keysField.text = "";
        descriptionField.text = "";
        categoryField.text = "";
        root.contextValue = "";
        root.iconValue = "";
        notesField.text = "";
        keysField.error = false;
        descriptionField.error = false;
        root.detailsExpanded = false;
        root.confirmingDelete = false;
    }

    function openCreate(): void {
        root.editingKeybindId = "";
        root.sessionAddCount = 0;
        root.resetFields();
        root.isOpen = true;
    }

    function openEdit(entry): void {
        if (!entry)
            return;
        root.editingKeybindId = String(entry.id ?? "");
        root.sessionAddCount = 0;
        keysField.text = String(entry.keys ?? "");
        descriptionField.text = String(entry.description ?? "");
        categoryField.text = String(entry.category ?? "");
        root.contextValue = String(entry.context ?? "");
        root.iconValue = String(entry.icon ?? "");
        notesField.text = String(entry.notes ?? "");
        root.detailsExpanded = Boolean(categoryField.text || root.contextValue || root.iconValue || notesField.text);
        root.confirmingDelete = false;
        root.isOpen = true;
    }

    function saveForm(andNext = false): void {
        const keys = keysField.text.trim();
        const description = descriptionField.text.trim();
        keysField.error = !keys;
        descriptionField.error = !description;
        if (!keys) {
            keysField.forceActiveFocus();
            return;
        }
        if (!description) {
            descriptionField.forceActiveFocus();
            return;
        }

        const saved = root.editingKeybindId
            ? KeybindsService.updateKeybind(root.pageId, root.editingKeybindId, keys, description, categoryField.text, root.contextValue, notesField.text, root.iconValue)
            : Boolean(KeybindsService.addKeybind(root.pageId, keys, description, categoryField.text, root.contextValue, notesField.text, root.iconValue));
        if (saved) {
            if (andNext && !root.editingKeybindId) {
                root.sessionAddCount++;
                keysField.text = "";
                descriptionField.text = "";
                if (!root.keepCategory)
                    categoryField.text = "";
                if (!root.keepContext)
                    root.contextValue = "";
                root.iconValue = "";
                notesField.text = "";
                keysField.error = false;
                descriptionField.error = false;
                Qt.callLater(() => keysField.forceActiveFocus());
            } else {
                root.close();
            }
        }
    }

    function requestDelete(): void {
        if (!root.editingKeybindId)
            return;
        if (!root.confirmingDelete) {
            root.confirmingDelete = true;
            deleteConfirmationTimer.restart();
            return;
        }
        deleteConfirmationTimer.stop();
        if (KeybindsService.deleteKeybind(root.pageId, root.editingKeybindId))
            root.close();
    }

    function close(): void {
        if (!root.isOpen)
            return;
        openAnimation.stop();
        closeAnimation.restart();
    }

    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root.isAnimating = true;
        root.pageShift = 28;
        root.pageOpacity = 0;
        openAnimation.restart();
        Qt.callLater(() => keysField.forceActiveFocus());
    }

    Timer {
        id: deleteConfirmationTimer
        interval: 4500
        repeat: false
        onTriggered: root.confirmingDelete = false
    }

    ParallelAnimation {
        id: openAnimation

        NumberAnimation {
            target: root
            property: "pageShift"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }

        NumberAnimation {
            target: root
            property: "pageOpacity"
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }

        onFinished: root.isAnimating = false
    }

    ParallelAnimation {
        id: closeAnimation

        NumberAnimation {
            target: root
            property: "pageShift"
            to: 28
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }

        NumberAnimation {
            target: root
            property: "pageOpacity"
            to: 0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }

        onFinished: {
            root.isAnimating = false;
            root.isOpen = false;
            root.editingKeybindId = "";
            root.confirmingDelete = false;
            root.closeRequested();
        }
    }

    Keys.onEscapePressed: event => {
        root.close();
        event.accepted = true;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    text: root.editingKeybindId ? "edit_square" : "add"
                    iconSize: Appearance.font.pixelSize.large
                    padding: 10
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.editingKeybindId ? Translation.tr("Edit shortcut") : Translation.tr("New shortcut")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: String(root.page?.name ?? Translation.tr("Personal library"))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    visible: Boolean(root.editingKeybindId)
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.confirmingDelete ? Appearance.colors.colError : "transparent"
                    colBackgroundHover: root.confirmingDelete ? Appearance.colors.colErrorHover : Appearance.colors.colErrorContainer
                    Accessible.name: root.confirmingDelete ? Translation.tr("Click again to delete") : Translation.tr("Delete shortcut")
                    onClicked: root.requestDelete()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.confirmingDelete ? "delete_forever" : "delete"
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.confirmingDelete ? Appearance.colors.colOnError : Appearance.colors.colError
                    }

                    StyledToolTip {
                        text: root.confirmingDelete ? Translation.tr("Click again to delete") : Translation.tr("Delete shortcut")
                    }
                }

                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    Accessible.name: Translation.tr("Close")
                    onClicked: root.close()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip { text: Translation.tr("Close") }
                }
            }

            Item {
                id: pageHost
                Layout.fillWidth: true
                Layout.fillHeight: true
                opacity: root.pageOpacity

                transform: Translate {
                    x: root.pageShift
                }

                StyledFlickable {
                    id: editorFlick
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: editorColumn.implicitHeight + 4

                    ColumnLayout {
                        id: editorColumn
                        width: editorFlick.width
                        spacing: 10

                        RowLayout {
                            visible: !root.editingKeybindId
                            Layout.fillWidth: true
                            spacing: 6

                            StyledText {
                                visible: root.sessionAddCount > 0
                                text: Translation.tr("%1 added").arg(String(root.sessionAddCount))
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: Appearance.colors.colPrimary
                            }

                            Item { Layout.fillWidth: true }

                            ChoiceChip {
                                symbol: root.keepCategory ? "check" : "bookmark"
                                label: Translation.tr("Keep category")
                                selected: root.keepCategory
                                onTriggered: root.keepCategory = !root.keepCategory
                            }

                            ChoiceChip {
                                symbol: root.keepContext ? "check" : "tune"
                                label: Translation.tr("Keep context")
                                selected: root.keepContext
                                onTriggered: root.keepContext = !root.keepContext
                            }
                        }

                        Rectangle {
                            id: previewCard
                            Layout.fillWidth: true
                            Layout.preferredHeight: 94
                            radius: Appearance.rounding.large
                            color: Appearance.colors.colPrimaryContainer

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 12
                                anchors.topMargin: 10
                                anchors.bottomMargin: 10
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "visibility"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("LIVE PREVIEW")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }

                                    StyledText {
                                        text: root.editingKeybindId ? Translation.tr("EDITING") : Translation.tr("NEW")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 10

                                    KeybindShortcutSequence {
                                        Layout.alignment: Qt.AlignVCenter
                                        maximumWidth: Math.max(1, previewCard.width * 0.44)
                                        shortcutText: keysField.text.trim() || Translation.tr("Press keys")
                                    }

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: root.previewIcon
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: descriptionField.text.trim() || Translation.tr("What this shortcut does")
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimaryContainer
                                        opacity: descriptionField.text.trim() ? 1 : 0.62
                                    }

                                    MaterialSymbol {
                                        visible: Boolean(root.contextValue.trim())
                                        Layout.alignment: Qt.AlignVCenter
                                        text: root.contextIcon(root.contextValue)
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnPrimaryContainer

                                        HoverHandler {
                                            id: previewContextHover
                                        }

                                        StyledToolTip {
                                            extraVisibleCondition: previewContextHover.hovered
                                            text: root.contextValue
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            EditorFieldCard {
                                id: keysField
                                Layout.fillWidth: true
                                symbol: "keyboard"
                                label: root.recordingKeys ? Translation.tr("Listening for chord…") : Translation.tr("Keybind")
                                placeholder: root.recordingKeys ? Translation.tr("Press keys on keyboard…") : Translation.tr("Ctrl+Shift+P or <leader>ff")
                                monospace: true
                                requiredField: true
                                accentKind: root.recordingKeys ? 1 : 0
                                recordKeyMode: root.recordingKeys
                                onAccepted: descriptionField.forceActiveFocus()
                            }

                            RippleButton {
                                id: recordToggle
                                implicitWidth: 46
                                implicitHeight: 74
                                buttonRadius: Appearance.rounding.normal
                                toggled: root.recordingKeys
                                colBackground: root.recordingKeys ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainerHighest
                                colBackgroundHover: root.recordingKeys ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                                Accessible.name: root.recordingKeys ? Translation.tr("Stop recording keys") : Translation.tr("Record keys")
                                onClicked: {
                                    root.recordingKeys = !root.recordingKeys;
                                    if (root.recordingKeys)
                                        keysField.forceActiveFocus();
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.recordingKeys ? "fiber_manual_record" : "radio_button_checked"
                                    iconSize: Appearance.font.pixelSize.larger
                                    fill: root.recordingKeys ? 1 : 0
                                    color: root.recordingKeys ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                }

                                StyledToolTip {
                                    text: root.recordingKeys ? Translation.tr("Stop listening") : Translation.tr("Record key chord live")
                                }
                            }
                        }

                        Rectangle {
                            visible: root.conflicts.length > 0
                            Layout.fillWidth: true
                            implicitHeight: conflictRow.implicitHeight + 16
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colTertiaryContainer

                            RowLayout {
                                id: conflictRow
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                MaterialSymbol {
                                    text: "warning"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnTertiaryContainer
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Shortcut already assigned")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnTertiaryContainer
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.conflicts.length > 0
                                            ? Translation.tr("Matches '%1' in '%2'").arg(root.conflicts[0].description).arg(root.conflicts[0].category || Translation.tr("General"))
                                            : ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnTertiaryContainer
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        EditorFieldCard {
                            id: descriptionField
                            Layout.fillWidth: true
                            symbol: "subject"
                            label: Translation.tr("Action")
                            placeholder: Translation.tr("What does this shortcut do?")
                            requiredField: true
                            accentKind: 1
                            onAccepted: root.saveForm()
                        }

                        RippleButton {
                            id: detailsToggle
                            Layout.fillWidth: true
                            implicitHeight: 62
                            buttonRadius: Appearance.rounding.normal
                            toggled: root.detailsExpanded
                            colBackground: root.detailsExpanded ? Appearance.colors.colPrimaryContainer : Appearance.m3colors.m3surfaceContainerHighest
                            colBackgroundHover: root.detailsExpanded ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                            colBackgroundActive: root.detailsExpanded ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                            onClicked: root.detailsExpanded = !root.detailsExpanded

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                MaterialSymbol {
                                    text: "tune"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: root.detailsExpanded ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Organize & identify")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                        color: root.detailsExpanded ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.optionalSummary
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: root.detailsExpanded ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }

                                MaterialSymbol {
                                    text: root.detailsExpanded ? "expand_less" : "expand_more"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: root.detailsExpanded ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }

                        Item {
                            id: detailsHost
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.detailsExpanded ? detailsColumn.implicitHeight : 0
                            opacity: root.detailsExpanded ? 1 : 0
                            enabled: root.detailsExpanded
                            clip: true

                            Behavior on Layout.preferredHeight {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(detailsHost)
                            }

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(detailsHost)
                            }

                            ColumnLayout {
                                id: detailsColumn
                                width: detailsHost.width
                                spacing: 10

                                MetadataCard {
                                    Layout.fillWidth: true
                                    symbol: "category"
                                    title: Translation.tr("Category")
                                    subtitle: Translation.tr("Groups related shortcuts into one card.")

                                    FilledTextField {
                                        id: categoryField
                                        Layout.fillWidth: true
                                        accessibleName: Translation.tr("Category")
                                        placeholderText: Translation.tr("Movement, Editing, Search…")
                                        navigationTarget: root.keyNavTarget
                                        onAccepted: notesField.forceActiveFocus()
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        visible: root.categorySuggestions.length > 0
                                        spacing: 6

                                        Repeater {
                                            model: root.categorySuggestions
                                            delegate: ChoiceChip {
                                                required property string modelData
                                                symbol: root.inferredIcon(modelData, "")
                                                label: modelData
                                                selected: categoryField.text.trim() === modelData
                                                onTriggered: categoryField.text = modelData
                                            }
                                        }
                                    }
                                }

                                MetadataCard {
                                    Layout.fillWidth: true
                                    symbol: "adjust"
                                    title: Translation.tr("Mode or context")
                                    subtitle: Translation.tr("Shown as a compact symbol on each shortcut.")

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Repeater {
                                            model: [
                                                { label: Translation.tr("Auto"), value: "", icon: "auto_awesome" },
                                                { label: Translation.tr("Normal"), value: "Normal mode", icon: "arrow_selector_tool" },
                                                { label: Translation.tr("Insert"), value: "Insert mode", icon: "edit" },
                                                { label: Translation.tr("Visual"), value: "Visual mode", icon: "select" },
                                                { label: Translation.tr("Command"), value: "Command mode", icon: "terminal" }
                                            ]
                                            delegate: ChoiceChip {
                                                required property var modelData
                                                symbol: modelData.icon
                                                label: modelData.label
                                                selected: root.contextValue.trim() === modelData.value
                                                onTriggered: root.contextValue = root.contextValue.trim() === modelData.value ? "" : modelData.value
                                            }
                                        }
                                    }
                                }

                                MetadataCard {
                                    Layout.fillWidth: true
                                    symbol: "shapes"
                                    title: Translation.tr("Visual symbol")
                                    subtitle: Translation.tr("Choose a recognizable action icon or keep Auto.")

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 7

                                        Repeater {
                                            model: root.iconChoices
                                            delegate: IconChoice {
                                        required property var modelData
                                        symbol: modelData.icon
                                        choiceValue: modelData.value
                                        label: modelData.label
                                        selected: root.iconValue.trim() === modelData.value
                                        onTriggered: root.iconValue = choiceValue
                                    }
                                }
                            }
                        }

                                MetadataCard {
                                    Layout.fillWidth: true
                                    symbol: "notes"
                                    title: Translation.tr("Note or command")
                                    subtitle: Translation.tr("Kept out of the card; available as a hover hint.")

                                    FilledTextField {
                                        id: notesField
                                        Layout.fillWidth: true
                                        accessibleName: Translation.tr("Note or command")
                                        placeholderText: Translation.tr("Plugin, command, or extra hint…")
                                        navigationTarget: root.keyNavTarget
                                        onAccepted: root.saveForm()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SecondaryAction {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    label: root.editingKeybindId ? Translation.tr("Cancel") : Translation.tr("Add & finish")
                    symbol: root.editingKeybindId ? "close" : "check"
                    onTriggered: {
                        if (root.editingKeybindId) {
                            root.close();
                        } else {
                            root.saveForm(false);
                        }
                    }
                }

                PrimaryAction {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1.35
                    label: root.editingKeybindId ? Translation.tr("Save") : Translation.tr("Add & next")
                    symbol: root.editingKeybindId ? "check" : "add"
                    enabled: keysField.text.trim().length > 0 && descriptionField.text.trim().length > 0
                    onTriggered: root.saveForm(!root.editingKeybindId)
                }
            }
        }
    }

    component FilledTextField: Rectangle {
        id: filledField
        property string accessibleName: ""
        property string placeholderText: ""
        property bool monospace: false
        property bool error: false
        property bool recordKeyMode: false
        property Item navigationTarget: null
        property alias text: filledInput.text
        signal accepted

        function forceActiveFocus(): void {
            filledInput.forceActiveFocus();
        }

        implicitHeight: 46
        radius: Appearance.rounding.small
        color: {
            if (filledField.error)
                return Appearance.colors.colErrorContainer;
            if (filledInput.activeFocus)
                return Appearance.m3colors.m3surfaceContainer;
            return Appearance.m3colors.m3surfaceContainerLow;
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(filledField)
        }

        StyledTextInput {
            id: filledInput
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            font.family: filledField.monospace ? Appearance.font.family.monospace : Appearance.font.family.main
            color: filledField.error ? Appearance.colors.colOnErrorContainer : Appearance.m3colors.m3onSurface
            Accessible.name: filledField.accessibleName || filledField.placeholderText
            Keys.forwardTo: filledField.navigationTarget ? [filledField.navigationTarget] : []
            Keys.onPressed: event => {
                if (filledField.recordKeyMode) {
                    const captured = KeybindTokenizer.keyEventToString(event);
                    if (captured) {
                        filledInput.text = captured;
                        event.accepted = true;
                        return;
                    }
                }
            }
            onTextChanged: filledField.error = false
            onAccepted: filledField.accepted()
        }

        StyledText {
            anchors.fill: filledInput
            visible: filledInput.text.length === 0
            verticalAlignment: Text.AlignVCenter
            text: filledField.placeholderText
            elide: Text.ElideRight
            font.family: filledField.monospace ? Appearance.font.family.monospace : Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            color: filledField.error ? Appearance.colors.colOnErrorContainer : Appearance.m3colors.m3onSurfaceVariant
        }
    }

    component EditorFieldCard: Rectangle {
        id: fieldCard
        property string symbol: ""
        property string label: ""
        property string placeholder: ""
        property bool monospace: false
        property bool requiredField: false
        property int accentKind: 0
        property bool recordKeyMode: false
        property alias text: fieldInput.text
        property alias error: fieldInput.error
        signal accepted

        function forceActiveFocus(): void {
            fieldInput.forceActiveFocus();
        }

        Layout.preferredHeight: 74
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHighest

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: fieldCard.symbol
                iconSize: Appearance.font.pixelSize.larger
                color: fieldCard.accentKind === 0 ? Appearance.colors.colPrimary : Appearance.colors.colSecondary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: fieldCard.requiredField
                        ? fieldCard.label + " · " + Translation.tr("required")
                        : fieldCard.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: fieldInput.error ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                }

                FilledTextField {
                    id: fieldInput
                    Layout.fillWidth: true
                    accessibleName: fieldCard.label
                    placeholderText: fieldCard.placeholder
                    monospace: fieldCard.monospace
                    recordKeyMode: fieldCard.recordKeyMode
                    navigationTarget: root.keyNavTarget
                    onAccepted: fieldCard.accepted()
                }
            }
        }
    }

    component MetadataCard: Rectangle {
        id: metadataCard
        default property alias content: metadataContent.data
        property string symbol: ""
        property string title: ""
        property string subtitle: ""

        implicitHeight: metadataColumn.implicitHeight + 18
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHighest

        ColumnLayout {
            id: metadataColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 9
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 9

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: metadataCard.symbol
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colTertiary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: metadataCard.title
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: metadataCard.subtitle
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            ColumnLayout {
                id: metadataContent
                Layout.fillWidth: true
                spacing: 7
            }
        }
    }

    component ChoiceChip: RippleButtonWithIcon {
        id: choiceChip
        property string symbol: ""
        property string label: ""
        property bool selected: false
        signal triggered

        implicitHeight: 36
        implicitWidth: contentImplicitWidth + 18
        buttonRadius: Appearance.rounding.full
        materialIcon: choiceChip.symbol
        materialIconFill: choiceChip.selected
        mainText: choiceChip.label
        iconPixelSize: Appearance.font.pixelSize.normal
        textPixelSize: Appearance.font.pixelSize.smallest
        centerContent: true
        colBackground: choiceChip.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colBackgroundHover: choiceChip.selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colBackgroundActive: choiceChip.selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
        colText: choiceChip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
        Accessible.name: choiceChip.label
        Accessible.checked: choiceChip.selected
        onClicked: choiceChip.triggered()
    }

    component IconChoice: RippleButton {
        id: iconChoice
        property string symbol: ""
        property string choiceValue: ""
        property string label: ""
        property bool selected: false
        signal triggered

        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        colBackground: iconChoice.selected ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colBackgroundHover: iconChoice.selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colBackgroundActive: iconChoice.selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
        Accessible.name: iconChoice.label
        Accessible.checked: iconChoice.selected
        onClicked: iconChoice.triggered()

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: iconChoice.symbol
            iconSize: Appearance.font.pixelSize.normal
            fill: iconChoice.selected ? 1 : 0
            color: iconChoice.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
        }

        StyledToolTip { text: iconChoice.label }
    }

    component PrimaryAction: RippleButtonWithIcon {
        id: primaryAction
        property string label: ""
        property string symbol: ""
        signal triggered

        implicitHeight: 48
        buttonRadius: Appearance.rounding.full
        centerContent: true
        materialIcon: primaryAction.symbol
        materialIconFill: false
        mainText: primaryAction.label
        iconPixelSize: Appearance.font.pixelSize.larger
        textPixelSize: Appearance.font.pixelSize.small
        mainTextWeight: Font.Bold
        colText: Appearance.colors.colOnPrimary
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colBackgroundActive: Appearance.colors.colPrimaryActive
        onClicked: primaryAction.triggered()
    }

    component SecondaryAction: RippleButtonWithIcon {
        id: secondaryAction
        property string label: ""
        property string symbol: ""
        signal triggered

        implicitHeight: 48
        buttonRadius: Appearance.rounding.full
        centerContent: true
        materialIcon: secondaryAction.symbol
        materialIconFill: false
        mainText: secondaryAction.label
        iconPixelSize: Appearance.font.pixelSize.large
        textPixelSize: Appearance.font.pixelSize.small
        mainTextWeight: Font.DemiBold
        colText: Appearance.colors.colOnSecondaryContainer
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colBackgroundActive: Appearance.colors.colSecondaryContainerActive
        onClicked: secondaryAction.triggered()
    }
}
