pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    readonly property color colBg: "transparent"
    readonly property color colTitleText: Appearance.colors.colOnSurface
    
    readonly property color colSaveBtnBg: Appearance.colors.colPrimary
    readonly property color colSaveBtnBgHover: Appearance.colors.colPrimaryHover
    readonly property color colSaveBtnText: Appearance.colors.colOnPrimary
    readonly property color colSaveBtnDisabledBg: Appearance.colors.colSurfaceContainerHighest
    readonly property color colSaveBtnDisabledBgHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property color colSaveBtnDisabledText: Appearance.colors.colOnSurfaceVariant
    
    readonly property color colSaveFeedbackBg: Appearance.colors.colTertiary
    readonly property color colSaveFeedbackBgHover: Appearance.colors.colTertiaryHover
    readonly property color colSaveFeedbackText: Appearance.colors.colOnTertiary
    
    readonly property color colCloseBtnBg: Appearance.colors.colSurfaceContainerHighest
    readonly property color colCloseBtnBgHover: Appearance.colors.colSurfaceContainerHighestHover
    readonly property color colCloseBtnIcon: Appearance.colors.colOnSurface
    
    readonly property color colFieldBg: Appearance.colors.colSurfaceContainerHigh
    readonly property color colFieldLabel: Appearance.colors.colOnSurface
    readonly property color colFieldText: Appearance.colors.colOnSurface
    readonly property color colFieldPlaceholder: Appearance.colors.colOnSurfaceVariant

    property bool isOpen: false
    property bool isAnimating: false
    // Keybind hints (already gated upstream by the page's Ctrl-hold state).
    property bool showShortcutHints: false
    property string mode: "add"
    property string editId: ""
    property string editCommand: ""
    property string editDescription: ""
    property string editTags: ""
    property bool isSavedFeedback: false

    signal closeRequested

    MouseArea {
        anchors.fill: parent
        z: 0
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        enabled: root.isOpen || root.isAnimating
    }

    onIsOpenChanged: {
        if (isOpen) {
            isAnimating = true;
            background.x = root.width;
            background.width = root.width;
            background.y = 0;
            background.height = root.height;
            contentArea.opacity = 0;
            openAnim.start();

            commandField.text = root.editCommand;
            descField.text = root.editDescription;
            tagsField.text = root.editTags;
            commandField.inputItem.forceActiveFocus();
        }
    }

    SequentialAnimation {
        id: openAnim
        ParallelAnimation {
            NumberAnimation {
                target: background; property: "x"; to: 0; duration: 380
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: contentArea; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic
            }
        }
        ScriptAction { script: isAnimating = false }
    }

    function startClose() { closeAnim.start(); }

    SequentialAnimation {
        id: closeAnim
        ScriptAction { script: isAnimating = true }
        ParallelAnimation {
            NumberAnimation {
                target: background; property: "x"; to: root.width; duration: 300
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
            NumberAnimation {
                target: contentArea; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: {
                isAnimating = false;
                root.isOpen = false;
                root.closeRequested();
            }
        }
    }

    Timer {
        id: saveFeedbackTimer
        interval: 2000
        onTriggered: root.isSavedFeedback = false
    }

    // Save from anywhere in the form; Esc steps back to the list.
    Shortcut {
        enabled: root.isOpen
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        onActivated: root.confirmSave()
    }
    Shortcut {
        enabled: root.isOpen
        sequence: "Escape"
        onActivated: root.startClose()
    }

    function confirmSave() {
        const cmd = commandField.text.trim();
        if (!cmd) return;

        const desc = descField.text.trim();
        const tags = tagsField.text.split(",").map(t => t.trim()).filter(t => t.length > 0);

        if (root.mode === "add") {
            CommandsService.addCommand(cmd, desc, tags);
            commandField.text = ""; descField.text = ""; tagsField.text = "";
            commandField.inputItem.forceActiveFocus();
            root.isSavedFeedback = true;
            saveFeedbackTimer.restart();
        } else {
            CommandsService.updateCommand(root.editId, cmd, desc, tags);
            root.startClose();
        }
    }

    component FormField: RowLayout {
        id: fieldRoot
        property string label: ""
        property string placeholder: ""
        property alias text: input.text
        property alias inputItem: input
        property bool isMonospace: false
        signal returnPressed
        
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        spacing: 4

        Rectangle {
            Layout.preferredWidth: labelText.implicitWidth + 40
            Layout.preferredHeight: 56
            color: root.colFieldBg
            topLeftRadius: Appearance.rounding.verylarge
            bottomLeftRadius: Appearance.rounding.verylarge
            topRightRadius: Appearance.rounding.small
            bottomRightRadius: Appearance.rounding.small
            antialiasing: true

            StyledText {
                id: labelText
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.leftMargin: 20
                text: fieldRoot.label
                font.weight: Font.Bold
                color: root.colFieldLabel
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            color: root.colFieldBg
            topLeftRadius: Appearance.rounding.small
            bottomLeftRadius: Appearance.rounding.small
            topRightRadius: Appearance.rounding.verylarge
            bottomRightRadius: Appearance.rounding.verylarge
            antialiasing: true

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.IBeamCursor
                onClicked: input.forceActiveFocus()
            }

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 16; anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                font.family: fieldRoot.isMonospace ? Appearance.font.family.monospace : Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.normal
                color: root.colFieldText
                clip: true

                Keys.onReturnPressed: fieldRoot.returnPressed()
                Keys.onEscapePressed: root.startClose()

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: fieldRoot.placeholder
                    color: root.colFieldPlaceholder
                    visible: input.text.length === 0 && !input.activeFocus
                }
            }
        }
    }

    Rectangle {
        id: background
        x: root.isOpen || root.isAnimating ? undefined : root.width
        y: 0
        width: root.width; height: root.height
        color: root.colBg
        visible: root.isOpen || root.isAnimating
        radius: Appearance.rounding.windowRounding
        antialiasing: true
        clip: true

        Item {
            id: contentArea
            anchors.fill: parent; anchors.margins: 16
            opacity: 0

            ColumnLayout {
                anchors.fill: parent; spacing: 16

                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    StyledText {
                        Layout.fillWidth: true
                        text: root.mode === "add" ? qsTr("Add Command") : qsTr("Edit Command")
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: root.colTitleText
                    }

                    RippleButton {
                        implicitHeight: 44
                        implicitWidth: saveRow.implicitWidth + 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.isSavedFeedback ? root.colSaveFeedbackBg : (commandField.text.trim().length > 0 ? root.colSaveBtnBg : root.colSaveBtnDisabledBg)
                        colBackgroundHover: root.isSavedFeedback ? root.colSaveFeedbackBgHover : (commandField.text.trim().length > 0 ? root.colSaveBtnBgHover : root.colSaveBtnDisabledBgHover)
                        enabled: commandField.text.trim().length > 0 || root.isSavedFeedback
                        onClicked: if (!root.isSavedFeedback) root.confirmSave()

                        RowLayout {
                            id: saveRow
                            anchors.centerIn: parent; spacing: 8
                            TaskShortcutContent {
                                symbol: root.isSavedFeedback ? "check" : "save"
                                labelText: root.isSavedFeedback ? qsTr("Saved!") : qsTr("Save")
                                shortcut: "Ctrl + ↵"
                                showHint: root.showShortcutHints
                                iconSize: Appearance.font.pixelSize.normal
                                labelPixelSize: Appearance.font.pixelSize.small
                                color: (commandField.text.trim().length > 0 || root.isSavedFeedback) ? (root.isSavedFeedback ? root.colSaveFeedbackText : root.colSaveBtnText) : root.colSaveBtnDisabledText
                            }
                        }
                    }

                    RippleButton {
                        implicitWidth: 44; implicitHeight: 44
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.colCloseBtnBg
                        colBackgroundHover: root.colCloseBtnBgHover
                        onClicked: root.startClose()
                        TaskShortcutContent {
                            anchors.centerIn: parent
                            symbol: "close"
                            shortcut: "Esc"
                            showHint: root.showShortcutHints
                            iconSize: Appearance.font.pixelSize.large
                            color: root.colCloseBtnIcon
                        }
                    }
                }

                FormField {
                    id: commandField
                    label: qsTr("Command")
                    placeholder: "git stash pop"
                    isMonospace: true
                    onReturnPressed: descField.inputItem.forceActiveFocus()
                }

                FormField {
                    id: descField
                    label: qsTr("Description")
                    placeholder: qsTr("What does it do?")
                    onReturnPressed: tagsField.inputItem.forceActiveFocus()
                }

                FormField {
                    id: tagsField
                    label: qsTr("Tags")
                    placeholder: "git, workflow"
                    onReturnPressed: root.confirmSave()
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
