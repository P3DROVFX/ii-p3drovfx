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

    readonly property color colBg: Appearance.colors.colLayer0
    readonly property color colTitle: Appearance.colors.colOnSurface
    readonly property color colSubtitle: Appearance.colors.colOnSurfaceVariant
    readonly property color colAccent: Appearance.colors.colPrimary
    readonly property color colAccentHover: Appearance.colors.colPrimaryHover
    readonly property color colOnAccent: Appearance.colors.colOnPrimary

    property string activeTag: ""
    property string searchText: ""
    property var allTags: []

    property bool importSuccess: false
    property bool importError: false
    property string lastImportError: ""
    property var filteredIndices: {
        const model = CommandsService.commandsModel;
        if (!model)
            return [];
        const q = root.searchText.toLowerCase();
        const tag = root.activeTag;
        const result = [];
        for (let i = 0; i < model.count; i++) {
            const item = model.get(i);
            if (!item)
                continue;
            let tagMatch = tag === "";
            if (!tagMatch && item.tags) {
                for (let t = 0; t < item.tags.count; t++) {
                    if (item.tags.get(t).modelData === tag) {
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

    function countForTag(tag) {
        const model = CommandsService.commandsModel;
        if (!model)
            return 0;
        if (tag === "")
            return model.count;
        let count = 0;
        for (let i = 0; i < model.count; i++) {
            const item = model.get(i);
            if (!item || !item.tags)
                continue;
            for (let t = 0; t < item.tags.count; t++) {
                if (item.tags.get(t).modelData === tag) {
                    count++;
                    break;
                }
            }
        }
        return count;
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
                                                        text: root.countForTag(tagMa.tagValue)
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        font.weight: Font.Bold
                                                        color: root.activeTag === tagMa.tagValue ? Appearance.colors.colOnPrimary : Appearence.colors.colOnSecondaryContainer
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
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: cardGrid.implicitHeight + 100
                        clip: true

                        GridLayout {
                            id: cardGrid
                            width: parent.width - 32
                            x: 16
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10

                            Repeater {
                                model: root.filteredIndices
                                delegate: CommandCard {
                                    required property int modelData
                                    readonly property var cmdItem: CommandsService.commandsModel.get(modelData)

                                    Layout.fillWidth: true

                                    commandId: cmdItem?.id ?? ""
                                    command: cmdItem?.command ?? ""
                                    description: cmdItem?.description ?? ""
                                    tags: {
                                        if (!cmdItem)
                                            return [];
                                        const arr = [];
                                        for (let t = 0; t < cmdItem.tags.count; t++)
                                            arr.push(cmdItem.tags.get(t).modelData);
                                        return arr;
                                    }

                                    onEditClicked: {
                                        const item = cmdItem;
                                        if (!item)
                                            return;
                                        const tagArr = [];
                                        for (let t = 0; t < item.tags.count; t++)
                                            tagArr.push(item.tags.get(t).modelData);

                                        commandForm.mode = "edit";
                                        commandForm.editId = item.id;
                                        commandForm.editCommand = item.command;
                                        commandForm.editDescription = item.description;
                                        commandForm.editTags = tagArr.join(", ");
                                        commandForm.isOpen = true;
                                    }

                                    onDeleteClicked: CommandsService.deleteCommand(commandId)
                                }
                            }
                        }
                    }
                }
            }
        }

        PagePlaceholder {
            anchors.centerIn: parent
            shown: root.filteredIndices.length === 0
            icon: (root.searchText !== "" || root.activeTag !== "") ? "search_off" : "terminal"
            description: (root.searchText !== "" || root.activeTag !== "") ? qsTr("No results") : qsTr("No commands yet.\nClick \"Add command\" to get started.")
            shape: MaterialShape.Shape.Ghostish
            descriptionHorizontalAlignment: Text.AlignHCenter
        }

        Toolbar {
            id: extraOptions
            z: 5
            colBackground: Appearance.colors.colSecondaryContainer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: Config.options.cheatsheet.commandsTagsSidebar ? (tagSidebar.width / 2) : 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20

            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }

            ToolbarTextField {
                id: filterField
                placeholderText: focus ? qsTr("Filter commands") : qsTr("Hit \"/\" to filter")
                clip: true
                font.pixelSize: Appearance.font.pixelSize.small
                onTextChanged: root.searchText = text
                colBackground: Qt.alpha(Appearance.colors.colOnTertiaryContainer, 0.05)
                color: Appearance.colors.colOnTertiaryContainer
                placeholderTextColor: Qt.alpha(Appearance.colors.colOnTertiaryContainer, 0.6)
            }

            IconToolbarButton {
                implicitWidth: height
                onClicked: root.searchText = filterField.text = ''
                text: "close"
                colText: Appearance.colors.colOnTertiaryContainer
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
        color: Appearance.colors.colLayer1Base
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
