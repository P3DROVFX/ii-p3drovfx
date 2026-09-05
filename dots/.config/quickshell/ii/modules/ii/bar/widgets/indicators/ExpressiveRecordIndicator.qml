pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Material 3 Expressive record indicator.
 *
 * The old design was two loose shapes — a nine-sided cookie holding a dot, and
 * a pill holding the clock — that never resolved into one object. This family
 * commits to one silhouette per variant and lets the *type* carry the state:
 *
 *   capsule  One filled capsule. A wordmark that swaps REC -> STOP under the
 *            pointer, and the clock rolling beside it.
 *   badge    An organic badge overhanging a plate, the same construction the
 *            Expressive date uses, so the two sit together in a bar.
 *   ribbon   One capsule cut in two tones by type alone: the accent end is the
 *            wordmark, the container end is the clock. No glyph anywhere.
 *
 * Nothing here breathes, glows or oscillates. The only movement is the digit
 * that just changed and the wordmark that swaps on hover — both one-shot, both
 * caused by something.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property bool minimal: false
    property bool live: false
    property bool loading: false
    property bool paused: false
    property bool hovering: false
    property bool animateDigits: true
    property bool showLabel: true
    property string timeText: "00:00"
    property string label: "REC"
    property string stateIcon: "videocam"

    readonly property string variant: Config.options.bar.indicators.record.expressiveVariant ?? "capsule"
    readonly property bool showTime: !root.minimal && !root.loading

    BarWidgetPalette {
        id: theme
        colorMode: Config.options.bar.indicators.record.colorMode ?? "alert"
    }

    readonly property real labelPixelSize: Math.max(9, Math.round(root.thickness * (root.vertical ? 0.25 : 0.29)))
    readonly property real timePixelSize: Math.max(10, Math.round(root.thickness * (root.vertical ? 0.34 : 0.42)))
    readonly property real iconPixelSize: Math.round(root.thickness * (root.vertical ? 0.42 : 0.46))

    // A paused capture is still a capture, so it keeps its colour and loses its
    // insistence instead.
    readonly property real stateOpacity: root.paused ? 0.72 : 1.0

    implicitWidth: contentLoader.implicitWidth
    implicitHeight: contentLoader.implicitHeight

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: {
            if (root.variant === "badge")
                return badgeVariant;
            if (root.variant === "ribbon")
                return ribbonVariant;
            return capsuleVariant;
        }
    }

    // ── capsule ──────────────────────────────────────────────────────────────
    Component {
        id: capsuleVariant

        Rectangle {
            id: capsule

            implicitWidth: root.vertical
                ? root.thickness
                : capsuleContent.implicitWidth + Math.round(root.thickness * 0.56)
            implicitHeight: root.vertical
                ? capsuleContent.implicitHeight + Math.round(root.thickness * 0.44)
                : root.thickness
            radius: Appearance.rounding.full
            color: root.hovering ? theme.colContainer : theme.colAccent
            opacity: root.stateOpacity

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(capsule)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(capsule)
            }

            readonly property color colContent: root.hovering ? theme.colOnContainer : theme.colOnAccent

            GridLayout {
                id: capsuleContent
                anchors.centerIn: parent
                columns: root.vertical ? 1 : 2
                columnSpacing: Math.round(root.thickness * 0.22)
                rowSpacing: -1

                // The wordmark doubles as the spinner slot: while the portal is
                // still deciding there is no elapsed time to show, so the word
                // is all there is.
                RowLayout {
                    Layout.alignment: Qt.AlignCenter
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.loading
                        text: "progress_activity"
                        iconSize: root.labelPixelSize + 2
                        color: capsule.colContent

                        RotationAnimator on rotation {
                            running: root.loading
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.showLabel || root.minimal || root.loading
                        text: root.label
                        // The swap is the hover feedback in full: no scale, no
                        // border, just the word sliding to the other word.
                        animateChange: !Appearance.reducedMotion
                        animationDistanceX: 0
                        animationDistanceY: Math.round(root.labelPixelSize * 0.4)
                        color: capsule.colContent
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.labelPixelSize
                        font.variableAxes: ({
                            "wght": 800
                        })
                        font.letterSpacing: 1.1
                    }
                }

                RecordTimerText {
                    Layout.alignment: Qt.AlignCenter
                    visible: root.showTime
                    value: root.timeText
                    stacked: root.vertical
                    stackSpacing: -3
                    pixelSize: root.timePixelSize
                    colText: capsule.colContent
                    weight: 750
                    letterSpacing: -0.4
                    animate: root.animateDigits
                }
            }
        }
    }

    // ── badge ────────────────────────────────────────────────────────────────
    Component {
        id: badgeVariant

        Item {
            id: badgeRoot

            readonly property real badgeSize: Math.round(root.thickness * (root.vertical ? 0.84 : 0.96))
            // How far the badge sits over the plate's rounded end. It stays
            // inside the measured box, so the overhang is drawn and never
            // spills onto the next widget in the bar.
            readonly property real overlap: Math.round(badgeRoot.badgeSize * 0.4)

            implicitWidth: root.vertical
                ? root.thickness
                : (root.showTime
                    ? badgeRoot.badgeSize + timePlate.implicitWidth - badgeRoot.overlap
                    : badgeRoot.badgeSize)
            implicitHeight: root.vertical
                ? (root.showTime
                    ? badgeRoot.badgeSize + timePlate.implicitHeight - badgeRoot.overlap
                    : badgeRoot.badgeSize)
                : root.thickness
            opacity: root.stateOpacity

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(badgeRoot)
            }

            Rectangle {
                id: timePlate
                visible: root.showTime
                implicitWidth: root.vertical
                    ? root.thickness
                    : plateTime.implicitWidth + badgeRoot.overlap + Math.round(root.thickness * 0.44)
                implicitHeight: root.vertical
                    ? plateTime.implicitHeight + badgeRoot.overlap + Math.round(root.thickness * 0.28)
                    : Math.round(root.thickness * 0.82)
                // A block against an organic badge. Matching the badge's own
                // curvature welds the pair into one blob at bar scale.
                radius: Appearance.rounding.small
                color: theme.colContainer

                anchors.right: root.vertical ? undefined : parent.right
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.bottom: root.vertical ? parent.bottom : undefined
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

                RecordTimerText {
                    id: plateTime
                    value: root.timeText
                    stacked: root.vertical
                    stackSpacing: -3
                    pixelSize: root.timePixelSize
                    colText: theme.colOnContainer
                    weight: 750
                    letterSpacing: -0.4
                    animate: root.animateDigits

                    anchors.right: root.vertical ? undefined : parent.right
                    anchors.rightMargin: root.vertical ? 0 : Math.round(root.thickness * 0.22)
                    anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                    anchors.bottom: root.vertical ? parent.bottom : undefined
                    anchors.bottomMargin: root.vertical ? Math.round(root.thickness * 0.11) : 0
                }
            }

            MaterialShape {
                id: stateBadge
                implicitSize: badgeRoot.badgeSize
                shape: MaterialShape.Shape.Cookie9Sided
                color: root.hovering ? theme.colContainer : theme.colAccent

                anchors.left: root.vertical ? undefined : parent.left
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.top: root.vertical ? parent.top : undefined
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(stateBadge)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.stateIcon
                    iconSize: Math.round(badgeRoot.badgeSize * 0.46)
                    fill: root.live ? 1 : 0
                    color: root.hovering ? theme.colOnContainer : theme.colOnAccent

                    RotationAnimator on rotation {
                        running: root.loading
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                    }
                }
            }
        }
    }

    // ── ribbon ───────────────────────────────────────────────────────────────
    Component {
        id: ribbonVariant

        Rectangle {
            id: ribbon

            // The wordmark end. It is sized off the type, not off a circle:
            // `badge` already owns "a round thing beside a plate", and a second
            // variant built the same way would only differ by its outline.
            readonly property real capLength: root.vertical
                ? Math.round(root.thickness * 0.58)
                : capContent.implicitWidth + Math.round(root.thickness * 0.5)

            // Minimal keeps both tones. Collapsing to the cap alone would make
            // this variant indistinguishable from `capsule`, which is exactly
            // the same pill with the same word in it.
            // While the portal is still deciding there is no clock and no state
            // to put in the body — the cap already carries the spinner — so the
            // body closes up rather than showing the same spinner twice.
            readonly property bool showBodyIcon: !root.showTime && !root.loading
            readonly property real bodyLength: root.showTime
                ? ribbonTime.implicitWidth + Math.round(root.thickness * 0.52)
                : (ribbon.showBodyIcon ? root.thickness : 0)
            readonly property real bodyThickness: root.showTime
                ? ribbonTime.implicitHeight + Math.round(root.thickness * 0.4)
                : (ribbon.showBodyIcon ? root.thickness : 0)

            implicitWidth: root.vertical
                ? root.thickness
                : ribbon.capLength + ribbon.bodyLength
            implicitHeight: root.vertical
                ? ribbon.capLength + ribbon.bodyThickness
                : root.thickness
            radius: Appearance.rounding.full
            color: theme.colContainer
            opacity: root.stateOpacity

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(ribbon)
            }

            Rectangle {
                id: ribbonCap
                width: root.vertical ? root.thickness : ribbon.capLength
                height: root.vertical ? ribbon.capLength : root.thickness
                radius: Appearance.rounding.full
                color: root.hovering ? theme.colOnContainer : theme.colAccent

                anchors.left: root.vertical ? undefined : parent.left
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.top: root.vertical ? parent.top : undefined
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(ribbonCap)
                }

                Row {
                    id: capContent
                    anchors.centerIn: parent
                    spacing: 3

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.loading
                        text: "progress_activity"
                        iconSize: root.labelPixelSize + 2
                        color: root.hovering ? theme.colContainer : theme.colOnAccent

                        RotationAnimator on rotation {
                            running: root.loading
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }

                    // With the wordmark switched off the cap still has to say
                    // something, or this variant loses the half that makes it
                    // two-tone. The glyph takes the word's place rather than
                    // leaving a blank lozenge.
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.showLabel && !root.loading
                        text: root.stateIcon
                        iconSize: root.iconPixelSize
                        fill: root.live ? 1 : 0
                        color: root.hovering ? theme.colContainer : theme.colOnAccent
                    }

                    StyledText {
                        id: ribbonLabel
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.showLabel
                        text: root.label
                        animateChange: !Appearance.reducedMotion
                        animationDistanceX: 0
                        animationDistanceY: Math.round(root.labelPixelSize * 0.4)
                        color: root.hovering ? theme.colContainer : theme.colOnAccent
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.labelPixelSize
                        font.variableAxes: ({
                            "wght": 800
                        })
                        font.letterSpacing: 1.1
                    }
                }
            }

            // What the body carries when there is no clock to carry.
            MaterialSymbol {
                visible: ribbon.showBodyIcon
                text: root.stateIcon
                iconSize: root.iconPixelSize
                fill: root.live ? 1 : 0
                color: theme.colOnContainer

                anchors.left: root.vertical ? undefined : ribbonCap.right
                anchors.leftMargin: root.vertical ? 0 : Math.round((ribbon.bodyLength - width) / 2)
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.top: root.vertical ? ribbonCap.bottom : undefined
                anchors.topMargin: root.vertical ? Math.round((ribbon.bodyThickness - height) / 2) : 0
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            }

            RecordTimerText {
                id: ribbonTime
                visible: root.showTime
                value: root.timeText
                stacked: root.vertical
                stackSpacing: -3
                pixelSize: root.timePixelSize
                colText: theme.colOnContainer
                weight: 750
                letterSpacing: -0.4
                animate: root.animateDigits

                anchors.left: root.vertical ? undefined : ribbonCap.right
                anchors.leftMargin: root.vertical ? 0 : Math.round(root.thickness * 0.24)
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.top: root.vertical ? ribbonCap.bottom : undefined
                anchors.topMargin: root.vertical ? Math.round(root.thickness * 0.1) : 0
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            }
        }
    }
}
