import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Color picker: a click picks any colour on screen (hyprpicker), the code goes
 * to the clipboard and the last ones stay on the tile. Square: the newest
 * colour IS the tile's swatch — a nine-sided cookie with the dropper inked in
 * contrast. Wide: the dropper, the newest colour as a wide swatch carrying its
 * code, and the two before it; every swatch copies its code again. Colours
 * picked with the shortcut land in the same history.
 */
UtilityTile {
    id: tile

    readonly property var colors: Persistent.ready ? Array.from(Persistent.states.dockUtilities.colors ?? []) : []
    readonly property string latest: tile.colors.length > 0 ? tile.colors[0] : ""
    readonly property bool picking: picker.running
    property string copied: ""

    function remember(hex) {
        const value = String(hex).trim().toUpperCase();
        if (!/^#[0-9A-F]{6}([0-9A-F]{2})?$/.test(value) || !Persistent.ready)
            return;
        Persistent.states.dockUtilities.colors = [value].concat(tile.colors.filter(c => c !== value)).slice(0, 15);
    }
    function pick() {
        picker.running = false;
        Qt.callLater(() => picker.running = true);
    }
    function copy(hex) {
        Quickshell.clipboardText = hex;
        tile.copied = hex;
        copiedTimer.restart();
    }
    function clear() {
        Persistent.states.dockUtilities.colors = [];
    }
    function ink(hex) {
        return ColorUtils.getContrastingTextColor(hex);
    }

    // The pointer is still on the dock when the click lands; give the
    // release a moment before the picker grabs the screen.
    Process {
        id: picker
        command: ["bash", "-c", "sleep 0.2; hyprpicker -a -f hex"]
        stdout: SplitParser {
            onRead: data => tile.remember(data)
        }
    }
    Connections {
        target: GlobalStates
        function onColorPickerPopupColorChanged() {
            tile.remember(GlobalStates.colorPickerPopupColor);
        }
    }
    Timer {
        id: copiedTimer
        interval: 1600
        onTriggered: tile.copied = ""
    }

    function activate() {
        if (tile.wide)
            return false;
        tile.pick();
        return true;
    }

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface

    tooltipText: tile.copied !== "" ? Translation.tr("Copied %1").arg(tile.copied)
        : tile.latest !== "" ? Translation.tr("Pick a color · last: %1").arg(tile.latest)
        : Translation.tr("Pick a color from the screen")
    panelSubtitle: tile.colors.length === 0 ? Translation.tr("No colors yet")
        : tile.colors.length === 1 ? Translation.tr("1 color") : Translation.tr("%1 colors").arg(tile.colors.length)
    menuActions: [
        { id: "pick", icon: "colorize", text: Translation.tr("Pick a color") },
        { id: "copy", icon: "content_copy", text: Translation.tr("Copy %1").arg(tile.latest), visible: tile.latest !== "" },
        { id: "clear", icon: "delete_sweep", text: Translation.tr("Clear history"), visible: tile.colors.length > 0 }
    ]
    function menuAction(actionId) {
        if (actionId === "pick")
            tile.pick();
        else if (actionId === "copy")
            tile.copy(tile.latest);
        else if (actionId === "clear")
            tile.clear();
    }

    // ── Square ──────────────────────────────────────────────────────────
    TileBadge {
        anchors.centerIn: parent
        visible: !tile.wide
        width: Math.round(tile.side * 0.8)
        height: width
        renderScale: tile.renderScale
        // Picking morphs the swatch; the colour fills it when it lands.
        shape: tile.picking ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie9Sided
        color: tile.latest !== "" ? tile.latest : ClockStyle.colSecondaryContainer
        colSymbol: tile.latest !== "" ? tile.ink(tile.latest) : ClockStyle.colOnSecondaryContainer
        text: tile.copied !== "" ? "check" : "colorize"
        iconScale: 0.46
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        visible: tile.wide
        spacing: tile.pad

        TileButton {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            symbol: "colorize"
            filled: true
            active: tile.picking
            tip: Translation.tr("Pick a color")
            onClicked: tile.pick()
        }

        // The newest colour, wide, with its code.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tile.latest !== ""
            Rectangle {
                anchors.fill: parent
                radius: latestArea.pressed ? Math.round(height * 0.24) : Math.max(4, tile.radius - tile.pad)
                color: tile.latest || "transparent"
                Behavior on radius {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }
            }
            TileValue {
                anchors.left: parent.left
                anchors.leftMargin: Math.round(tile.pad * 1.4)
                anchors.verticalCenter: parent.verticalCenter
                text: tile.copied === tile.latest ? Translation.tr("Copied") : tile.latest.slice(1)
                color: tile.latest ? tile.ink(tile.latest) : tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.32)
            }
            MouseArea {
                id: latestArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.copy(tile.latest)
            }
        }

        // The two before it, as round swatches.
        Repeater {
            model: tile.colors.slice(1, 3)
            delegate: Item {
                id: older
                required property string modelData
                implicitWidth: Math.round(tile.badgeSize * 0.7)
                implicitHeight: implicitWidth
                Rectangle {
                    anchors.fill: parent
                    radius: olderArea.pressed ? Math.round(height * 0.24) : height / 2
                    color: older.modelData
                    Behavior on radius {
                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                    }
                }
                TileSymbol {
                    anchors.centerIn: parent
                    visible: tile.copied === older.modelData
                    text: "check"
                    iconSize: Math.round(parent.height * 0.6)
                    color: tile.ink(older.modelData)
                }
                MouseArea {
                    id: olderArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.copy(older.modelData)
                }
                StyledToolTip {
                    text: older.modelData
                    extraVisibleCondition: olderArea.containsMouse
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: tile.latest === ""
            spacing: 0
            TileText {
                Layout.fillWidth: true
                text: Translation.tr("Pick a color")
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.27)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            TileCaption {
                Layout.fillWidth: true
                text: Translation.tr("Copies its hex")
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }
    }
}
