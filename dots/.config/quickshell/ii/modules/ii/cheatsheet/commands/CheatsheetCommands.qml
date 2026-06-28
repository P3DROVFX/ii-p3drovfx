import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.services
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

Item {
    id: root

    readonly property color colBg: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
    readonly property color colTitle: Appearance.colors.colOnSurface
    readonly property color colSubtitle: Appearance.colors.colOnSurfaceVariant
    readonly property color colAccent: Appearance.colors.colPrimary
    readonly property color colAccentHover: Appearance.colors.colPrimaryHover
    readonly property color colOnAccent: Appearance.colors.colOnPrimary

    property string activeTag: ""
    property string searchText: ""
    property var allTags: []

    readonly property bool isCurrentTab: {
        try {
            return swipeView.currentIndex === index;
        } catch (e) {
            return true;
        }
    }
    readonly property bool isTabActive: root.visible && root.isCurrentTab

    property bool importSuccess: false
    property bool importError: false
    property string lastImportError: ""
    property var filteredIndices: {
        const model = CommandsService.commandsModel;
        if (!model || model.count === undefined)
            return [];
        
        // Force re-evaluation when model changes
        const _count = model.count;
        const _tags = CommandsService.tagCounts;
        
        const q = (root.searchText || "").toLowerCase();
        const tag = root.activeTag;
        const result = [];
        for (let i = 0; i < model.count; i++) {
            const item = model.get(i);
            if (!item || item.command === undefined)
                continue;
            
            let tagMatch = tag === "";
            if (!tagMatch && item.tags && item.tags.count !== undefined) {
                for (let t = 0; t < item.tags.count; t++) {
                    const tagObj = item.tags.get(t);
                    if (tagObj && tagObj.modelData === tag) {
                        tagMatch = true;
                        break;
                    }
                }
            }
            const textMatch = q === "" || (item.command && item.command.toLowerCase().includes(q)) || (item.description && item.description.toLowerCase().includes(q));
            if (tagMatch && textMatch)
                result.push(i);
        }
        return result;
    }

    onFocusChanged: focus => {
        if (focus)
            filterField.forceActiveFocus();
    }

    function refreshTags() {
        if (CommandsService)
            allTags = CommandsService.allTags();
    }

    Connections {
        target: CommandsService.commandsModel
        function onCountChanged() {
            if (!CommandsService.importing)
                root.refreshTags();
        }
    }

    Connections {
        target: CommandsService
        function onImportFinished(success, errorMsg) {
            root.refreshTags();
            if (success) {
                root.importSuccess = true;
                root.importError = false;
                successTimer.restart();
            } else {
                root.importSuccess = false;
                root.importError = true;
                root.lastImportError = errorMsg;
                errorTimer.restart();
            }
        }
    }

    Timer {
        id: successTimer
        interval: 2000
        onTriggered: root.importSuccess = false
    }

    Timer {
        id: errorTimer
        interval: 4000
        onTriggered: root.importError = false
    }



    Component.onCompleted: root.refreshTags()

    Rectangle {
        anchors.fill: parent
        color: root.colBg
        radius: Appearance.rounding.windowRounding
        antialiasing: true
    }

    Item {
        id: inboxContent
        anchors.fill: parent

        opacity: (commandForm.isOpen || commandForm.isAnimating || qmlFilePicker.visible) ? 0.0 : 1.0
        enabled: !commandForm.isOpen && !commandForm.isAnimating && !qmlFilePicker.visible

        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 14
                Layout.leftMargin: 20
                Layout.rightMargin: 16
                Layout.bottomMargin: 4
                spacing: 12

                ColumnLayout {
                    spacing: 1
                    StyledText {
                        text: "CHEATSHEET"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.colSubtitle
                        font.family: Appearance.font.family.main
                    }
                    StyledText {
                        text: qsTr("Commands")
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: root.colTitle
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                RippleButton {
                    implicitHeight: 44
                    implicitWidth: 44
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.importError ? Appearance.colors.colError : (root.importSuccess ? Appearance.colors.colTertiary : Appearance.colors.colSecondaryContainer)
                    colBackgroundHover: root.importError ? Appearance.colors.colErrorHover : (root.importSuccess ? Appearance.colors.colTertiaryHover : Appearance.colors.colSecondaryContainerHover)
                    onClicked: qmlFilePicker.visible = true

                    MaterialSymbol {
                        id: importIcon
                        anchors.centerIn: parent
                        text: root.importError ? "close" : (root.importSuccess ? "done" : "folder_open")
                        iconSize: Appearance.font.pixelSize.large
                        color: root.importError ? Appearance.colors.colOnError : (root.importSuccess ? Appearance.colors.colOnTertiary : Appearance.colors.colOnSecondaryContainer)

                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation {
                                    target: importIcon
                                    property: "scale"
                                    to: 0
                                    duration: 100
                                }
                                PropertyAction {}
                                NumberAnimation {
                                    target: importIcon
                                    property: "scale"
                                    to: 1
                                    duration: 100
                                }
                            }
                        }
                    }

                    StyledToolTip {
                        text: qsTr("Import commands")
                    }
                }

                RippleButton {
                    implicitHeight: 44
                    implicitWidth: addRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.colAccent
                    colBackgroundHover: root.colAccentHover
                    onClicked: {
                        commandForm.mode = "add";
                        commandForm.editId = "";
                        commandForm.editCommand = "";
                        commandForm.editDescription = "";
                        commandForm.editTags = "";
                        commandForm.isOpen = true;
                    }

                    RowLayout {
                        id: addRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "add"
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.large
                            color: root.colOnAccent
                        }
                        StyledText {
                            text: qsTr("Add command")
                            font.weight: Font.Bold
                            color: root.colOnAccent
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Rectangle {
                    id: tagSidebar
                    Layout.fillHeight: true
                    width: Config.options.cheatsheet.commandsTagsSidebar ? 260 : 0
                    visible: Config.options.cheatsheet.commandsTagsSidebar
                    color: "transparent"
                    clip: true

                    Behavior on width {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 20
                        anchors.bottomMargin: 20
                        spacing: 4

                        StyledFlickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentHeight: sidebarTagsColumn.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: sidebarTagsColumn
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: [""].concat(root.allTags)
                                    delegate: MouseArea {
                                        id: tagMa
                                        property string tagValue: modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 40
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeTag = tagValue

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            radius: Appearance.rounding.large
                                            color: root.activeTag === tagMa.tagValue ? Qt.alpha(root.colAccent, 0.15) : tagMa.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 150
                                                }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16
                                                anchors.rightMargin: 12
                                                spacing: 8

                                                StyledText {
                                                    text: tagMa.tagValue === "" ? qsTr("All") : tagMa.tagValue
                                                    font.pixelSize: Appearance.font.pixelSize.default
                                                    font.weight: root.activeTag === tagMa.tagValue ? Font.Medium : Font.Normal
                                                    color: root.activeTag === tagMa.tagValue ? root.colTitle : root.colSubtitle
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }

                                                Rectangle {
                                                    implicitWidth: countText.implicitWidth + 14
                                                    implicitHeight: 22
                                                    radius: 11
                                                    color: root.activeTag === tagMa.tagValue ? root.colAccent : Appearance.colors.colSecondaryContainer

                                                    StyledText {
                                                        id: countText
                                                        anchors.centerIn: parent
                                                        text: CommandsService.tagCounts[tagMa.tagValue] || 0
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        font.weight: Font.Bold
                                                        color: root.activeTag === tagMa.tagValue ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Appearance.colors.colLayer3Base
                        opacity: 0.3
                    }
                }

                ColumnLayout {
                    id: mainContentArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Item {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        Layout.bottomMargin: 4
                        implicitHeight: Config.options.cheatsheet.commandsTagsSidebar ? 0 : tagFlickable.height
                        visible: !Config.options.cheatsheet.commandsTagsSidebar
                        clip: true

                        Flickable {
                            id: tagFlickable
                            width: parent.width
                            height: tagButtonGroup.implicitHeight
                            contentWidth: tagButtonGroup.implicitWidth
                            contentHeight: height
                            flickableDirection: Flickable.HorizontalFlick
                            clip: true

                            ButtonGroup {
                                id: tagButtonGroup
                                spacing: 4
                                padding: 0

                                SelectionGroupButton {
                                    buttonText: qsTr("All")
                                    toggled: root.activeTag === ""
                                    onClicked: root.activeTag = ""
                                    leftmost: true
                                    rightmost: root.allTags.length === 0
                                }

                                Repeater {
                                    model: root.allTags
                                    delegate: SelectionGroupButton {
                                        required property string modelData
                                        required property int index
                                        buttonText: modelData
                                        toggled: root.activeTag === modelData
                                        onClicked: root.activeTag = (root.activeTag === modelData ? "" : modelData)
                                        leftmost: false
                                        rightmost: index === root.allTags.length - 1
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.leftMargin: 20
                        Layout.bottomMargin: 4
                        text: root.filteredIndices.length + " " + qsTr("commands")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.colSubtitle
                    }

                    StyledFlickable {
                        id: cardFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        contentHeight: gridArea.implicitHeight + 100
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Item {
                            id: gridArea
                            width: parent.width

                            readonly property real cardSpacing: 10
                            readonly property real cardWidth: (width - cardSpacing) / 2
                            property int visibleCardCount: 0

                            Connections {
                                target: root
                                function onIsTabActiveChanged() {
                                    gridArea.triggerLayout();
                                }
                            }

                            Connections {
                                target: CommandsService.commandsModel
                                function onCountChanged() {
                                    gridArea.triggerLayout();
                                }
                            }

                            function recalculateLayout() {
                                var heights = [0, 0];
                                var isActive = root.isTabActive;
                                for (var i = 0; i < cardRepeater.count; i++) {
                                    var card = cardRepeater.itemAt(i);
                                    if (!card)
                                        continue;
                                    if (card.visible) {
                                        if (isActive) {
                                            var minCol = (heights[0] <= heights[1]) ? 0 : 1;
                                            card.x = minCol * (cardWidth + cardSpacing);
                                            card.y = heights[minCol];
                                            heights[minCol] += card.implicitHeight + cardSpacing;
                                        } else {
                                            // Stacked at center and staggered slightly downwards
                                            card.x = (width - cardWidth) / 2;
                                            card.y = i * 20;
                                        }
                                    }
                                }
                                var maxH = Math.max(heights[0], heights[1]);
                                gridArea.implicitHeight = (maxH > cardSpacing) ? maxH - cardSpacing : 0;
                            }

                            function triggerLayout() {
                                layoutTimer.restart();
                            }

                            function recountVisible() {
                                var n = 0;
                                for (var i = 0; i < cardRepeater.count; i++) {
                                    var item = cardRepeater.itemAt(i);
                                    if (item && item.visible)
                                        n++;
                                }
                                visibleCardCount = n;
                            }

                            Repeater {
                                id: cardRepeater
                                model: CommandsService.commandsModel
                                onCountChanged: gridArea.triggerLayout()

                                delegate: Item {
                                    id: cardDelegate
                                    width: gridArea.cardWidth

                                    required property string id
                                    required property string command
                                    required property string description
                                    required property var tags
                                    required property int index

                                    property bool hasMatches: root.filteredIndices.includes(index)
                                    property bool entered: false

                                    visible: hasMatches || opacity > 0.0
                                    opacity: entered && hasMatches ? 1.0 : 0.0
                                    scale: entered && hasMatches ? 1.0 : 0.97

                                    // Height driven by content and filter matching
                                    height: entered && hasMatches ? implicitHeight : 0
                                    implicitHeight: entered && hasMatches ? 180 : 0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 180
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.emphasized
                                        }
                                    }

                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 180
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.emphasized
                                        }
                                    }

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 180
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.emphasized
                                        }
                                    }

                                    Behavior on x {
                                        NumberAnimation {
                                            duration: 220
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.emphasized
                                        }
                                    }

                                    Behavior on y {
                                        NumberAnimation {
                                            duration: 220
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.emphasized
                                        }
                                    }

                                    onImplicitHeightChanged: gridArea.triggerLayout()
                                    onVisibleChanged: {
                                        gridArea.triggerLayout();
                                        gridArea.recountVisible();
                                    }
                                    Component.onCompleted: {
                                        entranceTimer.start();
                                    }
                                    Component.onDestruction: Qt.callLater(gridArea.recountVisible)

                                    Timer {
                                        id: entranceTimer
                                        interval: (index % 4) * 45
                                        onTriggered: cardDelegate.entered = true
                                    }

                                    CommandCard {
                                        id: commandCard
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        
                                        commandId: cardDelegate.id
                                        command: cardDelegate.command
                                        description: cardDelegate.description
                                        tags: {
                                            if (!cardDelegate.tags) return [];
                                            const t = [];
                                            for (let i = 0; i < cardDelegate.tags.count; i++)
                                                t.push(cardDelegate.tags.get(i).modelData);
                                            return t;
                                        }

                                        onEditClicked: {
                                            const tagArr = [];
                                            for (let i = 0; i < cardDelegate.tags.count; i++)
                                                tagArr.push(cardDelegate.tags.get(i).modelData);

                                            commandForm.mode = "edit";
                                            commandForm.editId = cardDelegate.id;
                                            commandForm.editCommand = cardDelegate.command;
                                            commandForm.editDescription = cardDelegate.description;
                                            commandForm.editTags = tagArr.join(", ");
                                            commandForm.isOpen = true;
                                        }

                                        onDeleteClicked: CommandsService.deleteCommand(commandId)
                                    }
                                }
                            }

                            // layout debounce timer
                            Timer {
                                id: layoutTimer
                                interval: 20
                                repeat: false
                                onTriggered: gridArea.recalculateLayout()
                            }

                            Component.onCompleted: {
                                gridArea.triggerLayout();
                                gridArea.recountVisible();
                            }
                        }

                        ScrollBar.vertical: StyledScrollBar {}
                    }
                }
            }
        }

        PagePlaceholder {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: Config.options.cheatsheet.commandsTagsSidebar ? (tagSidebar.width / 2) : 0
            anchors.verticalCenter: parent.verticalCenter

            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
            shown: root.filteredIndices.length === 0
            icon: (root.searchText !== "" || root.activeTag !== "") ? "search_off" : "terminal"
            description: (root.searchText !== "" || root.activeTag !== "") ? qsTr("No results") : qsTr("No commands yet.\nClick \"Add command\" to get started.")
            shape: MaterialShape.Shape.Ghostish
            descriptionHorizontalAlignment: Text.AlignHCenter
        }

        Toolbar {
            id: extraOptions
            z: 5
            enableShadow: false
            colBackground: Appearance.colors.colSecondaryContainer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8

            ToolbarTextField {
                id: filterField
                placeholderText: focus ? qsTr("Filter commands") : qsTr("Hit \"/\" to filter")
                clip: true
                font.pixelSize: Appearance.font.pixelSize.small
                 onTextChanged: root.searchText = text
            }

            IconToolbarButton {
                implicitWidth: height
                onClicked: root.searchText = filterField.text = ''
                text: "close"
                StyledToolTip {
                    text: qsTr("Clear filter")
                }
            }
        }
    }

    CommandForm {
        id: commandForm
        anchors.fill: parent
        z: 10
        visible: isOpen || isAnimating
        onCloseRequested: refreshTags()
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80
        z: 150
        radius: Appearance.rounding.normal
        color: Appearance.colors.colErrorContainer
        border.color: Appearance.colors.colError
        border.width: 1
        width: errorLabel.implicitWidth + 32
        height: errorLabel.implicitHeight + 16
        opacity: root.importError ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        StyledText {
            id: errorLabel
            anchors.centerIn: parent
            text: root.lastImportError
            color: Appearance.colors.colOnErrorContainer
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    // ── Internal File Picker Overlay ──────────────────────────────────────────
    Rectangle {
        id: qmlFilePicker
        anchors.fill: parent
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer1Base : Appearance.m3colors.m3surfaceContainerLow
        visible: false
        z: 100
        radius: Appearance.rounding.windowRounding
        antialiasing: true
        clip: true

        FolderListModelWithHistory {
            id: localFolderModel
            folder: "file://" + (Directories.home ? FileUtils.trimFileProtocol(Directories.home) : "")
            showDirs: true
            showDotAndDotDot: false
            sortField: FolderListModel.Name
            nameFilters: ["*.json"]
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    text: "attach_file"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: qsTr("Select JSON to Import")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    Layout.fillWidth: true
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2Base
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: qmlFilePicker.visible = false

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            AddressBar {
                id: pickerAddressBar
                Layout.fillWidth: true
                directory: localFolderModel.folder ? FileUtils.trimFileProtocol(localFolderModel.folder) : ""
                onNavigateToDirectory: path => {
                    if (!path)
                        return;
                    localFolderModel.folder = Qt.resolvedUrl(path.startsWith("/") ? "file://" + path : path);
                }
                radius: Appearance.rounding.normal
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2Base
                clip: true

                ListView {
                    id: localFileView
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 2
                    model: localFolderModel

                    delegate: MouseArea {
                        id: fileDelegate
                        width: localFileView.width
                        height: 48
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        property bool capturedIsDir: fileIsDir
                        property string capturedPath: filePath
                        property string capturedName: fileName

                        onClicked: {
                            if (fileDelegate.capturedIsDir) {
                                localFolderModel.folder = "file://" + fileDelegate.capturedPath;
                            } else {
                                qmlFilePicker.visible = false;
                                CommandsService.importCommands(fileDelegate.capturedPath);
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: fileDelegate.pressed ? Appearance.colors.colLayer3Active : fileDelegate.containsMouse ? Appearance.colors.colLayer3Hover : "transparent"
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            MaterialSymbol {
                                text: fileDelegate.capturedIsDir ? "folder" : "code"
                                iconSize: 18
                                color: fileDelegate.capturedIsDir ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
                            }

                            StyledText {
                                text: fileDelegate.capturedName
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                    ScrollBar.vertical: StyledScrollBar {}
                }
            }
        }
    }
}
