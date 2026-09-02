import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common

/**
 * The desktop right-click menu's surface: one per screen, and it exists only
 * while the menu is open on that screen.
 *
 * Why a surface of its own: the menu is asked for from two windows - the
 * widget canvas when it is mapped, the wallpaper window when it is not - and
 * outside Edit Mode there is no chrome to draw it on. A per-open Overlay
 * surface is the honest shape: a menu is a rare gesture, not a mode.
 *
 * The surface is the whole screen so a click anywhere else dismisses, and
 * takes keyboard focus on demand so Escape does too.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: menuLoader
            required property var modelData

            readonly property string screenName: modelData ? modelData.name : ""
            active: GlobalStates.desktopMenuOpen && GlobalStates.desktopMenuScreenName === menuLoader.screenName

            component: PanelWindow {
                id: menuWindow
                screen: menuLoader.modelData
                color: "transparent"
                WlrLayershell.namespace: "quickshell:desktopMenu"
                WlrLayershell.layer: WlrLayer.Overlay
                // Exclusive: a menu is modal for as long as it is up, and Escape must
                // reach it whichever window had focus before the right-click.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: GlobalStates.closeDesktopMenu()
                }

                // The menu opens with its corner under the pointer, so the row it
                // opened on is already beneath the cursor. Until the pointer has
                // actually gone somewhere, a second click - either button - is the
                // user waving the menu away, not choosing that row; this sheet takes
                // it and dismisses. It stops mattering the moment the pointer moves,
                // and every following click reaches the card as usual.
                MouseArea {
                    id: dismissGuard
                    anchors.fill: parent
                    z: 100
                    readonly property real moveThreshold: 6
                    property bool armed: true
                    enabled: dismissGuard.armed
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPositionChanged: mouse => {
                        if (Math.abs(mouse.x - GlobalStates.desktopMenuX) <= dismissGuard.moveThreshold
                            && Math.abs(mouse.y - GlobalStates.desktopMenuY) <= dismissGuard.moveThreshold)
                            return;
                        dismissGuard.armed = false;
                    }
                    onPressed: GlobalStates.closeDesktopMenu()
                }

                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onPressed: event => {
                        if (event.key !== Qt.Key_Escape)
                            return;
                        event.accepted = true;
                        GlobalStates.closeDesktopMenu();
                    }
                }

                DesktopMenuCard {
                    id: menuCard
                    origin: GlobalStates.desktopMenuOrigin
                    x: Math.min(Math.max(GlobalStates.desktopMenuX, 8), menuWindow.width - width - 8)
                    y: Math.min(Math.max(GlobalStates.desktopMenuY, 8), menuWindow.height - height - 8)
                    onDismissRequested: GlobalStates.closeDesktopMenu()
                    transformOrigin: Item.TopLeft
                    scale: 0.85
                    opacity: 0
                    Component.onCompleted: {
                        scale = 1.0;
                        opacity = 1.0;
                    }
                    Behavior on scale {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(menuCard)
                    }
                    Behavior on opacity {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(menuCard)
                    }
                }
            }
        }
    }
}
