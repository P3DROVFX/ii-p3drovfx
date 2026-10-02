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

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: EasyEffectsStyle.gap

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
