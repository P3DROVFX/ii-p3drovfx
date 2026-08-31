import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: dockConfigRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Behavior ──────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Behavior")
            icon: "dock"
            tooltip: Translation.tr("Master enable switch, multi-monitor isolation and trigger options.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "toggle_on"
                    text: Translation.tr("Enable")
                    checked: Config.options.dock.enable
                    onCheckedChanged: {
                        Config.options.dock.enable = checked;
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.dock.enable
                    visible: Config.options.dock.enable
                    buttonIcon: "center_focus_strong"
                    text: Translation.tr("Show only on focused monitor")
                    checked: Config.options.dock.showOnlyOnFocusedMonitor
                    onCheckedChanged: {
                        Config.options.dock.showOnlyOnFocusedMonitor = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("When workspace is empty, show the dock only on the focused monitor instead of all monitors")
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.dock.enable
                    visible: Config.options.dock.enable
                    buttonIcon: "monitor"
                    text: Translation.tr("Isolate monitors")
                    checked: Config.options.dock.isolateMonitors
                    onCheckedChanged: {
                        Config.options.dock.isolateMonitors = checked;
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.dock.enable
                    visible: Config.options.dock.enable
                    buttonIcon: "mouse"
                    text: Translation.tr("Hover to reveal")
                    checked: Config.options.dock.hoverToReveal
                    onCheckedChanged: {
                        Config.options.dock.hoverToReveal = checked;
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.dock.enable
                    visible: Config.options.dock.enable
                    buttonIcon: "push_pin"
                    text: Translation.tr("Pinned on startup")
                    checked: Config.options.dock.pinnedOnStartup
                    onCheckedChanged: {
                        Config.options.dock.pinnedOnStartup = checked;
                    }
                }

                ContentSubsection {
                    enabled: Config.options.dock.enable
                    visible: Config.options.dock.enable
                    title: Translation.tr("Hover content")
                    icon: "touch_app"
                    Layout.fillWidth: true
                    tooltip: Translation.tr("Choose what to display when hovering pinned or running apps in the dock.")

                    ConfigSelectionArray {
                        currentValue: Config.options.dock.enablePreview ? "preview" : (Config.options.dock.enableAppTooltip ? "tooltip" : "none")
                        onSelected: newValue => {
                            Config.options.dock.enablePreview = (newValue === "preview");
                            Config.options.dock.enableAppTooltip = (newValue === "tooltip");
                        }
                        options: [
                            { displayName: Translation.tr("None"), icon: "block", value: "none" },
                            { displayName: Translation.tr("App Name"), icon: "subtitles", value: "tooltip" },
                            { displayName: Translation.tr("Window Preview"), icon: "preview", value: "preview" }
                        ]
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.dock.enable
                    visible: Config.options.dock.enable
                    buttonIcon: "group_work"
                    text: Translation.tr("Smart auto-grouping")
                    checked: Config.options.dock.smartGrouping
                    onCheckedChanged: {
                        Config.options.dock.smartGrouping = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Automatically groups matching or related application instances in the dock.")
                    }
                }
            }
        }

        // ── Placement & Size ──────────────────────────────────────────────────
        ContentSection {
            visible: Config.options.dock.enable
            title: Translation.tr("Placement & Size")
            icon: "open_in_full"
            tooltip: Translation.tr("Dock height and edge positioning.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Dock height")
                    value: Config.options.dock.height
                    from: 20
                    to: 200
                    stepSize: 1
                    onValueChanged: {
                        Config.options.dock.height = value;
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Dock position")
                    icon: "border_all"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.dock.position
                        onSelected: (newValue) => {
                            Config.options.dock.position = newValue;
                        }
                        options: [{
                            "displayName": Translation.tr("Auto"),
                            "icon": "auto_awesome",
                            "value": "auto"
                        }, {
                            "displayName": Translation.tr("Bottom"),
                            "icon": "border_bottom",
                            "value": "bottom"
                        }, {
                            "displayName": Translation.tr("Top"),
                            "icon": "border_top",
                            "value": "top"
                        }, {
                            "displayName": Translation.tr("Left"),
                            "icon": "border_left",
                            "value": "left"
                        }, {
                            "displayName": Translation.tr("Right"),
                            "icon": "border_right",
                            "value": "right"
                        }]
                    }
                }
            }
        }

        // ── Navigation to Content & Appearance ────────────────────────────────
        ContentSection {
            visible: Config.options.dock.enable
            title: Translation.tr("Dock customization")
            tooltip: Translation.tr("Widgets, pinned folders, appearance, radii and magnification.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "widgets"
                    title: Translation.tr("Content & widgets")
                    description: Translation.tr("Media, weather, sports, phone mirror, buttons and folders")
                    onClicked: dockConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/DockContentConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "palette"
                    title: Translation.tr("Appearance & style")
                    description: Translation.tr("Dock styles, corner radii, icon masks and magnification")
                    onClicked: dockConfigRoot.activeSubPage = Qt.resolvedUrl("widgets/DockAppearanceConfig.qml")
                }
            }
        }

        Loader {
            id: dockPresetsLoader
            Layout.fillWidth: true
            asynchronous: true
            visible: Config.options.dock.enable
            source: Qt.resolvedUrl("widgets/DockPresetsManager.qml")
            Layout.preferredHeight: item ? item.implicitHeight : 0
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
