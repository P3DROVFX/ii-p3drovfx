pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.easyEffects.components

/**
 * Every EasyEffects option in one place: how the quick switchers pick presets, the
 * editor, EasyEffects itself, and the island bubble. Writes go straight to Config.
 *
 * Three panes like the Devices page's: wide, the quick-switching pane stands beside the
 * other two stacked; narrow, all three stack. Switch rows fill with the secondary
 * container while they are on; choices are dashed chips.
 */
Rectangle {
    id: root

    property bool compact: false
    property real layoutWidth: root.width

    readonly property var options: Config.options.easyEffects
    readonly property var hero: Config.options.easyEffects.hero
    readonly property bool islandBubble: !(Config.options.bar.floatingNotch?.disableEasyEffects ?? false)
    readonly property bool twoColumns: root.layoutWidth >= EasyEffectsStyle.devicePaneMin * 2 + EasyEffectsStyle.gap

    function setIslandBubble(on: bool): void {
        Config.options.bar.floatingNotch.disableEasyEffects = !on;
        if (Config.options.dynamicIsland?.widgets?.easyEffects)
            Config.options.dynamicIsland.widgets.easyEffects.enable = on;
    }

    color: EasyEffectsStyle.colBackground

    /// A titled pane of setting rows.
    component Section: Rectangle {
        id: section

        property string title: ""
        property string symbol: ""
        property int shapeKind: MaterialShape.Shape.Cookie9Sided
        default property alias rows: rowColumn.data

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        implicitHeight: sectionColumn.implicitHeight + EasyEffectsStyle.panePadding * 2
        radius: EasyEffectsStyle.radiusPane
        color: EasyEffectsStyle.colPane

        ColumnLayout {
            id: sectionColumn
            anchors {
                fill: parent
                margins: EasyEffectsStyle.panePadding
            }
            spacing: EasyEffectsStyle.gapSmall + 2

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: EasyEffectsStyle.gapTiny
                spacing: EasyEffectsStyle.gap + 2

                EasyEffectsBadge {
                    size: EasyEffectsStyle.deviceColumnBadge
                    text: section.symbol
                    shape: section.shapeKind
                    color: EasyEffectsStyle.colPrimary
                    colSymbol: EasyEffectsStyle.colOnPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: section.title
                    elide: Text.ElideRight
                    font.family: EasyEffectsStyle.fontTitle
                    font.variableAxes: EasyEffectsStyle.axesName
                    font.pixelSize: EasyEffectsStyle.textHeading
                    color: EasyEffectsStyle.colOnSurface
                }
            }

            ColumnLayout {
                id: rowColumn
                Layout.fillWidth: true
                spacing: EasyEffectsStyle.gapSmall + 2
            }
        }
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: grid.implicitHeight + EasyEffectsStyle.gapHuge

        GridLayout {
            id: grid
            width: flick.width
            columns: root.twoColumns ? 2 : 1
            rowSpacing: EasyEffectsStyle.gap
            columnSpacing: EasyEffectsStyle.gap

            // What the Presets page's hero shows: the same parts as the desktop widget.
            Section {
                title: Translation.tr("Preset card")
                symbol: "dashboard_customize"
                shapeKind: MaterialShape.Shape.Puffy

                EasyEffectsSettingRow {
                    symbol: "interests"
                    shapeKind: MaterialShape.Shape.Cookie9Sided
                    title: Translation.tr("Centrepiece")

                    Repeater {
                        model: [
                            { id: "shape", label: Translation.tr("Shape") },
                            { id: "curve", label: Translation.tr("Tone curve") },
                            { id: "none", label: Translation.tr("None") }
                        ]

                        EasyEffectsFilterChip {
                            required property var modelData
                            label: modelData.label
                            selected: root.hero.art === modelData.id
                            onTriggered: root.hero.art = modelData.id
                        }
                    }
                }

                EasyEffectsSettingRow {
                    symbol: "opacity"
                    shapeKind: MaterialShape.Shape.Sunny
                    title: Translation.tr("Line opacity")

                    Repeater {
                        model: [
                            { id: 50, label: Translation.tr("Faint") },
                            { id: 100, label: Translation.tr("Normal") },
                            { id: 150, label: Translation.tr("Strong") }
                        ]

                        EasyEffectsFilterChip {
                            required property var modelData
                            label: modelData.label
                            selected: Math.abs(root.hero.topographyStrength - modelData.id) < 25
                            onTriggered: root.hero.topographyStrength = modelData.id
                        }
                    }
                }

                    EasyEffectsSettingRow {
                        symbol: "ssid_chart"
                        shapeKind: MaterialShape.Shape.Cookie9Sided
                        title: Translation.tr("Contour lines")
                        description: Translation.tr("The fine topographic lines behind the card. Off leaves the plain surface.")
                        toggle: true
                        checked: root.hero.topography
                        onToggled: checked => root.hero.topography = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "music_note"
                        shapeKind: MaterialShape.Shape.Clover4Leaf
                        title: Translation.tr("Follow the music")
                        description: Translation.tr("The lines speed up and swell with the beat of what is playing. Off, they only drift slowly.")
                        toggle: true
                        checked: root.hero.topographyReactive
                        onToggled: checked => root.hero.topographyReactive = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "speaker"
                        shapeKind: MaterialShape.Shape.Sunny
                        title: Translation.tr("Device")
                        description: Translation.tr("The pill naming the device the preset plays through.")
                        toggle: true
                        checked: root.hero.showDevice
                        onToggled: checked => root.hero.showDevice = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "play_circle"
                        shapeKind: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("State")
                        description: Translation.tr("The pill saying whether the effects are playing, bypassed or off.")
                        toggle: true
                        checked: root.hero.showState
                        onToggled: checked => root.hero.showState = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "star"
                        shapeKind: MaterialShape.Shape.Cookie12Sided
                        title: Translation.tr("Device default")
                        description: Translation.tr("The pill with the preset this device starts with; when it isn't the one loaded, click it to load it.")
                        toggle: true
                        checked: root.hero.showDefault
                        onToggled: checked => root.hero.showDefault = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "waves"
                        shapeKind: MaterialShape.Shape.Puffy
                        title: Translation.tr("Wave")
                        toggle: true
                        checked: root.hero.showWave
                        onToggled: checked => root.hero.showWave = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "label"
                        shapeKind: MaterialShape.Shape.Flower
                        title: Translation.tr("Family")
                        description: Translation.tr("The small line above the name: the preset's family and whether it is the device default.")
                        toggle: true
                        checked: root.hero.showCaption
                        onToggled: checked => root.hero.showCaption = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "title"
                        shapeKind: MaterialShape.Shape.Cookie7Sided
                        title: Translation.tr("Preset name")
                        toggle: true
                        checked: root.hero.showName
                        onToggled: checked => root.hero.showName = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "instant_mix"
                        shapeKind: MaterialShape.Shape.Clover4Leaf
                        title: Translation.tr("Effects in the chain")
                        toggle: true
                        checked: root.hero.showEffects
                        onToggled: checked => root.hero.showEffects = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "smart_button"
                        shapeKind: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("Buttons")
                        description: Translation.tr("Edit effects and Bypass. Off, the card is only to look at.")
                        toggle: true
                        checked: root.hero.showButtons
                        onToggled: checked => root.hero.showButtons = checked
                    }

            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: EasyEffectsStyle.gap

                Section {
                    title: Translation.tr("Quick switching")
                    symbol: "swap_horiz"
                    shapeKind: MaterialShape.Shape.Cookie9Sided

                    EasyEffectsSettingRow {
                        symbol: "category"
                        shapeKind: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("Presets to switch between")
                        description: root.options.cycleScope === "all"
                            ? Translation.tr("Every output preset")
                            : Translation.tr("The family of the device's default preset: \"A50 · Music\" offers every \"A50 · …\" preset")

                        EasyEffectsFilterChip {
                            label: Translation.tr("Device")
                            selected: root.options.cycleScope !== "all"
                            onTriggered: root.options.cycleScope = "device"
                        }

                        EasyEffectsFilterChip {
                            label: Translation.tr("All")
                            selected: root.options.cycleScope === "all"
                            onTriggered: root.options.cycleScope = "all"
                        }
                    }

                    EasyEffectsSettingRow {
                        symbol: "notifications"
                        shapeKind: MaterialShape.Shape.Clover4Leaf
                        title: Translation.tr("Show the preset on switch")
                        description: Translation.tr("A pill on the island or the OSD names the new preset")
                        toggle: true
                        checked: root.options.osdOnSwitch
                        onToggled: checked => root.options.osdOnSwitch = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "bubble_chart"
                        shapeKind: MaterialShape.Shape.Cookie12Sided
                        title: Translation.tr("Island bubble")
                        description: Translation.tr("The preset beside the Dynamic Island while EasyEffects runs: scroll to switch, rest on it for more")
                        toggle: true
                        checked: root.islandBubble
                        onToggled: checked => root.setIslandBubble(checked)
                    }

                    EasyEffectsSettingRow {
                        symbol: "keyboard"
                        shapeKind: MaterialShape.Shape.Cookie7Sided
                        title: Translation.tr("Keybinds")
                        description: Translation.tr("Super+Ctrl+E opens this app. Bind the shortcuts easyEffectsNextPreset, easyEffectsPreviousPreset and easyEffectsBypassToggle, or call \"qs -c ii ipc call easyeffects next\".")
                    }
                }

                Section {
                    title: Translation.tr("Editor")
                    symbol: "instant_mix"
                    shapeKind: MaterialShape.Shape.Clover4Leaf

                    EasyEffectsSettingRow {
                        symbol: "hearing"
                        shapeKind: MaterialShape.Shape.Sunny
                        title: Translation.tr("Hear edits at once")
                        description: Translation.tr("Knob changes play before they are saved to the preset")
                        toggle: true
                        checked: root.options.liveApply
                        onToggled: checked => root.options.liveApply = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "start"
                        shapeKind: MaterialShape.Shape.Puffy
                        title: Translation.tr("Open on")

                        Repeater {
                            model: [
                                { id: "last", label: Translation.tr("Last") },
                                { id: "presets", label: Translation.tr("Presets") },
                                { id: "effects", label: Translation.tr("Effects") }
                            ]

                            EasyEffectsFilterChip {
                                required property var modelData
                                label: modelData.label
                                selected: root.options.startTab === modelData.id
                                onTriggered: root.options.startTab = modelData.id
                            }
                        }
                    }
                }

                Section {
                    title: Translation.tr("EasyEffects")
                    symbol: "graphic_eq"
                    shapeKind: MaterialShape.Shape.Cookie12Sided

                    EasyEffectsSettingRow {
                        symbol: "restart_alt"
                        shapeKind: MaterialShape.Shape.SoftBurst
                        title: Translation.tr("Apply the device's preset on start")
                        description: Translation.tr("EasyEffects skips it on Pro Audio devices when it starts; the shell loads it instead")
                        toggle: true
                        checked: root.options.applyDeviceDefaultOnStart
                        onToggled: checked => root.options.applyDeviceDefaultOnStart = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: "swap_horiz"
                        shapeKind: MaterialShape.Shape.Cookie9Sided
                        title: Translation.tr("Switch preset with the device")
                        description: Translation.tr("When the default output or input device changes, load the preset saved for the new one (a device with none keeps the current preset)")
                        toggle: true
                        checked: root.options.applyDeviceDefaultOnSwitch
                        onToggled: checked => root.options.applyDeviceDefaultOnSwitch = checked
                    }

                    EasyEffectsSettingRow {
                        symbol: EasyEffects.running ? "stop_circle" : "play_circle"
                        shapeKind: MaterialShape.Shape.Flower
                        title: EasyEffects.running ? Translation.tr("Running") : Translation.tr("Not running")
                        description: EasyEffects.available
                            ? `${EasyEffects.isFlatpak ? "Flatpak" : Translation.tr("Native")} · EasyEffects ${EasyEffects.majorVersion} · ${EasyEffects.presetsDir}`
                            : Translation.tr("Not installed")

                        EasyEffectsButton {
                            visible: EasyEffects.available
                            variant: EasyEffects.running ? "danger" : "filled"
                            symbol: EasyEffects.running ? "stop" : "play_arrow"
                            label: EasyEffects.running ? Translation.tr("Quit") : Translation.tr("Start")
                            onClicked: EasyEffects.running ? EasyEffects.quit() : EasyEffects.start()
                        }
                    }
                }
            }
        }
    }
}
