import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function openSubPage(url) {
        subPageOverlay.open(Qt.resolvedUrl(url));
    }

    anchors.fill: parent

    ContentPage {
        id: page

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        KeyboardShortcutBox {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            text: Translation.tr("Toggle the Cheatsheet")
            keys: ["Super", "/"]
        }

        // ── Cheatsheet Widgets ────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Cheatsheet Widgets")
            icon: "widgets"
            tooltip: Translation.tr("Enable or configure interactive reference panels in the cheatsheet.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "settings"
                    text: Translation.tr("Each page's own options — key symbols and font sizes for Keybinds; display, reminders, calendar colors and sources for Timetable; the Amino acids classification; the Commands layout — live inside the Cheatsheet, behind the gear next to its close button.")
                }

                ConfigSwitch {
                    buttonIcon: "bolt"
                    text: Translation.tr("Keep last tab ready")
                    checked: Config.options.cheatsheet.keepLastTabLoaded
                    onCheckedChanged: {
                        if (Config.ready && checked !== Config.options.cheatsheet.keepLastTabLoaded)
                            Config.options.cheatsheet.keepLastTabLoaded = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Keep only the last opened tab in memory for quick reopening. Switching tabs releases the previous one.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "calendar_month"
                    text: Translation.tr("Enable Timetable")
                    checked: Config.options.cheatsheet.enableTimetable
                    onCheckedChanged: {
                        Config.options.cheatsheet.enableTimetable = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Weekly and monthly calendar timetable with event scheduling, alarms, and sports integration.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "mail"
                    text: Translation.tr("Enable Gmail")
                    checked: Config.options.cheatsheet.enableGmail
                    onCheckedChanged: {
                        Config.options.cheatsheet.enableGmail = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("View and manage unread Gmail messages directly in the Cheatsheet.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "biotech"
                    text: Translation.tr("Enable Amino acids")
                    checked: Config.options.cheatsheet.enableAminoAcids
                    onCheckedChanged: {
                        Config.options.cheatsheet.enableAminoAcids = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Reference guide for amino acids with structural formulas and classification schemes.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "terminal"
                    text: Translation.tr("Enable Commands")
                    checked: Config.options.cheatsheet.enableCommands
                    onCheckedChanged: {
                        Config.options.cheatsheet.enableCommands = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Quick reference cheatsheet for terminal commands and shell workflows.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "dashboard"
                    text: Translation.tr("Enable Workspaces")
                    checked: Config.options.cheatsheet.enableWorkspaceProfiles
                    onCheckedChanged: {
                        Config.options.cheatsheet.enableWorkspaceProfiles = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Manage workspace profiles, saved application layouts, and monitor assignments.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "experiment"
                    text: Translation.tr("Enable Elements")
                    checked: Config.options.cheatsheet.enablePeriodicTable
                    onCheckedChanged: {
                        Config.options.cheatsheet.enablePeriodicTable = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Interactive periodic table of chemical elements with atomic properties.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "speed"
                    text: Translation.tr("Enable Typing test")
                    checked: Config.options.cheatsheet.enableTypingTest
                    onCheckedChanged: {
                        Config.options.cheatsheet.enableTypingTest = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("The same offline typing test the Overview search hosts, as a full-size page. Its own settings and score history live inside it.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "handyman"
                    text: Translation.tr("Enable Dev tools")
                    checked: Config.options.cheatsheet.enableDevTools
                    onCheckedChanged: {
                        Config.options.cheatsheet.enableDevTools = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("The Search Tools as a full-size page: generators, encoders, hashes, converters, cron, chmod, URL and HTTP helpers. Everything runs offline.")
                    }
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
