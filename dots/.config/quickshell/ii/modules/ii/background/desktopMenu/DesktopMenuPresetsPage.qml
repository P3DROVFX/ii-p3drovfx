import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The desktop menu's "Presets" page: the saved looks as one column of cards,
 * each its wallpaper with the name on a chip over it; the preset on now is ringed in
 * primary. A click applies it through PresetStore - the same path as Edit
 * Mode's Style catalogue and Settings' Preset Manager - and closes the menu,
 * since the preset brings its own transition over the whole shell.
 *
 * The list comes from `presets.sh list`, one JSON object per line, as
 * EditStylePresets reads it, and is ordered by use: the preset on now, then
 * the rest by PresetStore.recentPresets, then the never-applied ones in the
 * script's order. The image is clipped by a ClippingRectangle, not
 * an OpacityMask: Qt5Compat effects pin their window and this surface is
 * kept alive and remapped for every open.
 */
ColumnLayout {
    id: root

    signal backRequested()
    // Applying a preset, or leaving for Settings, closes the whole menu.
    signal dismissRequested()

    spacing: 8

    // The page change, 0 -> 1, driven by the card (see DesktopMenuColorsPage).
    property real reveal: 1
    function slice(index: int): real {
        const t = (root.reveal - index * 0.14) / 0.72;
        return Math.max(0, Math.min(1, t));
    }

    // Room for three cards and a peek of the fourth.
    readonly property real wellHeight: 456

    // [{name, wallpaper, configVersion}]
    property var presets: []
    readonly property var orderedPresets: {
        const recents = Array.from(PresetStore.recentPresets);
        const rank = p => {
            if (p.name === root.activePreset)
                return -1;
            const i = recents.indexOf(p.name);
            return i >= 0 ? i : recents.length;
        };
        // Array.sort is stable, so the unranked keep the script's order.
        return root.presets.slice().sort((a, b) => rank(a) - rank(b));
    }
    readonly property string activePreset: PresetStore.activePreset
    readonly property string presetsScript: `${Directories.scriptPath}/presets.sh`

    function refresh(): void {
        listProc.running = false;
        listProc.running = true;
    }

    function apply(name: string): void {
        if (name === "" || root.activePreset === name || PresetStore.busy)
            return;
        PresetStore.applyPreset(name);
        root.dismissRequested();
    }

    Component.onCompleted: {
        PresetStore.ensureLoaded();
        root.refresh();
    }

    Connections {
        target: PresetStore
        function onPresetFilesChanged() {
            root.refresh();
        }
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
                for (const line of String(data).split("\n")) {
                    const text = line.trim();
                    if (text === "")
                        continue;
                    try {
                        listProc.collected.push(JSON.parse(text));
                    } catch (e) {
                        console.warn("[DesktopMenuPresetsPage] bad preset line:", text);
                    }
                }
            }
        }
        onExited: root.presets = listProc.collected
    }

    // ── Header ───────────────────────────────────────────────────────────────
    DesktopMenuPageHeader {
        title: Translation.tr("Presets")
        actionSymbol: "arrow_outward"
        actionTooltip: Translation.tr("Open in Settings")
        onActionRequested: {
            root.dismissRequested();
            GlobalStates.openSettingsFromEditMode("presets");
        }
        opacity: root.slice(0)
        transform: Translate { x: (1 - root.slice(0)) * 16 }
        onBackRequested: root.backRequested()
    }

    // ── List ─────────────────────────────────────────────────────────────────
    // A ClippingRectangle, not a Rectangle with a clipping Flickable inside:
    // the flick's clip is square, so cards scrolled to the edge showed
    // sharp corners against the well's rounded ones.
    ClippingRectangle {
        id: well
        readonly property real inset: 6
        Layout.fillWidth: true
        Layout.preferredHeight: root.wellHeight
        radius: Math.max(Appearance.rounding.verysmall, Appearance.rounding.windowRounding - 8)
        color: Appearance.colors.colLayer1
        opacity: root.slice(1)
        transform: Translate { x: (1 - root.slice(1)) * 16 }

        StyledText {
            anchors.centerIn: parent
            visible: root.presets.length === 0 && !listProc.running
            text: Translation.tr("No presets saved")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        StyledFlickable {
            id: flick
            anchors.fill: parent
            topMargin: well.inset
            bottomMargin: well.inset
            contentHeight: list.implicitHeight

            ColumnLayout {
                id: list
                x: well.inset
                width: flick.width - well.inset * 2
                spacing: 6

                Repeater {
                    model: root.orderedPresets

                    delegate: Rectangle {
                        id: presetCard
                        required property var modelData
                        readonly property string presetName: String(modelData.name ?? "")
                        readonly property string wallpaper: String(modelData.wallpaper ?? "")
                        readonly property bool active: root.activePreset === presetCard.presetName
                        readonly property bool busy: PresetStore.busyFor(presetCard.presetName)
                        readonly property bool hovered: cardMouse.containsMouse && !presetCard.active

                        Layout.fillWidth: true
                        implicitHeight: 140
                        radius: Math.max(Appearance.rounding.verysmall, well.radius - well.inset)
                        color: "transparent"
                        border.width: presetCard.active ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        opacity: presetCard.busy ? 0.5 : 1
                        scale: cardMouse.pressed && !presetCard.active ? 0.98 : 1

                        Behavior on scale {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(presetCard)
                        }

                        ClippingRectangle {
                            id: imageClip
                            anchors.fill: parent
                            anchors.margins: presetCard.active ? 4 : 0
                            radius: presetCard.active ? Math.max(Appearance.rounding.verysmall, presetCard.radius - 4) : presetCard.radius
                            color: Appearance.colors.colLayer3

                            StyledImage {
                                anchors.fill: parent
                                sourceSize: Qt.size(520, 300)
                                source: presetCard.wallpaper !== ""
                                    ? presetCard.wallpaper
                                    : `${Directories.assetsPath}/images/default_wallpaper.png`
                                fillMode: Image.PreserveAspectCrop
                                // The hover: a small push into the picture.
                                scale: presetCard.hovered ? 1.06 : 1
                                Behavior on scale {
                                    enabled: !Appearance.reducedMotion
                                    animation: Appearance.animation.elementMove.numberAnimation.createObject(imageClip)
                                }
                            }

                            // ...and a wash of the accent over it.
                            Rectangle {
                                anchors.fill: parent
                                color: Appearance.colors.colPrimary
                                opacity: presetCard.hovered ? 0.18 : 0
                                Behavior on opacity {
                                    enabled: !Appearance.reducedMotion
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(imageClip)
                                }
                            }

                            // The name, on a chip over the picture.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 8
                                width: Math.min(nameRow.implicitWidth + 20, parent.width - 16)
                                height: 30
                                radius: height / 2
                                color: presetCard.active ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh

                                RowLayout {
                                    id: nameRow
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 4

                                    MaterialSymbol {
                                        visible: presetCard.active
                                        text: "check"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: presetCard.presetName
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        color: presetCard.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !presetCard.busy
                            cursorShape: presetCard.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: root.apply(presetCard.presetName)
                        }
                    }
                }
            }
        }
    }
}
