import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * The Modes & Routines manager, on Super+Y.
 *
 * Same shape as the usage overlay: one centred surface on the overlay layer,
 * held open by a focus grab and dismissed by anything that takes focus away.
 * The window is torn down on close, so the editor costs nothing while shut.
 * The IPC target `modes` lives in the engine; this only answers the
 * GlobalShortcuts and GlobalStates.modesOpen.
 */
Scope {
    id: root

    property bool activeState: false
    // Written back by the content as it is used, read once per opening.
    property string pendingTab: "modes"

    function resolveView() {
        root.pendingTab = Config.options.modes.lastTab || "modes";
    }

    Connections {
        target: GlobalStates

        function onModesOpenChanged() {
            if (GlobalStates.modesOpen && !root.activeState) {
                root.requestOpen();
            } else if (!GlobalStates.modesOpen && root.activeState) {
                root.requestClose();
            }
        }
    }

    // Outlives the close animation, so the surface is not destroyed mid-fade.
    Timer {
        id: closeTimer
        interval: 400
        onTriggered: root.activeState = false
    }

    function requestOpen() {
        closeTimer.stop();
        root.resolveView();
        root.activeState = true;
        GlobalStates.modesOpen = true;
    }

    function requestClose() {
        GlobalStates.modesOpen = false;
        closeTimer.start();
    }

    function requestToggle() {
        if (GlobalStates.modesOpen) {
            root.requestClose();
        } else {
            root.requestOpen();
        }
    }

    Loader {
        id: modesLoader
        active: root.activeState

        sourceComponent: PanelWindow {
            id: modesRoot

            visible: modesLoader.active
            color: "transparent"
            exclusiveZone: 0
            implicitWidth: modesBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: modesBackground.height + Appearance.sizes.elevationMargin * 2

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.namespace: "quickshell:modes"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.modesOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Clicks outside the panel belong to whatever is underneath.
            mask: Region {
                item: modesInputMask
            }

            function hide() {
                root.requestClose();
            }

            // Registering the grab immediately would catch the keypress that
            // opened the overlay and close it again.
            Timer {
                id: registerGrabTimer
                interval: 150
                onTriggered: GlobalFocusGrab.addDismissable(modesRoot)
            }

            Component.onCompleted: registerGrabTimer.start()

            Component.onDestruction: {
                registerGrabTimer.stop();
                GlobalFocusGrab.removeDismissable(modesRoot);
            }

            Connections {
                target: GlobalFocusGrab

                function onDismissed() {
                    modesRoot.hide();
                }
            }

            onVisibleChanged: {
                if (visible)
                    initialFocusTimer.restart();
            }

            Timer {
                id: initialFocusTimer
                interval: 50
                onTriggered: modesBackground.forceActiveFocus()
            }

            Item {
                id: modesInputMask
                anchors.centerIn: parent
                width: modesBackground.width
                height: modesBackground.height
            }

            Item {
                id: dialogWrap
                anchors.fill: parent
                transformOrigin: Item.Center
                scale: modesBackground.animateIn && GlobalStates.modesOpen ? 1.0 : 0.94
                opacity: modesBackground.animateIn && GlobalStates.modesOpen ? 1.0 : 0.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                StyledRectangularShadow {
                    target: modesBackground
                }

                Rectangle {
                    id: modesBackground

                    property real padding: 20
                    property bool animateIn: false
                    readonly property real maxBgWidth: modesRoot.screen ? modesRoot.screen.width * 0.95 : 1900
                    readonly property real maxBgHeight: modesRoot.screen ? modesRoot.screen.height * 0.80 : 1000

                    anchors.centerIn: parent
                    color: Appearance.colors.colLayer0
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.windowRounding
                    implicitWidth: Math.min(maxBgWidth, modesContent.implicitWidth + padding * 2)
                    implicitHeight: Math.min(maxBgHeight, modesContent.implicitHeight + padding * 2)

                    // Held back one frame so the panel is laid out before it moves.
                    Timer {
                        id: animDelayTimer
                        interval: 80
                        running: true
                        onTriggered: modesBackground.animateIn = true
                    }

                    // Escape belongs to the window unless a picker is open and
                    // wants it first; everything else is the content's.
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            if (modesContent.handleEscape()) {
                                event.accepted = true;
                                return;
                            }
                            modesRoot.hide();
                            event.accepted = true;
                            return;
                        }
                        event.accepted = modesContent.handleKey(event.key, event.modifiers);
                    }

                    RippleButton {
                        id: closeButton

                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        scale: modesBackground.animateIn ? 1.0 : 0.0
                        z: 2
                        onClicked: modesRoot.hide()

                        anchors {
                            top: parent.top
                            right: parent.right
                            topMargin: 20
                            rightMargin: 20
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.5
                            }
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.title
                            text: "close"
                            rotation: closeButton.isHovered ? 90 : 0

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.5
                                }
                            }
                        }
                    }

                    ModesContent {
                        id: modesContent

                        readonly property real calculatedWidth: modesRoot.screen ? modesRoot.screen.width * 0.92 : 1700
                        readonly property real calculatedHeight: modesRoot.screen ? modesRoot.screen.height * 0.62 : 650

                        anchors.centerIn: parent
                        width: Math.min(1500, Math.max(900, calculatedWidth), parent.width - parent.padding * 2)
                        height: Math.min(700, Math.max(460, calculatedHeight), parent.height - parent.padding * 2)
                        initialTab: root.pendingTab
                        onRequestClose: modesRoot.hide()
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "modesToggle"
        description: "Toggles the Modes & Routines overlay on press"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "modesOpen"
        description: "Opens the Modes & Routines overlay on press"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "modesClose"
        description: "Closes the Modes & Routines overlay on press"
        onPressed: root.requestClose()
    }
}
