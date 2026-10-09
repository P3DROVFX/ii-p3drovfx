pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The workspace compactor. The band shows what it does — five workspaces with gaps, the
 * empty ones fading out and the others sliding together and renumbering — while the
 * pointer is over it or auto-compact is on, so the option is understood before it is
 * enabled. The knobs of the automatic mode unfold under it; the helper and the shortcut
 * stay as the original boxes.
 */
WorkspacesPane {
    id: root

    readonly property real bandHeight: 96
    readonly property real cellSize: 40
    readonly property real cellGap: 10
    readonly property var occupied: [true, false, true, false, true]
    readonly property int occupiedCount: root.occupied.filter(Boolean).length

    readonly property var cfg: Config.options.bar.workspaces
    readonly property bool compacted: root.cfg.autoCompact || bandHover.hovered

    // The slot a workspace holds once the gaps are gone.
    function rankOf(index) {
        let rank = 0;
        for (let i = 0; i < index; i++) {
            if (root.occupied[i])
                rank++;
        }
        return rank;
    }

    symbol: "compress"
    title: Translation.tr("Workspace Compactor")
    engaged: root.compacted
    subtitle: root.cfg.autoCompact
        ? Translation.tr("Automatic · after %1 ms of quiet").arg(root.cfg.autoCompactDelay)
        : Translation.tr("Manual · Ctrl + Super + C")

    headerExtra: StyledSwitch {
        checked: root.cfg.autoCompact
        onToggled: root.cfg.autoCompact = checked
        StyledToolTip {
            text: Translation.tr("Compact automatically whenever closing or moving a window leaves a gap on the focused monitor. The keybind above keeps working either way.")
        }
    }

    Rectangle {
        id: band
        Layout.fillWidth: true
        implicitHeight: root.bandHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        HoverHandler {
            id: bandHover
        }

        // Cells in a row, centred as a group: the group narrows as the gaps close.
        property real shownCount: root.compacted ? root.occupiedCount : root.occupied.length
        Behavior on shownCount {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        readonly property real pitch: root.cellSize + root.cellGap
        readonly property real originX: (band.width - (band.shownCount * band.pitch - root.cellGap)) / 2

        Repeater {
            model: root.occupied
            delegate: Rectangle {
                id: cell

                required property bool modelData
                required property int index
                readonly property bool gone: !cell.modelData && root.compacted
                readonly property int slot: cell.modelData && root.compacted ? root.rankOf(cell.index) : cell.index

                x: band.originX + cell.slot * band.pitch
                y: (band.height - height) / 2
                width: root.cellSize
                height: root.cellSize
                radius: cell.modelData ? Appearance.rounding.normal : width / 2
                color: cell.modelData ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                opacity: cell.gone ? 0 : 1

                Behavior on x {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledText {
                    anchors.centerIn: parent
                    text: cell.modelData ? String(cell.slot + 1) : "·"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: cell.modelData ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                }
            }
        }
    }

    WorkspacesReveal {
        Layout.fillWidth: true
        open: root.cfg.autoCompact
        sourceComponent: ColumnLayout {
            spacing: 8

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Auto-Compact delay (ms)")
                value: root.cfg.autoCompactDelay
                from: 100
                to: 5000
                stepSize: 100
                onValueChanged: root.cfg.autoCompactDelay = value
            }

            ContentSubsection {
                title: Translation.tr("When the gap is the current workspace")
                icon: "conditions"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: root.cfg.autoCompactCurrentGap
                    onSelected: newValue => root.cfg.autoCompactCurrentGap = newValue
                    options: [
                        { displayName: Translation.tr("Compact on switch"), icon: "move_group", value: "onswitch" },
                        { displayName: Translation.tr("Immediately"), icon: "bolt", value: "immediate" },
                        { displayName: Translation.tr("Never"), icon: "block", value: "never" }
                    ]
                }
            }
        }
    }

    HelperCodeBox {
        Layout.fillWidth: true
        icon: "terminal"
        title: Translation.tr("Build it once")
        text: Translation.tr("Pulls the focused monitor's occupied workspaces down to 1..N with no gaps. The workspaces themselves are renumbered, so every window keeps its exact place. Rust is the only requirement.")
        codeSnippet: `${Directories.rustHelpersScriptPath.replace(FileUtils.trimFileProtocol(Directories.home), "~")} build workspace_compactor`
        snippetWrapMode: Text.Wrap
    }

    KeyboardShortcutBox {
        Layout.fillWidth: true
        text: Translation.tr("Compact workspaces into 1..N")
        keys: ["Ctrl", "Super", "C"]
    }
}
