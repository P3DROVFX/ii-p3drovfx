pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Picking which shell you are running.
 *
 * The shell has had three panel families and a working hot switch for a long time, reachable
 * only through `qs -c ii ipc call panelFamily cycle` and a keybind nobody binds. Neither
 * Settings nor the first-run flow mentioned that the choice existed, so in practice the
 * feature was invisible: the tablet family in particular was something you had to be told
 * about. This is the surface that offers it.
 *
 * Modelled on SessionScreen — dimmed backdrop, click anywhere to cancel, a centred column
 * with a cascade of large targets, arrow keys and Escape — because it is the same kind of
 * decision, made the same way. It differs in two respects, both deliberate:
 *
 *  - It selects rather than cycles. Three families means three targets; making someone pass
 *    through the middle one to reach the third rebuilds a whole shell for nothing.
 *  - It lives in modules/common and every family loads it. A chooser that only one family
 *    offered would be a chooser you could switch away from and never find again.
 */
Scope {
    id: root

    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    property bool activeState: false
    property bool contentShown: false

    // Outlives the fade so the cards can animate away instead of vanishing with the window.
    Timer {
        id: closeTimer
        interval: 280
        repeat: false
        onTriggered: root.activeState = false
    }

    Connections {
        target: GlobalStates
        function onShellSwitcherOpenChanged() {
            if (GlobalStates.shellSwitcherOpen) {
                closeTimer.stop();
                root.activeState = true;
                Qt.callLater(() => root.contentShown = true);
            } else {
                root.contentShown = false;
                closeTimer.restart();
            }
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                GlobalStates.shellSwitcherOpen = false;
        }
    }

    Loader {
        id: switcherLoader
        active: root.activeState

        sourceComponent: PanelWindow {
            id: switcherWindow
            visible: switcherLoader.active

            screen: root.focusedScreen
            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }
            implicitWidth: root.focusedScreen?.width ?? 0
            implicitHeight: root.focusedScreen?.height ?? 0

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:shellSwitcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            function hide() {
                GlobalStates.shellSwitcherOpen = false;
            }

            /**
             * Switching tears down every surface on screen and builds another set, which
             * takes a beat. Closing first and switching after means the user watches a bare
             * desktop with no explanation of what is happening; keeping the sheet up with a
             * message means the pause is accounted for.
             */
            function choose(familyId) {
                if (familyId === PanelFamily.current) {
                    switcherWindow.hide();
                    return;
                }
                switcherWindow.switching = true;
                switchTimer.restart();
            }

            property bool switching: false
            property string pendingFamily: ""

            Timer {
                id: switchTimer
                interval: 220
                repeat: false
                onTriggered: {
                    // This window belongs to the family being replaced, so it goes away on
                    // its own the moment the loader swaps. Clearing the state first keeps
                    // the next family from coming up with the chooser still open.
                    GlobalStates.shellSwitcherOpen = false;
                    PanelFamily.select(switcherWindow.pendingFamily);
                }
            }

            Component.onCompleted: {
                if (root.contentShown)
                    switcherWindow.cascadeIn();
            }

            function cascadeIn() {
                for (let i = 0; i < cardRepeater.count; i++)
                    cardRepeater.itemAt(i)?.animateIn();
                cardRepeater.itemAt(0)?.forceActiveFocus();
            }
            function cascadeOut() {
                for (let i = 0; i < cardRepeater.count; i++)
                    cardRepeater.itemAt(i)?.animateOut();
            }

            Connections {
                target: root
                function onContentShownChanged() {
                    if (root.contentShown)
                        switcherWindow.cascadeIn();
                    else
                        switcherWindow.cascadeOut();
                }
            }

            Rectangle {
                id: dimBackground
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.m3colors.m3background,
                                                 Appearance.m3colors.darkmode ? 0.05 : 0.12)
                opacity: root.contentShown ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !switcherWindow.switching
                    onClicked: switcherWindow.hide()
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 26
                scale: root.contentShown ? 1.0 : 0.92
                opacity: root.contentShown ? 1.0 : 0.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Keys.onEscapePressed: switcherWindow.hide()

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 2

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Shell")
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.title
                            variableAxes: Appearance.font.variableAxes.title
                        }
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: switcherWindow.switching
                            ? Translation.tr("Rebuilding the shell…")
                            : Translation.tr("Choose the interface for this device\nArrow keys to navigate, Enter to select, Esc to cancel")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 18
                    // Cards differ in height now, so they hang from a shared centre line
                    // instead of stretching to the tallest.
                    uniformCellSizes: false
                    enabled: !switcherWindow.switching
                    opacity: switcherWindow.switching ? 0.45 : 1.0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Repeater {
                        id: cardRepeater
                        model: PanelFamily.available

                        delegate: ShellFamilyCard {
                            id: familyCard
                            required property var modelData
                            required property int index

                            Layout.alignment: Qt.AlignVCenter
                            family: familyCard.modelData
                            animIndex: familyCard.index
                            isCurrent: familyCard.modelData.id === PanelFamily.current

                            // Wrapping arrow keys: three targets in a row, and a chooser you
                            // can walk off the end of is a chooser that traps the focus ring.
                            KeyNavigation.right: cardRepeater.itemAt((familyCard.index + 1) % cardRepeater.count)
                            KeyNavigation.left: cardRepeater.itemAt((familyCard.index - 1 + cardRepeater.count) % cardRepeater.count)

                            onClicked: {
                                switcherWindow.pendingFamily = familyCard.modelData.id;
                                switcherWindow.choose(familyCard.modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }
}
