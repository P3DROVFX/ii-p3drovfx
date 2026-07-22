import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

Rectangle {
    id: root
    property int messageIndex
    property var messageData
    property var messageInputField

    property real messagePadding: 7
    property real contentSpacing: 3

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.messageData?.content)

    property int entranceTrigger: -1
    property bool hasAnimated: false

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight + root.messagePadding * 2

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    layer.enabled: msgBlur.radius > 0
    layer.effect: FastBlur {
        id: msgBlur
        radius: 0
    }

    opacity: root.hasAnimated ? 1.0 : 0.0
    transform: [
        Translate {
            id: messageTransform
            x: 0
            y: 0
        },
        Scale {
            id: messageScale
            origin.x: root.messageData?.role === 'user' ? root.width : 0
            origin.y: root.height / 2
            xScale: 1.0
            yScale: 1.0
        }
    ]

    function startEntrance() {
        messageEntranceAnim.stop();
        root.hasAnimated = false;
        
        // Reset properties prior to animation trigger based on role
        const isUser = root.messageData?.role === 'user';
        const isAssistant = root.messageData?.role === 'assistant';
        
        messageTransform.x = isUser ? 80 : (isAssistant ? -60 : 0);
        messageTransform.y = (!isUser && !isAssistant) ? 25 : 0;
        messageScale.xScale = isUser ? 0.7 : 1.0;
        messageScale.yScale = (!isUser && !isAssistant) ? 0.8 : 1.0;
        msgBlur.radius = isAssistant ? 12 : 0;

        messageEntranceAnim.start();
    }

    Component.onCompleted: {
        Qt.callLater(startEntrance);
    }

    onEntranceTriggerChanged: {
        if (entranceTrigger >= 0) {
            Qt.callLater(startEntrance);
        }
    }

    SequentialAnimation {
        id: messageEntranceAnim
        PauseAnimation { duration: Math.min(root.messageIndex * 55, 450) }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; from: 0.0; to: 1.0; duration: 320; easing.type: Easing.OutQuart }
            NumberAnimation { target: messageTransform; property: "x"; to: 0; duration: 380; easing.type: Easing.OutQuart }
            NumberAnimation { target: messageTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutQuart }
            NumberAnimation { target: messageScale; property: "xScale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
            NumberAnimation { target: messageScale; property: "yScale"; to: 1.0; duration: 380; easing.type: Easing.OutQuart }
            NumberAnimation { target: msgBlur; property: "radius"; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: root.hasAnimated = true; }
    }

    function saveMessage() {
        if (!root.editing) return;
        // Get all Loader children (each represents a segment)
        const segments = messageContentColumnLayout.children
            .map(child => child.segment)
            .filter(segment => (segment));

        // Reconstruct markdown
        const newContent = segments.map(segment => {
            if (segment.type === "code") {
                const lang = segment.lang ? segment.lang : "";
                // Remove trailing newlines
                const code = segment.content.replace(/\n+$/, "");
                return "```" + lang + "\n" + code + "\n```";
            } else {
                return segment.content;
            }
        }).join("");

        root.editing = false
        root.messageData.content = newContent;
    }

    Keys.onPressed: (event) => {
        if ( // Prevent de-select
            event.key === Qt.Key_Control || 
            event.key == Qt.Key_Shift || 
            event.key == Qt.Key_Alt || 
            event.key == Qt.Key_Meta
        ) {
            event.accepted = true
        }
        // Ctrl + S to save
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true;
        }
    }

    ColumnLayout { // Main layout of the whole thing
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: messagePadding
        spacing: root.contentSpacing

        Rectangle {
            Layout.fillWidth: true
            implicitWidth: headerRowLayout.implicitWidth + 4 * 2
            implicitHeight: headerRowLayout.implicitHeight + 4 * 2
            color: Appearance.colors.colSecondaryContainer
            radius: Appearance.rounding.small
        
            RowLayout { // Header
                id: headerRowLayout
                anchors {
                    fill: parent
                    margins: 4
                }
                spacing: 18

                Item { // Name
                    id: nameWrapper
                    implicitHeight: Math.max(nameRowLayout.implicitHeight + 5 * 2, 30)
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: nameRowLayout
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillHeight: true
                            implicitWidth: messageData?.role == 'assistant' ? modelIcon.width : roleIcon.implicitWidth
                            implicitHeight: messageData?.role == 'assistant' ? modelIcon.height : roleIcon.implicitHeight

                            CustomIcon {
                                id: modelIcon
                                anchors.centerIn: parent
                                visible: messageData?.role == 'assistant' && Ai.models[messageData?.model].icon
                                width: Appearance.font.pixelSize.large
                                height: Appearance.font.pixelSize.large
                                source: messageData?.role == 'assistant' ? Ai.models[messageData?.model].icon :
                                    messageData?.role == 'user' ? 'linux-symbolic' : 'desktop-symbolic'

                                colorize: true
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }

                            MaterialSymbol {
                                id: roleIcon
                                anchors.centerIn: parent
                                visible: !modelIcon.visible
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.m3colors.m3onSecondaryContainer
                                text: messageData?.role == 'user' ? 'person' : 
                                    messageData?.role == 'interface' ? 'settings' : 
                                    messageData?.role == 'assistant' ? 'neurology' : 
                                    'computer'
                            }
                        }

                        StyledText {
                            id: providerName
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onSecondaryContainer
                            text: messageData?.role == 'assistant' ? Ai.models[messageData?.model].name :
                                (messageData?.role == 'user' && SystemInfo.username) ? SystemInfo.username :
                                Translation.tr("Interface")
                        }
                    }
                }

                Button { // Not visible to model
                    id: modelVisibilityIndicator
                    visible: messageData?.role == 'interface'
                    implicitWidth: 16
                    implicitHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    background: Item

                    MaterialSymbol {
                        id: notVisibleToModelText
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: "visibility_off"
                    }
                    StyledToolTip {
                        text: Translation.tr("Not visible to model")
                    }
                }

                ButtonGroup {
                    spacing: 5

                    AiMessageControlButton {
                        id: regenButton
                        buttonIcon: "refresh"
                        visible: messageData?.role === 'assistant'

                        onClicked: {
                            Ai.regenerate(root.messageIndex)
                        }
                        
                        StyledToolTip {
                            text: Translation.tr("Regenerate")
                        }
                    }

                    AiMessageControlButton {
                        id: copyButton
                        buttonIcon: activated ? "inventory" : "content_copy"

                        onClicked: {
                            Quickshell.clipboardText = root.messageData?.content
                            copyButton.activated = true
                            copyIconTimer.restart()
                        }

                        Timer {
                            id: copyIconTimer
                            interval: 1500
                            repeat: false
                            onTriggered: {
                                copyButton.activated = false
                            }
                        }
                        
                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }
                    AiMessageControlButton {
                        id: editButton
                        activated: root.editing
                        enabled: root.messageData?.done ?? false
                        buttonIcon: "edit"
                        onClicked: {
                            root.editing = !root.editing
                            if (!root.editing) { // Save changes
                                root.saveMessage()
                            }
                        }
                        StyledToolTip {
                            text: root.editing ? Translation.tr("Save") : Translation.tr("Edit")
                        }
                    }
                    AiMessageControlButton {
                        id: toggleMarkdownButton
                        activated: !root.renderMarkdown
                        buttonIcon: "code"
                        onClicked: {
                            root.renderMarkdown = !root.renderMarkdown
                        }
                        StyledToolTip {
                            text: Translation.tr("View Markdown source")
                        }
                    }
                    AiMessageControlButton {
                        id: deleteButton
                        buttonIcon: "close"
                        onClicked: {
                            Ai.removeMessage(root.messageIndex)
                        }
                        StyledToolTip {
                            text: Translation.tr("Delete")
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.messageData?.localFilePath && root.messageData?.localFilePath.length > 0
            sourceComponent: AttachedFileIndicator {
                filePath: root.messageData?.localFilePath
                canRemove: false
            }
        }

        ColumnLayout { // Message content
            id: messageContentColumnLayout
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                implicitWidth: loadingIndicatorLoader.implicitWidth
                visible: implicitHeight > 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                FadeLoader {
                    id: loadingIndicatorLoader
                    anchors.centerIn: parent
                    shown: (root.messageBlocks.length < 1) && (!root.messageData.done)
                    sourceComponent: MaterialLoadingIndicator {
                        loading: true
                    }
                }
            }
            Repeater {
                model: ScriptModel {
                    values: root.messageBlocks
                }
                delegate: DelegateChooser {
                    id: messageDelegate
                    role: "type"

                    DelegateChoice { roleValue: "code"; MessageCodeBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        segmentLang: modelData.lang
                        messageData: root.messageData
                    } }
                    DelegateChoice { roleValue: "think"; MessageThinkBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        completed: modelData.completed ?? false
                    } }
                    DelegateChoice { roleValue: "text"; MessageTextBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                    } }
                }
            }
        }

        Flow { // Annotations
            visible: root.messageData?.annotationSources?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources || []
                }
                delegate: AnnotationSourceButton {
                    id: annotBtn
                    required property var modelData
                    required property int index
                    displayText: modelData.text
                    url: modelData.url

                    opacity: 0.0
                    transform: Translate {
                        id: annotTrans
                        x: -10
                    }

                    Component.onCompleted: {
                        annotAnim.start();
                    }

                    SequentialAnimation {
                        id: annotAnim
                        PauseAnimation { duration: index * 35 }
                        ParallelAnimation {
                            NumberAnimation { target: annotBtn; property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                            NumberAnimation { target: annotTrans; property: "x"; from: -10; to: 0; duration: 250; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }

        Flow { // Search queries
            visible: root.messageData?.searchQueries?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.searchQueries || []
                }
                delegate: SearchQueryButton {
                    id: searchBtn
                    required property var modelData
                    required property int index
                    query: modelData

                    opacity: 0.0
                    transform: Translate {
                        id: searchTrans
                        x: -10
                    }

                    Component.onCompleted: {
                        searchAnim.start();
                    }

                    SequentialAnimation {
                        id: searchAnim
                        PauseAnimation { duration: index * 35 }
                        ParallelAnimation {
                            NumberAnimation { target: searchBtn; property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                            NumberAnimation { target: searchTrans; property: "x"; from: -10; to: 0; duration: 250; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }

    }
}

