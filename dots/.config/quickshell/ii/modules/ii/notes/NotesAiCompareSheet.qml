pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * Side-by-side AI comparison sheet.
 *
 * Displays original text vs. AI generated proposal before any changes are applied.
 * Inviolable rule: The AI NEVER overwrites document content directly without the
 * user explicitly choosing "Substituir".
 *
 * Offers 4 actions:
 * 1. Substituir (Replace): Applies AI proposal in place of the original text.
 * 2. Inserir abaixo (Insert below): Keeps original text and appends proposal as a new block.
 * 3. Copiar (Copy): Copies proposal to Wayland clipboard.
 * 4. Descartar (Discard): Cancels and closes without modifying document.
 */
Item {
    id: root

    property string taskTitle: Translation.tr("AI Review")
    property string originalText: ""
    property string proposedText: ""
    property var task: null // AiTextTask instance
    property string targetBlockId: ""
    property string mode: "selection" // "selection" | "block" | "note" | "title" | "tags"

    signal replaceRequested(string newText)
    signal insertBelowRequested(string newText)
    signal copyRequested(string text)
    signal discardRequested()

    readonly property bool isStreaming: root.task && root.task.running
    readonly property bool hasError: root.task && root.task.status === "error"
    readonly property string errorText: root.task ? root.task.errorText : ""
    readonly property string modelName: root.task ? root.task.modelName : Translation.tr("AI Model")
    readonly property bool isLocalModel: root.task ? root.task.isLocal : false

    // Diff view mode toggle: "sideBySide" | "diff"
    property string viewMode: "sideBySide"

    // Toast/Feedback state for copy
    property bool copiedFeedback: false
    Timer {
        id: copyFeedbackTimer
        interval: 2000
        repeat: false
        onTriggered: root.copiedFeedback = false
    }

    function copyToClipboard(): void {
        const textToCopy = root.proposedText.length > 0 ? root.proposedText : (root.task ? root.task.resultText : "");
        if (textToCopy.length === 0)
            return;
        Quickshell.execDetached(["wl-copy", "--", textToCopy]);
        root.copiedFeedback = true;
        copyFeedbackTimer.restart();
        root.copyRequested(textToCopy);
    }

    function discard(): void {
        if (root.task && root.task.running)
            root.task.cancel();
        root.discardRequested();
    }

    // Connect to AiTextTask signals if provided
    Connections {
        target: root.task
        function onChunk(added) {
            if (root.task)
                root.proposedText = root.task.resultText;
        }
        function onFinished(result) {
            root.proposedText = result;
        }
    }

    // ── Scrim backdrop ────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
            anchors.fill: parent
            onClicked: {} // Block clicks outside
        }
    }

    // ── Dialog Card ───────────────────────────────────────────────────────
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 860)
        height: Math.min(parent.height - 32, 600)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHighest
        clip: true

        StyledRectangularShadow {
            target: dialogCard
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // ── Header Bar ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: "auto_awesome"
                    iconSize: 24
                    color: Appearance.colors.colTertiary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: root.taskTitle
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    RowLayout {
                        spacing: 8

                        // Model info chip
                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: modelLabel.implicitWidth + 14
                            radius: Appearance.rounding.small
                            color: root.isLocalModel
                                ? Appearance.m3colors.m3primaryContainer
                                : Appearance.colors.colLayer2

                            RowLayout {
                                id: modelLabel
                                anchors.centerIn: parent
                                spacing: 5

                                Rectangle {
                                    implicitWidth: 6
                                    implicitHeight: 6
                                    radius: 3
                                    color: root.isLocalModel
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colTertiary
                                }

                                StyledText {
                                    text: root.modelName
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.isLocalModel
                                        ? Appearance.m3colors.m3onPrimaryContainer
                                        : Appearance.colors.colOnLayer1
                                }
                            }
                        }

                        // Char delta count
                        StyledText {
                            text: Translation.tr("%1 → %2 chars").arg(root.originalText.length).arg(root.proposedText.length)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // View Mode Toggle (Side-by-side vs Diff)
                RowLayout {
                    spacing: 2

                    RippleButton {
                        implicitHeight: 28
                        implicitWidth: 84
                        buttonRadius: Appearance.rounding.verysmall
                        toggled: root.viewMode === "sideBySide"
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.viewMode = "sideBySide"

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Side-by-side")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.viewMode === "sideBySide" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }
                    }

                    RippleButton {
                        implicitHeight: 28
                        implicitWidth: 70
                        buttonRadius: Appearance.rounding.verysmall
                        toggled: root.viewMode === "diff"
                        colBackground: Appearance.colors.colLayer1
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.viewMode = "diff"

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Changes")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.viewMode === "diff" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }
                    }
                }

                NotesIconButton {
                    symbol: "close"
                    size: 34
                    iconSize: 20
                    tooltipText: Translation.tr("Discard & Close")
                    onTriggered: root.discard()
                }
            }

            // ── Main Content Area ─────────────────────────────────────────
            // Side-by-side view
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.viewMode === "sideBySide"
                spacing: 12

                // Left Column: Original Text
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "history"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: Translation.tr("What you wrote")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: Translation.tr("%1 chars").arg(root.originalText.length)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        clip: true

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 12
                            contentWidth: width
                            contentHeight: origTextItem.implicitHeight
                            clip: true

                            StyledText {
                                id: origTextItem
                                width: parent.width
                                text: root.originalText.length > 0 ? root.originalText : Translation.tr("(Empty)")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: root.originalText.length > 0 ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnLayer1Inactive
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                // Right Column: AI Proposal
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "auto_awesome"
                            iconSize: 16
                            color: Appearance.colors.colTertiary
                        }

                        StyledText {
                            text: Translation.tr("AI Proposal")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colTertiary
                        }

                        Item { Layout.fillWidth: true }

                        // Status badge (streaming vs ready vs error)
                        RowLayout {
                            spacing: 4

                            Rectangle {
                                visible: root.isStreaming
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: Appearance.colors.colTertiary

                                SequentialAnimation on opacity {
                                    running: root.isStreaming
                                    loops: Animation.Infinite
                                    PropertyAnimation { to: 0.3; duration: 600 }
                                    PropertyAnimation { to: 1.0; duration: 600 }
                                }
                            }

                            StyledText {
                                text: {
                                    if (root.isStreaming)
                                        return Translation.tr("Writing…");
                                    if (root.hasError)
                                        return Translation.tr("Failed");
                                    return Translation.tr("%1 chars").arg(root.proposedText.length);
                                }
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: root.hasError ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        clip: true

                        // Error Banner if failed
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            visible: root.hasError
                            spacing: 8

                            MaterialSymbol {
                                text: "error"
                                iconSize: 32
                                color: Appearance.m3colors.m3error
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.errorText
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.m3colors.m3error
                                wrapMode: Text.Wrap
                            }

                            Item { Layout.fillHeight: true }

                            RippleButton {
                                implicitHeight: 32
                                implicitWidth: 90
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colLayer2
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                onClicked: {
                                    if (root.task)
                                        root.task.start(root.task.systemPrompt, root.task.userText);
                                }

                                contentItem: StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Try again")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }

                        // Proposal text content
                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 12
                            visible: !root.hasError
                            contentWidth: width
                            contentHeight: propTextItem.implicitHeight
                            clip: true

                            StyledText {
                                id: propTextItem
                                width: parent.width
                                text: root.proposedText.length > 0 ? root.proposedText : (root.isStreaming ? Translation.tr("Writing…") : Translation.tr("Nothing came back."))
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: root.proposedText.length > 0 ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnLayer1Inactive
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }

            // Diff changes view
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.viewMode === "diff"
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 12
                    contentWidth: width
                    contentHeight: diffCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: diffCol
                        width: parent.width
                        spacing: 8

                        // Removed box (Original)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: remCol.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.m3colors.m3errorContainer
                            opacity: 0.9

                            ColumnLayout {
                                id: remCol
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "remove_circle_outline"
                                        iconSize: 16
                                        color: Appearance.m3colors.m3onErrorContainer
                                    }
                                    StyledText {
                                        text: Translation.tr("Original text to replace:")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        color: Appearance.m3colors.m3onErrorContainer
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.originalText
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3onErrorContainer
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        // Added box (Proposed)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: addCol.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.m3colors.m3primaryContainer
                            opacity: 0.9

                            ColumnLayout {
                                id: addCol
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "add_circle_outline"
                                        iconSize: 16
                                        color: Appearance.m3colors.m3onPrimaryContainer
                                    }
                                    StyledText {
                                        text: Translation.tr("Proposed replacement:")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        color: Appearance.m3colors.m3onPrimaryContainer
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.proposedText.length > 0 ? root.proposedText : Translation.tr("(Generating...)")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3onPrimaryContainer
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }

            // ── Footer: 4 Action Buttons ──────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Action 4: Descartar (Discard)
                RippleButton {
                    implicitHeight: 38
                    implicitWidth: 100
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.discard()

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "close"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: Translation.tr("Discard")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                // Action 3: Copiar (Copy)
                RippleButton {
                    implicitHeight: 38
                    implicitWidth: 110
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    enabled: root.proposedText.length > 0
                    onClicked: root.copyToClipboard()

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: root.copiedFeedback ? "check" : "content_copy"
                            iconSize: 18
                            color: root.copiedFeedback ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            text: root.copiedFeedback ? Translation.tr("Copied!") : Translation.tr("Copy")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: root.copiedFeedback ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Action 2: Inserir abaixo (Insert Below)
                RippleButton {
                    implicitHeight: 38
                    implicitWidth: 130
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    enabled: root.proposedText.length > 0 && !root.isStreaming
                    onClicked: {
                        root.insertBelowRequested(root.proposedText);
                        root.discardRequested();
                    }

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "playlist_add"
                            iconSize: 18
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            text: Translation.tr("Add it below")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }

                // Action 1: Substituir (Replace)
                RippleButton {
                    implicitHeight: 38
                    implicitWidth: 120
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.m3colors.m3primary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    enabled: root.proposedText.length > 0 && !root.isStreaming
                    onClicked: {
                        root.replaceRequested(root.proposedText);
                        root.discardRequested();
                    }

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "check"
                            iconSize: 18
                            color: Appearance.m3colors.m3onPrimary
                        }

                        StyledText {
                            text: Translation.tr("Replace")
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
