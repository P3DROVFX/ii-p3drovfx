pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A screen recording, expanded: one low, wide bar.
 *
 * The dot and the timer hold the left end, the two actions the right end, and the bar
 * between them is deliberately empty - the card is short, so nothing in it may be a
 * second copy of something already said. The state is read from the two actions and the
 * dot's own colour: a pause button showing `play_arrow` and a dot gone amber is a paused
 * recording, without a line of text claiming so.
 *
 * This is one presentation of one activity, loaded by whatever hosts an expanded face
 * (today the auxiliary bubble's card). It is handed a size and never asks for one; the
 * descriptor in IslandRegistry is where the card's box is decided.
 */
Item {
    id: root
    anchors.fill: parent

    /** The recording's own state, wherever the script has written it last. */
    readonly property var state: Persistent.states.screenRecord ?? null
    readonly property bool active: root.state ? root.state.active === true : false
    readonly property bool paused: root.state ? root.state.paused === true : false
    readonly property int elapsedSeconds: root.state ? root.state.seconds : 0
    /** The dot and the clock the glance's own land on (see AuxiliaryBubble's heroes). */
    readonly property var heroItems: [dot, clock]

    /** The script counts whole seconds; MM:SS is the whole of what it can say. */
    readonly property string timeText: {
        const mins = Math.floor(root.elapsedSeconds / 60);
        const secs = root.elapsedSeconds % 60;
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    /**
     * The two surfaces, and the step each takes under the pointer.
     *
     * The theme's own hover tokens move a colour by 5-10% of the layer it sits on, which
     * is a whisper on an opaque card and nothing at all on the island's translucent body
     * over a wallpaper: the button looked dead under the pointer. Same recipe, a step
     * wide enough to read - the resting colour, mixed toward the colour that is legible
     * on top of it.
     */
    readonly property color pauseSurface: Appearance.colors.colSurfaceContainerHighest
    readonly property color pauseSurfaceHover: ColorUtils.mix(root.pauseSurface, Appearance.colors.colOnSurface, 0.84)
    readonly property color pauseSurfaceActive: ColorUtils.mix(root.pauseSurface, Appearance.colors.colOnSurface, 0.72)

    readonly property color stopSurface: Appearance.colors.colErrorContainer
    readonly property color stopSurfaceHover: ColorUtils.mix(root.stopSurface, Appearance.colors.colOnErrorContainer, 0.82)
    readonly property color stopSurfaceActive: ColorUtils.mix(root.stopSurface, Appearance.colors.colOnErrorContainer, 0.7)

    RowLayout {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 16
        spacing: 12

        // ── The state: a steady dot, and the clock ───────────────────────────
        Rectangle {
            id: dot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 10
            implicitHeight: 10
            radius: width / 2
            color: root.paused ? Appearance.colors.colWarning : Appearance.colors.colErrorContainer
            // A held capture is dimmed and goes amber; a running one is the saturated red
            // the bar's own indicator wears, so the two surfaces agree on what red means.
            opacity: root.active ? (root.paused ? 0.65 : 1) : 0

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledText {
            id: clock
            Layout.alignment: Qt.AlignVCenter
            text: root.timeText
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            font.features: ({
                    "tnum": 1
                })
            // A held capture greys its clock: the digits stay put while the recording does.
            color: root.paused ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // The bar is the gap between the two ends; the actions stay where the pointer
        // expects to find them.
        Item {
            Layout.fillWidth: true
        }

        // ── The actions ──────────────────────────────────────────────────────
        RippleButton {
            id: pauseButton
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            // Driven by the pointer rather than left to the button's own `hovered`: the
            // colour is the affordance here, and both ends of it are this file's to state.
            colBackground: pauseHover.hovered ? root.pauseSurfaceHover : root.pauseSurface
            colBackgroundHover: root.pauseSurfaceHover
            colBackgroundActive: root.pauseSurfaceActive
            colRipple: root.pauseSurfaceActive
            onClicked: Quickshell.execDetached([Directories.recordScriptPath, "--pause"])

            HoverHandler {
                id: pauseHover
            }

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.paused ? "play_arrow" : "pause"
                fill: 1
                iconSize: 20
                color: Appearance.colors.colOnSurface
            }
        }

        // Stop is the wide one: the action a recording ends with should be the easiest
        // thing on the card to hit, and a label says what it does without a tooltip.
        RippleButton {
            id: stopButton
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 36
            implicitWidth: stopContent.implicitWidth + 2 * 16
            buttonRadius: Appearance.rounding.full
            colBackground: stopHover.hovered ? root.stopSurfaceHover : root.stopSurface
            colBackgroundHover: root.stopSurfaceHover
            colBackgroundActive: root.stopSurfaceActive
            colRipple: root.stopSurfaceActive
            onClicked: Quickshell.execDetached([Directories.recordScriptPath])

            HoverHandler {
                id: stopHover
            }

            contentItem: Item {
                implicitWidth: stopContent.implicitWidth
                implicitHeight: stopContent.implicitHeight

                Row {
                    id: stopContent
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "stop"
                        fill: 1
                        iconSize: 18
                        color: Appearance.colors.colOnErrorContainer
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Stop")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
            }
        }
    }
}