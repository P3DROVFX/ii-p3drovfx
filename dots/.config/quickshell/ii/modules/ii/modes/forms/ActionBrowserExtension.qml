pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.modes
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `browserExtension` action: a known focus extension or one of
 * the user's own (ids + store pages). Shows whether the default browser has it.
 * `row` is the ActionRow this form unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: form
    required property var row

    readonly property string currentId: String(row.obj.id ?? "custom")
    readonly property bool custom: ModeSchema.focusExtensionById(form.currentId) === null
    /// The helper's answer for the current value, or null while it runs.
    property var probe: null

    function refresh() {
        form.probe = null;
        checker.command = ["python3", FocusTools.helper, "check", JSON.stringify(row.obj)];
        checker.running = true;
    }

    function statusText() {
        if (!form.probe)
            return Translation.tr("Checking your browser…");
        const browser = form.probe.browser || Translation.tr("your browser");
        if (!form.probe.family.length)
            return Translation.tr("Your default browser (%1) can't be checked.").arg(form.probe.desktop || "?");
        if (!form.probe.installed)
            return Translation.tr("Not installed in %1.").arg(browser);
        if (!form.probe.enabled)
            return Translation.tr("Installed in %1, but disabled.").arg(browser);
        return form.probe.openUrl.length ? Translation.tr("Installed in %1. The mode will offer to open it.").arg(browser)
            : Translation.tr("Installed in %1 and always on.").arg(browser);
    }

    Component.onCompleted: form.refresh()

    Connections {
        target: form.row
        function onValueChanged() {
            refreshDelay.restart();
        }
    }

    Timer {
        id: refreshDelay
        interval: 400
        onTriggered: form.refresh()
    }

    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    form.probe = JSON.parse(text);
                } catch (e) {
                    form.probe = { family: "", desktop: "", browser: "", installed: false, enabled: false, openUrl: "", storeUrl: "" };
                }
            }
        }
    }

    spacing: 10

    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.gapTiny + 2

        Repeater {
            model: ModeSchema.FOCUS_EXTENSIONS

            ClockChip {
                required property var modelData
                height_: 34
                symbol: "extension"
                label: modelData.name
                selected: form.currentId === modelData.id
                onClicked: row.setValue(ModeSchema.focusExtensionValue(modelData.id))
            }
        }

        ClockChip {
            height_: 34
            symbol: "add"
            label: Translation.tr("Another one")
            selected: form.custom
            onClicked: row.setValue(ModeSchema.focusExtensionValue("custom"))
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: !form.custom && String(row.obj.note ?? "").length > 0
        wrapMode: Text.WordWrap
        text: String(row.obj.note ?? "")
        font.pixelSize: ClockStyle.textNormal
        color: ClockStyle.colOnSurface
    }

    // An extension of the user's own: its ids, store pages and the page to open.
    Repeater {
        model: form.custom ? [
            { key: "name", label: Translation.tr("Name"), hint: Translation.tr("Shown in the notification"), mono: false },
            { key: "firefoxId", label: Translation.tr("Firefox id"), hint: "addon@example.com", mono: true },
            { key: "firefoxUrl", label: Translation.tr("Firefox page"), hint: "https://addons.mozilla.org/…", mono: true },
            { key: "chromeId", label: Translation.tr("Chrome id"), hint: Translation.tr("32 letters"), mono: true },
            { key: "chromeUrl", label: Translation.tr("Chrome page"), hint: "https://chromewebstore.google.com/…", mono: true },
            { key: "page", label: Translation.tr("Page to open"), hint: Translation.tr("options.html, or empty when always on"), mono: true }
        ] : []

        RowLayout {
            id: field
            required property var modelData
            Layout.fillWidth: true
            spacing: 10

            FormLabel {
                Layout.preferredWidth: 96
                text: field.modelData.label
            }
            PlainField {
                Layout.fillWidth: true
                monospace: field.modelData.mono
                value: String(form.row.obj[field.modelData.key] ?? "")
                placeholder: field.modelData.hint
                onCommitted: v => {
                    const patch = {};
                    patch[field.modelData.key] = v.trim();
                    form.row.patchValue(patch);
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            text: !form.probe ? "hourglass_top" : (form.probe.installed && form.probe.enabled ? "check_circle" : "info")
            iconSize: ClockStyle.iconSmall + 2
            color: form.probe?.installed && form.probe?.enabled ? ClockStyle.colPrimary : ClockStyle.colOnSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: form.statusText()
            font.pixelSize: ClockStyle.textNormal
            color: ClockStyle.colOnSurfaceVariant
        }

        SmallButton {
            visible: !!form.probe && !form.probe.installed && form.probe.storeUrl.length > 0
            buttonText: Translation.tr("Install")
            onClicked: Qt.openUrlExternally(form.probe.storeUrl)
        }
    }

    FormHint {
        text: Translation.tr("Extensions can't be switched on from outside the browser. When the mode starts, a notification offers a button that opens the extension (or its store page if it's missing). Remove this action to skip it.")
    }
}
