pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sessionScreen
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

/**
 * The session menu, inside the island.
 *
 * The same eight actions in the same four-by-two grid as the full-screen session
 * screen, drawn with the same SessionActionButton - only smaller, and on the island's
 * surface instead of over a dimmed desktop. Reusing the button is what keeps the two in
 * step: its shape, its colours, its focus behaviour and its keyboard handling are the
 * session screen's, not a copy of them.
 *
 * Sized like search: it declares what it wants and the island animates to it, so the
 * two are never chasing each other.
 */
Item {
    id: root

    /** The island hands these over; see NotchContent. */
    property bool active: false
    signal closeRequested

    // ── What the island should be ────────────────────────────────────────────
    /** Declared, never measured off anything that moves. */
    readonly property real buttonSize: 84
    readonly property real gridSpacing: 10
    readonly property real padding: 14
    readonly property real headerHeight: 30

    readonly property real contentTargetWidth: 4 * root.buttonSize + 3 * root.gridSpacing + 2 * root.padding
    readonly property real contentTargetHeight: root.headerHeight + 2 * root.buttonSize
        + root.gridSpacing + 2 * root.padding

    /** The action the keyboard is on, named in the header - the icons alone are terse. */
    property string focusedAction: Translation.tr("Lock")

    function hide() {
        root.closeRequested();
    }

    /** The cascade the session screen plays, so the buttons arrive the same way. */
    function animateIn() {
        sessionLock.animateIn();
        sessionSleep.animateIn();
        sessionLogout.animateIn();
        sessionOledSaver.animateIn();
        sessionHibernate.animateIn();
        sessionShutdown.animateIn();
        sessionReboot.animateIn();
        sessionFirmwareReboot.animateIn();
        sessionLock.forceActiveFocus();
    }

    function animateOut() {
        sessionLock.animateOut();
        sessionSleep.animateOut();
        sessionLogout.animateOut();
        sessionOledSaver.animateOut();
        sessionHibernate.animateOut();
        sessionShutdown.animateOut();
        sessionReboot.animateOut();
        sessionFirmwareReboot.animateOut();
    }

    onActiveChanged: {
        if (root.active) {
            SessionWarnings.refresh();
            root.animateIn();
        } else {
            root.animateOut();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.hide();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 0

        // Title on the left, the focused action on the right: the session screen says
        // both too, and here it costs one row rather than three.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 8

            StyledText {
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.large
                    variableAxes: Appearance.font.variableAxes.title
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Session")
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: root.focusedAction
                elide: Text.ElideRight
                Layout.maximumWidth: root.width / 2
            }
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 4
            columnSpacing: root.gridSpacing
            rowSpacing: root.gridSpacing

            component IslandSessionButton: SessionActionButton {
                size: root.buttonSize
                onFocusChanged: {
                    if (focus)
                        root.focusedAction = buttonText;
                }
            }

            IslandSessionButton {
                id: sessionLock
                animIndex: 0
                focus: root.active
                buttonIcon: "lock"
                buttonText: Translation.tr("Lock")
                onClicked: {
                    root.hide();
                    Session.lock();
                }
                KeyNavigation.right: sessionSleep
                KeyNavigation.down: sessionHibernate
            }
            IslandSessionButton {
                id: sessionSleep
                animIndex: 1
                buttonIcon: "dark_mode"
                buttonText: Translation.tr("Sleep")
                onClicked: {
                    root.hide();
                    Session.suspend();
                }
                KeyNavigation.left: sessionLock
                KeyNavigation.right: sessionLogout
                KeyNavigation.down: sessionShutdown
            }
            IslandSessionButton {
                id: sessionLogout
                animIndex: 2
                buttonIcon: "logout"
                buttonText: Translation.tr("Logout")
                onClicked: {
                    root.hide();
                    Session.logout();
                }
                KeyNavigation.left: sessionSleep
                KeyNavigation.right: sessionOledSaver
                KeyNavigation.down: sessionReboot
            }
            IslandSessionButton {
                id: sessionOledSaver
                animIndex: 3
                buttonIcon: "tv_off"
                buttonText: Translation.tr("OLED Saver")
                onClicked: {
                    root.hide();
                    const name = Hyprland.focusedMonitor?.name || (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
                    if (name) {
                        const monitors = GlobalStates.oledSaverMonitors;
                        GlobalStates.oledSaverMonitors = monitors.includes(name) ? monitors.filter(n => n !== name) : [...monitors, name];
                    }
                }
                KeyNavigation.left: sessionLogout
                KeyNavigation.down: sessionFirmwareReboot
            }

            IslandSessionButton {
                id: sessionHibernate
                animIndex: 4
                buttonIcon: "downloading"
                buttonText: Translation.tr("Hibernate")
                onClicked: {
                    root.hide();
                    Session.hibernate();
                }
                KeyNavigation.up: sessionLock
                KeyNavigation.right: sessionShutdown
            }
            IslandSessionButton {
                id: sessionShutdown
                animIndex: 5
                buttonIcon: "power_settings_new"
                buttonText: Translation.tr("Shutdown")
                onClicked: {
                    root.hide();
                    Session.poweroff();
                }
                KeyNavigation.left: sessionHibernate
                KeyNavigation.right: sessionReboot
                KeyNavigation.up: sessionSleep
            }
            IslandSessionButton {
                id: sessionReboot
                animIndex: 6
                buttonIcon: "restart_alt"
                buttonText: Translation.tr("Reboot")
                onClicked: {
                    root.hide();
                    Session.reboot();
                }
                KeyNavigation.left: sessionShutdown
                KeyNavigation.right: sessionFirmwareReboot
                KeyNavigation.up: sessionLogout
            }
            IslandSessionButton {
                id: sessionFirmwareReboot
                animIndex: 7
                buttonIcon: "settings_applications"
                buttonText: Translation.tr("Reboot to firmware settings")
                onClicked: {
                    root.hide();
                    Session.rebootToFirmware();
                }
                KeyNavigation.left: sessionReboot
                KeyNavigation.up: sessionOledSaver
            }
        }
    }
}
