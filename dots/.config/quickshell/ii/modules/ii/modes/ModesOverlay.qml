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
    // Snapshot the saved page before asynchronously constructing the surface.
    property string pendingTab: "modes"

    function resolveView() {
        root.pendingTab = Config.options.modes?.lastTab ?? "modes";
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


    function requestOpen() {
        root.resolveView();
        root.activeState = true;
        GlobalStates.modesOpen = true;
    }

    function requestClose() {
        GlobalStates.modesOpen = false;
        if (!modesLoader.item) root.activeState = false;
    }

    function requestToggle() {
        if (GlobalStates.modesOpen) {
            root.requestClose();
        } else {
            root.requestOpen();
        }
    }

    RetainedLoader {
        id: modesLoader
        requested: root.activeState
        // Keep only the most recently used Modes surface warm. Once the short
        // retention window expires, the editor/list tree is destroyed fully.
        retainFor: 30000

        sourceComponent: PanelWindow {
            id: modesRoot

            visible: root.activeState
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
                interval: 0
                onTriggered: GlobalFocusGrab.addDismissable(modesRoot)
            }

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
                if (visible) {
                    initialFocusTimer.restart();
                    registerGrabTimer.restart();
                    return;
                }
                registerGrabTimer.stop();
                GlobalFocusGrab.removeDismissable(modesRoot);
            }

            Timer {
                id: initialFocusTimer
                interval: 0
                onTriggered: modesBackground.forceActiveFocus()
            }

            Item {
                id: modesInputMask
                anchors.centerIn: parent
                width: modesBackground.width
                height: modesBackground.height
            }


            WindowAnimationSurface {
                id: dialogWrap
                anchors.fill: parent
                open: GlobalStates.modesOpen
                mapped: modesRoot.visible
                panelWidth: modesBackground.width
                panelHeight: modesBackground.height
                onClosed: if (!GlobalStates.modesOpen) root.activeState = false

                StyledRectangularShadow {
                    target: modesBackground
                }

                Rectangle {
                    id: modesBackground

                    property real padding: 20
                    readonly property real maxBgWidth: modesRoot.screen ? modesRoot.screen.width * 0.95 : 1900
                    readonly property real maxBgHeight: modesRoot.screen ? modesRoot.screen.height * 0.80 : 1000

                    anchors.centerIn: parent
                    color: Appearance.colors.colLayer0
                    radius: Appearance.rounding.windowRounding
                    implicitWidth: Math.min(maxBgWidth, modesContent.implicitWidth + padding * 2)
                    implicitHeight: Math.min(maxBgHeight, modesContent.implicitHeight + padding * 2)


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
                        z: 2
                        onClicked: modesRoot.hide()

                        anchors {
                            top: parent.top
                            right: parent.right
                            topMargin: 20
                            rightMargin: 20
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
                        // Match Usage's page size plus its tab row and spacing.
                        implicitWidth: Math.min(1500, Math.max(900, calculatedWidth))
                        implicitHeight: Math.min(700, Math.max(460, calculatedHeight)) + headerHeight

                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - parent.padding * 2)
                        height: Math.min(implicitHeight, parent.height - parent.padding * 2)
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
