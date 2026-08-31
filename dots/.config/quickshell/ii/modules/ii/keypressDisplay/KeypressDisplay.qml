pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * On-screen keystrokes, drawn on top of everything so a screen recording picks
 * them up: wlr-screencopy composites layer surfaces, so whatever is shown here
 * lands in the file without any extra plumbing.
 *
 * Each chip is a chord of keycaps — `Ctrl` `+` `Shift` `+` `P` — drawn the way
 * a key looks on a keyboard: a face sitting on a darker lip, which it drops
 * onto while pressed. A cap arrives pressed and pops back up; a repeat presses
 * it again and counts up in a badge; a modifier held on its own stays down,
 * filled with the accent, until it is let go.
 *
 * The window is fully click-through (an empty mask) and reserves no space, so
 * it never disturbs the tiling underneath. It is drawn on every output, because
 * focus can move to another monitor mid-recording and an overlay that follows
 * the focus would then vanish from the footage.
 */
Scope {
    id: root

    readonly property string position: Config.options.screenRecord.keypress.position
    readonly property bool atTop: root.position.startsWith("top")
    readonly property bool atLeft: root.position.endsWith("Left")
    readonly property bool atRight: root.position.endsWith("Right")

    readonly property real fontSize: Appearance.font.pixelSize.huge * Config.options.screenRecord.keypress.scale
    readonly property real capHeight: Math.round(root.fontSize * 1.9)
    readonly property real capRadius: Math.round(root.fontSize * 0.45)
    readonly property real lipHeight: Math.max(2, Math.round(root.fontSize * 0.22))
    readonly property real chipHeight: root.capHeight + root.lipHeight
    // Room around the strip for the caps' shadows, which the window would
    // otherwise cut off at its edge.
    readonly property real shadowPad: Appearance.sizes.elevationMargin

    // The lip is the cap's own colour in shadow, whichever way the theme goes.
    function lipColor(face) {
        return Qt.darker(face, Appearance.m3colors.darkmode ? 1.45 : 1.22);
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: keypressWindow
            required property ShellScreen modelData
            screen: keypressWindow.modelData

            visible: KeypressService.visible
            WlrLayershell.namespace: "quickshell:keypressDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // Nothing here is ever clicked; an empty region lets every event
            // through to the application being recorded.
            mask: Region {}

            anchors {
                top: root.atTop
                bottom: !root.atTop
                left: true
                right: true
            }
            margins {
                top: root.atTop ? Config.options.screenRecord.keypress.marginV : 0
                bottom: root.atTop ? 0 : Config.options.screenRecord.keypress.marginV
                left: Config.options.screenRecord.keypress.marginH
                right: Config.options.screenRecord.keypress.marginH
            }

            implicitHeight: root.chipHeight + root.shadowPad * 2

            ListView {
                id: chipList
                model: KeypressService.chips
                orientation: ListView.Horizontal
                interactive: false
                spacing: Math.round(root.fontSize * 0.7)

                width: Math.min(parent.width, contentWidth)
                // Height is stated rather than measured: taking it from
                // contentHeight would mean no height until a delegate exists,
                // and no delegate until there is a height to put it in.
                height: root.chipHeight
                // Newest chips sit at the model's tail, so a run of keys grows
                // away from the anchored edge instead of jumping around.
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: root.atLeft ? parent.left : undefined
                    right: root.atRight ? parent.right : undefined
                    horizontalCenter: (root.atLeft || root.atRight) ? undefined : parent.horizontalCenter
                }

                // Anchored to the right or the centre, a wider strip moves its
                // left end; easing the width lets the chips already there slide
                // over instead of teleporting when a new one lands.
                Behavior on width {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                add: Transition {
                    NumberAnimation {
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                    NumberAnimation {
                        property: "scale"
                        from: 0.7
                        to: 1
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }

                remove: Transition {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                    NumberAnimation {
                        property: "scale"
                        to: 0.8
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                delegate: Item {
                    id: chip
                    required property string keysJson
                    required property string kind
                    required property int count
                    required property bool held
                    required property int pulse

                    readonly property var keys: JSON.parse(chip.keysJson)

                    implicitWidth: chord.implicitWidth
                    width: implicitWidth
                    height: root.chipHeight

                    Row {
                        id: chord
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Math.round(root.fontSize * 0.3)

                        // Counting the keys rather than listing them keeps the
                        // one cap of a word chip alive as the word grows, so its
                        // width eases instead of a fresh cap snapping in.
                        Repeater {
                            model: chip.keys.length

                            delegate: Row {
                                id: keySlot
                                required property int index
                                readonly property bool isLast: keySlot.index === chip.keys.length - 1
                                spacing: chord.spacing

                                // Centred on the face, not on face plus lip.
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -root.lipHeight / 2
                                    visible: keySlot.index > 0
                                    text: "+"
                                    color: Appearance.colors.colOnSurface
                                    opacity: 0.85
                                    font.pixelSize: root.fontSize
                                    font.weight: Font.DemiBold
                                    font.family: Appearance.font.family.main
                                }

                                Keycap {
                                    label: chip.keys[keySlot.index]
                                    // Modifiers lead in to the key that matters,
                                    // which is the one that carries the accent.
                                    tone: chip.kind === "text" ? "text"
                                        : chip.kind === "modifier" ? "modifier"
                                        : chip.kind === "mouse" ? (keySlot.isLast ? "mouse" : "modifier")
                                        : (keySlot.isLast ? "key" : "modifier")
                                    icon: chip.kind === "mouse" && keySlot.isLast ? root.mouseIcon(chip.keys[keySlot.index]) : ""
                                    held: chip.held
                                    pulse: chip.pulse
                                }
                            }
                        }

                        CountBadge {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -root.lipHeight / 2
                            count: chip.count
                        }
                    }
                }
            }
        }
    }

    function mouseIcon(label) {
        switch (label) {
        case "Click": return "left_click";
        case "Right click": return "right_click";
        case "Back": return "arrow_back";
        case "Forward": return "arrow_forward";
        default: return "mouse";
        }
    }

    /**
     * One key. The face sits `lipHeight` above a darker lip and drops onto it
     * while down; the label rides on the face.
     */
    component Keycap: Item {
        id: cap
        property string label: ""
        property string icon: ""
        // "text" | "modifier" | "key" | "mouse"
        property string tone: "text"
        property bool held: false
        property int pulse: 0

        // A cap arrives already pressed and pops up, so even a tap is seen to
        // land; a repeat presses it again.
        property bool pressing: true
        readonly property bool down: cap.held || cap.pressing

        readonly property color faceColor: cap.held ? Appearance.colors.colPrimary
            : cap.tone === "key" ? Appearance.colors.colPrimaryContainer
            : cap.tone === "modifier" ? Appearance.colors.colSecondaryContainer
            : cap.tone === "mouse" ? Appearance.colors.colTertiaryContainer
            : Appearance.colors.colSurfaceContainerHigh
        readonly property color labelColor: cap.held ? Appearance.colors.colOnPrimary
            : cap.tone === "key" ? Appearance.colors.colOnPrimaryContainer
            : cap.tone === "modifier" ? Appearance.colors.colOnSecondaryContainer
            : cap.tone === "mouse" ? Appearance.colors.colOnTertiaryContainer
            : Appearance.colors.colOnSurface
        readonly property real horizontalPadding: Math.round(root.fontSize * 0.7)

        implicitWidth: Math.max(root.capHeight, content.implicitWidth + cap.horizontalPadding * 2)
        implicitHeight: root.chipHeight

        Behavior on implicitWidth {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        function press() {
            cap.pressing = true;
            releaseTimer.restart();
        }

        Timer {
            id: releaseTimer
            interval: 110
            running: true
            onTriggered: cap.pressing = false
        }

        onPulseChanged: cap.press()

        StyledRectangularShadow {
            target: lip
        }

        Rectangle {
            id: lip
            anchors.left: parent.left
            anchors.right: parent.right
            y: root.lipHeight
            height: root.capHeight
            radius: root.capRadius
            color: root.lipColor(cap.faceColor)

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                }
            }
        }

        Rectangle {
            id: face
            anchors.left: parent.left
            anchors.right: parent.right
            y: cap.down ? root.lipHeight : 0
            height: root.capHeight
            radius: root.capRadius
            color: cap.faceColor
            border.width: 1
            border.color: cap.held ? cap.faceColor : Appearance.colors.colOutlineVariant

            Behavior on y {
                NumberAnimation {
                    duration: 90
                    easing.type: Easing.OutQuad
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                }
            }

            Row {
                id: content
                anchors.centerIn: parent
                spacing: Math.round(root.fontSize * 0.25)

                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    active: cap.icon.length > 0
                    visible: active
                    sourceComponent: MaterialSymbol {
                        text: cap.icon
                        iconSize: Math.round(root.fontSize * 1.15)
                        color: cap.labelColor
                        fill: 1
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: cap.label
                    color: cap.labelColor
                    font.pixelSize: root.fontSize
                    font.weight: Font.DemiBold
                    font.family: Appearance.font.family.main

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }
                }
            }
        }
    }

    /** The `×N` after a chord that was pressed again; bounces on every count. */
    component CountBadge: Item {
        id: badge
        property int count: 1

        // Air between the last cap and the badge, over the row's own spacing,
        // so the badge is read as a count and not as one more key.
        readonly property real gap: Math.round(root.fontSize * 0.2)

        visible: badge.count > 1
        implicitWidth: badge.gap + pill.implicitWidth
        implicitHeight: pill.implicitHeight

        onCountChanged: bounce.restart()

        SequentialAnimation {
            id: bounce
            NumberAnimation {
                target: pill
                property: "scale"
                to: 1.25
                duration: 70
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: pill
                property: "scale"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Rectangle {
            id: pill
            x: badge.gap
            implicitWidth: countText.implicitWidth + Math.round(root.fontSize * 0.6)
            implicitHeight: Math.round(root.fontSize * 1.2)
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary

            Behavior on implicitWidth {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            StyledText {
                id: countText
                anchors.centerIn: parent
                text: "×" + badge.count
                color: Appearance.colors.colOnPrimary
                font.pixelSize: Math.round(root.fontSize * 0.65)
                font.weight: Font.Bold
                font.family: Appearance.font.family.main
            }
        }
    }
}
