pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * Which preset each device starts with: EasyEffects' own autoload entries, edited in
 * the files it reads. Connected devices first, then the entries saved for devices that
 * are not here right now, so a headset's default can be changed while it is away.
 */
Item {
    id: root

    required property var panels
    property bool compact: false
    property bool wide: false

    function presetChoices(pipeline: string): var {
        const names = Array.from(pipeline === "input" ? EasyEffects.inputPresets : EasyEffects.outputPresets);
        return [{ displayName: Translation.tr("No default"), value: "" }]
            .concat(names.map(name => ({ displayName: name, value: name })));
    }

    function absent(pipeline: string): var {
        const devices = pipeline === "input" ? Audio.inputDevices : Audio.outputDevices;
        const present = Array.from(devices).map(node => node.name);
        return Array.from(pipeline === "input" ? EasyEffects.inputAutoload : EasyEffects.outputAutoload)
            .filter(entry => !present.includes(entry.device));
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 2

        ColumnLayout {
            id: column
            x: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
            y: ClockStyle.gapSmall
            width: flick.width - x * 2
            spacing: ClockStyle.gapHuge

            Repeater {
                model: [
                    { pipeline: "output", title: Translation.tr("Output devices"), symbol: "speaker" },
                    { pipeline: "input", title: Translation.tr("Input devices"), symbol: "mic" }
                ]

                ClockSettingsSection {
                    id: section
                    required property var modelData
                    Layout.fillWidth: true
                    title: section.modelData.title
                    symbol: section.modelData.symbol

                    readonly property var devices: Array.from(section.modelData.pipeline === "input"
                        ? Audio.inputDevices : Audio.outputDevices).filter(node => !String(node.name).startsWith("easyeffects_"))
                    readonly property var away: root.absent(section.modelData.pipeline)
                    readonly property int total: section.devices.length + section.away.length

                    Repeater {
                        model: section.devices

                        DeviceRow {
                            required property var modelData
                            required property int index
                            pipeline: section.modelData.pipeline
                            deviceName: modelData.name
                            label: Audio.friendlyDeviceName(modelData)
                            detail: {
                                const route = Logic.routeFor(modelData.properties);
                                const inUse = (section.modelData.pipeline === "input" ? EasyEffects.inputDevice : EasyEffects.outputDevice) === modelData;
                                return [inUse ? Translation.tr("In use") : "", route].filter(part => part.length > 0).join(" · ");
                            }
                            node: modelData
                            entry: Logic.autoloadFor(section.modelData.pipeline === "input" ? EasyEffects.inputAutoload : EasyEffects.outputAutoload,
                                modelData.name, Logic.routeFor(modelData.properties))
                            first: index === 0
                            last: index === section.total - 1
                        }
                    }

                    Repeater {
                        model: section.away

                        DeviceRow {
                            required property var modelData
                            required property int index
                            pipeline: section.modelData.pipeline
                            deviceName: modelData.device
                            label: modelData["device-description"] || modelData.device
                            detail: [Translation.tr("Not connected"), modelData["device-profile"] ?? ""].filter(part => part.length > 0).join(" · ")
                            node: null
                            entry: modelData
                            first: section.devices.length === 0 && index === 0
                            last: section.devices.length + index === section.total - 1
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Translation.tr("EasyEffects loads a device's preset whenever that device becomes the default. The quick switchers (the island bubble, the quick toggle, the bar and the keybinds) offer the presets of the same family as the device's default one; change that in Settings.")
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }
    }

    component DeviceRow: ClockSettingsRow {
        id: row
        required property string pipeline
        required property string deviceName
        required property string label
        required property string detail
        required property var node
        required property var entry

        readonly property string preset: row.entry?.["preset-name"] ?? ""
        readonly property var choices: root.presetChoices(row.pipeline)

        symbol: row.pipeline === "input" ? "mic" : (row.node ? "speaker" : "speaker_group")
        title: row.label
        description: row.detail

        function choose(value: string): void {
            // A device that is away is rewritten from its saved entry.
            const device = row.node ?? {
                name: row.deviceName,
                description: row.entry?.["device-description"] ?? "",
                properties: {
                    "device.routes": (row.entry?.["device-profile"] ?? "").length > 0 ? 1 : 0,
                    "device.profile.description": row.entry?.["device-profile"] ?? ""
                }
            };
            EasyEffects.setDeviceDefault(row.pipeline, device, value);
        }

        StyledComboBox {
            Layout.fillWidth: false
            Layout.preferredWidth: root.compact ? 160 : 260
            implicitHeight: 38
            buttonIcon: row.preset.length > 0 ? "star" : "block"
            textRole: "displayName"
            model: row.choices
            currentIndex: Math.max(0, row.choices.findIndex(choice => choice.value === row.preset))
            onActivated: index => row.choose(row.choices[index].value)
        }
    }
}
