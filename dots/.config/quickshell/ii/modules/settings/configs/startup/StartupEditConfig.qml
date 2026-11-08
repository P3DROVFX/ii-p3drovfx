import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * Startup & Services → add or edit one startup entry. Adding picks where the command comes
 * from (an installed app, a script/file through the system file dialog, or typed), then the
 * name, the command (always editable, it is what lands in execs.lua) and a delay. Editing
 * shows the name and command of the line; a delay is part of the command there.
 */
ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    readonly property var target: StartupManager.editTarget
    readonly property bool editing: root.target !== null
    // "app" | "file" | "command"
    property string source: "app"
    property string appQuery: ""
    property string pickedFile: ""
    property bool fileExecutable: true
    property int delay: 0

    Component.onCompleted: {
        if (root.editing) {
            nameField.text = root.target.name ?? "";
            commandField.text = root.target.command ?? "";
            root.source = "command";
        } else if (StartupManager.addPreset) {
            nameField.text = StartupManager.addPreset.name ?? "";
            commandField.text = StartupManager.addPreset.command ?? "";
            root.source = "command";
        }
    }

    readonly property bool canSave: commandField.text.trim().length > 0 && !StartupManager.busy

    function save() {
        const name = nameField.text.trim();
        const cmd = commandField.text.trim();
        if (root.editing)
            StartupManager.edit(root.target, name, cmd);
        else
            StartupManager.add(name, cmd, root.delay);
        root.goBack();
    }

    function shellQuote(s) {
        return /^[A-Za-z0-9_\/.,:+=@%-]+$/.test(s) ? s : "'" + s.replace(/'/g, "'\\''") + "'";
    }
    function useFile(path) {
        root.pickedFile = path;
        execCheck.command = ["test", "-x", path];
        execCheck.running = true;
    }
    function commandForFile(path, executable) {
        const q = root.shellQuote(path.replace(/^~/, "$HOME"));
        if (executable)
            return q;
        if (/\.(sh|bash)$/.test(path))
            return "bash " + q;
        if (/\.py$/.test(path))
            return "python3 " + q;
        return "xdg-open " + q;
    }
    function baseName(path) {
        return path.split("/").pop().replace(/\.(sh|bash|py|AppImage|appimage)$/, "");
    }

    Process {
        id: execCheck
        onExited: (code, status) => {
            root.fileExecutable = code === 0;
            commandField.text = root.commandForFile(root.pickedFile, root.fileExecutable);
            if (nameField.text.trim() === "")
                nameField.text = root.baseName(root.pickedFile);
        }
    }
    Process {
        id: picker
        command: ["bash", "-c", "if command -v kdialog >/dev/null 2>&1; then kdialog --getopenfilename \"$HOME\" 2>/dev/null; "
            + "elif command -v zenity >/dev/null 2>&1; then zenity --file-selection 2>/dev/null; fi"]
        stdout: StdioCollector {
            id: pickerOut
        }
        onExited: (code, status) => {
            const path = pickerOut.text.trim();
            if (code === 0 && path !== "")
                root.useFile(path);
        }
    }
    Process {
        id: chmodProc
        onExited: (code, status) => {
            if (code === 0)
                root.useFile(root.pickedFile);
        }
    }

    // ── header ──
    ConfigSubPageHeader {
        visible: root.showBackButton
        title: root.editing ? Translation.tr("Edit startup entry") : Translation.tr("Add to startup")
        onBack: root.goBack()
    }

    // ── where it comes from (adding only) ──
    Rectangle {
        Layout.fillWidth: true
        visible: !root.editing
        implicitHeight: sourceCol.implicitHeight + 40
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: sourceCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 20
            }
            spacing: 14

            Item {
                id: sourceHeader
                Layout.fillWidth: true
                readonly property bool stacked: width < 600
                implicitHeight: stacked ? titleRow.height + 8 + 48 : Math.max(titleRow.height, 48)

                RowLayout {
                    id: titleRow
                    width: sourceHeader.stacked ? sourceHeader.width : sourceHeader.width - sourceToggle.width - 16
                    spacing: 14
                    MaterialShapeWrappedMaterialSymbol {
                        text: "rocket_launch"
                        iconSize: 24
                        padding: 12
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("What starts")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.source === "app" ? Translation.tr("An installed app, by its launcher entry")
                                : root.source === "file" ? Translation.tr("A script, AppImage or any file")
                                : Translation.tr("Any shell command")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }

                ConnectedToggle {
                    id: sourceToggle
                    x: sourceHeader.stacked ? 0 : sourceHeader.width - width
                    y: sourceHeader.stacked ? titleRow.height + 8 : (sourceHeader.height - height) / 2
                    width: sourceHeader.stacked ? sourceHeader.width : 380
                    current: root.source
                    model: [
                        { key: "app", label: Translation.tr("App"), symbol: "apps", shape: MaterialShape.Shape.Cookie9Sided },
                        { key: "file", label: Translation.tr("File"), symbol: "draft", shape: MaterialShape.Shape.Clover4Leaf },
                        { key: "command", label: Translation.tr("Command"), symbol: "terminal", shape: MaterialShape.Shape.SoftBurst }
                    ]
                    onSelected: key => root.source = key
                }
            }

            // ── app picker ──
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.source === "app"
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: height / 2
                    color: Appearance.colors.colLayer2
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10
                        MaterialSymbol {
                            text: "search"
                            iconSize: 20
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledTextInput {
                            id: appSearch
                            Layout.fillWidth: true
                            clip: true
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.small
                            onTextChanged: root.appQuery = text
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: appSearch.text.length === 0
                                text: Translation.tr("Search apps")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }

                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(appGrid.implicitHeight, 300)
                    contentHeight: appGrid.implicitHeight
                    clip: true

                    Grid {
                        id: appGrid
                        width: parent.width
                        spacing: 6
                        columns: Math.max(2, Math.floor((width + spacing) / (180 + spacing)))
                        readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
                        readonly property var apps: {
                            const q = root.appQuery.trim().toLowerCase();
                            return Array.from(DesktopEntries.applications.values)
                                .filter(a => !a.noDisplay && (q === "" || a.name.toLowerCase().includes(q) || (a.id ?? "").toLowerCase().includes(q)))
                                .sort((a, b) => a.name.localeCompare(b.name))
                                .slice(0, 60);
                        }

                        Repeater {
                            model: appGrid.apps
                            delegate: RippleButton {
                                id: appButton
                                required property var modelData
                                readonly property string cmd: Array.from(modelData.command ?? []).map(w => root.shellQuote(String(w))).join(" ")
                                readonly property bool chosen: commandField.text === appButton.cmd
                                width: appGrid.cellWidth
                                implicitHeight: 52
                                buttonRadius: Appearance.rounding.normal
                                colBackground: appButton.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                                colBackgroundHover: appButton.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                onClicked: {
                                    commandField.text = appButton.cmd;
                                    nameField.text = modelData.name;
                                }
                                contentItem: RowLayout {
                                    spacing: 10
                                    IconImage {
                                        Layout.leftMargin: 10
                                        implicitSize: 28
                                        source: Quickshell.iconPath(appButton.modelData.icon, "application-x-executable")
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 10
                                        text: appButton.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: appButton.chosen ? Font.DemiBold : Font.Normal
                                        color: appButton.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── file picker ──
            RowLayout {
                Layout.fillWidth: true
                visible: root.source === "file"
                spacing: 10

                RippleButton {
                    implicitHeight: 48
                    implicitWidth: pickRow.implicitWidth + 36
                    buttonRadius: height / 2
                    buttonRadiusPressed: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    enabled: !picker.running
                    onClicked: picker.running = true
                    contentItem: Item {
                        RowLayout {
                            id: pickRow
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "folder_open"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: Translation.tr("Choose file")
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.pickedFile !== "" ? root.pickedFile : Translation.tr("Scripts run with their interpreter; other files open with their default app")
                        font.family: root.pickedFile !== "" ? Appearance.font.family.monospace : Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.pickedFile !== "" ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        elide: Text.ElideMiddle
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.pickedFile !== "" && !root.fileExecutable
                        text: Translation.tr("Not executable, so it runs through an interpreter")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                ColorsChip {
                    visible: root.pickedFile !== "" && !root.fileExecutable
                    symbol: "verified_user"
                    label: Translation.tr("Make executable")
                    onClicked: {
                        chmodProc.command = ["chmod", "+x", root.pickedFile];
                        chmodProc.running = true;
                    }
                }
            }
        }
    }

    // ── the entry itself ──
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: entryCol.implicitHeight + 40
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: entryCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 20
            }
            spacing: 12

            Item {
                id: fields
                Layout.fillWidth: true
                readonly property bool stacked: width < 640
                implicitHeight: stacked ? nameField.implicitHeight * 2 + 10 : nameField.implicitHeight

                MaterialTextField {
                    id: nameField
                    x: 0
                    width: fields.stacked ? fields.width : Math.min(280, fields.width * 0.35)
                    placeholderText: Translation.tr("Name (optional)")
                }
                MaterialTextField {
                    id: commandField
                    x: fields.stacked ? 0 : nameField.width + 10
                    y: fields.stacked ? nameField.implicitHeight + 10 : 0
                    width: fields.stacked ? fields.width : fields.width - nameField.width - 10
                    placeholderText: Translation.tr("Command")
                    font.family: Appearance.font.family.monospace
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    visible: !root.editing
                    Layout.rightMargin: 4
                    text: Translation.tr("Wait")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                Repeater {
                    model: root.editing ? [] : [0, 3, 10, 30]
                    delegate: ColorsChip {
                        required property int modelData
                        label: modelData === 0 ? Translation.tr("No delay") : Translation.tr("%1 s").arg(modelData)
                        chosen: root.delay === modelData
                        onClicked: root.delay = modelData
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                RippleButton {
                    implicitHeight: 40
                    implicitWidth: testRow.implicitWidth + 30
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    enabled: commandField.text.trim().length > 0
                    opacity: enabled ? 1 : 0.5
                    onClicked: StartupManager.runNow(commandField.text.trim())
                    contentItem: Item {
                        RowLayout {
                            id: testRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "play_arrow"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: Translation.tr("Try it now")
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                RippleButton {
                    implicitHeight: 40
                    implicitWidth: saveRow.implicitWidth + 32
                    buttonRadius: height / 2
                    buttonRadiusPressed: Appearance.rounding.small
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    enabled: root.canSave
                    opacity: enabled ? 1 : 0.5
                    onClicked: root.save()
                    contentItem: Item {
                        RowLayout {
                            id: saveRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "check"
                                iconSize: 18
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: root.editing ? Translation.tr("Save") : Translation.tr("Add to startup")
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("It runs on the next login through the shell, from your home folder. Commands that stay in the foreground are fine.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }
    }
}
