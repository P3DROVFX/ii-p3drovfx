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
 * review Settings shows before an apply is kept, in a shorter form: what the
 * preset was made for, what in it reads like a command, and the note that
 * shared presets are used at your own discretion.
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
    // The preset a click picked, awaiting the review below the strip.
    property string pendingName: ""
    property var pendingScan: null
    readonly property bool confirming: root.pendingName !== ""
    readonly property bool scanUsable: root.pendingScan !== null && root.pendingScan.ok === true
    readonly property var scanGroups: root.scanUsable ? (root.pendingScan.groups ?? []) : []
    readonly property var scanCompat: (root.scanUsable && root.pendingScan.compatibility) ? root.pendingScan.compatibility : null
    readonly property bool compatBlocked: root.scanCompat !== null && root.scanCompat.ok === false
    readonly property bool compatMigrates: root.scanCompat !== null && root.scanCompat.status === "migrate"
    readonly property string activePreset: PresetStore.activePreset
    readonly property string presetsScript: `${Directories.scriptPath}/presets.sh`

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

    function pick(name) {
        if (root.activePreset === name || PresetStore.busy)
            return;
        root.pendingName = name;
        root.pendingScan = null;
        scanProc.running = false;
        scanProc.command = [root.presetsScript, "scan", name];
        scanProc.running = true;
    }

    function cancelPick() {
        root.pendingName = "";
        root.pendingScan = null;
        scanProc.running = false;
    }

    function applyPending() {
        const name = root.pendingName;
        root.cancelPick();
        if (name === "" || root.compatBlocked)
            return;
        PresetStore.applyPreset(name);
    }

    function riskLabel(group) {
        if (group.id === "shell")
            return Translation.tr("Commands it can run on your system: %1").arg(group.count);
        if (group.id === "ai")
            return Translation.tr("Assistant permissions it widens: %1").arg(group.count);
        if (group.id === "network")
            return Translation.tr("Servers and search engines it redirects: %1").arg(group.count);
        return Translation.tr("Other settings that read like commands: %1").arg(group.count);
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

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                let result = null;
                try {
                    result = JSON.parse(text.trim());
                } catch (e) {
                    result = null;
                }
                if (root.pendingName !== "")
                    root.pendingScan = result;
            }
        }
    }

    EditPanelSectionLabel {
        text: Translation.tr("Presets")
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

    ListView {
        id: strip
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.presets.length > 0
        implicitHeight: 104
        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.presets

        delegate: Item {
            id: card
            required property var modelData
            readonly property string name: String(card.modelData.name ?? "")
            readonly property string wallpaper: String(card.modelData.wallpaper ?? "")
            readonly property bool active: root.activePreset === card.name
            readonly property bool pending: root.pendingName === card.name
            readonly property bool busy: PresetStore.busyFor(card.name)
            width: 136
            height: strip.implicitHeight

            Rectangle {
                id: tile
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: card.pending ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                border.width: card.active ? 2 : 1
                border.color: card.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                opacity: card.busy ? 0.5 : 1
                scale: cardMouse.containsPress ? 0.96 : 1
                Behavior on scale {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tile)
                }

                ClippingRectangle {
                    id: picture
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: tile.border.width
                    height: 70
                    topLeftRadius: tile.radius - tile.border.width
                    topRightRadius: tile.radius - tile.border.width
                    color: Appearance.colors.colLayer2

                    Loader {
                        anchors.fill: parent
                        active: card.wallpaper !== ""
                        sourceComponent: ThumbnailImage {
                            sourcePath: card.wallpaper
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: card.wallpaper === ""
                        text: "style"
                        iconSize: 26
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 5
                        visible: card.active
                        width: 20
                        height: 20
                        radius: width / 2
                        color: Appearance.colors.colPrimary

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: 14
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: picture.bottom
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    text: card.name
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: card.active ? Font.DemiBold : Font.Normal
                    color: card.pending ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: card.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: {
                        if (card.pending)
                            root.cancelPick();
                        else
                            root.pick(card.name);
                    }
                }
            }
        }
    }

    // ── The review ───────────────────────────────────────────────────────────
    // What Settings shows in a dialog, as a card under the strip: the reasons
    // to think twice, then Apply and Cancel as rows.
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.confirming
        implicitHeight: reviewColumn.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: reviewColumn
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Apply %1?").arg(root.pendingName)
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.pendingScan === null && scanProc.running
                text: Translation.tr("Looking through it…")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.compatBlocked
                text: Translation.tr("Made for a newer version of the shell. Update the shell first.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.compatMigrates
                text: Translation.tr("Made for an older version of the shell; its settings are brought up to date as it is applied.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.pendingScan !== null && !root.scanUsable
                text: Translation.tr("It could not be inspected, so there is no telling what it changes. Apply it only if you trust where it came from.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
            }

            Repeater {
                model: root.scanGroups

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: modelData.id === "shell" ? "terminal"
                            : modelData.id === "ai" ? "smart_toy"
                            : modelData.id === "network" ? "public" : "warning"
                        iconSize: 18
                        color: Appearance.colors.colError
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.riskLabel(modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurface
                        wrapMode: Text.Wrap
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.scanUsable && root.scanGroups.length === 0
                text: Translation.tr("Nothing in it runs commands or sends your data anywhere new.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: PresetStore.isFromStore(root.pendingName)
                text: Translation.tr("Presets shared by other people are used at your own discretion; this project does not review them.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Your current settings are saved first. Undo preset brings them back; the mode's own undo history is cleared.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 3

                EditPanelRow {
                    Layout.fillWidth: true
                    hostRadius: Appearance.rounding.normal
                    hostPadding: 10
                    first: true
                    last: false
                    rowEnabled: root.pendingScan !== null && !root.compatBlocked
                    symbol: "check"
                    title: Translation.tr("Apply")
                    trailingKind: "none"
                    onActivated: root.applyPending()
                }
                EditPanelRow {
                    Layout.fillWidth: true
                    hostRadius: Appearance.rounding.normal
                    hostPadding: 10
                    first: false
                    last: true
                    symbol: "close"
                    title: Translation.tr("Cancel")
                    trailingKind: "none"
                    onActivated: root.cancelPick()
                }
            }
        }
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
            ? Translation.tr("%1 updates").arg(PresetStore.updateCount) : ""
        trailingKind: "chevron"
        onActivated: GlobalStates.openSettingsFromEditMode("presets", "store")
    }
}
