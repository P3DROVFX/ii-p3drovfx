import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
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

    Item {
        id: stripContainer
        Layout.fillWidth: true
        Layout.topMargin: 6
        implicitHeight: strip.implicitHeight
        visible: root.presets.length > 0

        ListView {
            id: strip
            anchors.fill: parent
            orientation: ListView.Horizontal
            spacing: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.presets

            readonly property real cardWidth: Math.min(160, Math.max(132, Math.floor((width - spacing) / 2)))
            readonly property real cardHeight: cardWidth * 0.8
            implicitHeight: cardHeight

            delegate: Rectangle {
                    id: presetItem
                    required property var modelData
                    width: strip.cardWidth
                    height: strip.cardHeight
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerLow
                    opacity: presetBusy ? 0.5 : 1
                    scale: presetButton.down ? 0.96 : 1

                    readonly property string presetName: String(modelData.name ?? "")
                    readonly property string wallpaper: String(modelData.wallpaper ?? "")
                    readonly property bool active: root.activePreset === presetItem.presetName
                    readonly property bool presetBusy: PresetStore.busyFor(presetItem.presetName)
                    readonly property bool tooNew: Number(modelData.configVersion ?? 0) > 0
                        && Number(modelData.configVersion) > Config.currentConfigVersion

                    Behavior on scale {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(presetItem)
                    }

                    // The whole card is the single apply action. Keeping the
                    // real RippleButton above the image gives the pointer a
                    // hand cursor on every hover, including over the artwork.
                    RippleButton {
                        id: presetButton
                        anchors.fill: parent
                        enabled: !presetItem.active && !presetItem.presetBusy && !PresetStore.busy
                        hoverEnabled: true
                        pointingHandCursor: true
                        buttonRadius: Appearance.rounding.normal
                        colBackground: "transparent"
                        colBackgroundHover: "transparent"
                        colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                        onClicked: root.applyPreset(presetItem.presetName)

                        StyledToolTip {
                            text: presetItem.active
                                ? Translation.tr("Active preset") : Translation.tr("Apply preset")
                        }
                    }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        StyledImage {
                            id: previewImage
                            anchors.fill: parent
                            sourceSize: Qt.size(400, 400)
                            source: presetItem.wallpaper !== ""
                                ? presetItem.wallpaper
                                : `${Directories.assetsPath}/images/default_wallpaper.png`
                            fillMode: Image.PreserveAspectCrop
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: previewImage.width
                                    height: previewImage.height
                                    radius: Appearance.rounding.small
                                }
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: presetItem.wallpaper === ""
                            text: "style"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 6
                            visible: presetItem.tooNew
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colErrorContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "system_update_alt"
                                iconSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnErrorContainer
                            }
                        }

                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            visible: presetItem.active
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimary

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 30

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: presetItem.presetName
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: presetItem.active ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }
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
            ? Translation.tr("%1 updates").arg(String(PresetStore.updateCount)) : ""
        trailingKind: "chevron"
        onActivated: GlobalStates.openSettingsFromEditMode("presets", "store")
    }
}
