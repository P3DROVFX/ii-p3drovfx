pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property bool isOpen: false
    property bool isAnimating: false
    property string mode: "create"
    property string editPageId: ""
    property string selectedIcon: "keyboard"
    property string selectedProgram: ""
    property string selectedProgramId: ""
    property bool useProgramIcon: false
    property var iconChoices: [
        "keyboard", "code", "terminal", "developer_mode", "data_object", "source", "integration_instructions",
        "desktop_windows", "laptop", "phone_android", "tablet_mac", "apps", "grid_view", "dashboard", "widgets",
        "folder", "folder_open", "description", "article", "edit_note", "menu_book", "school", "auto_stories",
        "language", "public", "web", "travel_explore", "map", "database", "cloud", "dns", "storage",
        "settings", "tune", "build", "construction", "security", "lock", "notifications", "mail",
        "calendar_month", "schedule", "sports_esports", "gamepad", "palette"
    ]
    readonly property var availableIconChoices: {
        const choices = root.iconChoices.slice();
        const selected = String(root.selectedIcon ?? "").trim();
        if (selected && !choices.includes(selected))
            choices.unshift(selected);
        return choices;
    }

    // Keep the persisted label human-readable (existing templates use names),
    // while programId resolves the selected desktop entry for its artwork.
    readonly property var programChoices: {
        const choices = [{
            id: "",
            value: "",
            name: Translation.tr("No related program"),
            icon: "link_off",
            iconSource: ""
        }];
        const seen = new Set();
        for (const app of AppSearch.list ?? []) {
            const name = String(app?.name ?? "").trim();
            if (!name)
                continue;
            const id = String(app?.id ?? name).trim() || name;
            const key = id.toLowerCase();
            if (seen.has(key))
                continue;
            seen.add(key);
            const iconCandidate = String(app?.icon ?? "").trim();
            // Validate the desktop entry's icon once per cached name. Invalid
            // absolute paths fall back to the Material `apps` glyph in the
            // combo instead of leaving a broken image row behind.
            const iconSource = iconCandidate
                && iconCandidate !== "image-missing"
                && iconCandidate !== "application-x-executable"
                && AppSearch.iconExists(iconCandidate)
                ? iconCandidate
                : "";
            choices.push({
                id: id,
                programId: id,
                value: name,
                name: name,
                // Material fallback is used only by combo-boxes that do not
                // opt into iconSourceRole; this picker renders iconSource.
                icon: "apps",
                iconSource: iconSource === "image-missing" || iconSource === "application-x-executable" ? "" : iconSource
            });
        }

        const selected = String(root.selectedProgram ?? "").trim();
        const selectedKey = selected.toLowerCase();
        if (selected && !choices.some(choice => String(choice.value ?? "").toLowerCase() === selectedKey
                || String(choice.id ?? "").toLowerCase() === selectedKey)) {
            const guessed = AppSearch.guessIcon(selected);
            choices.splice(1, 0, {
                id: selected,
                programId: root.selectedProgramId || selected,
                value: selected,
                name: selected,
                icon: "apps",
                iconSource: guessed === "image-missing" || guessed === "application-x-executable" ? "" : guessed
            });
        }
        return choices;
    }

    readonly property int selectedProgramIndex: {
        const selected = String(root.selectedProgram ?? "").trim().toLowerCase();
        const selectedId = String(root.selectedProgramId ?? "").trim().toLowerCase();
        if (!selected && !selectedId)
            return 0;
        for (let index = 0; index < root.programChoices.length; index++) {
            const choice = root.programChoices[index];
            if ((selectedId && String(choice?.programId ?? choice?.id ?? "").toLowerCase() === selectedId)
                    || String(choice?.value ?? "").toLowerCase() === selected
                    || String(choice?.id ?? "").toLowerCase() === selected)
                return index;
        }
        return 0;
    }

    readonly property var selectedProgramEntry: {
        const selected = String(root.selectedProgram ?? "").trim().toLowerCase();
        const selectedId = String(root.selectedProgramId ?? "").trim().toLowerCase();
        if (!selected && !selectedId)
            return null;
        for (const app of AppSearch.list ?? []) {
            if ((selectedId && String(app?.id ?? "").trim().toLowerCase() === selectedId)
                    || (selected && String(app?.name ?? "").trim().toLowerCase() === selected)
                    || (selected && String(app?.id ?? "").trim().toLowerCase() === selected))
                return app;
        }
        return null;
    }

    readonly property string selectedProgramIcon: {
        const entry = root.selectedProgramEntry;
        let icon = String(entry?.icon ?? "").trim();
        if (icon && icon !== "image-missing" && icon !== "application-x-executable" && AppSearch.iconExists(icon))
            return icon;
        icon = root.selectedProgramId ? AppSearch.guessIcon(root.selectedProgramId) : (root.selectedProgram ? AppSearch.guessIcon(root.selectedProgram) : "");
        if (!icon || icon === "image-missing" || icon === "application-x-executable" || !AppSearch.iconExists(icon))
            return "";
        return icon;
    }

    signal pageChosen(string pageId)
    signal closeRequested

    Connections {
        target: KeybindsService
        function onOperationFinished(success, message, pageId) {
            if (!root.isOpen)
                return;
            if (success && pageId) {
                root.pageChosen(pageId);
                root.startClose();
            }
        }
    }

    function openCreate(): void {
        root.mode = "create";
        root.editPageId = "";
        nameField.text = "";
        root.selectedIcon = "keyboard";
        root.selectedProgram = "";
        root.selectedProgramId = "";
        root.useProgramIcon = false;
        root.isOpen = true;
        if (!KeybindsService.hasScanned && !KeybindsService.scanning && KeybindsService.detectedSources.length === 0) {
            KeybindsService.scanKnownPrograms();
        }
    }

    function openEdit(pageId): void {
        const page = KeybindsService.pageById(pageId);
        if (!page)
            return;
        root.mode = "edit";
        root.editPageId = pageId;
        nameField.text = String(page.name ?? "");
        root.selectedIcon = String(page.icon ?? "keyboard").trim() || "keyboard";
        root.selectedProgram = String(page.program ?? "").trim();
        root.selectedProgramId = String(page.programId ?? "").trim();
        if (!root.selectedProgramId && root.selectedProgram) {
            const matchingApp = (AppSearch.list ?? []).find(app =>
                String(app?.name ?? "").trim().toLowerCase() === root.selectedProgram.toLowerCase()
                || String(app?.id ?? "").trim().toLowerCase() === root.selectedProgram.toLowerCase());
            root.selectedProgramId = String(matchingApp?.id ?? "").trim();
        }
        root.useProgramIcon = Boolean(page.useProgramIcon);
        root.isOpen = true;
    }

    function startClose(): void {
        if (!root.isOpen)
            return;
        openAnimation.stop();
        closeAnimation.restart();
    }

    function savePage(): void {
        const name = nameField.text.trim();
        if (!name) {
            nameField.error = true;
            nameField.forceActiveFocus();
            return;
        }
        nameField.error = false;
        if (root.mode === "edit") {
            if (KeybindsService.updatePage(root.editPageId, name, root.selectedIcon, root.selectedProgram, root.useProgramIcon, root.selectedProgramId)) {
                root.pageChosen(root.editPageId);
                root.startClose();
            }
            return;
        }
        const pageId = KeybindsService.createPage(name, root.selectedIcon, root.selectedProgram, [], {
            useProgramIcon: root.useProgramIcon,
            programId: root.selectedProgramId
        });
        if (pageId) {
            root.pageChosen(pageId);
            root.startClose();
        }
    }

    visible: root.isOpen || root.isAnimating
    enabled: root.isOpen || root.isAnimating

    onIsOpenChanged: {
        if (!root.isOpen)
            return;
        root.isAnimating = true;
        pageSurface.x = root.width;
        formContent.opacity = 0;
        openAnimation.restart();
        Qt.callLater(() => nameField.forceActiveFocus());
    }

    SequentialAnimation {
        id: openAnimation

        ParallelAnimation {
            NumberAnimation {
                target: pageSurface
                property: "x"
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            NumberAnimation {
                target: formContent
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        ScriptAction { script: root.isAnimating = false }
    }

    SequentialAnimation {
        id: closeAnimation

        ScriptAction { script: root.isAnimating = true }
        ParallelAnimation {
            NumberAnimation {
                target: pageSurface
                property: "x"
                to: root.width
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            NumberAnimation {
                target: formContent
                property: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        ScriptAction {
            script: {
                root.isAnimating = false;
                root.isOpen = false;
                root.closeRequested();
            }
        }
    }

    Keys.onEscapePressed: event => {
        root.startClose();
        event.accepted = true;
    }

    Rectangle {
        id: pageSurface
        y: 0
        width: root.width
        height: root.height
        radius: Appearance.rounding.windowRounding
        color: Config.options.appearance.transparency.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainerLow
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            id: formContent
            anchors.fill: parent
            anchors.margins: 18
            opacity: 0
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialShape {
                    implicitSize: 48
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.mode === "create" ? "library_add" : "edit"
                        iconSize: Appearance.font.pixelSize.huge
                        fill: 1
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    spacing: 0

                    StyledText {
                        text: root.mode === "create" ? Translation.tr("Create a shortcut page") : Translation.tr("Edit shortcut page")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.title
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.startClose()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.mode === "create" ? Math.min(430, pageSurface.width * 0.34) : pageSurface.width - 36
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        StyledFlickable {
                            id: blankPageFlickable
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: width
                            contentHeight: blankPageColumn.implicitHeight + 4

                            ColumnLayout {
                                id: blankPageColumn
                                width: blankPageFlickable.width
                                spacing: 12

                                StyledText {
                                    text: Translation.tr("Blank page")
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                }

                                MaterialTextField {
                                    id: nameField
                                    Layout.fillWidth: true
                                    placeholderText: Translation.tr("Page name · required")
                                    selectByMouse: true
                                    onTextChanged: error = false
                                    onAccepted: programSelector.forceActiveFocus()
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Page icon")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: implicitHeight
                                    spacing: 6

                                    Repeater {
                                        model: root.availableIconChoices

                                        delegate: RippleButton {
                                            required property string modelData
                                            implicitWidth: 38
                                            implicitHeight: 34
                                            buttonRadius: Appearance.rounding.full
                                            toggled: root.selectedIcon === modelData
                                            colBackground: toggled ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
                                            colBackgroundHover: toggled ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
                                            colBackgroundActive: toggled ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer3Active
                                            Accessible.name: Translation.tr("Page icon") + ": " + modelData
                                            Accessible.checked: toggled
                                            onClicked: root.selectedIcon = modelData

                                            contentItem: MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: modelData
                                                iconSize: Appearance.font.pixelSize.normal
                                                fill: root.selectedIcon === modelData ? 1 : 0
                                                color: root.selectedIcon === modelData ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                            }
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Related program · optional")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                }

                                StyledComboBox {
                                    id: programSelector
                                    Layout.fillWidth: true
                                    implicitHeight: 46
                                    popupWidth: Math.min(420, pageSurface.width - 64)
                                    model: root.programChoices
                                    textRole: "name"
                                    iconSourceRole: "iconSource"
                                    currentIndex: root.selectedProgramIndex
                                    Accessible.name: Translation.tr("Related program")
                                    onActivated: index => {
                                        const choice = root.programChoices[index];
                                        root.selectedProgram = String(choice?.value ?? "").trim();
                                        root.selectedProgramId = String(choice?.programId ?? choice?.id ?? "").trim();
                                        if (!root.selectedProgramIcon)
                                            root.useProgramIcon = false;
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: Boolean(root.selectedProgram)
                                    spacing: 10

                                    Loader {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        active: root.selectedProgramIcon.length > 0
                                        visible: active
                                        sourceComponent: IconImage {
                                            source: Quickshell.iconPath(root.selectedProgramIcon, "image-missing")
                                        }
                                    }

                                    MaterialShape {
                                        visible: !root.selectedProgramIcon
                                        implicitSize: 32
                                        shape: MaterialShape.Shape.Cookie9Sided
                                        color: Appearance.colors.colLayer3

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "apps"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.selectedProgram
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnSurface
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.selectedProgramIcon
                                                ? Translation.tr("Application icon detected")
                                                : Translation.tr("No application icon found")
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: root.selectedProgramIcon
                                                ? Appearance.colors.colOnSurfaceVariant
                                                : Appearance.colors.colError
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: Boolean(root.selectedProgram)
                                    implicitHeight: 48
                                    radius: Appearance.rounding.normal
                                    color: root.useProgramIcon
                                        ? Appearance.colors.colSecondaryContainer
                                        : Appearance.colors.colLayer3

                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        MaterialSymbol {
                                            text: "view_sidebar"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: root.useProgramIcon
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnSurfaceVariant
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("Use app icon in sidebar")
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Bold
                                            color: root.useProgramIcon
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnSurface
                                        }

                                        StyledSwitch {
                                            id: useProgramIconSwitch
                                            sizeScale: 1
                                            checked: root.useProgramIcon
                                            enabled: root.selectedProgramIcon.length > 0
                                            Accessible.name: Translation.tr("Use app icon in sidebar")
                                            Accessible.checked: checked
                                            onClicked: root.useProgramIcon = checked
                                        }
                                    }
                                }
                            }
                        }

                        RippleButtonWithIcon {
                            Layout.fillWidth: true
                            implicitHeight: 48
                            centerContent: true
                            buttonRadius: Appearance.rounding.full
                            materialIcon: root.mode === "create" ? "add" : "save"
                            mainText: root.mode === "create" ? Translation.tr("Create blank page") : Translation.tr("Save page")
                            colBackground: nameField.text.trim() ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                            colBackgroundHover: nameField.text.trim() ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover
                            colText: nameField.text.trim() ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                            enabled: nameField.text.trim().length > 0
                            onClicked: root.savePage()
                        }
                    }
                }

                Rectangle {
                    visible: root.mode === "create"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                text: Translation.tr("Ready-made collections")
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }

                            Item { Layout.fillWidth: true }

                            RippleButtonWithIcon {
                                implicitHeight: 38
                                implicitWidth: contentImplicitWidth + 24
                                centerContent: true
                                buttonRadius: Appearance.rounding.full
                                materialIcon: "upload_file"
                                mainText: Translation.tr("JSON")
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                colText: Appearance.colors.colOnSecondaryContainer
                                onClicked: {
                                    KeybindsService.openImportDialog();
                                }
                            }
                        }

                        Flow {
                            id: flowContainer
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            spacing: 8

                            Repeater {
                                model: KeybindsService.templates

                                delegate: RippleButton {
                                    id: templateButton
                                    required property var modelData
                                    width: Math.max(150, Math.floor((flowContainer.width - 16) / 3))
                                    height: 50
                                    buttonRadius: Appearance.rounding.normal
                                    colBackground: Appearance.colors.colLayer3
                                    colBackgroundHover: Appearance.colors.colLayer3Hover
                                    colBackgroundActive: Appearance.colors.colLayer3Active
                                    onClicked: {
                                        const pageId = KeybindsService.createFromTemplate(String(modelData.id ?? ""));
                                        if (pageId) {
                                            root.pageChosen(pageId);
                                            root.startClose();
                                        }
                                    }

                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: String(templateButton.modelData.icon ?? "keyboard")
                                            iconSize: Appearance.font.pixelSize.larger
                                            fill: 1
                                            color: Appearance.colors.colPrimary
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 0

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: String(templateButton.modelData.name ?? "")
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.Bold
                                                color: Appearance.colors.colOnSurface
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: Translation.tr("%1 shortcuts").arg(String((templateButton.modelData.keybinds ?? []).length))
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnSurfaceVariant
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSecondaryContainer

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 6
                                spacing: 8

                                MaterialSymbol {
                                    text: "auto_awesome"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnSecondaryContainer
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Import from installed apps")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSecondaryContainer
                                }

                                RippleButtonWithIcon {
                                    implicitHeight: 34
                                    implicitWidth: contentImplicitWidth + 20
                                    centerContent: true
                                    buttonRadius: Appearance.rounding.full
                                    materialIcon: KeybindsService.scanning ? "progress_activity" : "search"
                                    mainText: KeybindsService.scanning ? Translation.tr("Scanning") : Translation.tr("Find")
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    colText: Appearance.colors.colOnPrimary
                                    enabled: !KeybindsService.scanning
                                    onClicked: KeybindsService.scanKnownPrograms()
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            StyledListView {
                                id: detectedList
                                anchors.fill: parent
                                anchors.leftMargin: 2
                                anchors.rightMargin: 2
                                clip: false
                                spacing: 6
                                model: ScriptModel {
                                    values: KeybindsService.detectedSources
                                }

                                delegate: Item {
                                    id: detectedDelegate
                                    required property var modelData
                                    width: detectedList.width
                                    height: 58

                                    RippleButton {
                                        id: detectedButton
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        buttonRadius: Appearance.rounding.normal
                                        colBackground: Appearance.colors.colLayer3
                                        colBackgroundHover: Appearance.colors.colLayer3Hover
                                        enabled: !KeybindsService.importing && Number(detectedDelegate.modelData.count ?? 0) > 0
                                        onClicked: {
                                            KeybindsService.importDetectedSource(detectedDelegate.modelData);
                                        }

                                        contentItem: RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10

                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: String(detectedDelegate.modelData.icon ?? "keyboard")
                                                iconSize: Appearance.font.pixelSize.larger
                                                color: Appearance.colors.colPrimary
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 0

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(detectedDelegate.modelData.name ?? "")
                                                    elide: Text.ElideRight
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Bold
                                                    color: Appearance.colors.colOnSurface
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(detectedDelegate.modelData.detail ?? "")
                                                    elide: Text.ElideRight
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnSurfaceVariant
                                                }
                                            }

                                            Rectangle {
                                                Layout.alignment: Qt.AlignVCenter
                                                implicitWidth: detectedCount.implicitWidth + 16
                                                implicitHeight: 26
                                                radius: Appearance.rounding.full
                                                color: detectedDelegate.modelData.confidence === "partial"
                                                    ? Appearance.colors.colTertiaryContainer
                                                    : Appearance.colors.colPrimaryContainer

                                                StyledText {
                                                    id: detectedCount
                                                    anchors.centerIn: parent
                                                    text: detectedDelegate.modelData.confidence === "partial"
                                                        ? Translation.tr("%1 found · partial").arg(String(detectedDelegate.modelData.count ?? 0))
                                                        : Translation.tr("%1 found").arg(String(detectedDelegate.modelData.count ?? 0))
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: Font.Bold
                                                    color: detectedDelegate.modelData.confidence === "partial"
                                                        ? Appearance.colors.colOnTertiaryContainer
                                                        : Appearance.colors.colOnPrimaryContainer
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            PagePlaceholder {
                                shown: !KeybindsService.scanning && KeybindsService.detectedSources.length === 0
                                anchors.fill: parent
                                icon: KeybindsService.hasScanned ? "search_off" : "manage_search"
                                title: KeybindsService.hasScanned
                                    ? Translation.tr("No shortcut sources found")
                                    : Translation.tr("Nothing scanned yet")
                                description: KeybindsService.hasScanned
                                    ? Translation.tr("No supported configurations with keybindings were detected.")
                                    : Translation.tr("Find reads local config files only. It never launches an editor.")
                                titlePixelSize: Appearance.font.pixelSize.normal
                                descriptionPixelSize: Appearance.font.pixelSize.smallest
                                animateIconOnShow: false
                            }

                            PagePlaceholder {
                                shown: KeybindsService.scanning
                                anchors.fill: parent
                                icon: "progress_activity"
                                title: Translation.tr("Scanning installed apps...")
                                description: Translation.tr("Checking config files for Neovim, Kitty, Tmux, VS Code, and others.")
                                titlePixelSize: Appearance.font.pixelSize.normal
                                descriptionPixelSize: Appearance.font.pixelSize.smallest
                                animateIconOnShow: true
                            }
                        }
                    }
                }
            }
        }
    }
}
