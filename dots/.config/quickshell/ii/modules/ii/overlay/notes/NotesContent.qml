import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

OverlayBackground {
    id: root

    property alias content: textInput.text
    property bool pendingReload: false
    property var copyListEntries: []
    property string lastParsedCopylistText: ""
    property var parsedCopylistLines: []
    property bool isClickthrough: false
    property real maxCopyButtonSize: 20
    property int currentTabIndex: Persistent.states.overlay.notes.tabIndex
    property bool tabEditModeEnabled: false
    // See Config.qml for the rationale on these guards.
    property real initTimestamp: Date.now()
    property int missingFileGracePeriod: 2000
    property int missingFileRetryInterval: 1500

    Component.onCompleted: {
        noteFile.reload();
        updateCopyListEntries();
    }

    property var tabsData: ({
        tabs: root.defaultTabs
    })

    property list<var> defaultTabs: [
        { title: "Tab 1", icon: "article", content: "" },
        { title: "Tab 2", icon: "article", content: "" },
        { title: "Tab 3", icon: "article", content: "" }
    ]

    property var tabOptions: root.tabsData.tabs.map((tab, index) => ({
        displayName: tab.title,
        icon: tab.icon,
        value: index
    }))

    function saveToFile() {
        if (!textInput)
            return;
        
        if (currentTabIndex >= 0 && currentTabIndex < tabsData.tabs.length) {
            tabsData.tabs[currentTabIndex].content = root.content;
        }
        
        const jsonString = JSON.stringify(tabsData, null, 2);
        noteFile.setText(jsonString);
    }

    function loadTabContent(tabIndex) {
        if (tabIndex >= 0 && tabIndex < tabsData.tabs.length) {
            root.content = tabsData.tabs[tabIndex].content || "";
            updateCopyListEntries();
        }
    }

    function changeCurrentTab(index) {
        Persistent.states.overlay.notes.tabIndex = index;
    }

    function addNewTab() {
        const newTabIndex = root.tabsData.tabs.length;
        const newTab = {
            title: "Tab " + (newTabIndex + 1),
            icon: "article",
            content: ""
        };
        
        let newTabs = root.tabsData.tabs.slice();
        newTabs.push(newTab);
        
        root.tabsData = {
            tabs: newTabs
        };
        
        saveToFile();
        
        root.changeCurrentTab(newTabIndex);
        Qt.callLater(() => {
            loadTabContent(newTabIndex);
            focusAtEnd();
        });
    }

    function deleteCurrentTab() {
        if (root.tabsData.tabs.length <= 1) { // not deleting the last tab
            return;
        }
        
        const deletedIndex = currentTabIndex;
        let newTabs = root.tabsData.tabs.slice();
        newTabs.splice(deletedIndex, 1);
        
        const newIndex = Math.min(deletedIndex, newTabs.length - 1);
        
        root.tabsData = { tabs: newTabs };
        Persistent.states.overlay.notes.tabIndex = newIndex;
        root.content = newTabs[newIndex].content || "";
        
        saveToFile();
        
        Qt.callLater(() => {
            updateCopyListEntries();
        });
    }


    function focusAtEnd() {
        if (!textInput)
            return;
        textInput.forceActiveFocus();
        const endPos = root.content.length;
        applySelection(endPos, endPos);
    }

    function applySelection(cursorPos, anchorPos) {
        if (!textInput)
            return;
        const textLength = root.content.length;
        const cursor = Math.max(0, Math.min(cursorPos, textLength));
        const anchor = Math.max(0, Math.min(anchorPos, textLength));
        textInput.select(anchor, cursor);
        if (cursor === anchor)
            textInput.deselect();
    }

    function scheduleCopylistUpdate(immediate = false) {
        if (!textInput)
            return;
        if (immediate) {
            copyListDebounce?.stop();
            updateCopyListEntries();
        } else {
            copyListDebounce.restart();
        }
    }

    function updateCopyListEntries() {
        if (!textInput)
            return;
        const textValue = root.content;
        if (!textValue || textValue.length === 0) {
            lastParsedCopylistText = "";
            parsedCopylistLines = [];
            root.copyListEntries = [];
            return;
        }

        if (textValue !== lastParsedCopylistText) {
            const lineRegex = /(.*?)(\r?\n|$)/g;
            let match = null;
            const parsed = [];
            while ((match = lineRegex.exec(textValue)) !== null) {
                const lineText = match[1];
                const newlineText = match[2];
                const lineStart = match.index;
                const lineEnd = lineStart + lineText.length;
                const bulletMatch = lineText.match(/^\s*-\s+(.*\S)\s*$/);
                if (bulletMatch) {
                    parsed.push({
                        content: bulletMatch[1].trim(),
                        start: lineStart,
                        end: lineEnd
                    });
                }
                if (newlineText === "")
                    break;
            }
            lastParsedCopylistText = textValue;
            parsedCopylistLines = parsed;
            if (parsed.length === 0) {
                root.copyListEntries = [];
                return;
            }
        }

        updateCopylistPositions();
    }

    function updateCopylistPositions() {
        if (!textInput || parsedCopylistLines.length === 0)
            return;
        const rawSelectionStart = textInput.selectionStart;
        const rawSelectionEnd = textInput.selectionEnd;
        const selectionStart = rawSelectionStart === -1 ? textInput.cursorPosition : rawSelectionStart;
        const selectionEnd = rawSelectionEnd === -1 ? textInput.cursorPosition : rawSelectionEnd;
        const rangeStart = Math.min(selectionStart, selectionEnd);
        const rangeEnd = Math.max(selectionStart, selectionEnd);

        const entries = parsedCopylistLines.map(line => {
            // Don't show copy button if line is (partially) selected
            const caretIntersects = rangeEnd > line.start && rangeStart <= line.end;
            if (caretIntersects)
                return null;
            const startRect = textInput.positionToRectangle(line.start);
            let endRect = textInput.positionToRectangle(line.end);
            if (!isFinite(startRect.y))
                return null;
            if (!isFinite(endRect.y))
                endRect = startRect;
            const lineBottom = endRect.y + endRect.height;
            const rectHeight = Math.max(lineBottom - startRect.y, textInput.font.pixelSize + 8);
            return {
                content: line.content,
                y: startRect.y,
                height: rectHeight
            };
        }).filter(entry => entry !== null);

        root.copyListEntries = entries;
    }

    implicitWidth: 300
    implicitHeight: 200

    ColumnLayout {
        id: contentItem
        property int margin: Config.options.overlay.notes.showTabs ? 26 : 14
        anchors {
            fill: parent
            leftMargin: margin
            rightMargin: margin
            topMargin: margin 
        }
        spacing: 14

        

        Loader {
            Layout.fillWidth: true
            active: Config.options.overlay.notes.showTabs
            sourceComponent: RowLayout {
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: root.currentTabIndex
                    Layout.fillWidth: true
                    
                    onSelected: newValue => {
                        if (root.tabEditModeEnabled) return;

                        saveToFile();
                        root.content = "";
                        root.changeCurrentTab(newValue);

                        Qt.callLater(() => loadTabContent(newValue));
                    }

                    options: root.tabOptions
                }

                MaterialSymbol {
                    text: "info"
                    iconSize: Appearance.font.pixelSize.large
                    
                    color: Appearance.colors.colSubtext
                    MouseArea {
                        id: infoMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.WhatsThisCursor
                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: infoMouseArea.containsMouse
                            text: Translation.tr("You can delete a tab with SHIFT+DELETE")
                        }
                    }
                }

                ConfigSelectionArray {
                    currentValue: root.tabEditModeEnabled ? 0 : -1
                    Layout.fillWidth: false
                    options: [
                        {
                            displayName: "",
                            icon: "edit",
                            value: 0,
                            releaseAction: (() => root.tabEditModeEnabled = !root.tabEditModeEnabled)
                        },
                        {
                            displayName: "",
                            icon: "add",
                            value: 1,
                            releaseAction: (() => root.addNewTab())
                        }
                    ]
                }
            }
        }
        
        Loader {
            Layout.fillWidth: true
            active: Config.options.overlay.notes.showTabs
            sourceComponent: RowLayout {
                Layout.fillWidth: true
                Item {
                    Layout.fillWidth: true
                }

                Loader {
                    active: root.tabEditModeEnabled || (item && item.height > 0)
                    sourceComponent: TitleEditComp {
                        Layout.fillWidth: false
                    }
                    onLoaded: item.height = 50
                }
            }
        }
        
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Delete && event.modifiers & Qt.ShiftModifier) {
                root.deleteCurrentTab();
            }
        }

        ScrollView {
            id: editorScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: -12
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            onWidthChanged: root.scheduleCopylistUpdate(true)

            

            StyledTextArea { // This has to be a direct child of ScrollView for proper scrolling
                id: textInput
                anchors.fill: parent
                wrapMode: TextEdit.Wrap
                implicitWidth: parent.implicitWidth - padding * 2 - 6
                placeholderText: Translation.tr("Write something here...\nUse '-' to create copyable bullet points, like this:\n\nSheep fricker\n- 4x Slab\n- 1x Boat\n- 4x Redstone Dust\n- 1x Sticky Piston\n- 1x End Rod\n- 4x Redstone Repeater\n- 1x Redstone Torch\n- 1x Sheep")
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.PlainText
                background: null
                padding: 12

                onTextChanged: {
                    if (textInput.activeFocus) {
                        saveDebounce.restart();
                    }
                    root.scheduleCopylistUpdate(true);
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Delete && event.modifiers & Qt.ShiftModifier) {
                        root.deleteCurrentTab();
                    }
                }
                
                onHeightChanged: root.scheduleCopylistUpdate(true)
                onContentHeightChanged: root.scheduleCopylistUpdate(true)
                onCursorPositionChanged: root.scheduleCopylistUpdate()
                onSelectionStartChanged: root.scheduleCopylistUpdate()
                onSelectionEndChanged: root.scheduleCopylistUpdate()
            }

            Item {
                anchors.fill: parent
                visible: root.copyListEntries.length > 0
                clip: true

                Repeater {
                    model: ScriptModel {
                        values: root.copyListEntries
                    }
                    delegate: RippleButton {
                        id: copyButton
                        required property var modelData
                        readonly property real lineHeight: Math.min(Math.max(modelData.height, Appearance.font.pixelSize.normal + 6), root.maxCopyButtonSize)
                        readonly property real iconSizeLocal: Appearance.font.pixelSize.normal
                        readonly property real hitPadding: 4
                        property bool justCopied: false

                        implicitHeight: lineHeight
                        implicitWidth: lineHeight
                        buttonRadius: height / 2
                        y: modelData.y
                        anchors.right: parent.right
                        anchors.rightMargin: -hitPadding
                        z: 5

                        Timer {
                            id: resetState
                            interval: 700
                            onTriggered: {
                                copyButton.justCopied = false;
                            }
                        }

                        onClicked: {
                            Quickshell.clipboardText = copyButton.modelData.content;
                            justCopied = true;
                            resetState.start();
                        }

                        contentItem: Item {
                            anchors.centerIn: parent
                            MaterialSymbol {
                                id: iconItem
                                anchors.centerIn: parent
                                text: copyButton.justCopied ? "check" : "content_copy"
                                iconSize: copyButton.iconSizeLocal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            id: statusLabel
            Layout.fillWidth: true
            Layout.margins: 16
            horizontalAlignment: Text.AlignRight
            text: saveDebounce.running ? Translation.tr("Saving...") : Translation.tr("Saved    ")
            color: Appearance.colors.colSubtext
        }
    }

    Timer {
        id: saveDebounce
        interval: 500
        repeat: false
        onTriggered: saveToFile()
    }

    Timer {
        id: copyListDebounce
        interval: 100
        repeat: false
        onTriggered: updateCopylistPositions()
    }

    FileView {
        id: noteFile
        path: Qt.resolvedUrl(Directories.notesPath)
        atomicWrites: true
        onLoaded: {
            try {
                const jsonText = noteFile.text();
                const parsed = JSON.parse(jsonText);
                
                if (parsed && parsed.tabs && Array.isArray(parsed.tabs)) {
                    root.tabsData = parsed;
                } else {
                    root.tabsData = {
                        tabs: root.defaultTabs
                    };
                }
            } catch (e) {
                console.log("[Overlay Notes] JSON parse error: " + e);
                root.tabsData = {
                    tabs: root.defaultTabs
                };
            }
            
            loadTabContent(root.currentTabIndex);
            
            if (pendingReload) {
                pendingReload = false;
                Qt.callLater(root.focusAtEnd);
            }
            Qt.callLater(root.updateCopyListEntries);
        }
        onLoadFailed: error => {
            if (error != FileViewError.FileNotFound) {
                console.log("[Overlay Notes] Error loading file: " + error);
                return;
            }
            // Lazy-create the notes file: defer past the startup grace window so
            // a transient missing file (hot-reload / restart) doesn't wipe the
            // user's existing notes.json with the empty default layout.
            if (Date.now() - root.initTimestamp > root.missingFileGracePeriod) {
                root.tabsData = {
                    tabs: root.defaultTabs
                };
                root.content = "";
                saveToFile();

                if (pendingReload) {
                    pendingReload = false;
                    Qt.callLater(root.focusAtEnd);
                }
                Qt.callLater(root.updateCopyListEntries);
            } else {
                missingFileRetryTimer.restart();
            }
        }
    }

    Timer {
        id: missingFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: noteFile.reload()
    }

    component TitleEditComp: Row {
        id: row
        spacing: 4
        height: 0

        property bool editMode: root.tabEditModeEnabled
        onEditModeChanged: {
            if (!editMode) height = 0
        }

        function updateTitle(disableEditMode = false) {
            let newTabs = root.tabsData.tabs.slice();
            newTabs[currentTabIndex] = {
                title: titleInput.text.split("\n")[0],  // only getting the first line
                icon: iconInput.text.split("\n")[0],
                content: newTabs[currentTabIndex].content
            };
            
            if (disableEditMode) root.tabEditModeEnabled = false;

            root.tabsData = { tabs: newTabs };
            
            saveToFile();
        }

        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        EditInput {
            id: iconInput
            visible: Config.options.overlay.notes.allowEditingIcon
            placeholderText: Translation.tr("Icon")
            text: root.tabsData.tabs[currentTabIndex].icon
        }

        EditInput {
            id: titleInput
            placeholderText: Translation.tr("Title")
            text: root.tabsData.tabs[currentTabIndex].title
        }        

    }


    component EditInput: MaterialTextArea {
        property int textAreaPadding: 6

        implicitWidth: 150
        implicitHeight: parent.height
        placeholderTextColor: height >= 40 ? Appearance.m3colors.m3outline : "transparent"  

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                row.updateTitle(true);
            }
        }

        anchors.top: parent.top
        anchors.topMargin: -textAreaPadding
        topInset: textAreaPadding
    }
}
