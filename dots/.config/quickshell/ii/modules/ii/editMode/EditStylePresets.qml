import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Presets, at the top of the Style catalogue: save the look on the card,
 * apply one that was saved before, take the last one back, and the way to
 * the store.
 *
 * Edit Mode is where a look gets made, so it is the natural place to keep
 * one: you have just arranged everything and the card is showing exactly
 * what the preset will hold. The list is the same folder Settings' Preset
 * Manager reads, through the same script, so a preset saved here is there
 * and the other way round.
 *
 * Applying replaces the whole config, which is more than the mode's history
 * can walk back one step at a time: the stack is cleared and "Undo preset"
 * - the snapshot the script takes before it merges - stands in for it. The
 * card applies directly, keeping this compact catalogue focused on choosing
 * a look rather than opening another set of controls.
 *
 * The saved looks are a two-row carousel (EditPresetCarousel) that scrolls
 * sideways, ordered by the connected group in the header - last applied, by
 * name or newest saved - with the order remembered in Persistent.
 *
 * The store itself stays in Settings. It needs a sign-in, publishing, diffs
 * and a review dialog, which is a window's worth of surface; the row here
 * says how many installed presets have an update waiting and hands off.
 */
ColumnLayout {
    id: root

    // The name field needs the keyboard, and on this surface the keyboard is
    // held only on request (see EditModeDrawer's search field).
    signal fieldFocusRequested(Item field)
    signal fieldFocusReleased()

    spacing: 3

    // [{name, wallpaper, configVersion}], as the script lists them.
    property var presets: []
    property bool saving: false
    readonly property string activePreset: PresetStore.activePreset
    readonly property string presetsScript: `${Directories.scriptPath}/presets.sh`

    // ── Order ────────────────────────────────────────────────────────────────
    // Remembered across sessions (Persistent, not Config: a preset carries
    // Config, and applying one must not change how the list is read).
    readonly property string sortKey: Persistent.ready ? String(Persistent.states.background.presetSort ?? "recent") : "recent"
    readonly property bool sortReversed: Persistent.ready ? (Persistent.states.background.presetSortReversed ?? false) : false
    // Bumped on every re-order, so the cards re-deal instead of jumping.
    property int sortEpoch: 0

    function setSort(key, reversed) {
        if (!Persistent.ready)
            return;
        Persistent.states.background.presetSort = key;
        Persistent.states.background.presetSortReversed = reversed;
        root.sortEpoch++;
    }

    function _byName(a, b) {
        return String(a.name).localeCompare(String(b.name), undefined, { "sensitivity": "base", "numeric": true });
    }

    // Each order reads naturally first - the last used, A to Z, the newest -
    // and the direction button turns it around.
    readonly property var sortedPresets: {
        const list = root.presets.slice();
        if (root.sortKey === "name") {
            list.sort(root._byName);
        } else if (root.sortKey === "newest") {
            list.sort((a, b) => (Number(b.modified ?? 0) - Number(a.modified ?? 0)) || root._byName(a, b));
        } else {
            // Never applied: after the used ones, by name.
            const recents = Array.from(PresetStore.recentPresets);
            const rank = p => {
                const i = recents.indexOf(p.name);
                return i >= 0 ? i : recents.length;
            };
            list.sort((a, b) => (rank(a) - rank(b)) || root._byName(a, b));
        }
        if (root.sortReversed)
            list.reverse();
        return list;
    }

    function refresh() {
        listProc.running = false;
        listProc.running = true;
    }

    function cleanName(text) {
        return String(text ?? "").replace(/[\/\\"]/g, "").trim();
    }

    function save() {
        const name = root.cleanName(nameField.text);
        if (name === "")
            return;
        Quickshell.execDetached([root.presetsScript, "save", name]);
        nameField.text = "";
        root.saving = false;
        root.fieldFocusReleased();
        refreshTimer.restart();
    }

    function applyPreset(name) {
        if (root.activePreset === name || PresetStore.busy)
            return;
        PresetStore.applyPreset(name);
    }

    Component.onCompleted: {
        PresetStore.ensureLoaded();
        root.refresh();
    }

    Connections {
        target: PresetStore
        function onPresetFilesChanged() {
            refreshTimer.restart();
        }
        function onApplyFinished(name, ok) {
            refreshTimer.restart();
        }
        function onRevertFinished(ok) {
            refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 900
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: [root.presetsScript, "list"]
        property var collected: []
        onRunningChanged: {
            if (listProc.running)
                listProc.collected = [];
        }
        stdout: SplitParser {
            onRead: data => {
                // One JSON object per line - and a chunk may carry several
                // lines at once, so the payload is split before it is parsed.
                for (const line of String(data).split("\n")) {
                    const text = line.trim();
                    if (text === "")
                        continue;
                    try {
                        listProc.collected.push(JSON.parse(text));
                    } catch (e) {
                        console.log("[EditStylePresets] bad preset line:", text);
                    }
                }
            }
        }
        onExited: root.presets = listProc.collected
    }

    // ── Header: the count, and the order ─────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        spacing: 8

        StyledText {
            text: Translation.tr("Presets")
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.variableAxes: Appearance.font.variableAxes.titleRounded
            color: Appearance.colors.colOnSurface
        }

        // The one number this block is about, in the shell's condensed digits.
        StyledText {
            visible: root.presets.length > 0
            text: String(root.presets.length)
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.hugeass
            font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
            color: Appearance.colors.colPrimary
        }

        Item {
            Layout.fillWidth: true
        }

        EditPresetSortGroup {
            visible: root.presets.length > 1
            current: root.sortKey
            reversed: root.sortReversed
            onPicked: key => root.setSort(key, key === root.sortKey ? !root.sortReversed : false)
        }
    }

    // ── Save ─────────────────────────────────────────────────────────────────
    EditPanelRow {
        Layout.fillWidth: true
        first: true
        last: !root.saving
        symbol: "save"
        title: Translation.tr("Save the current look")
        subtitle: Translation.tr("Layout, wallpaper, colours and settings, as a preset")
        trailingKind: root.saving ? "none" : "add"
        selected: root.saving
        onActivated: {
            root.saving = !root.saving;
            if (root.saving)
                root.fieldFocusRequested(nameField);
            else
                root.fieldFocusReleased();
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: root.saving
        implicitHeight: 52
        color: Appearance.colors.colLayer1
        bottomLeftRadius: Appearance.rounding.normal
        bottomRightRadius: Appearance.rounding.normal

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            ToolbarTextField {
                id: nameField
                Layout.fillWidth: true
                Layout.fillHeight: true
                colBackground: Appearance.colors.colLayer2
                placeholderText: Translation.tr("Preset name")
                onPressed: root.fieldFocusRequested(nameField)
                onAccepted: root.save()
                Keys.onEscapePressed: event => {
                    if (nameField.text !== "") {
                        nameField.text = "";
                        return;
                    }
                    root.saving = false;
                    root.fieldFocusReleased();
                    event.accepted = true;
                }
            }

            RippleButton {
                Layout.fillHeight: true
                implicitWidth: 44
                buttonRadius: Appearance.rounding.full
                enabled: root.cleanName(nameField.text) !== ""
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: root.save()
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "check"
                    iconSize: 20
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // ── The saved looks ──────────────────────────────────────────────────────
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.topMargin: 6
        visible: root.presets.length === 0 && !listProc.running
        text: Translation.tr("Nothing saved yet.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnSurfaceVariant
    }

    EditPresetCarousel {
        id: carousel
        Layout.fillWidth: true
        Layout.topMargin: 8
        visible: root.presets.length > 0
        presets: root.sortedPresets
        activePreset: root.activePreset
        sortEpoch: root.sortEpoch
        onApplyRequested: name => root.applyPreset(name)
    }

    // ── Undo, and the store ──────────────────────────────────────────────────
    EditPanelRow {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.activePreset !== ""
        first: true
        last: false
        rowEnabled: !PresetStore.busy
        symbol: "history"
        title: Translation.tr("Undo preset")
        subtitle: Translation.tr("Back to the settings from before %1").arg(root.activePreset)
        trailingKind: "none"
        onActivated: PresetStore.revert()
    }

    EditPanelRow {
        Layout.fillWidth: true
        Layout.topMargin: root.activePreset !== "" ? 0 : 6
        first: root.activePreset === ""
        last: true
        symbol: "storefront"
        title: Translation.tr("Browse the store")
        subtitle: Translation.tr("Leaves Edit Mode")
        valueText: PresetStore.updateCount > 0
            ? Translation.tr("%1 updates").arg(String(PresetStore.updateCount)) : ""
        trailingKind: "chevron"
        onActivated: GlobalStates.openSettingsFromEditMode("presets", "store")
    }
}
