pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Every EasyEffects option in one place: how the quick switchers pick presets, the
 * editor, EasyEffects itself, and the island bubble. Writes go straight to Config.
 */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width

    readonly property var options: Config.options.easyEffects
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property bool islandBubble: !(Config.options.bar.floatingNotch?.disableEasyEffects ?? false)

    function setIslandBubble(on: bool): void {
        Config.options.bar.floatingNotch.disableEasyEffects = !on;
        if (Config.options.dynamicIsland?.widgets?.easyEffects)
            Config.options.dynamicIsland.widgets.easyEffects.enable = on;
    }

    color: ClockStyle.colBackground

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 2

        ColumnLayout {
            id: column
            x: Math.max(root.padding, (flick.width - Math.min(flick.width - root.padding * 2, ClockStyle.sheetMaxWidth * 1.3)) / 2)
            y: ClockStyle.gapSmall
            width: Math.min(flick.width - root.padding * 2, ClockStyle.sheetMaxWidth * 1.3)
            spacing: ClockStyle.gapHuge

            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Quick switching")
                symbol: "swap_horiz"

                ClockSettingsRow {
                    first: true
                    symbol: "category"
                    title: Translation.tr("Presets to switch between")
                    description: root.options.cycleScope === "all"
                        ? Translation.tr("Every output preset")
                        : Translation.tr("The family of the device's default preset: \"A50 · Music\" offers every \"A50 · …\" preset")

                    ClockChip {
                        label: Translation.tr("Device")
                        selected: root.options.cycleScope !== "all"
                        onClicked: root.options.cycleScope = "device"
                    }

                    ClockChip {
                        label: Translation.tr("All")
                        selected: root.options.cycleScope === "all"
                        onClicked: root.options.cycleScope = "all"
                    }
                }

                ClockSettingsRow {
                    symbol: "notifications"
                    title: Translation.tr("Show the preset on switch")
                    description: Translation.tr("A pill on the island or the OSD names the new preset")
                    clickable: true
                    onClicked: root.options.osdOnSwitch = !root.options.osdOnSwitch

                    StyledSwitch {
                        checked: root.options.osdOnSwitch
                        checkable: false
                        onClicked: root.options.osdOnSwitch = !root.options.osdOnSwitch
                    }
                }

                ClockSettingsRow {
                    symbol: "bubble_chart"
                    title: Translation.tr("Island bubble")
                    description: Translation.tr("The preset beside the Dynamic Island while EasyEffects runs: scroll to switch, rest on it for more")
                    clickable: true
                    onClicked: root.setIslandBubble(!root.islandBubble)

                    StyledSwitch {
                        checked: root.islandBubble
                        checkable: false
                        onClicked: root.setIslandBubble(!root.islandBubble)
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "keyboard"
                    title: Translation.tr("Keybinds")
                    description: Translation.tr("Super+Ctrl+E opens this app. Bind the shortcuts easyEffectsNextPreset, easyEffectsPreviousPreset and easyEffectsBypassToggle, or call \"qs -c ii ipc call easyeffects next\".")
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Editor")
                symbol: "instant_mix"

                ClockSettingsRow {
                    first: true
                    symbol: "hearing"
                    title: Translation.tr("Hear edits at once")
                    description: Translation.tr("Knob changes play before they are saved to the preset")
                    clickable: true
                    onClicked: root.options.liveApply = !root.options.liveApply

                    StyledSwitch {
                        checked: root.options.liveApply
                        checkable: false
                        onClicked: root.options.liveApply = !root.options.liveApply
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: "start"
                    title: Translation.tr("Open on")

                    Repeater {
                        model: [
                            { id: "last", label: Translation.tr("Last") },
                            { id: "presets", label: Translation.tr("Presets") },
                            { id: "effects", label: Translation.tr("Effects") }
                        ]

                        ClockChip {
                            required property var modelData
                            label: modelData.label
                            selected: root.options.startTab === modelData.id
                            onClicked: root.options.startTab = modelData.id
                        }
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("EasyEffects")
                symbol: "graphic_eq"

                ClockSettingsRow {
                    first: true
                    symbol: "restart_alt"
                    title: Translation.tr("Apply the device's preset on start")
                    description: Translation.tr("EasyEffects skips it on Pro Audio devices when it starts; the shell loads it instead")
                    clickable: true
                    onClicked: root.options.applyDeviceDefaultOnStart = !root.options.applyDeviceDefaultOnStart

                    StyledSwitch {
                        checked: root.options.applyDeviceDefaultOnStart
                        checkable: false
                        onClicked: root.options.applyDeviceDefaultOnStart = !root.options.applyDeviceDefaultOnStart
                    }
                }

                ClockSettingsRow {
                    last: true
                    symbol: EasyEffects.running ? "stop_circle" : "play_circle"
                    title: EasyEffects.running ? Translation.tr("Running") : Translation.tr("Not running")
                    description: EasyEffects.available
                        ? `${EasyEffects.isFlatpak ? "Flatpak" : Translation.tr("Native")} · EasyEffects ${EasyEffects.majorVersion} · ${EasyEffects.presetsDir}`
                        : Translation.tr("Not installed")

                    ClockButton {
                        visible: EasyEffects.available
                        variant: EasyEffects.running ? "tonal" : "filled"
                        danger: EasyEffects.running
                        symbol: EasyEffects.running ? "stop" : "play_arrow"
                        label: EasyEffects.running ? Translation.tr("Quit") : Translation.tr("Start")
                        onClicked: EasyEffects.running ? EasyEffects.quit() : EasyEffects.start()
                    }
                }
            }
        }
    }
}
