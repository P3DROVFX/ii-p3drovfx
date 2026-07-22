import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4
    property var inputField: messageInputField
    property string commandPrefix: "/"

    property var suggestionQuery: ""
    property var suggestionList: []

    property bool containsDrag: false
    property string previewPath: ""

    property int entranceTrigger: -1

    function triggerContentEntrance() {
        root.entranceTrigger++;
    }

    onFocusChanged: focus => {
        if (focus) {
            root.inputField.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        messageInputField.forceActiveFocus();
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            Ai.clearMessages();
        }
    }

    property var allCommands: [
        {
            name: "attach",
            description: Translation.tr("Attach a file. Only works with Gemini."),
            execute: args => {
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: args => {
                Persistent.states.ai.model = args[0];
            }
        },
        {
            name: "provider",
            description: Translation.tr("Choose provider"),
            execute: args => {
                Persistent.states.ai.provider = args[0];
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: args => {
                if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs);
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs);
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear chat history"),
            execute: () => {

                Ai.clearMessages();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                } else {
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`, Ai.interfaceRole);
            }
        },
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            // Handle special commands
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
        } else {
            Ai.sendUserMessage(inputText);
        }

        // Always scroll to bottom when user sends a message
        messageListView.positionViewAtEnd();
    }

    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1]);
            decodeImageAndAttachProc.exec(["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content");
            }
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string statusText
        property string description
        property int animIndex: 0
        property var rootRef: null
        hoverEnabled: true
        implicitHeight: statusItemRowLayout.implicitHeight
        implicitWidth: statusItemRowLayout.implicitWidth

        opacity: 0.0
        transform: [
            Translate {
                id: statusItemTransform
                x: 0
                y: 0
            },
            Rotation {
                id: statusItemRotation
                origin.x: statusItem.width / 2
                origin.y: statusItem.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: 0
            }
        ]

        Connections {
            target: statusItem.rootRef
            function onEntranceTriggerChanged() {
                if (statusItem.rootRef && statusItem.rootRef.entranceTrigger >= 0) {
                    statusItem.opacity = 0.0;
                    statusItem.scale = statusItem.animIndex === 2 ? 0.2 : 1.0;
                    statusItemTransform.x = statusItem.animIndex === 1 ? -20 : 0;
                    statusItemTransform.y = statusItem.animIndex === 0 ? 15 : 0;
                    statusItemRotation.angle = statusItem.animIndex === 0 ? 90 : 0;
                    Qt.callLater(function() {
                        statusItemAnim.start();
                    });
                }
            }
        }

        SequentialAnimation {
            id: statusItemAnim
            PauseAnimation { duration: 140 + statusItem.animIndex * 80 }
            ParallelAnimation {
                NumberAnimation { target: statusItem; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                NumberAnimation { target: statusItem; property: "scale"; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                NumberAnimation { target: statusItemTransform; property: "x"; to: 0; duration: 350; easing.type: Easing.OutBack }
                NumberAnimation { target: statusItemTransform; property: "y"; to: 0; duration: 350; easing.type: Easing.OutCubic }
                NumberAnimation { target: statusItemRotation; property: "angle"; to: 0; duration: 350; easing.type: Easing.OutBack }
            }
        }

        RowLayout {
            id: statusItemRowLayout
            spacing: 0
            MaterialSymbol {
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                text: statusItem.statusText
                color: Appearance.colors.colSubtext
                animateChange: true
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    component StatusSeparator: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item {
            id: messagesArea
            // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swipeView.width
                    height: swipeView.height
                    radius: Appearance.rounding.small
                }
            }

            // Animation properties
            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: messagesAreaTransform
                y: 25
            }

            Connections {
                target: root
                function onEntranceTriggerChanged() {
                    if (root.entranceTrigger >= 0) {
                        messagesArea.opacity = 0.0;
                        messagesArea.scale = 0.85;
                        messagesAreaTransform.y = 25;
                        Qt.callLater(function() {
                            messagesAreaAnim.start();
                        });
                    }
                }
            }

            SequentialAnimation {
                id: messagesAreaAnim
                PauseAnimation { duration: 100 }
                ParallelAnimation {
                    NumberAnimation { target: messagesArea; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                    NumberAnimation { target: messagesArea; property: "scale"; from: 0.85; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: messagesAreaTransform; property: "y"; from: 25; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            StyledRectangularShadow {
                z: 1
                target: statusBg
                opacity: messageListView.atYBeginning ? 0 : 1
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: statusBg
                z: 2
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 4
                }
                implicitWidth: statusRowLayout.implicitWidth + 10 * 2
                implicitHeight: Math.max(statusRowLayout.implicitHeight, 38)
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                RowLayout {
                    id: statusRowLayout
                    anchors.centerIn: parent
                    spacing: 10

                    StatusItem {
                        rootRef: root
                        animIndex: 0
                        icon: Ai.currentModelHasApiKey ? "key" : "key_off"
                        statusText: ""
                        description: Ai.currentModelHasApiKey ? Translation.tr("API key is set\nChange with /key YOUR_API_KEY") : Translation.tr("No API key\nSet it with /key YOUR_API_KEY")
                    }
                    StatusSeparator {}
                    StatusItem {
                        rootRef: root
                        animIndex: 1
                        icon: "device_thermostat"
                        statusText: Ai.temperature.toFixed(1)
                        description: Translation.tr("Temperature\nChange with /temp VALUE")
                    }
                    StatusSeparator {
                        visible: Ai.tokenCount.total > 0
                    }
                    StatusItem {
                        rootRef: root
                        animIndex: 2
                        visible: Ai.tokenCount.total > 0
                        icon: "token"
                        statusText: Ai.tokenCount.total
                        description: Translation.tr("Total token count\nInput: %1\nOutput: %2").arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
                    }
                }
            }

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView { // Message list
                id: messageListView
                z: 0
                anchors.fill: parent
                spacing: 10
                popin: false
                animateAppearance: false
                topMargin: statusBg.implicitHeight + statusBg.anchors.topMargin * 2

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                property int lastResponseLength: 0
                onContentHeightChanged: {
                    if (atYEnd) {
                        Qt.callLater(function() {
                            messageListView.positionViewAtEnd();
                        });
                    }
                }
                onCountChanged: {
                    Qt.callLater(function() {
                        messageListView.positionViewAtEnd();
                    });
                }

                add: null // Prevent function calls from being janky

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        return message?.visibleToUser ?? true;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    required property int index
                    messageIndex: index
                    messageData: {
                        Ai.messageByID[modelData];
                    }
                    messageInputField: root.inputField
                    entranceTrigger: root.entranceTrigger
                }
            }

            PagePlaceholder {
                id: emptyStatePlaceholder
                z: 2
                shown: Ai.messageIDs.length === 0
                icon: "neurology"
                title: Translation.tr("Large language models")
                description: Translation.tr("Type /key to get started with online models\nCtrl+O to expand sidebar\nCtrl+P to pin sidebar\nCtrl+D to detach sidebar")
                shape: MaterialShape.Shape.PixelCircle
                animateIconOnShow: true
                entranceTrigger: root.entranceTrigger
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }
        }

        DescriptionBox {
            id: descriptionBox
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: descriptionBoxTransform
                y: 25
            }

            Connections {
                target: root
                function onEntranceTriggerChanged() {
                    if (root.entranceTrigger >= 0) {
                        descriptionBox.opacity = 0.0;
                        descriptionBox.scale = 0.85;
                        descriptionBoxTransform.y = 25;
                        Qt.callLater(function() {
                            descriptionBoxAnim.start();
                        });
                    }
                }
            }

            SequentialAnimation {
                id: descriptionBoxAnim
                PauseAnimation { duration: 160 }
                ParallelAnimation {
                    NumberAnimation { target: descriptionBox; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                    NumberAnimation { target: descriptionBox; property: "scale"; from: 0.85; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: descriptionBoxTransform; property: "y"; from: 25; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }

        Loader {
            id: modelAndProviderLoader
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter

            active: Config.options.sidebar.ai.showProviderAndModelButtons && Ai.messageIDs.length === 0
            visible: active

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: modelProviderTransform
                y: 25
            }

            Connections {
                target: root
                function onEntranceTriggerChanged() {
                    if (root.entranceTrigger >= 0 && modelAndProviderLoader.active) {
                        modelAndProviderLoader.opacity = 0.0;
                        modelAndProviderLoader.scale = 0.85;
                        modelProviderTransform.y = 25;
                        Qt.callLater(function() {
                            modelProviderAnim.start();
                        });
                    }
                }
            }

            SequentialAnimation {
                id: modelProviderAnim
                PauseAnimation { duration: 220 }
                ParallelAnimation {
                    NumberAnimation { target: modelAndProviderLoader; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                    NumberAnimation { target: modelAndProviderLoader; property: "scale"; from: 0.85; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: modelProviderTransform; property: "y"; from: 25; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            sourceComponent: ColumnLayout {
                id: contentLayout
                width: modelAndProviderLoader.width

                Connections {
                    target: root
                    function onEntranceTriggerChanged() {
                        if (root.entranceTrigger >= 0 && modelAndProviderLoader.active) {
                            providerButton1.opacity = 0.0;
                            providerButton1Transform.x = -35;
                            providerButton1Transform.y = 0;
                            
                            providerButton2.opacity = 0.0;
                            providerButton2Transform.x = 0;
                            providerButton2Transform.y = 25;
                            
                            providerButton3.opacity = 0.0;
                            providerButton3Transform.x = 35;
                            providerButton3Transform.y = 0;
                            
                            modelSelector.opacity = 0.0;
                            modelSelectorScale.xScale = 0.8;
                            modelSelectorTransform.y = 0;
                            
                            Qt.callLater(function() {
                                providerButton1Anim.start();
                                providerButton2Anim.start();
                                providerButton3Anim.start();
                                modelSelectorAnim.start();
                            });
                        }
                    }
                }

                RowLayout {
                    id: providerSelector
                    Layout.fillWidth: true
                    spacing: 2

                    property string currentValue: Persistent.states.ai.provider

                    SelectionGroupButton {
                        id: providerButton1
                        Layout.fillWidth: true
                        leftmost: true
                        rightmost: false
                        buttonSymbol: "spark-symbolic"
                        buttonText: "Google"
                        toggled: providerSelector.currentValue === "google"
                        onClicked: {
                            Persistent.states.ai.provider = "google";
                            Persistent.states.ai.model = Ai.modelsOfProviders["google"][0].value;
                        }
                        
                        opacity: 0.0
                        transform: Translate {
                            id: providerButton1Transform
                            x: -35
                            y: 0
                        }
                        
                        SequentialAnimation {
                            id: providerButton1Anim
                            PauseAnimation { duration: 220 + 0 * 60 }
                            ParallelAnimation {
                                NumberAnimation { target: providerButton1; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                                NumberAnimation { target: providerButton1Transform; property: "x"; from: -35; to: 0; duration: 380; easing.type: Easing.OutBack }
                            }
                        }
                    }
                    SelectionGroupButton {
                        id: providerButton2
                        Layout.fillWidth: true
                        leftmost: false
                        rightmost: false
                        buttonSymbol: "openrouter-symbolic"
                        buttonText: "OpenRouter"
                        toggled: providerSelector.currentValue === "openrouter"
                        onClicked: {
                            Persistent.states.ai.provider = "openrouter";
                            Persistent.states.ai.model = Ai.modelsOfProviders["openrouter"][0].value;
                        }
                        
                        opacity: 0.0
                        transform: Translate {
                            id: providerButton2Transform
                            x: 0
                            y: 25
                        }
                        
                        SequentialAnimation {
                            id: providerButton2Anim
                            PauseAnimation { duration: 220 + 1 * 60 }
                            ParallelAnimation {
                                NumberAnimation { target: providerButton2; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                                NumberAnimation { target: providerButton2Transform; property: "y"; from: 25; to: 0; duration: 380; easing.type: Easing.OutBack }
                            }
                        }
                    }
                    SelectionGroupButton {
                        id: providerButton3
                        Layout.fillWidth: true
                        leftmost: false
                        rightmost: true
                        buttonIcon: "more_horiz"
                        buttonText: Translation.tr("Others")
                        toggled: providerSelector.currentValue === "others"
                        onClicked: {
                            Persistent.states.ai.provider = "others";
                            Persistent.states.ai.model = Ai.modelsOfProviders["others"][0].value;
                        }
                        
                        opacity: 0.0
                        transform: Translate {
                            id: providerButton3Transform
                            x: 35
                            y: 0
                        }
                        
                        SequentialAnimation {
                            id: providerButton3Anim
                            PauseAnimation { duration: 220 + 2 * 60 }
                            ParallelAnimation {
                                NumberAnimation { target: providerButton3; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                                NumberAnimation { target: providerButton3Transform; property: "x"; from: 35; to: 0; duration: 380; easing.type: Easing.OutBack }
                            }
                        }
                    }
                }

                StyledComboBox {
                    id: modelSelector
                    Layout.fillWidth: true

                    buttonIcon: "wand_stars"
                    textRole: "title"
                    model: Ai.modelsOfProviders[providerSelector.currentValue]
                    enabled: true
                    currentIndex: {
                        const models = Ai.modelsOfProviders[providerSelector.currentValue];
                        for (var i = 0; i < models.length; i++) {
                            if (models[i].value === Persistent.states.ai.model) {
                                return i;
                            }
                        }
                        return 0;
                    }

                    function updateModel(index = 0) {
                        Persistent.states.ai.model = Ai.modelsOfProviders[providerSelector.currentValue][index].value
                    }

                    onActivated: index => updateModel(index)
                    
                    opacity: 0.0
                    transform: [
                        Translate {
                            id: modelSelectorTransform
                            y: 0
                        },
                        Scale {
                            id: modelSelectorScale
                            origin.x: modelSelector.width / 2
                            origin.y: modelSelector.height / 2
                            xScale: 0.8
                            yScale: 1.0
                        }
                    ]
                    
                    SequentialAnimation {
                        id: modelSelectorAnim
                        PauseAnimation { duration: 220 + 3 * 60 }
                        ParallelAnimation {
                            NumberAnimation { target: modelSelector; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: modelSelectorScale; property: "xScale"; from: 0.8; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        }
                    }
                }
            }
        }
        
        

        FlowButtonGroup { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            opacity: visible ? 1.0 : 0.0
            scale: visible ? 1.0 : 0.85
            transform: Translate {
                id: suggestionsTransform
                y: visible ? 0 : 25
            }

            Connections {
                target: root
                function onEntranceTriggerChanged() {
                    if (root.entranceTrigger >= 0 && suggestions.visible) {
                        suggestions.opacity = 0.0;
                        suggestions.scale = 0.85;
                        suggestionsTransform.y = 25;
                        Qt.callLater(function() {
                            suggestionsAnim.start();
                        });
                    }
                }
            }

            SequentialAnimation {
                id: suggestionsAnim
                PauseAnimation { duration: 280 }
                ParallelAnimation {
                    NumberAnimation { target: suggestions; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                    NumberAnimation { target: suggestions; property: "scale"; from: 0.85; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: suggestionsTransform; property: "y"; from: 25; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList.slice(0, 10);
                }
                delegate: ApiCommandButton {
                    id: commandButton
                    required property int index
                    required property var modelData
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    
                    opacity: 0.0
                    transform: Translate {
                        id: cmdBtnTranslate
                        y: 10
                    }

                    Component.onCompleted: {
                        btnEntranceAnim.start();
                    }

                    SequentialAnimation {
                        id: btnEntranceAnim
                        PauseAnimation { duration: index * 40 }
                        ParallelAnimation {
                            NumberAnimation { target: commandButton; property: "opacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
                            NumberAnimation { target: cmdBtnTranslate; property: "y"; from: 10; to: 0; duration: 280; easing.type: Easing.OutBack }
                        }
                    }

                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.displayName ?? modelData.name
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData.name);
                    }
                }
            }

            function acceptSuggestion(word) {
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    const word = root.suggestionList[suggestions.selectedIndex].name;
                    suggestions.acceptSuggestion(word);
                }
            }
        }

        AttachedFileIndicator {
            visible: implicitHeight > 0
            implicitHeight: root.containsDrag ? contentHeight : 0
            opacity: root.containsDrag ? 1 : 0
            highlight: false

            Layout.fillWidth: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            filePath: root.previewPath
            
        }

        

        Rectangle { // Input area
            id: inputWrapper
            property real spacing: 5
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 45) + (attachedFileIndicator.implicitHeight + spacing + attachedFileIndicator.anchors.topMargin)
            clip: true

            FastBlur {
                id: inputBlur
                radius: 0
            }

            layer.enabled: inputBlur.radius > 0
            layer.effect: Component {
                FastBlur {
                    radius: inputBlur.radius
                }
            }

            opacity: 0.0
            transform: Translate {
                id: inputWrapperTransform
                y: 40
            }

            Connections {
                target: root
                function onEntranceTriggerChanged() {
                    if (root.entranceTrigger >= 0) {
                        inputWrapper.opacity = 0.0;
                        inputBlur.radius = 20;
                        inputWrapperTransform.y = 40;
                        Qt.callLater(function() {
                            inputWrapperAnim.start();
                        });
                    }
                }
            }

            SequentialAnimation {
                id: inputWrapperAnim
                PauseAnimation { duration: 320 }
                ParallelAnimation {
                    NumberAnimation { target: inputWrapper; property: "opacity"; from: 0.0; to: 1.0; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { target: inputBlur; property: "radius"; from: 20; to: 0; duration: 350; easing.type: Easing.OutCubic }
                    NumberAnimation { target: inputWrapperTransform; property: "y"; from: 40; to: 0; duration: 450; easing.type: Easing.OutExpo }
                }
            }

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            AttachedFileIndicator {
                id: attachedFileIndicator
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: visible ? 5 : 0
                }
                filePath: Ai.pendingFilePath
                onRemove: Ai.attachFile("")
            }

            DropArea {
                id: dropArea
                anchors.fill: parent

                readonly property string currentProvider: Persistent.states.ai.provider

                onContainsDragChanged: {
                    if (currentProvider !== "google") return
                    root.containsDrag = dropArea.containsDrag
                }

                onPreviewPathChanged: {
                    if (currentProvider !== "google") return
                    root.previewPath = dropArea.previewPath
                }

                property string previewPath: ""
    
                onEntered: (drag) => {
                    if (currentProvider !== "google") return
                    if (drag.hasUrls && drag.urls.length > 0) {
                        previewPath = drag.urls[0]
                    }
                }
                
                onExited: {
                    previewPath = ""
                }
                
                onDropped: (drop) => {
                    if (drop.hasUrls) {
                        for (var i = 0; i < drop.urls.length; i++) {
                            console.log("[AI Chat] Dropped file:", drop.urls[i])
                            Ai.attachFile(drop.urls[i])
                        }
                        drop.accept(Qt.CopyAction)
                    }
                }
            } 

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors {
                    bottom: commandButtonsRow.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: 5
                }
                spacing: 0

                ScrollView {
                    id: inputScrollView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.height * 3/5, messageInputField.height)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea { // The actual TextArea (inside ScrollView to enable scrolling)
                        id: messageInputField
                        anchors.fill: parent
                        wrapMode: TextArea.Wrap
                        padding: 10
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                        background: null

                        onTextChanged: {
                            // Handle suggestions
                            if (messageInputField.text.length === 0) {
                                root.suggestionQuery = "";
                                root.suggestionList = [];
                                return;
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}provider`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                
                                const providers = Object.keys(Ai.models)
                                
                                const providerResults = Fuzzy.go(root.suggestionQuery, providers.map(p => ({
                                    name: Fuzzy.prepare(p),
                                    obj: p
                                })), {
                                    all: true,
                                    key: "name"
                                });
                                
                                root.suggestionList = providerResults.map(result => {
                                    const providerName = result.target;
                                    const providerInfo = Ai.models[providerName];
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "provider ") : ""}${providerName}`,
                                        displayName: providerInfo.name.split(" -")[0], // Remove " - model name"
                                        description: providerInfo.description
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                            
                                const providerModels = Ai.modelsOfProviders[Persistent.states.ai.provider] || [];
                            
                                const modelList = providerModels.map(model => ({
                                    name: Fuzzy.prepare(model.value),
                                    obj: model
                                }));

                                const modelResults = Fuzzy.go(root.suggestionQuery, modelList, {
                                    all: true,
                                    key: "name"
                                });
                            
                                root.suggestionList = modelResults.map(result => {
                                    const modelValue = result.target;
                                    const model = providerModels.find(m => m.value === modelValue);
                                    
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.value}`,
                                        displayName: model.title,
                                        description: model.modelProvider ? `Provider: ${model.modelProvider}` : `${Ai.currentProvider} model`
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                        displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                        description: Translation.tr("Load prompt from %1").arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr("Save chat to %1").arg(chatName)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr(`Load chat from %1`).arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                    return {
                                        name: Fuzzy.prepare(tool),
                                        obj: tool
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = toolResults.map(tool => {
                                    const toolName = tool.target;
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                        displayName: toolName,
                                        description: Ai.toolDescriptions[toolName]
                                    };
                                });
                            } else if (messageInputField.text.startsWith(root.commandPrefix)) {
                                root.suggestionQuery = messageInputField.text;
                                root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                    return {
                                        name: `${root.commandPrefix}${cmd.name}`,
                                        description: `${cmd.description}`
                                    };
                                });
                            }
                        }

                        function accept() {
                            root.handleInput(text);
                            text = "";
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab) {
                                suggestions.acceptSelectedWord();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Insert newline
                                    messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    event.accepted = true;
                                } else {
                                    // Accept text
                                    const inputText = messageInputField.text;
                                    messageInputField.clear();
                                    root.handleInput(inputText);
                                    event.accepted = true;
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                // Intercept Ctrl+V to handle image/file pasting
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Let Shift+Ctrl+V = plain paste
                                    messageInputField.text += Quickshell.clipboardText;
                                    event.accepted = true;
                                    return;
                                }
                                // Try image paste first
                                const currentClipboardEntry = Cliphist.entries[0];
                                const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                    // First entry = currently copied entry = image?
                                    decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                    event.accepted = true;
                                    return;
                                } else if (cleanCliphistEntry.startsWith("file://")) {
                                    // First entry = currently copied entry = image?
                                    const fileName = decodeURIComponent(cleanCliphistEntry);
                                    Ai.attachFile(fileName);
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false; // No image, let text pasting proceed
                            } else if (event.key === Qt.Key_Escape) {
                                // Esc to detach file
                                if (Ai.pendingFilePath.length > 0) {
                                    Ai.attachFile("");
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }
                        }
                    }
                }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab) {
                                suggestions.acceptSelectedWord();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Insert newline
                                    messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    event.accepted = true;
                                } else {
                                    // Accept text
                                    const inputText = messageInputField.text;
                                    messageInputField.clear();
                                    root.handleInput(inputText);
                                    event.accepted = true;
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                // Intercept Ctrl+V to handle image/file pasting
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Let Shift+Ctrl+V = plain paste
                                    messageInputField.text += Quickshell.clipboardText;
                                    event.accepted = true;
                                    return;
                                }
                                // Try image paste first
                                const currentClipboardEntry = Cliphist.entries[0];
                                const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                    // First entry = currently copied entry = image?
                                    decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                    event.accepted = true;
                                    return;
                                } else if (cleanCliphistEntry.startsWith("file://")) {
                                    // First entry = currently copied entry = image?
                                    const fileName = decodeURIComponent(cleanCliphistEntry);
                                    Ai.attachFile(fileName);
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false; // No image, let text pasting proceed
                            } else if (event.key === Qt.Key_Escape) {
                                // Esc to detach file
                                if (Ai.pendingFilePath.length > 0) {
                                    Ai.attachFile("");
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }
                        }
                    
                
                RippleButton { // Send button
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: messageInputField.text.length > 0
                    toggled: enabled

                    Behavior on enabled {
                        SequentialAnimation {
                            PauseAnimation { duration: 50 }
                            NumberAnimation {
                                target: sendButton
                                property: "opacity"
                                to: sendButton.enabled ? 1.0 : 0.5
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const inputText = messageInputField.text;
                            root.handleInput(inputText);
                            messageInputField.clear();
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: "arrow_upward"
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 10
                anchors.rightMargin: 5
                spacing: 4

                property var commandsShown: [
                    {
                        name: "",
                        sendDirectly: false,
                        dontAddSpace: true
                    },
                    {
                        name: "clear",
                        sendDirectly: true
                    },
                ]

                ApiInputBoxIndicator {
                    // Model indicator
                    property string currentProvider: Persistent.states.ai.provider
                    property string providerIcon: currentProvider === "openrouter" ? "openrouter-symbolic" : currentProvider === "google" ? "spark-symbolic" : "mistral-symbolic"

                    symbol: providerIcon
                    text: Persistent.states.ai.model // TODO: add a readable version
                    tooltipText: Translation.tr("Current model: %1\nSet it with %2model MODEL").arg(Ai.getModel().name).arg(root.commandPrefix)
                }

                ApiInputBoxIndicator {
                    // Tool indicator
                    icon: "service_toolbox"
                    text: Ai.currentTool.charAt(0).toUpperCase() + Ai.currentTool.slice(1)
                    tooltipText: Translation.tr("Current tool: %1\nSet it with %2tool TOOL").arg(Ai.currentTool).arg(root.commandPrefix)
                }

                Item {
                    Layout.fillWidth: true
                }

                ButtonGroup {
                    // Command buttons
                    padding: 0

                    Repeater {
                        // Command buttons
                        model: commandButtonsRow.commandsShown
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            downAction: () => {
                                if (modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation);
                                } else {
                                    messageInputField.text = commandRepresentation + (modelData.dontAddSpace ? "" : " ");
                                    messageInputField.cursorPosition = messageInputField.text.length;
                                    messageInputField.forceActiveFocus();
                                }
                                if (modelData.name === "clear") {
                                    messageInputField.text = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}