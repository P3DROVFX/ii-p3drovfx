pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The workspace arranger. The band shows both halves of what it does: five workspaces with
 * gaps, the empty ones fading out and the others sliding together and renumbering, then an
 * empty workspace opening after the first one while the rest slide up to make room. It loops
 * through them while the pointer is over it, and otherwise rests on what auto-close keeps the
 * numbering at, so the option is understood before it is enabled. The knobs of the automatic
 * mode unfold under it; the helper and the shortcuts stay as the original boxes.
 */
WorkspacesPane {
    id: root

    readonly property real bandHeight: 120
    readonly property real cellSize: 40
    readonly property real cellGap: 10
    readonly property real captionSpace: 28
    readonly property var occupied: [true, false, true, false, true]
    readonly property int occupiedCount: root.occupied.filter(Boolean).length
    // Where the demo opens its workspace: right after the first one.
    readonly property int insertSlot: 1

    readonly property var cfg: Config.options.bar.workspaces.arranger

    // "gaps": the numbering as closed windows left it. "closed": gaps closed. "inserted": an
    // empty workspace opened after the first one.
    readonly property var demoLoop: ["gaps", "closed", "inserted", "closed"]
    readonly property string restState: root.cfg.autoCloseGaps ? "closed" : "gaps"
    property int demoStep: 0
    readonly property string demo: bandHover.hovered ? root.demoLoop[root.demoStep] : root.restState

    // The slot a workspace holds once the gaps are gone.
    function rankOf(index) {
        let rank = 0;
        for (let i = 0; i < index; i++) {
            if (root.occupied[i])
                rank++;
        }
        return rank;
    }

    function slotOf(index) {
        if (root.demo === "gaps")
            return index;
        const rank = root.rankOf(index);
        return root.demo === "inserted" && rank >= root.insertSlot ? rank + 1 : rank;
    }

    symbol: "reorder"
    title: Translation.tr("Workspace Arranger")
    engaged: root.cfg.autoCloseGaps || bandHover.hovered
    subtitle: root.cfg.autoCloseGaps
        ? Translation.tr("Closes gaps on its own · after %1 ms of quiet").arg(root.cfg.delay)
        : Translation.tr("Closes gaps and opens new workspaces in between")

    headerExtra: StyledSwitch {
        checked: root.cfg.autoCloseGaps
        onToggled: root.cfg.autoCloseGaps = checked
        StyledToolTip {
            text: Translation.tr("Close gaps automatically whenever opening, closing or moving a window leaves one on the focused monitor. The shortcuts below keep working either way.")
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
            // Start the loop from what the band is resting on, so its first step is a change.
            onHoveredChanged: {
                if (hovered)
                    root.demoStep = root.demoLoop.indexOf(root.restState);
            }
        }

        Timer {
            running: bandHover.hovered
            interval: 1400
            repeat: true
            onTriggered: root.demoStep = (root.demoStep + 1) % root.demoLoop.length
        }

        // Cells in a row, centred as a group: the group narrows as the gaps close and widens
        // again as a workspace opens.
        property real shownCount: root.demo === "gaps" ? root.occupied.length
            : root.occupiedCount + (root.demo === "inserted" ? 1 : 0)
        Behavior on shownCount {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        readonly property real pitch: root.cellSize + root.cellGap
        readonly property real originX: (band.width - (band.shownCount * band.pitch - root.cellGap)) / 2
        readonly property real cellY: (band.height - root.captionSpace - root.cellSize) / 2 + 6

        Repeater {
            model: root.occupied
            delegate: Rectangle {
                id: cell

                required property bool modelData
                required property int index
                readonly property bool gone: !cell.modelData && root.demo !== "gaps"
                readonly property int slot: cell.modelData ? root.slotOf(cell.index) : cell.index

                x: band.originX + cell.slot * band.pitch
                y: band.cellY
                width: root.cellSize
                height: root.cellSize
                radius: cell.modelData ? Appearance.rounding.normal : width / 2
                color: cell.modelData ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                // An empty workspace is outlined so it reads against the band at all.
                border.width: cell.modelData ? 0 : 1
                border.color: Appearance.colors.colOutlineVariant
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

        // The workspace an insert opens: empty, so outlined, and already holding its number.
        Rectangle {
            id: newCell
            readonly property bool shown: root.demo === "inserted"

            x: band.originX + root.insertSlot * band.pitch
            y: band.cellY
            width: root.cellSize
            height: root.cellSize
            radius: Appearance.rounding.normal
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary
            opacity: newCell.shown ? 1 : 0
            scale: newCell.shown ? 1 : 0.6

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on scale {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            StyledText {
                anchors.centerIn: parent
                text: String(root.insertSlot + 1)
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
            }
        }

        StyledText {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 12
            }
            text: root.demo === "inserted" ? Translation.tr("Insert after 1 · Ctrl + Super + I")
                : root.demo === "closed" ? Translation.tr("Close gaps · Ctrl + Super + C")
                : Translation.tr("Gaps left by closed windows")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    WorkspacesReveal {
        Layout.fillWidth: true
        open: root.cfg.autoCloseGaps
        sourceComponent: ColumnLayout {
            spacing: 8

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Delay before closing a gap (ms)")
                value: root.cfg.delay
                from: 100
                to: 5000
                stepSize: 100
                onValueChanged: root.cfg.delay = value
            }

            ContentSubsection {
                title: Translation.tr("When the gap is the current workspace")
                icon: "conditions"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: root.cfg.currentGap
                    onSelected: newValue => root.cfg.currentGap = newValue
                    options: [
                        { displayName: Translation.tr("Close on switch"), icon: "move_group", value: "onswitch" },
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
        text: Translation.tr("Renumbers the focused monitor's workspaces in place: it closes the gaps so the occupied ones run 1..N, and opens an empty workspace wherever you ask by shifting the ones after it up. Every window keeps its exact place. Rust is the only requirement.")
        codeSnippet: `${Directories.rustHelpersScriptPath.replace(FileUtils.trimFileProtocol(Directories.home), "~")} build workspace_arranger`
        snippetWrapMode: Text.Wrap
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        KeyboardShortcutBox {
            Layout.fillWidth: true
            text: Translation.tr("Close gaps, so workspaces run 1..N")
            keys: ["Ctrl", "Super", "C"]
        }
        KeyboardShortcutBox {
            Layout.fillWidth: true
            text: Translation.tr("Insert an empty workspace after this one")
            keys: ["Ctrl", "Super", "I"]
        }
        KeyboardShortcutBox {
            Layout.fillWidth: true
            text: Translation.tr("Insert an empty workspace before this one")
            keys: ["Ctrl", "Super", "Shift", "I"]
        }
        KeyboardShortcutBox {
            Layout.fillWidth: true
            text: Translation.tr("Insert an empty workspace first")
            keys: ["Ctrl", "Super", "Home"]
        }
        KeyboardShortcutBox {
            Layout.fillWidth: true
            text: Translation.tr("Same, taking the focused window along (Shift: before, Home: first)")
            keys: ["Super", "Alt", "I"]
        }
    }
}
