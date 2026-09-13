pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Which screen is which, said on the screens themselves.
 *
 * The displays step asks the reader to arrange rectangles that stand for
 * their monitors, and nothing on the page says which rectangle is the panel
 * in front of them and which is the one off to the side. Every other desktop
 * answers this the same way: put a number on each physical screen.
 *
 * One surface per screen, so the number is genuinely on that panel rather
 * than being a picture of it.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: identifier

            required property var modelData

            readonly property int position: Math.max(0,
                Array.from(Quickshell.screens).findIndex(screen => screen.name === identifier.modelData.name))

            screen: identifier.modelData
            visible: GlobalStates.displayIdentifyActive
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:displayIdentify"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Nothing here is clickable: the card is an answer, not a control,
            // and a screen-wide surface that takes input would swallow the
            // arrangement the reader is meant to be dragging.
            mask: Region {}

            // In a corner, not in the middle. This is an Overlay surface, so a
            // centred badge lands squarely on top of the very page that is
            // asking the question — and the answer is about the screen, not
            // about the middle of it. The surface is only as big as the badge
            // for the same reason: a screen-sized transparent layer is one the
            // compositor still has to composite over everything.
            anchors.bottom: true
            anchors.left: true
            margins.bottom: Appearance.rounding.verylarge
            margins.left: Appearance.rounding.verylarge

            implicitWidth: badge.implicitWidth
            implicitHeight: badge.implicitHeight

            Rectangle {
                id: badge

                anchors.centerIn: parent
                implicitWidth: Math.max(badgeBody.implicitWidth + Appearance.rounding.large * 2,
                    badge.implicitHeight)
                implicitHeight: badgeBody.implicitHeight + Appearance.rounding.large
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colPrimaryContainer

                // Arrives with the page rather than blinking into place.
                scale: GlobalStates.displayIdentifyActive ? 1 : 0.86
                opacity: GlobalStates.displayIdentifyActive ? 1 : 0

                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(badge)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(badge)
                }

                ColumnLayout {
                    id: badgeBody

                    anchors.centerIn: parent
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: String(identifier.position + 1)
                        color: Appearance.colors.colOnPrimaryContainer
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.title
                        // Big enough to read from across a desk — the distance
                        // the second monitor usually is — without being the
                        // size it would be if it owned the whole screen.
                        font.pixelSize: Appearance.font.pixelSize.hugeass * 3
                        font.weight: Font.Bold
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Appearance.rounding.verysmall
                        text: identifier.modelData.name
                        color: Appearance.colors.colOnPrimaryContainer
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("%1 × %2")
                            .arg(String(identifier.modelData.width))
                            .arg(String(identifier.modelData.height))
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.7
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }
}
