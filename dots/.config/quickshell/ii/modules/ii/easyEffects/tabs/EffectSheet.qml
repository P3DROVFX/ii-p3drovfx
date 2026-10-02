pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.easyEffects.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * One effect's settings, in the side sheet beside the chain.
 *
 * Every control comes from the generated table, so any effect EasyEffects ships can be
 * edited without a hand-written form: each is a tile with the glyph of what it sets.
 * Equalizers get their curve and a column of bars, one per band (tap a band for its
 * frequency, Q and type); multiband effects a band picker. Edits are heard at once when
 * live apply is on and saved with "Save to preset" on the Effects page.
 */
EasyEffectsSheet {
    id: root

    required property var editor
    required property string instance

    readonly property var spec: root.editor.specOf(root.instance)
    readonly property var block: root.editor.blockOf(root.instance)
    readonly property string plugin: Logic.instanceParts(root.instance).plugin
    readonly property var bands: root.spec?.bands ?? null
    readonly property var channels: root.spec?.channels ?? []
    readonly property bool isEqualizer: root.channels.length > 0
    readonly property bool split: root.block?.["split-channels"] === true
    readonly property int bandCount: root.isEqualizer ? Number(root.block?.["num-bands"] ?? 0) : (root.bands?.count ?? 0)
    readonly property var modeControl: root.isEqualizer ? (root.spec?.controls ?? []).find(control => control.key === "mode" && !control.section) : null
    readonly property var topControls: (root.spec?.controls ?? []).filter(control => control.key !== "bypass" && control !== root.modeControl)
    readonly property var gainControl: (root.bands?.controls ?? []).find(control => control.key === "gain")
    readonly property var sections: {
        const order = [];
        root.topControls.forEach(control => {
            const section = control.section ?? "";
            if (!order.includes(section))
                order.push(section);
        });
        return order;
    }

    property string channel: root.channels[0] ?? ""
    property int openBand: -1
    property int multibandBand: 0
    /// The bars' range in dB: set when the sheet opens or the channel changes, never while a
    /// bar is dragged, so the bar under the hand doesn't move away from it.
    property real bandRange: 12

    // An equalizer band opens on what gets tuned most; the table keeps EasyEffects' order.
    readonly property var bandLead: ["frequency", "gain", "q", "type"]
    readonly property var bandControls: {
        const controls = (root.bands?.controls ?? []).filter(control => control.key !== "width");
        const rank = control => {
            const lead = root.bandLead.indexOf(control.key);
            return lead >= 0 ? lead : root.bandLead.length + controls.indexOf(control);
        };
        return controls.slice().sort((a, b) => rank(a) - rank(b));
    }

    title: root.editor.nameOf(root.instance)
    subtitle: root.editor.presetName
    badge: Logic.effectIcon(root.instance)
    badgeShape: EasyEffectsStyle.shapeFor(root.plugin)

    readonly property var modeNames: ({ IIR: Translation.tr("Parametric"), FIR: Translation.tr("Linear phase") })
    readonly property var modeIcons: ({ IIR: "graphic_eq", FIR: "waves" })

    function bandValue(control: var, band: int): var {
        const section = root.isEqualizer ? `${root.channel}/band${band}` : `band${band}`;
        const value = root.editor.value(root.instance, section, control.key);
        return value === undefined ? (control.defaults ?? [])[band] : value;
    }

    function setBand(control: var, band: int, value: var): void {
        // Unsplit, one curve drives both channels: write it to both.
        const targets = root.isEqualizer ? (root.split ? [root.channel] : root.channels) : [""];
        targets.forEach(channel => root.editor.setValue(root.instance, control, value, band, channel));
    }

    function setTop(control: var, value: var): void {
        if (root.isEqualizer && control.key === root.bands?.countKey) {
            root.growBands(Math.round(value));
            return;
        }
        root.editor.setValue(root.instance, control, value, 0, "");
    }

    // EasyEffects reads every band below the count and fails on a missing one, so a
    // larger count brings its bands along, and the chain is saved at once.
    function growBands(count: int): void {
        let data = root.editor.data;
        root.channels.forEach(channel => {
            for (let n = 0; n < count; n++) {
                if (Logic.valueAt(data, root.editor.pipeline, root.instance, `${channel}/band${n}`, "type") !== undefined)
                    continue;
                root.bands.controls.forEach(control => {
                    data = Logic.setValue(data, root.editor.pipeline, root.instance, `${channel}/band${n}`, control.key,
                        (control.defaults ?? [])[n]);
                });
            }
        });
        data = Logic.setValue(data, root.editor.pipeline, root.instance, "", root.bands.countKey, count);
        root.editor.data = data;
        root.editor.save();
    }

    function bandSummary(band: int): string {
        const controls = root.bands?.controls ?? [];
        const find = key => controls.find(control => control.key === key);
        const type = root.bandValue(find("type"), band);
        const parts = [String(type), Logic.formatValue(find("frequency"), root.bandValue(find("frequency"), band))];
        if (/Bell|shelf/i.test(String(type)))
            parts.push(Logic.formatValue(find("gain"), root.bandValue(find("gain"), band)));
        parts.push("Q " + Number(root.bandValue(find("q"), band)).toFixed(2));
        return parts.join(" · ");
    }

    // The label under a bar: 31, 125, 1k, 16k.
    function shortFrequency(hz: real): string {
        return hz >= 1000 ? String(Number((hz / 1000).toFixed(1))) + "k" : String(Math.round(hz));
    }

    function fitRange(): void {
        if (!root.isEqualizer || !root.gainControl)
            return;
        let peak = 0;
        for (let band = 0; band < root.bandCount; band++)
            peak = Math.max(peak, Math.abs(Number(root.bandValue(root.gainControl, band)) || 0));
        root.bandRange = Math.min(Math.abs(root.gainControl.max), Math.max(12, Math.ceil(peak / 6) * 6));
    }

    onChannelChanged: root.fitRange()
    Component.onCompleted: root.fitRange()

    // Opening a band's own settings brings them, and the bars they belong to, into view.
    onOpenBandChanged: {
        if (root.openBand >= 0)
            Qt.callLater(() => root.scrollTo(bandsTile));
    }

    // ── Enabled ──────────────────────────────────────────────────────────
    ClockFormToggle {
        symbol: "power_settings_new"
        label: Translation.tr("Enabled")
        description: root.block?.bypass === true ? Translation.tr("Bypassed: the sound passes through untouched")
            : Translation.tr("Processing the sound")
        checked: root.block?.bypass !== true
        onToggled: checked => root.editor.setBypass(root.instance, !checked)
    }

    // An effect this build of the table doesn't know: EasyEffects' window can edit it.
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.spec === null
        spacing: EasyEffectsStyle.gapSmall

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Translation.tr("This effect is newer than the shell's editor. Its settings are edited in EasyEffects' own window.")
            font.pixelSize: EasyEffectsStyle.textNormal
            color: EasyEffectsStyle.colOnSurfaceVariant
        }

        EasyEffectsButton {
            symbol: "open_in_new"
            label: Translation.tr("Open EasyEffects")
            onClicked: EasyEffects.openNativeWindow()
        }
    }

    // ── Equalizer: the curve ─────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: root.isEqualizer
        implicitHeight: curveColumn.implicitHeight + EasyEffectsStyle.gap + EasyEffectsStyle.gapSmall
        radius: EasyEffectsStyle.radiusField
        color: EasyEffectsStyle.colField

        ColumnLayout {
            id: curveColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: EasyEffectsStyle.gapLarge
                rightMargin: EasyEffectsStyle.gapLarge
                topMargin: EasyEffectsStyle.gap
            }
            spacing: EasyEffectsStyle.gapSmall - 2

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("RESPONSE")
                    font.pixelSize: EasyEffectsStyle.textCaption
                    font.variableAxes: EasyEffectsStyle.axesCaption
                    font.letterSpacing: EasyEffectsStyle.letterSpacingCaption
                    color: EasyEffectsStyle.colOnSurfaceVariant
                }

                EasyEffectsPill {
                    label: Translation.tr("%1 bands").arg(root.bandCount)
                    pillHeight: EasyEffectsStyle.pillHeight - EasyEffectsStyle.gapSmall / 2
                    labelSize: EasyEffectsStyle.textSmall
                    colContent: EasyEffectsStyle.colOnSurface
                    colFill: EasyEffectsStyle.colSheet
                }
            }

            ResponseCurve {
                Layout.fillWidth: true
                implicitHeight: EasyEffectsStyle.bandSliderHeight / 2 - EasyEffectsStyle.gapSmall
                lineWidth: EasyEffectsStyle.gapTiny - 0.5
                range: root.bandRange
                values: root.isEqualizer ? Logic.equalizerResponse(root.block?.[root.channels[0]], root.bandCount, curveFrequencies) : []
                secondary: root.split ? Logic.equalizerResponse(root.block?.[root.channels[1]], root.bandCount, curveFrequencies) : []
                highlight: {
                    if (root.openBand < 0)
                        return -1;
                    const hz = Number(root.block?.[root.channel || root.channels[0]]?.[`band${root.openBand}`]?.frequency) || 1000;
                    return (Math.log10(Math.max(20, Math.min(20000, hz))) - Math.log10(20)) / 3;
                }
                readonly property var curveFrequencies: Logic.logFrequencies(96, 20, 20000)
            }
        }
    }

    // ── Equalizer: one bar per band ──────────────────────────────────────
    Rectangle {
        id: bandsTile
        Layout.fillWidth: true
        visible: root.isEqualizer && root.gainControl !== undefined
        implicitHeight: bandsColumn.implicitHeight + EasyEffectsStyle.gap + EasyEffectsStyle.gapSmall
        radius: EasyEffectsStyle.radiusField
        color: EasyEffectsStyle.colField

        ColumnLayout {
            id: bandsColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: EasyEffectsStyle.gap
                rightMargin: EasyEffectsStyle.gap
                topMargin: EasyEffectsStyle.gap
            }
            spacing: EasyEffectsStyle.gapSmall + 2

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: EasyEffectsStyle.gapSmall - 2
                spacing: EasyEffectsStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("BANDS")
                    font.pixelSize: EasyEffectsStyle.textCaption
                    font.variableAxes: EasyEffectsStyle.axesCaption
                    font.letterSpacing: EasyEffectsStyle.letterSpacingCaption
                    color: EasyEffectsStyle.colOnSurfaceVariant
                }

                Repeater {
                    model: root.split ? root.channels : []

                    ClockChip {
                        required property string modelData
                        height_: EasyEffectsStyle.pillHeight - EasyEffectsStyle.gapTiny
                        label: Logic.labelFor(modelData)
                        selected: root.channel === modelData
                        onClicked: root.channel = modelData
                    }
                }
            }

            // Bars fill the tile; a long equalizer scrolls sideways instead of squeezing them.
            Flickable {
                id: barsFlick
                Layout.fillWidth: true
                implicitHeight: EasyEffectsStyle.bandSliderHeight + EasyEffectsStyle.fieldBadge
                contentWidth: Math.max(width, root.bandCount * EasyEffectsStyle.bandColumnMin)
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                readonly property real columnWidth: root.bandCount > 0 ? contentWidth / root.bandCount : 0

                Row {
                    Repeater {
                        model: root.isEqualizer ? root.bandCount : 0

                        Item {
                            id: bandColumn
                            required property int index
                            readonly property bool open: root.openBand === bandColumn.index
                            readonly property real gain: Number(root.bandValue(root.gainControl, bandColumn.index)) || 0
                            readonly property real frequency: Number(root.bandValue(root.bandControls.find(control => control.key === "frequency"), bandColumn.index)) || 0

                            width: barsFlick.columnWidth
                            height: barsFlick.height

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: EasyEffectsStyle.gapTiny / 2
                                anchors.rightMargin: EasyEffectsStyle.gapTiny / 2
                                radius: EasyEffectsStyle.pill(bandColumn.width)
                                color: EasyEffectsStyle.tint(EasyEffectsStyle.colPrimary, EasyEffectsStyle.tintIdle)
                                opacity: bandColumn.open ? 1 : 0

                                Behavior on opacity {
                                    animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
                                }
                            }

                            BandSlider {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: EasyEffectsStyle.gapSmall
                                width: bandColumn.width
                                height: EasyEffectsStyle.bandSliderHeight
                                from: -root.bandRange
                                to: root.bandRange
                                value: bandColumn.gain
                                selected: bandColumn.open
                                viewLeft: barsFlick.contentX - bandColumn.x
                                viewRight: barsFlick.contentX + barsFlick.width - bandColumn.x
                                valueText: `${bandColumn.gain > 0 ? "+" : ""}${Number(bandColumn.gain.toFixed(1))} dB`
                                onPicked: root.openBand = bandColumn.index
                                onMoved: value => root.setBand(root.gainControl, bandColumn.index, value)
                            }

                            StyledText {
                                anchors {
                                    horizontalCenter: parent.horizontalCenter
                                    bottom: parent.bottom
                                    bottomMargin: EasyEffectsStyle.gapSmall
                                }
                                text: root.shortFrequency(bandColumn.frequency)
                                font.pixelSize: EasyEffectsStyle.textCaption
                                font.weight: bandColumn.open ? Font.Bold : Font.DemiBold
                                color: bandColumn.open ? EasyEffectsStyle.colPrimary : EasyEffectsStyle.colSubtext
                            }

                            MouseArea {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                height: EasyEffectsStyle.fieldBadge
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openBand = bandColumn.open ? -1 : bandColumn.index
                            }
                        }
                    }
                }
            }

            // Where the visible bands sit among all of them; drag it to scroll sideways.
            Item {
                id: barsScroll
                Layout.fillWidth: true
                visible: barsFlick.contentWidth > barsFlick.width + 1
                implicitHeight: EasyEffectsStyle.gapSmall + EasyEffectsStyle.gapTiny

                readonly property real ratio: barsFlick.width / Math.max(1, barsFlick.contentWidth)
                readonly property real range: Math.max(1, width - thumb.width)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: EasyEffectsStyle.gapTiny + 2
                    radius: height / 2
                    color: EasyEffectsStyle.tint(EasyEffectsStyle.colOnSurfaceVariant, EasyEffectsStyle.tintHover)
                }

                Rectangle {
                    id: thumb
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(EasyEffectsStyle.gapHuge, barsScroll.width * barsScroll.ratio)
                    height: EasyEffectsStyle.gapTiny + 2
                    radius: height / 2
                    color: EasyEffectsStyle.colPrimary
                    x: barsFlick.contentX / Math.max(1, barsFlick.contentWidth - barsFlick.width) * barsScroll.range
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -EasyEffectsStyle.gapSmall
                    anchors.bottomMargin: -EasyEffectsStyle.gapSmall
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => follow(mouse.x)
                    onPositionChanged: mouse => follow(mouse.x)

                    function follow(x: real): void {
                        const p = Math.max(0, Math.min(1, (x - thumb.width / 2) / barsScroll.range));
                        barsFlick.contentX = p * (barsFlick.contentWidth - barsFlick.width);
                    }
                }
            }
        }
    }

    // ── Equalizer: the mode ──────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        visible: root.modeControl !== undefined && root.modeControl !== null
        spacing: EasyEffectsStyle.gapSmall

        Repeater {
            model: root.modeControl?.options ?? []

            EasyEffectsFilterChip {
                required property string modelData
                label: root.modeNames[modelData] ?? modelData
                symbol: root.modeIcons[modelData] ?? "graphic_eq"
                selected: root.editor.value(root.instance, "", "mode") === modelData
                onTriggered: root.editor.setValue(root.instance, root.modeControl, modelData, 0, "")
            }
        }
    }

    // ── The open band's own settings ─────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.isEqualizer && root.openBand >= 0
        spacing: EasyEffectsStyle.gapSmall - 2

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: EasyEffectsStyle.gapTiny
            Layout.topMargin: EasyEffectsStyle.gapTiny
            visible: root.openBand >= 0
            text: root.openBand >= 0 ? Translation.tr("BAND %1").arg(root.openBand + 1) + " · " + root.bandSummary(root.openBand) : ""
            elide: Text.ElideRight
            font.pixelSize: EasyEffectsStyle.textCaption
            font.variableAxes: EasyEffectsStyle.axesCaption
            font.letterSpacing: EasyEffectsStyle.letterSpacingCaption
            color: EasyEffectsStyle.colPrimary
        }

        Repeater {
            model: root.isEqualizer && root.openBand >= 0 ? root.bandControls.filter(control => control.key !== "gain") : []

            EffectControl {
                required property var modelData
                control: modelData
                value: root.bandValue(modelData, root.openBand)
                onEdited: value => root.setBand(modelData, root.openBand, value)
            }
        }
    }

    // ── The effect's own settings, by section ────────────────────────────
    Repeater {
        model: root.sections

        ColumnLayout {
            id: sectionColumn
            required property string modelData
            Layout.fillWidth: true
            spacing: EasyEffectsStyle.gapSmall - 2

            StyledText {
                visible: sectionColumn.modelData.length > 0
                Layout.topMargin: EasyEffectsStyle.gapSmall
                Layout.leftMargin: EasyEffectsStyle.gapTiny
                text: Logic.labelFor(sectionColumn.modelData).toUpperCase()
                font.pixelSize: EasyEffectsStyle.textCaption
                font.variableAxes: EasyEffectsStyle.axesCaption
                font.letterSpacing: EasyEffectsStyle.letterSpacingCaption
                color: EasyEffectsStyle.colPrimary
            }

            Repeater {
                model: root.topControls.filter(control => (control.section ?? "") === sectionColumn.modelData)

                EffectControl {
                    required property var modelData
                    control: modelData
                    value: root.editor.value(root.instance, modelData.section ?? "", modelData.key)
                    onEdited: value => root.setTop(modelData, value)
                }
            }
        }
    }

    // ── Multiband bands ──────────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        Layout.topMargin: EasyEffectsStyle.gapSmall
        visible: !root.isEqualizer && root.bands !== null
        spacing: EasyEffectsStyle.gapTiny

        Repeater {
            model: !root.isEqualizer && root.bands ? root.bands.count : 0

            ClockChip {
                required property int index
                height_: EasyEffectsStyle.pillHeight - EasyEffectsStyle.gapTiny
                label: Translation.tr("Band %1").arg(index + 1)
                selected: root.multibandBand === index
                opacity: index === 0 || root.editor.value(root.instance, `band${index}`, "enable-band") === true ? 1 : EasyEffectsStyle.dimmed
                onClicked: root.multibandBand = index
            }
        }
    }

    Repeater {
        model: !root.isEqualizer && root.bands
            ? root.bands.controls.filter(control => root.multibandBand >= (control.fromBand ?? 0)) : []

        EffectControl {
            required property var modelData
            control: modelData
            value: root.bandValue(modelData, root.multibandBand)
            onEdited: value => root.setBand(modelData, root.multibandBand, value)
        }
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Reset to defaults")
            symbol: "restart_alt"
            danger: true
            visible: root.spec !== null
            onClicked: root.editor.resetEffect(root.instance)
        },
        ClockSheetAction {
            primary: true
            label: Translation.tr("Done")
            symbol: "check"
            onClicked: root.close()
        }
    ]
}
