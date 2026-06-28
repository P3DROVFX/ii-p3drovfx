pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
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
    readonly property color colSubtle: Appearance.colors.colOnSurfaceVariant
    readonly property color colSectionBg: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow

    property bool isOpen: false
    property bool isAnimating: false
    property string mode: "add" // "add" or "edit"
    property string editSlug: ""
    property string editNameValue: ""
    property string editEmojiValue: "🗂️"
    property string editDescriptionValue: ""
    property bool editCloseOthers: false
    property bool editKillOthers: false
    property bool isSavedFeedback: false

    property string newAppClass: ""
    property string newAppWorkspace: "1"
    property bool newAppAutolaunch: true
    property string newAppLaunchCmd: ""
    property bool showAddAppForm: false

    signal closeRequested

    MouseArea {
        anchors.fill: parent
        z: 0
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        enabled: root.isOpen || root.isAnimating
    }

    function openForAdd() {
        root.mode = "add";
        root.editSlug = "";
        root.editNameValue = "";
        root.editEmojiValue = "🗂️";
        root.editDescriptionValue = "";
        root.isOpen = true;
    }

    function openForEdit(slug, name, emoji, description) {
        root.mode = "edit";
        root.editSlug = slug;
        root.editNameValue = name;
        root.editEmojiValue = emoji || "🗂️";
        root.editDescriptionValue = description || "";
        root.isOpen = true;
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

            nameField.text = root.editNameValue;
            descField.text = root.editDescriptionValue;
            nameField.inputItem.forceActiveFocus();
            
            if (mode === "edit" && activeProfileItem) {
                editKillOthers = activeProfileItem.killOthers;
                editCloseOthers = activeProfileItem.closeOthers;
            } else {
                editKillOthers = false;
                editCloseOthers = false;
            }
            showAddAppForm = false;
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

    Timer {
        id: closeDelayTimer
        interval: 800
        onTriggered: root.startClose()
    }

    Connections {
        target: WorkspaceProfileService

        function onSnapshotFinished(success, slug) {
            if (root.isOpen && root.mode === "add") {
                if (success) {
                    root.isSavedFeedback = true;
                    saveFeedbackTimer.restart();
                    closeDelayTimer.restart();
                }
            }
        }
    }

    readonly property var activeProfileItem: {
        if (!editSlug) return null;
        for (let i = 0; i < WorkspaceProfileService.profilesModel.count; i++) {
            let p = WorkspaceProfileService.profilesModel.get(i);
            if (p.slug === editSlug) {
                return p;
            }
        }
        return null;
    }

    readonly property var windowsList: {
        if (!activeProfileItem || !activeProfileItem.windowsJson) return [];
        try {
            return JSON.parse(activeProfileItem.windowsJson);
        } catch (e) {
            return [];
        }
    }

    function confirmSave() {
        const name = nameField.text.trim();
        if (!name) return;

        const desc = descField.text.trim();
        const emoji = root.editEmojiValue;

        if (root.mode === "add") {
            WorkspaceProfileService.snapshot(name, emoji, desc, {});
        } else {
            if (name !== root.activeProfileItem.name) {
                WorkspaceProfileService.renameProfile(root.editSlug, name);
            }
            if (emoji !== root.activeProfileItem.emoji) {
                WorkspaceProfileService.updateEmoji(root.editSlug, emoji);
            }
            if (desc !== (root.activeProfileItem.description || "")) {
                WorkspaceProfileService.updateDescription(root.editSlug, desc);
            }
            root.startClose();
        }
    }

    function cleanAppName(cls) {
        if (!cls)
            return "";
        let name = cls.toLowerCase();
        if (name === "brave-browser" || name === "brave")
            return "Brave";
        if (name === "google-chrome" || name === "chrome")
            return "Chrome";
        if (name === "kitty")
            return "Kitty";
        if (name === "code" || name === "visual-studio-code")
            return "VS Code";
        if (name === "firefox")
            return "Firefox";
        if (name === "discord")
            return "Discord";
        if (name === "spotify")
            return "Spotify";
        if (name === "steam")
            return "Steam";
        if (name === "obs")
            return "OBS Studio";
        if (name === "thunderbird")
            return "Thunderbird";
        if (name === "dolphin")
            return "Dolphin";
        if (name === "thunar")
            return "Thunar";
        if (name === "nautilus")
            return "Files";
        if (name === "vlc")
            return "VLC";
        if (name === "mpv")
            return "mpv";
        if (name === "gimp")
            return "GIMP";
        if (name === "inkscape")
            return "Inkscape";
        if (name === "libreoffice-writer")
            return "Writer";
        if (name === "libreoffice-calc")
            return "Calc";
        name = name.replace(/[-_]/g, " ");
        return name.charAt(0).toUpperCase() + name.slice(1);
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
            anchors {
                fill: parent
                leftMargin: 16
                rightMargin: 16
                topMargin: 16
                bottomMargin: 0
            }
            opacity: 0

            ColumnLayout {
                anchors.fill: parent; spacing: 16

                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    StyledText {
                        Layout.fillWidth: true
                        text: root.mode === "add" ? qsTr("Create Snapshot") : qsTr("Edit Profile")
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: root.colTitleText
                    }

                    RippleButton {
                        implicitHeight: 44
                        implicitWidth: saveRow.implicitWidth + 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.isSavedFeedback ? root.colSaveFeedbackBg : (nameField.text.trim().length > 0 ? root.colSaveBtnBg : root.colSaveBtnDisabledBg)
                        colBackgroundHover: root.isSavedFeedback ? root.colSaveFeedbackBgHover : (nameField.text.trim().length > 0 ? root.colSaveBtnBgHover : root.colSaveBtnDisabledBgHover)
                        enabled: nameField.text.trim().length > 0 || root.isSavedFeedback
                        onClicked: if (!root.isSavedFeedback) root.confirmSave()

                        RowLayout {
                            id: saveRow
                            anchors.centerIn: parent; spacing: 8
                            MaterialSymbol {
                                text: root.isSavedFeedback ? "check" : "save"
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.normal
                                color: (nameField.text.trim().length > 0 || root.isSavedFeedback) ? (root.isSavedFeedback ? root.colSaveFeedbackText : root.colSaveBtnText) : root.colSaveBtnDisabledText
                            }
                            StyledText {
                                text: root.isSavedFeedback ? qsTr("Saved!") : qsTr("Save")
                                font.weight: Font.Bold
                                color: (nameField.text.trim().length > 0 || root.isSavedFeedback) ? (root.isSavedFeedback ? root.colSaveFeedbackText : root.colSaveBtnText) : root.colSaveBtnDisabledText
                            }
                        }
                    }

                    RippleButton {
                        implicitWidth: 44; implicitHeight: 44
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.colCloseBtnBg
                        colBackgroundHover: root.colCloseBtnBgHover
                        onClicked: root.startClose()
                        MaterialSymbol {
                            anchors.centerIn: parent; text: "close"
                            horizontalAlignment: Text.AlignHCenter; iconSize: Appearance.font.pixelSize.large
                            color: root.colCloseBtnIcon
                        }
                    }
                }

                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: formContent.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: formContent
                        width: parent.width - 12
                        spacing: 20
                        // ── SECTION 1: General Info ───────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            color: root.colSectionBg
                            radius: Appearance.rounding.large
                            implicitHeight: sec1Layout.implicitHeight + 32

                            Behavior on implicitHeight {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }

                            ColumnLayout {
                                id: sec1Layout
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 16
                                }
                                spacing: 20

                                FormField {
                                    id: nameField
                                    label: qsTr("Name")
                                    placeholder: qsTr("Work, Gaming, Music...")
                                    onReturnPressed: descField.inputItem.forceActiveFocus()
                                }

                                FormField {
                                    id: descField
                                    label: qsTr("Description")
                                    placeholder: qsTr("What is this workspace layout for? (Optional)")
                                    onReturnPressed: {
                                        if (root.mode === "add") {
                                            root.confirmSave();
                                        }
                                    }
                                }

                                // Emoji Selector Field
                                ColumnLayout {
                                    id: emojiSelectorSection
                                    Layout.fillWidth: true
                                    spacing: 12

                                    property string searchPattern: ""

                                    readonly property var filteredEmojisList: {
                                        const queryText = searchPattern.trim();
                                        return Emojis.fuzzyQuery(queryText);
                                    }

                                    onSearchPatternChanged: {
                                        emojiGridView.contentY = 0;
                                    }

                                    StyledText {
                                        text: qsTr("Select Emoji")
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSurface
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 16

                                        MaterialShape {
                                            shapeString: "Cookie9Sided"
                                            implicitSize: 56
                                            color: Appearance.colors.colPrimaryContainer
                                            Layout.alignment: Qt.AlignTop

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: root.editEmojiValue
                                                font.pixelSize: 28
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            // Text Input for search (aligned to preview height: 56px)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 56
                                                color: root.colFieldBg
                                                radius: Appearance.rounding.small
                                                antialiasing: true

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.IBeamCursor
                                                    onClicked: emojiSearchInput.forceActiveFocus()
                                                }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: 8

                                                    MaterialSymbol {
                                                        text: "search"
                                                        iconSize: Appearance.font.pixelSize.normal
                                                        color: root.colFieldPlaceholder
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }

                                                    TextInput {
                                                        id: emojiSearchInput
                                                        Layout.fillWidth: true
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        font.family: Appearance.font.family.main
                                                        font.pixelSize: Appearance.font.pixelSize.normal
                                                        color: root.colFieldText
                                                        clip: true
                                                        activeFocusOnTab: false

                                                        onTextChanged: emojiSelectorSection.searchPattern = text
                                                        Keys.onEscapePressed: root.startClose()

                                                        StyledText {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: qsTr("Search emojis...")
                                                            color: root.colFieldPlaceholder
                                                            font.pixelSize: Appearance.font.pixelSize.normal
                                                            visible: emojiSearchInput.text.length === 0 && !emojiSearchInput.activeFocus
                                                        }
                                                    }
                                                }
                                            }

                                            // Quick presets (visible when search is empty, emoji size 44)
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                visible: emojiSearchInput.text.trim().length === 0

                                                Repeater {
                                                    model: WorkspaceProfileService.presetEmojis
                                                    delegate: RippleButton {
                                                        id: presetBtn
                                                        required property var modelData
                                                        implicitWidth: 44
                                                        implicitHeight: 44
                                                        buttonRadius: Appearance.rounding.small
                                                        toggled: root.editEmojiValue === modelData
                                                        colBackgroundToggled: Appearance.colors.colPrimaryContainer

                                                        onClicked: root.editEmojiValue = modelData

                                                        StyledText {
                                                            anchors.centerIn: parent
                                                            text: parent.modelData
                                                            font.pixelSize: 22
                                                            scale: presetBtn.toggled ? 1.15 : 1.0

                                                            Behavior on scale {
                                                                NumberAnimation {
                                                                    duration: 150
                                                                    easing.type: Easing.BezierSpline
                                                                    easing.bezierCurve: Appearance.animationCurves.emphasized
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Scrollable GridView (virtually loaded to prevent lag, fits exactly 3 lines of 48px cells)
                                            GridView {
                                                id: emojiGridView
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 144
                                                cellWidth: 48
                                                cellHeight: 48
                                                clip: true
                                                visible: emojiSelectorSection.filteredEmojisList.length > 0
                                                model: emojiSelectorSection.filteredEmojisList

                                                delegate: Item {
                                                    width: 48
                                                    height: 48

                                                    required property var modelData
                                                    readonly property string emojiChar: modelData.match(/^\s*(\S+)/)?.[1] || ""
                                                    readonly property string emojiName: modelData.replace(/^\s*\S+\s+/, "")

                                                    RippleButton {
                                                        id: gridBtn
                                                        anchors.centerIn: parent
                                                        implicitWidth: 44
                                                        implicitHeight: 44
                                                        buttonRadius: Appearance.rounding.small

                                                        toggled: root.editEmojiValue === emojiChar
                                                        colBackgroundToggled: Appearance.colors.colPrimaryContainer

                                                        onClicked: root.editEmojiValue = emojiChar

                                                        StyledText {
                                                            anchors.centerIn: parent
                                                            text: emojiChar
                                                            font.pixelSize: 22
                                                            scale: gridBtn.toggled ? 1.15 : 1.0

                                                            Behavior on scale {
                                                                NumberAnimation {
                                                                    duration: 150
                                                                    easing.type: Easing.BezierSpline
                                                                    easing.bezierCurve: Appearance.animationCurves.emphasized
                                                                }
                                                            }
                                                        }

                                                        StyledToolTip {
                                                            text: emojiName
                                                        }
                                                    }
                                                }
                                            }

                                            // Empty state for when no emojis are found
                                            StyledText {
                                                visible: emojiSelectorSection.filteredEmojisList.length === 0
                                                text: qsTr("No emojis found")
                                                color: root.colSubtle
                                                font {
                                                    pixelSize: Appearance.font.pixelSize.small
                                                    weight: Font.Normal
                                                }
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.topMargin: 20
                                                Layout.bottomMargin: 20
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: root.mode === "edit"
                            Layout.fillWidth: true
                            color: root.colSectionBg
                            radius: Appearance.rounding.large
                            implicitHeight: sec2Layout.implicitHeight + 32

                            Behavior on implicitHeight {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }

                            ColumnLayout {
                                id: sec2Layout
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 16
                                }
                                spacing: 20

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: Math.max(switch1TextCol.implicitHeight, switch1.implicitHeight)

                                    ColumnLayout {
                                        id: switch1TextCol
                                        anchors {
                                            left: parent.left
                                            right: switch1.left
                                            rightMargin: 12
                                            verticalCenter: parent.verticalCenter
                                        }
                                        spacing: 2

                                        StyledText {
                                            text: qsTr("Kill other windows on restore")
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnSurface
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                        StyledText {
                                            text: qsTr("Forces closing all windows that are not part of this profile.")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnSurfaceVariant
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    StyledSwitch {
                                        id: switch1
                                        anchors {
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                        }
                                        checked: root.editKillOthers
                                        onCheckedChanged: {
                                            if (checked !== root.editKillOthers) {
                                                root.editKillOthers = checked;
                                                if (checked) root.editCloseOthers = false;
                                                if (root.mode === "edit") {
                                                    WorkspaceProfileService.updateProfileOptions(root.editSlug, root.editCloseOthers, root.editKillOthers);
                                                }
                                            }
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: Math.max(switch2TextCol.implicitHeight, switch2.implicitHeight)

                                    ColumnLayout {
                                        id: switch2TextCol
                                        anchors {
                                            left: parent.left
                                            right: switch2.left
                                            rightMargin: 12
                                            verticalCenter: parent.verticalCenter
                                        }
                                        spacing: 2

                                        StyledText {
                                            text: qsTr("Close other windows on restore")
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnSurface
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                        StyledText {
                                            text: qsTr("Gracefully requests all other windows to close on restore.")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnSurfaceVariant
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    StyledSwitch {
                                        id: switch2
                                        anchors {
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                        }
                                        checked: root.editCloseOthers
                                        onCheckedChanged: {
                                            if (checked !== root.editCloseOthers) {
                                                root.editCloseOthers = checked;
                                                if (checked) root.editKillOthers = false;
                                                if (root.mode === "edit") {
                                                    WorkspaceProfileService.updateProfileOptions(root.editSlug, root.editCloseOthers, root.editKillOthers);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: root.mode === "edit"
                            Layout.fillWidth: true
                            color: root.colSectionBg
                            radius: Appearance.rounding.large
                            implicitHeight: sec3Layout.implicitHeight + 32

                            Behavior on implicitHeight {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }

                            ColumnLayout {
                                id: sec3Layout
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 16
                                }
                                spacing: 20

                                RowLayout {
                                    spacing: 6
                                    Layout.topMargin: 4
                                    StyledText {
                                        text: qsTr("Configure Windows & Autolaunch")
                                        font {
                                            pixelSize: Appearance.font.pixelSize.small
                                            weight: Font.Bold
                                        }
                                        color: Appearance.colors.colOnSurface
                                    }
                                }

                                // Snapshot Window Rows
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: root.windowsList
                                        delegate: Item {
                                            id: windowRowItem
                                            required property int index
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: windowRow.implicitHeight + 16

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: Appearance.rounding.small
                                                color: Appearance.colors.colLayer2
                                                opacity: windowRowItem.index % 2 === 0 ? 0.45 : 0.0
                                            }

                                            RowLayout {
                                                id: windowRow
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    verticalCenter: parent.verticalCenter
                                                    leftMargin: 12
                                                    rightMargin: 8
                                                }
                                                spacing: 12

                                                Rectangle {
                                                    Layout.preferredWidth: 28
                                                    Layout.minimumWidth: 28
                                                    Layout.maximumWidth: 28
                                                    Layout.fillWidth: false
                                                    Layout.preferredHeight: 28
                                                    radius: Appearance.rounding.full
                                                    color: Appearance.colors.colSecondaryContainer

                                                    Image {
                                                        id: appIconImg
                                                        anchors.centerIn: parent
                                                        sourceSize: Qt.size(16, 16)
                                                        source: {
                                                            const _ = TaskbarApps.iconThemeRevision;
                                                            return Quickshell.iconPath(AppSearch.guessIcon(windowRowItem.modelData.class || ""), "");
                                                        }
                                                        smooth: true
                                                        visible: source.toString() !== "" && status !== Image.Error
                                                    }

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        visible: !appIconImg.visible
                                                        text: (windowRowItem.modelData.class || "?").charAt(0).toUpperCase()
                                                        font {
                                                            pixelSize: Appearance.font.pixelSize.smaller
                                                            weight: Font.Bold
                                                        }
                                                        color: Appearance.colors.colOnSecondaryContainer
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    StyledText {
                                                        text: windowRowItem.modelData.class || "unknown"
                                                        font {
                                                            pixelSize: Appearance.font.pixelSize.small
                                                            weight: Font.DemiBold
                                                        }
                                                        color: Appearance.colors.colOnSurface
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                    StyledText {
                                                        visible: windowRowItem.modelData.floating
                                                        text: qsTr("Floating")
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colOnSurfaceVariant
                                                    }
                                                }

                                                RowLayout {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Layout.preferredWidth: 100
                                                    Layout.minimumWidth: 100
                                                    Layout.maximumWidth: 100
                                                    Layout.fillWidth: false
                                                    spacing: 4
                                                    StyledText {
                                                        text: qsTr("WS")
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        color: Appearance.colors.colOnSurfaceVariant
                                                    }
                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 36
                                                        color: root.colFieldBg
                                                        radius: Appearance.rounding.small
                                                        antialiasing: true

                                                        TextInput {
                                                            id: wsInput
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 8; anchors.rightMargin: 8
                                                            verticalAlignment: TextInput.AlignVCenter
                                                            horizontalAlignment: TextInput.AlignHCenter
                                                            font.family: Appearance.font.family.main
                                                            font.pixelSize: Appearance.font.pixelSize.small
                                                            color: root.colFieldText
                                                            clip: true
                                                            text: {
                                                                let ws = windowRowItem.modelData.workspaceId;
                                                                if (typeof ws === "string" && ws.startsWith("special"))
                                                                    return "sp";
                                                                if (typeof ws === "number" && ws < 0)
                                                                    return "sp";
                                                                return ws.toString();
                                                            }

                                                            onEditingFinished: {
                                                                let val = text.trim();
                                                                if (val.toLowerCase() === "sp" || val.toLowerCase() === "special") {
                                                                    val = "special:special";
                                                                } else {
                                                                    let parsed = parseInt(val);
                                                                    if (!isNaN(parsed))
                                                                        val = parsed;
                                                                }
                                                                if (val !== windowRowItem.modelData.workspaceId) {
                                                                    WorkspaceProfileService.updateWindowWorkspace(root.editSlug, windowRowItem.index, val);
                                                                }
                                                            }
                                                            Keys.onEscapePressed: root.startClose()
                                                        }
                                                    }
                                                }

                                                RowLayout {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Layout.preferredWidth: 130
                                                    Layout.minimumWidth: 130
                                                    Layout.maximumWidth: 130
                                                    Layout.fillWidth: false
                                                    spacing: 6
                                                    StyledText {
                                                        text: qsTr("Autolaunch")
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        color: Appearance.colors.colOnSurfaceVariant
                                                    }
                                                    StyledSwitch {
                                                        checked: windowRowItem.modelData.autolaunch || false
                                                        onCheckedChanged: {
                                                            if (checked !== (windowRowItem.modelData.autolaunch || false)) {
                                                                WorkspaceProfileService.updateWindowOptions(root.editSlug, windowRowItem.index, checked, cmdFieldTextVal);
                                                            }
                                                        }
                                                    }
                                                }

                                                property string cmdFieldTextVal: windowRowItem.modelData.launchCmd || ""
                                                Rectangle {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Layout.preferredWidth: 220
                                                    Layout.minimumWidth: 220
                                                    Layout.maximumWidth: 220
                                                    Layout.fillWidth: false
                                                    Layout.preferredHeight: 36
                                                    color: root.colFieldBg
                                                    radius: Appearance.rounding.small
                                                    antialiasing: true
                                                    opacity: windowRowItem.modelData.autolaunch ? 1.0 : 0.5

                                                    TextInput {
                                                        id: cmdField
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8; anchors.rightMargin: 8
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        font.family: Appearance.font.family.main
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        color: root.colFieldText
                                                        clip: true
                                                        text: windowRowItem.cmdFieldTextVal
                                                        enabled: windowRowItem.modelData.autolaunch || false

                                                        onEditingFinished: {
                                                            if (text !== (windowRowItem.modelData.launchCmd || "")) {
                                                                WorkspaceProfileService.updateWindowOptions(root.editSlug, windowRowItem.index, windowRowItem.modelData.autolaunch || false, text);
                                                            }
                                                        }
                                                        onTextChanged: windowRowItem.cmdFieldTextVal = text
                                                        Keys.onEscapePressed: root.startClose()

                                                        StyledText {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            anchors.left: parent.left; anchors.leftMargin: 2
                                                            text: qsTr("Arguments...")
                                                            color: root.colFieldPlaceholder
                                                            font.pixelSize: Appearance.font.pixelSize.small
                                                            visible: cmdField.text.length === 0 && !cmdField.activeFocus
                                                        }
                                                    }
                                                }

                                                Item {
                                                    Layout.preferredWidth: 80
                                                    Layout.minimumWidth: 80
                                                    Layout.maximumWidth: 80
                                                    Layout.fillWidth: false
                                                    Layout.preferredHeight: 36

                                                    RippleButton {
                                                        id: delBtn
                                                        anchors.right: parent.right
                                                        implicitWidth: 36
                                                        implicitHeight: 36
                                                        buttonRadius: Appearance.rounding.full
                                                        colBackground: "transparent"
                                                        colBackgroundHover: Appearance.colors.colErrorContainer
                                                        onClicked: WorkspaceProfileService.deleteWindow(root.editSlug, windowRowItem.index)
                                                        StyledToolTip {
                                                            text: qsTr("Delete window entry")
                                                        }
                                                        MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            text: "delete"
                                                            iconSize: Appearance.font.pixelSize.normal
                                                            color: delBtn.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurfaceVariant
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Add App button/form
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Layout.topMargin: 4

                                    RippleButtonWithIcon {
                                        visible: !root.showAddAppForm
                                        Layout.alignment: Qt.AlignLeft
                                        materialIcon: "add_circle"
                                        materialIconFill: true
                                        mainText: qsTr("Add App")
                                        colText: Appearance.colors.colOnPrimaryContainer
                                        colBackground: Appearance.colors.colPrimaryContainer
                                        colBackgroundHover: Qt.lighter(Appearance.colors.colPrimaryContainer, 1.08)
                                        buttonRadius: Appearance.rounding.full
                                        implicitHeight: 36
                                        onClicked: {
                                            root.newAppClass = "";
                                            root.newAppWorkspace = "1";
                                            root.newAppAutolaunch = true;
                                            root.newAppLaunchCmd = "";
                                            root.showAddAppForm = true;
                                        }
                                    }

                                    ColumnLayout {
                                        visible: root.showAddAppForm
                                        Layout.fillWidth: true
                                        spacing: 12

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            Item {
                                                Layout.preferredWidth: 28
                                                Layout.minimumWidth: 28
                                                Layout.maximumWidth: 28
                                                Layout.fillWidth: false
                                                Layout.preferredHeight: 28
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36
                                                color: root.colFieldBg
                                                radius: Appearance.rounding.small
                                                antialiasing: true

                                                TextInput {
                                                    id: newClassInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    font.family: Appearance.font.family.main
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: root.colFieldText
                                                    clip: true
                                                    text: root.newAppClass
                                                    onTextChanged: root.newAppClass = text

                                                    StyledText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.left: parent.left
                                                        text: qsTr("App class (e.g. kitty)...")
                                                        color: root.colFieldPlaceholder
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        visible: newClassInput.text.length === 0 && !newClassInput.activeFocus
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: 100
                                                Layout.minimumWidth: 100
                                                Layout.maximumWidth: 100
                                                Layout.fillWidth: false
                                                spacing: 4
                                                StyledText {
                                                    text: qsTr("WS")
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colOnSurfaceVariant
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 36
                                                    color: root.colFieldBg
                                                    radius: Appearance.rounding.small
                                                    antialiasing: true

                                                    TextInput {
                                                        id: newWSInput
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8; anchors.rightMargin: 8
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        horizontalAlignment: TextInput.AlignHCenter
                                                        font.family: Appearance.font.family.main
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        color: root.colFieldText
                                                        clip: true
                                                        text: root.newAppWorkspace
                                                        onTextChanged: root.newAppWorkspace = text
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: 130
                                                Layout.minimumWidth: 130
                                                Layout.maximumWidth: 130
                                                Layout.fillWidth: false
                                                spacing: 4
                                                StyledText {
                                                    text: qsTr("Auto")
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colOnSurfaceVariant
                                                }
                                                StyledSwitch {
                                                    checked: root.newAppAutolaunch
                                                    onCheckedChanged: root.newAppAutolaunch = checked
                                                }
                                            }

                                            Rectangle {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: 220
                                                Layout.minimumWidth: 220
                                                Layout.maximumWidth: 220
                                                Layout.fillWidth: false
                                                Layout.preferredHeight: 36
                                                color: root.colFieldBg
                                                radius: Appearance.rounding.small
                                                antialiasing: true
                                                opacity: root.newAppAutolaunch ? 1.0 : 0.5

                                                TextInput {
                                                    id: newCmdInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    font.family: Appearance.font.family.main
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: root.colFieldText
                                                    clip: true
                                                    text: root.newAppLaunchCmd
                                                    onTextChanged: root.newAppLaunchCmd = text
                                                    enabled: root.newAppAutolaunch

                                                    StyledText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        anchors.left: parent.left
                                                        text: qsTr("Arguments (optional)...")
                                                        color: root.colFieldPlaceholder
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        visible: newCmdInput.text.length === 0 && !newCmdInput.activeFocus
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: 80
                                                Layout.minimumWidth: 80
                                                Layout.maximumWidth: 80
                                                Layout.fillWidth: false
                                                Layout.preferredHeight: 36
                                                spacing: 6

                                                RippleButton {
                                                    implicitWidth: 36
                                                    implicitHeight: 36
                                                    buttonRadius: Appearance.rounding.full
                                                    colBackground: Appearance.colors.colPrimary
                                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                                    enabled: root.newAppClass.trim().length > 0 && root.newAppWorkspace.trim().length > 0
                                                    onClicked: {
                                                        let ws = root.newAppWorkspace.trim();
                                                        if (ws.toLowerCase() === "sp" || ws.toLowerCase() === "special") {
                                                            ws = "special:special";
                                                        } else {
                                                            let parsed = parseInt(ws);
                                                            if (!isNaN(parsed))
                                                                ws = parsed;
                                                            else
                                                                ws = 1;
                                                        }
                                                        WorkspaceProfileService.addWindow(root.editSlug, root.newAppClass.trim(), ws, root.newAppAutolaunch, root.newAppLaunchCmd.trim());
                                                        root.showAddAppForm = false;
                                                    }
                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        text: "check"
                                                        iconSize: Appearance.font.pixelSize.small
                                                        color: Appearance.colors.colOnPrimary
                                                    }
                                                }

                                                RippleButton {
                                                    implicitWidth: 36
                                                    implicitHeight: 36
                                                    buttonRadius: Appearance.rounding.full
                                                    colBackground: Appearance.colors.colLayer2
                                                    onClicked: root.showAddAppForm = false
                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        text: "close"
                                                        iconSize: Appearance.font.pixelSize.small
                                                        color: root.colSubtle
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
