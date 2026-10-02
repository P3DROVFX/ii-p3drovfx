pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.easyEffects.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * Which preset each device starts with: EasyEffects' own autoload entries, edited in
 * the files it reads. A banner says what that means; below it the output and input
 * devices stand in two panes (stacked when the page is narrow), connected ones first
 * and the device in use as a primary container, then the entries saved for devices that
 * are not here right now, so a headset's default can be changed while it is away.
 */
Item {
    id: root

    required property var panels
    property bool compact: false
    property bool wide: false
    /// The page's settled width (see AppContent).
    property real layoutWidth: width

    /// Two panes side by side, decided on the settled width.
    readonly property bool sideBySide: root.layoutWidth >= EasyEffectsStyle.devicePaneMin * 2 + EasyEffectsStyle.gap
    readonly property var kinds: [
        { pipeline: "output", title: Translation.tr("Output devices"), symbol: "speaker" },
        { pipeline: "input", title: Translation.tr("Input devices"), symbol: "mic" }
    ]

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

    // A symbol for a device, from what PipeWire says about it.
    function symbolFor(node: var, pipeline: string): string {
        const text = `${node?.properties?.["device.form-factor"] ?? ""} ${node?.properties?.["device.icon-name"] ?? ""} ${node?.description ?? ""} ${node?.name ?? ""}`.toLowerCase();
        if (pipeline === "input") {
            if (/headset|headphone/.test(text))
                return "headset_mic";
            if (/usb/.test(text))
                return "mic_external_on";
            return "mic";
        }
        if (/headphone|headset|earbud|buds|airpods/.test(text))
            return "headphones";
        if (/hdmi|display|monitor|tv/.test(text))
            return "tv";
        if (/bluez|bluetooth/.test(text))
            return "bluetooth_audio";
        return "speaker";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: EasyEffectsStyle.gap

        // ── What this page is for ─────────────────────────────────────────
        Rectangle {
            id: banner
            Layout.fillWidth: true
            implicitHeight: Math.max(root.compact ? 0 : EasyEffectsStyle.bannerHeight, bannerText.implicitHeight + EasyEffectsStyle.gapHuge * 2)
            radius: EasyEffectsStyle.radiusPane
            color: EasyEffectsStyle.colTertiaryContainer

            // The banner's one ornament: a big scalloped shape parked off its corner. A plain
            // clip would square off the rounded corner, so a mask of the banner cuts it.
            Item {
                id: ornament
                anchors.fill: parent
                visible: false

                MaterialShape {
                    width: EasyEffectsStyle.heroShape + EasyEffectsStyle.gapHuge
                    height: width
                    x: banner.width - width * 0.72
                    y: -height * 0.24
                    shapeString: "Cookie12Sided"
                    color: EasyEffectsStyle.colOnTertiaryContainer
                }
            }

            Rectangle {
                id: bannerMask
                anchors.fill: parent
                radius: banner.radius
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: parent
                source: ornament
                maskEnabled: true
                maskSource: bannerMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                opacity: EasyEffectsStyle.opacityOrnament
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: EasyEffectsStyle.gapHuge
                    rightMargin: EasyEffectsStyle.gapHuge + EasyEffectsStyle.gapSmall
                }
                spacing: EasyEffectsStyle.gapHuge - 2

                EasyEffectsBadge {
                    visible: !root.compact
                    size: EasyEffectsStyle.heroButtonHeight + EasyEffectsStyle.gapHuge + EasyEffectsStyle.gapSmall
                    text: "speaker_group"
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: EasyEffectsStyle.colTertiary
                    colSymbol: EasyEffectsStyle.colOnTertiary
                }

                ColumnLayout {
                    id: bannerText
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: EasyEffectsStyle.gapTiny

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("A starting preset for every device")
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: EasyEffectsStyle.fontTitle
                        font.variableAxes: EasyEffectsStyle.axesDisplay
                        font.pixelSize: root.compact ? EasyEffectsStyle.textHeading : EasyEffectsStyle.textBanner
                        color: EasyEffectsStyle.colOnTertiaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.maximumWidth: EasyEffectsStyle.sheetWidth * 1.6
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: Translation.tr("EasyEffects loads a device's preset whenever that device becomes the default. The quick switchers offer presets from the same family.")
                        font.pixelSize: EasyEffectsStyle.textNormal
                        color: EasyEffectsStyle.colOnTertiaryContainer
                        opacity: EasyEffectsStyle.opacityBannerText
                    }
                }

                // Three kinds of device, overlapping, the last one the accent.
                Row {
                    visible: root.layoutWidth >= EasyEffectsStyle.bannerClusterMin
                    spacing: -EasyEffectsStyle.gapHuge + 2

                    EasyEffectsBadge {
                        size: EasyEffectsStyle.heroButtonHeight + EasyEffectsStyle.gapHuge * 2
                        iconSize: Math.round(size * 0.46)
                        text: "headphones"
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: EasyEffectsStyle.tint(EasyEffectsStyle.colOnTertiaryContainer, EasyEffectsStyle.tintHover)
                        colSymbol: EasyEffectsStyle.colOnTertiaryContainer
                    }

                    EasyEffectsBadge {
                        size: EasyEffectsStyle.heroButtonHeight + EasyEffectsStyle.gapHuge * 2
                        iconSize: Math.round(size * 0.46)
                        text: "speaker"
                        shape: MaterialShape.Shape.SoftBurst
                        color: EasyEffectsStyle.tint(EasyEffectsStyle.colOnTertiaryContainer, EasyEffectsStyle.tintPressed + EasyEffectsStyle.tintHover)
                        colSymbol: EasyEffectsStyle.colOnTertiaryContainer
                    }

                    EasyEffectsBadge {
                        size: EasyEffectsStyle.heroButtonHeight + EasyEffectsStyle.gapHuge * 2
                        iconSize: Math.round(size * 0.46)
                        text: "mic"
                        shape: MaterialShape.Shape.Clover4Leaf
                        color: EasyEffectsStyle.colTertiary
                        colSymbol: EasyEffectsStyle.colOnTertiary
                    }
                }
            }
        }

        // ── The devices ───────────────────────────────────────────────────
        StyledFlickable {
            id: page
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            interactive: !root.sideBySide
            contentWidth: width
            contentHeight: root.sideBySide ? height : panes.implicitHeight

            GridLayout {
                id: panes
                width: page.width
                height: root.sideBySide ? page.height : implicitHeight
                columns: root.sideBySide ? 2 : 1
                rowSpacing: EasyEffectsStyle.gap
                columnSpacing: EasyEffectsStyle.gap

                Repeater {
                    model: root.kinds

                    Rectangle {
                        id: pane
                        required property var modelData
                        readonly property string pipeline: modelData.pipeline
                        readonly property var devices: Array.from(pane.pipeline === "input"
                            ? Audio.inputDevices : Audio.outputDevices).filter(node => !String(node.name).startsWith("easyeffects_"))
                        readonly property var away: root.absent(pane.pipeline)
                        readonly property int total: pane.devices.length + pane.away.length

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: root.sideBySide
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: paneColumn.implicitHeight + EasyEffectsStyle.panePadding * 2
                        radius: EasyEffectsStyle.radiusPane
                        color: EasyEffectsStyle.colPane

                        ColumnLayout {
                            id: paneColumn
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
                                    text: pane.modelData.symbol
                                    shape: pane.pipeline === "input" ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie9Sided
                                    color: EasyEffectsStyle.colPrimary
                                    colSymbol: EasyEffectsStyle.colOnPrimary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: pane.modelData.title
                                    elide: Text.ElideRight
                                    font.family: EasyEffectsStyle.fontTitle
                                    font.variableAxes: EasyEffectsStyle.axesName
                                    font.pixelSize: EasyEffectsStyle.textHeading
                                    color: EasyEffectsStyle.colOnSurface
                                }

                                EasyEffectsPill {
                                    label: String(pane.total)
                                    labelSize: EasyEffectsStyle.textNormal - 1
                                    colContent: EasyEffectsStyle.colOnSecondaryContainer
                                    colFill: EasyEffectsStyle.colSecondaryContainer
                                    minWidth: EasyEffectsStyle.pillHeight
                                }
                            }

                            Flickable {
                                id: list
                                Layout.fillWidth: true
                                Layout.fillHeight: root.sideBySide
                                Layout.preferredHeight: root.sideBySide ? -1 : rows.implicitHeight
                                clip: true
                                interactive: root.sideBySide && contentHeight > height
                                contentWidth: width
                                contentHeight: rows.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds

                                ColumnLayout {
                                    id: rows
                                    width: list.width
                                    spacing: EasyEffectsStyle.gapSmall + 2

                                    Repeater {
                                        model: pane.devices

                                        DeviceRow {
                                            required property var modelData
                                            pipeline: pane.pipeline
                                            deviceName: modelData.name
                                            label: Audio.friendlyDeviceName(modelData)
                                            route: Logic.routeFor(modelData.properties)
                                            inUse: (pane.pipeline === "input" ? EasyEffects.inputDevice : EasyEffects.outputDevice) === modelData
                                            node: modelData
                                            entry: Logic.autoloadFor(pane.pipeline === "input" ? EasyEffects.inputAutoload : EasyEffects.outputAutoload,
                                                modelData.name, Logic.routeFor(modelData.properties))
                                        }
                                    }

                                    Repeater {
                                        model: pane.away

                                        DeviceRow {
                                            required property var modelData
                                            pipeline: pane.pipeline
                                            deviceName: modelData.device
                                            label: modelData["device-description"] || modelData.device
                                            route: modelData["device-profile"] ?? ""
                                            inUse: false
                                            node: null
                                            entry: modelData
                                        }
                                    }

                                    ClockEmptyState {
                                        Layout.alignment: Qt.AlignHCenter
                                        visible: pane.total === 0
                                        symbol: pane.modelData.symbol
                                        shapeSize: ClockStyle.emptyShapeSmall
                                        title: Translation.tr("No devices")
                                        subtitle: Translation.tr("Nothing is connected here right now.")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A decorative level meter for the device in use: bars of different heights.
    component Bars: Row {
        id: bars
        property color colBar: EasyEffectsStyle.colOnPrimaryContainer
        readonly property var heights: [0.36, 0.78, 0.5, 1, 0.64, 0.43, 0.86, 0.57]
        spacing: EasyEffectsStyle.gapTiny - 1

        Repeater {
            model: bars.heights

            Rectangle {
                required property real modelData
                anchors.verticalCenter: parent.verticalCenter
                width: EasyEffectsStyle.gapTiny
                height: EasyEffectsStyle.pillHeight * 0.875 * modelData
                radius: width / 2
                color: bars.colBar
            }
        }
    }

    component DeviceRow: Rectangle {
        id: row
        required property string pipeline
        required property string deviceName
        required property string label
        required property string route
        required property bool inUse
        required property var node
        required property var entry

        readonly property string preset: row.entry?.["preset-name"] ?? ""
        readonly property var choices: root.presetChoices(row.pipeline)
        readonly property bool away: row.node === null
        readonly property color colContent: row.inUse ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colOnSurface
        readonly property color colSubContent: row.inUse ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintSubtext) : EasyEffectsStyle.colSubtext

        Layout.fillWidth: true
        implicitHeight: EasyEffectsStyle.deviceRowHeight
        radius: EasyEffectsStyle.radiusRow
        color: row.inUse ? EasyEffectsStyle.colPrimaryContainer : EasyEffectsStyle.colRow
        opacity: row.away ? EasyEffectsStyle.dimmed + 0.08 : 1

        Behavior on color {
            animation: EasyEffectsStyle.motionFast.colorAnimation.createObject(row)
        }

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

        RowLayout {
            anchors {
                fill: parent
                leftMargin: EasyEffectsStyle.gapLarge - 2
                rightMargin: EasyEffectsStyle.gapLarge
            }
            spacing: EasyEffectsStyle.gap + 2

            EasyEffectsBadge {
                size: EasyEffectsStyle.deviceBadge
                text: row.away ? (row.pipeline === "input" ? "mic_external_on" : "speaker_group") : root.symbolFor(row.node, row.pipeline)
                shape: row.inUse ? MaterialShape.Shape.Cookie9Sided : EasyEffectsStyle.shapeFor(row.deviceName)
                color: row.inUse ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colSecondaryContainer
                colSymbol: row.inUse ? EasyEffectsStyle.colPrimaryContainer : EasyEffectsStyle.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: row.label
                    elide: Text.ElideRight
                    font.variableAxes: EasyEffectsStyle.axesName
                    font.pixelSize: EasyEffectsStyle.textName
                    color: row.colContent
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: EasyEffectsStyle.gap

                    StyledText {
                        Layout.fillWidth: !row.inUse
                        Layout.minimumWidth: 0
                        text: [row.inUse ? Translation.tr("In use") : (row.away ? Translation.tr("Not connected") : ""), row.route]
                            .filter(part => part.length > 0).join(" · ")
                        visible: text.length > 0
                        elide: Text.ElideRight
                        font.pixelSize: EasyEffectsStyle.textNormal - 1
                        color: row.colSubContent
                    }

                    Bars {
                        visible: row.inUse
                        Layout.preferredHeight: EasyEffectsStyle.pillHeight * 0.875
                        colBar: row.colContent
                    }

                    Item {
                        Layout.fillWidth: row.inUse
                    }
                }
            }

            StyledComboBox {
                Layout.fillWidth: false
                Layout.minimumWidth: EasyEffectsStyle.deviceSelectMinWidth - EasyEffectsStyle.gapHuge * 2
                Layout.preferredWidth: root.compact ? EasyEffectsStyle.deviceSelectMinWidth - EasyEffectsStyle.gapLarge : Math.min(EasyEffectsStyle.deviceSelectMinWidth + EasyEffectsStyle.gapHuge * 2, row.width * 0.4)
                implicitHeight: EasyEffectsStyle.buttonHeight
                buttonIcon: row.preset.length > 0 ? "star" : "block"
                buttonRadius: EasyEffectsStyle.radiusChip
                colBackground: row.inUse ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintHover) : EasyEffectsStyle.colField
                colBackgroundHover: row.inUse ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintPressed) : EasyEffectsStyle.colFieldHover
                textRole: "displayName"
                model: row.choices
                currentIndex: Math.max(0, row.choices.findIndex(choice => choice.value === row.preset))
                onActivated: index => row.choose(row.choices[index].value)
            }
        }
    }
}
