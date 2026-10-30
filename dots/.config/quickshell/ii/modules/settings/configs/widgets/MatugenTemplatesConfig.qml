pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Matugen templates and the theme catalog, edited in ~/.config/matugen/config.toml
 * through scripts/colors/matugen_templates.py (which keeps the user's comments and
 * validates every write). Changes reach apps on the next palette change, or now
 * through "Regenerate".
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property string script: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/matugen_templates.py`)

    property var templates: []
    property var themes: []
    property string configPath: ""
    property string templatesDir: ""
    property string configError: ""
    property bool loaded: false

    property string expandedName: ""      // template whose editor is open
    property string confirmRemove: ""     // template waiting for the second click
    property string pendingTheme: ""      // catalog card with a running action
    property bool addOpen: false
    property string message: ""
    property bool messageIsError: false
    property var testResults: ({})        // name → { ok, text }

    readonly property int activeCount: templates.filter(t => t.enabled).length

    // ── Script calls, one at a time so every write sees the previous one ──────
    property var _queue: []
    property var _current: null

    function call(args, done) {
        _queue = _queue.concat([{ args: args, done: done }]);
        _next();
    }

    function _next() {
        if (_current || _queue.length === 0)
            return;
        _current = _queue[0];
        _queue = _queue.slice(1);
        runner.exec(["python3", "-I", script, ..._current.args]);
    }

    function _finish(text) {
        const job = _current;
        _current = null;
        let payload;
        try {
            payload = JSON.parse(text.trim().split("\n").pop());
        } catch (e) {
            payload = { ok: false, error: Translation.tr("The template manager did not answer"), code: "no_output" };
        }
        if (job && job.done)
            job.done(payload);
        _next();
    }

    function refresh() {
        call(["list"], r => {
            if (!r.ok)
                return;
            templates = r.templates;
            themes = r.themes;
            configPath = r.config;
            templatesDir = r.templatesDir;
            configError = r.configError;
            loaded = true;
        });
    }

    // Mutations report, then reload the list either way.
    function mutate(args, successText, after) {
        call(args, r => {
            if (r.ok) {
                notify(successText, false);
            } else {
                notify(r.error, true);
            }
            if (after)
                after(r);
            refresh();
        });
    }

    function notify(text, isError) {
        message = text;
        messageIsError = isError;
        messageTimer.restart();
    }

    function regenerate() {
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"]);
        notify(Translation.tr("Regenerating colors for every template…"), false);
    }

    function openPath(path) {
        Qt.openUrlExternally("file://" + path.replace(/^~(?=\/|$)/, FileUtils.trimFileProtocol(Directories.home)));
    }

    function setTestResult(name, ok, text) {
        const copy = Object.assign({}, testResults);
        copy[name] = { ok: ok, text: text };
        testResults = copy;
    }

    Process {
        id: runner
        stdout: StdioCollector {
            onStreamFinished: subPageRoot._finish(text)
        }
    }

    // The file dialog blocks until closed, so it never holds up the queue.
    Process {
        id: picker
        property var target: null
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try {
                    r = JSON.parse(text.trim());
                } catch (e) {
                    return;
                }
                if (!r.ok)
                    subPageRoot.notify(r.error, true);
                else if (r.path && picker.target)
                    picker.target.text = r.path;
            }
        }
    }

    function pickInto(field, save) {
        picker.target = field;
        picker.exec(["python3", "-I", script, "pick-file", ...(save ? ["--save"] : [])]);
    }

    Timer {
        id: messageTimer
        interval: 6000
        onTriggered: subPageRoot.message = ""
    }

    Component.onCompleted: refresh()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("App templates")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Summary ────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: summaryColumn.implicitHeight + 40
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colPrimaryContainer

            ColumnLayout {
                id: summaryColumn
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    MaterialShapeWrappedMaterialSymbol {
                        text: "format_color_fill"
                        iconSize: 24
                        padding: 12
                        fill: 1
                        shape: MaterialShape.Shape.Flower
                        color: Appearance.colors.colPrimary
                        colSymbol: Appearance.colors.colOnPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: !subPageRoot.loaded ? Translation.tr("Reading Matugen config…")
                                : Translation.tr("%1 of %2 templates active").arg(subPageRoot.activeCount).arg(subPageRoot.templates.length)
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnPrimaryContainer
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Each template turns the palette into a file an app reads. They follow every wallpaper or scheme change.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.8
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    AppRowButton {
                        symbol: "refresh"
                        label: Translation.tr("Regenerate now")
                        tooltip: Translation.tr("Render every active template with the current palette")
                        filled: true
                        onClicked: subPageRoot.regenerate()
                    }
                    AppRowButton {
                        symbol: "folder_open"
                        label: Translation.tr("Templates folder")
                        enabled: subPageRoot.templatesDir.length > 0
                        onClicked: subPageRoot.openPath(subPageRoot.templatesDir)
                    }
                    AppRowButton {
                        symbol: "description"
                        label: Translation.tr("config.toml")
                        tooltip: subPageRoot.configPath
                        enabled: subPageRoot.configPath.length > 0
                        onClicked: subPageRoot.openPath(subPageRoot.configPath)
                    }
                }
            }
        }

        // Errors and confirmations, where the eye already is.
        Rectangle {
            Layout.fillWidth: true
            visible: subPageRoot.message.length > 0 || subPageRoot.configError.length > 0
            implicitHeight: messageRow.implicitHeight + 24
            radius: Appearance.rounding.large
            readonly property bool isError: subPageRoot.configError.length > 0 || subPageRoot.messageIsError
            color: isError ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer

            RowLayout {
                id: messageRow
                anchors.fill: parent
                anchors.margins: 12
                anchors.leftMargin: 16
                spacing: 12

                MaterialSymbol {
                    text: parent.parent.isError ? "error" : "check_circle"
                    iconSize: Appearance.font.pixelSize.larger
                    color: parent.parent.isError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: subPageRoot.configError.length > 0
                        ? Translation.tr("config.toml has a syntax error, so nothing can be changed here until it is fixed:\n%1").arg(subPageRoot.configError)
                        : subPageRoot.message
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: parent.parent.isError ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        // ── Theme catalog ──────────────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 12
            title: Translation.tr("Ready-made themes")
            symbol: "palette"
            description: Translation.tr("One click adds the template; the app then needs the one line shown on its card.")

            Item {
                id: catalog
                Layout.fillWidth: true
                implicitHeight: catalogFlow.implicitHeight

                readonly property int gap: 8
                readonly property int columns: Math.max(1, Math.floor((width + gap) / (250 + gap)))
                readonly property int cardWidth: Math.floor((width - gap * (columns - 1)) / columns)

                Flow {
                    id: catalogFlow
                    width: parent.width
                    spacing: catalog.gap

                    Repeater {
                        model: subPageRoot.themes
                        delegate: ThemeCard {
                            host: subPageRoot
                            width: catalog.cardWidth
                        }
                    }
                }
            }
        }

        // ── Templates ──────────────────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 12
            title: Translation.tr("Templates")
            symbol: "data_object"
            description: Translation.tr("A turned-off template stays in config.toml, commented out, and comes back unchanged.")

            AppSettingRow {
                symbol: subPageRoot.addOpen ? "close" : "add"
                title: subPageRoot.addOpen ? Translation.tr("New template") : Translation.tr("Add a template")
                description: subPageRoot.addOpen ? "" : Translation.tr("Theme any app that reads a config file")
                clickable: !subPageRoot.addOpen
                enabled: subPageRoot.configError.length === 0
                onClicked: subPageRoot.addOpen = true

                below: Loader {
                    Layout.fillWidth: true
                    active: subPageRoot.addOpen
                    visible: active
                    sourceComponent: AddForm {
                        host: subPageRoot
                    }
                }
            }

            Repeater {
                model: subPageRoot.templates
                delegate: TemplateRow {
                    host: subPageRoot
                }
            }
        }

        Item {
            implicitHeight: 24
        }
    }

    // ── Pieces ─────────────────────────────────────────────────────────────

    component PathField: RowLayout {
        id: pathField
        required property var host
        property alias text: field.text
        property alias placeholder: field.placeholderText
        property bool save: false
        Layout.fillWidth: true
        spacing: 8

        MaterialTextField {
            id: field
            Layout.fillWidth: true
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
        }
        RippleButton {
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: pathField.host.pickInto(field, pathField.save)

            MaterialSymbol {
                anchors.centerIn: parent
                text: "folder_open"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledToolTip {
                text: Translation.tr("Browse")
            }
        }
    }

    component AddForm: ColumnLayout {
        id: form
        required property var host
        spacing: 10

        property bool createNew: true
        readonly property string slug: nameField.text.trim().toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 64)
        readonly property string outputName: {
            const out = outputField.text.trim();
            const base = out.split("/").pop();
            return base.length > 0 ? base : "template.txt";
        }
        readonly property string suggestedInput: `${form.host.templatesDir}/${slug}/${outputName}`
        readonly property string inputPath: createNew ? suggestedInput : inputField.text.trim()
        readonly property bool valid: slug.length > 0 && outputField.text.trim().length > 0 && inputPath.length > 0
        property bool saving: false

        MaterialTextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Name (e.g. kitty, my-editor)")
        }

        PathField {
            id: outputField
            host: form.host
            save: true
            placeholder: Translation.tr("File the app reads (e.g. ~/.config/app/colors.conf)")
        }

        AppChoiceRow {
            Layout.fillWidth: true
            symbol: "draft"
            title: Translation.tr("Template file")
            options: [
                { label: Translation.tr("Start a new one"), value: true, icon: "note_add" },
                { label: Translation.tr("Use an existing file"), value: false, icon: "upload_file" }
            ]
            currentValue: form.createNew
            onSelected: value => form.createNew = value
        }

        StyledText {
            Layout.fillWidth: true
            visible: form.createNew
            text: form.slug.length > 0 ? Translation.tr("A starter file with the color variables is created at %1").arg(form.suggestedInput)
                : Translation.tr("A starter file with the color variables is created in the templates folder")
            wrapMode: Text.WrapAnywhere
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        PathField {
            id: inputField
            host: form.host
            visible: !form.createNew
            placeholder: Translation.tr("Template file with Matugen tags")
        }

        MaterialTextField {
            id: hookField
            Layout.fillWidth: true
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            placeholderText: Translation.tr("Command after rendering, optional (e.g. pkill -USR1 app)")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.fillWidth: true
            }
            AppRowButton {
                label: Translation.tr("Cancel")
                onClicked: form.host.addOpen = false
            }
            AppRowButton {
                symbol: "add"
                label: Translation.tr("Add template")
                filled: true
                enabled: form.valid && !form.saving
                onClicked: {
                    form.saving = true;
                    const args = ["add", form.slug, "--input", form.inputPath, "--output", outputField.text.trim(), "--post-hook", hookField.text.trim()];
                    if (form.createNew)
                        args.push("--create");
                    form.host.mutate(args, Translation.tr("Added %1. Edit its template file, then press Test.").arg(form.slug), r => {
                        form.saving = false;
                        if (r.ok) {
                            form.host.addOpen = false;
                            form.host.expandedName = r.name;
                        }
                    });
                }
            }
        }
    }

    component ThemeCard: Rectangle {
        id: card
        required property var host
        required property var modelData
        readonly property bool installed: modelData.installed
        readonly property bool busy: card.host.pendingTheme === modelData.id

        implicitHeight: cardColumn.implicitHeight + 32
        radius: Appearance.rounding.large
        color: installed ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    text: card.modelData.symbol
                    iconSize: 20
                    padding: 9
                    fill: card.installed ? 1 : 0
                    shape: card.installed ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                    color: card.installed ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: card.installed ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: card.installed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: card.installed ? (card.modelData.enabled ? Translation.tr("Active") : Translation.tr("Turned off"))
                            : card.modelData.appFound ? Translation.tr("Installed on this system") : Translation.tr("App not found")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr(card.installed ? card.modelData.setup : card.modelData.description)
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: card.installed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }
                AppRowButton {
                    visible: card.installed && !card.modelData.fromCatalog
                    symbol: "edit"
                    label: Translation.tr("Yours: %1").arg(card.modelData.templateName)
                    tooltip: Translation.tr("A template of yours already writes this file")
                    onClicked: card.host.expandedName = card.modelData.templateName
                }
                AppRowButton {
                    visible: !card.installed || card.modelData.fromCatalog
                    symbol: card.installed ? "delete" : "download"
                    label: card.busy ? Translation.tr("Working…") : card.installed ? Translation.tr("Remove") : Translation.tr("Add")
                    danger: card.installed
                    filled: !card.installed
                    enabled: !card.busy && card.host.configError.length === 0
                    onClicked: {
                        const id = card.modelData.id;
                        const name = card.modelData.name;
                        card.host.pendingTheme = id;
                        card.host.mutate([card.installed ? "uninstall-theme" : "install-theme", id],
                            card.installed ? Translation.tr("Removed the %1 theme").arg(name)
                                : Translation.tr("Added the %1 theme. It applies on the next color change, or press Regenerate now.").arg(name),
                            () => card.host.pendingTheme = "");
                    }
                }
            }
        }
    }

    component TemplateRow: AppSettingRow {
        id: tRow
        required property var host
        required property var modelData
        readonly property string name: modelData.name
        readonly property bool open: tRow.host.expandedName === name
        readonly property var test: tRow.host.testResults[name] ?? null

        symbol: modelData.locked ? "lock" : !modelData.inputExists ? "warning" : modelData.theme.length > 0 ? "palette" : "description"
        title: modelData.name + (modelData.core ? "  ·  ii" : "") + (!modelData.enabled ? "  ·  " + Translation.tr("off") : "")
        description: !modelData.inputExists ? Translation.tr("Template file missing: %1").arg(modelData.input)
            : "→ " + modelData.output
        help: modelData.locked ? Translation.tr("The shell paints itself from this template, so it can't be changed here")
            : !modelData.editable ? Translation.tr("Written in a form this page can't edit safely; change it in config.toml")
            : ""
        clickable: modelData.editable
        onClicked: {
            tRow.host.expandedName = tRow.open ? "" : tRow.name;
            tRow.host.confirmRemove = "";
        }

        MaterialSymbol {
            visible: tRow.modelData.editable
            text: "expand_more"
            rotation: tRow.open ? 180 : 0
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
        StyledSwitch {
            visible: tRow.modelData.editable
            enabled: tRow.host.configError.length === 0
            checked: tRow.modelData.enabled
            onToggled: tRow.host.mutate([checked ? "enable" : "disable", tRow.name],
                checked ? Translation.tr("%1 is on").arg(tRow.name) : Translation.tr("%1 is off; Matugen skips it").arg(tRow.name))
        }

        below: Loader {
            Layout.fillWidth: true
            active: tRow.open
            visible: active
            sourceComponent: ColumnLayout {
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    visible: tRow.modelData.core
                    text: Translation.tr("Shipped with ii: other parts of the shell may expect this file.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colTertiary
                }

                MaterialTextField {
                    id: nameEdit
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Name")
                    text: tRow.name
                }
                PathField {
                    id: inputEdit
                    host: tRow.host
                    placeholder: Translation.tr("Template file")
                    text: tRow.modelData.input
                }
                PathField {
                    id: outputEdit
                    host: tRow.host
                    save: true
                    placeholder: Translation.tr("Output file")
                    text: tRow.modelData.output
                }
                MaterialTextField {
                    id: hookEdit
                    Layout.fillWidth: true
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    placeholderText: Translation.tr("Command after rendering (optional)")
                    text: tRow.modelData.postHook
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: tRow.modelData.extraKeys.length > 0
                    text: Translation.tr("Also set in config.toml and kept as is: %1").arg(tRow.modelData.extraKeys.join(", "))
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    AppRowButton {
                        symbol: "save"
                        label: Translation.tr("Save")
                        filled: true
                        enabled: nameEdit.text.trim() !== tRow.name || inputEdit.text.trim() !== tRow.modelData.input
                            || outputEdit.text.trim() !== tRow.modelData.output || hookEdit.text.trim() !== tRow.modelData.postHook
                        onClicked: {
                            const newName = nameEdit.text.trim();
                            const args = ["update", tRow.name, "--input", inputEdit.text.trim(), "--output", outputEdit.text.trim(), "--post-hook", hookEdit.text.trim()];
                            if (newName !== tRow.name)
                                args.push("--rename", newName);
                            tRow.host.mutate(args, Translation.tr("Saved %1").arg(newName), r => {
                                if (r.ok)
                                    tRow.host.expandedName = r.name;
                            });
                        }
                    }
                    AppRowButton {
                        symbol: "science"
                        label: Translation.tr("Test")
                        tooltip: Translation.tr("Render with the current palette into a temporary file; no hooks run")
                        enabled: tRow.modelData.inputExists
                        onClicked: {
                            const name = tRow.name;
                            tRow.host.setTestResult(name, true, Translation.tr("Rendering…"));
                            tRow.host.call(["test", name], r => tRow.host.setTestResult(name, r.ok,
                                r.ok ? Translation.tr("Rendered %1 lines (%2 mode):").arg(r.lines).arg(r.mode) + "\n" + r.preview : r.error));
                        }
                    }
                    AppRowButton {
                        symbol: "edit_note"
                        label: Translation.tr("Edit template")
                        enabled: tRow.modelData.inputExists
                        onClicked: tRow.host.openPath(tRow.modelData.input)
                    }
                    AppRowButton {
                        readonly property bool confirming: tRow.host.confirmRemove === tRow.name
                        symbol: "delete"
                        label: confirming ? (tRow.modelData.managedFile ? Translation.tr("Remove it and its file") : Translation.tr("Confirm remove"))
                            : Translation.tr("Remove")
                        danger: true
                        filled: confirming
                        onClicked: {
                            if (!confirming) {
                                tRow.host.confirmRemove = tRow.name;
                                return;
                            }
                            tRow.host.confirmRemove = "";
                            tRow.host.expandedName = "";
                            tRow.host.mutate(["remove", tRow.name, ...(tRow.modelData.managedFile ? ["--delete-input"] : [])],
                                Translation.tr("Removed %1").arg(tRow.name));
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: tRow.test !== null
                    implicitHeight: testText.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: tRow.test && !tRow.test.ok ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHighest

                    StyledText {
                        id: testText
                        anchors.fill: parent
                        anchors.margins: 10
                        text: tRow.test ? tRow.test.text : ""
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 24
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: tRow.test && !tRow.test.ok ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
