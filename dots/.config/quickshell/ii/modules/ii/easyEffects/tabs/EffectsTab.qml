pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.easyEffects.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * The loaded preset's chain, in the order the sound goes through it.
 *
 * A header says which preset it is and whether it has unsaved edits, a curve shows what
 * the chain does to the tone, and each effect is a row: switch it off, move it, remove
 * it, or open it in the side sheet (the open one is the primary container). The page FAB
 * adds an effect. Moving, adding and removing save the preset at once (EasyEffects can
 * only rebuild a chain from its file); knob edits wait for "Save to preset", and are
 * heard meanwhile when live apply is on.
 *
 * The header and the curve stay put; only the rows scroll.
 */
Item {
    id: root

    required property var editor
    required property var panels
    property bool compact: false
    property bool wide: false
    /// The page's settled width (see AppContent).
    property real layoutWidth: width

    readonly property var chain: root.editor.chain
    readonly property var frequencies: Logic.logFrequencies(96, 20, 20000)
    /// What the whole chain does to the tone, redrawn as the knobs move.
    readonly property var response: root.editor.ready ? Logic.chainResponse(root.editor.data, root.editor.pipeline, root.frequencies) : root.frequencies.map(() => 0)
    readonly property real range: {
        let peak = 0;
        root.response.forEach(db => peak = Math.max(peak, Math.abs(db)));
        return Math.min(36, Math.max(12, Math.ceil((peak + 3) / 6) * 6));
    }
    /// The effect open in the side sheet, so its row can say so.
    readonly property string openInstance: root.panels.open && root.panels.currentSource === effectSheet
        ? String(root.panels.current?.instance ?? "") : ""
    /// With little height the curve gives way to the rows.
    readonly property bool showResponse: root.height >= EasyEffectsStyle.responseHeight * 3.5
    readonly property var axisLabels: [[20, "20 Hz"], [100, "100"], [1000, "1 k"], [10000, "10 k"], [20000, "20 kHz"]]

    // Summaries: the values that say the most about each kind of effect.
    readonly property var summaryKeys: ({
        equalizer: ["num-bands", "mode"],
        midside_equalizer: ["num-bands", "mode"],
        compressor: ["threshold", "ratio"],
        expander: ["threshold", "ratio"],
        limiter: ["threshold", "lookahead"],
        maximizer: ["threshold", "ceiling"],
        crossfeed: ["fcut", "feed"],
        gate: ["threshold", "reduction"],
        deesser: ["threshold", "ratio"],
        bass_enhancer: ["amount", "scope"],
        loudness: ["volume", "std"],
        reverb: ["room-size", "decay-time"],
        pitch: ["semitones", "cents"],
        delay: ["time-l", "time-r"],
        filter: ["type", "frequency"],
        stereo_tools: ["mode", "balance-in"],
        autogain: ["target"]
    })

    readonly property var bandKinds: ({
        "Lo-shelf": Translation.tr("low shelf"),
        "Hi-shelf": Translation.tr("high shelf"),
        "Bell": Translation.tr("bell")
    })

    // "10 bands · +4 dB low shelf": the band that moves the sound the most, or "flat".
    function equalizerSummary(instance: string, spec: var): string {
        const block = root.editor.blockOf(instance);
        const count = Number(block?.["num-bands"] ?? 0);
        const head = Translation.tr("%1 bands").arg(count);
        const strongest = Logic.strongestBand(block, spec.channels?.[0] ?? "left");
        if (!strongest)
            return `${head} · ${Translation.tr("flat")}`;
        const gain = `${strongest.gain > 0 ? "+" : ""}${Number(strongest.gain.toFixed(1))} dB`;
        if (strongest.type === "Bell")
            return `${head} · ${gain} ${Translation.tr("at %1").arg(Logic.formatValue({ key: "frequency", type: "double" }, strongest.frequency))}`;
        return `${head} · ${gain} ${root.bandKinds[strongest.type] ?? String(strongest.type).toLowerCase()}`;
    }

    function summaryOf(instance: string): string {
        const spec = root.editor.specOf(instance);
        if (!spec)
            return Translation.tr("Edited in EasyEffects");
        const plugin = Logic.instanceParts(instance).plugin;
        if (plugin === "equalizer" || plugin === "midside_equalizer")
            return root.equalizerSummary(instance, spec);
        const keys = root.summaryKeys[plugin] ?? ["input-gain", "output-gain"];
        return keys.map(key => spec.controls.find(control => control.key === key && !control.section))
            .filter(control => control !== undefined)
            .map(control => {
                const value = root.editor.value(instance, "", control.key);
                const label = control.key === "num-bands" ? Translation.tr("bands") : Logic.labelFor(control.key).toLowerCase();
                return control.key === "num-bands" ? `${value} ${label}` : `${label} ${Logic.formatValue(control, value ?? control.default)}`;
            }).join(" · ");
    }

    function openEffect(instance: string): void {
        root.panels.show(effectSheet, { editor: root.editor, instance: instance });
    }


    ColumnLayout {
        anchors.fill: parent
        spacing: EasyEffectsStyle.gap

        // ── The preset and its unsaved edits ──────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.editor.presetName.length > 0 || root.editor.error.length > 0
            implicitHeight: EasyEffectsStyle.headerHeight
            radius: EasyEffectsStyle.radiusCard
            color: EasyEffectsStyle.colPane

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: EasyEffectsStyle.gapLarge
                    rightMargin: EasyEffectsStyle.cardPadding
                }
                spacing: EasyEffectsStyle.gapLarge

                EasyEffectsBadge {
                    size: EasyEffectsStyle.deviceColumnBadge + EasyEffectsStyle.gapSmall
                    text: root.editor.presetName.length > 0 ? EasyEffects.iconFor(root.editor.presetName) : "instant_mix"
                    shape: EasyEffectsStyle.shapeFor(root.editor.presetName)
                    color: EasyEffectsStyle.colPrimary
                    colSymbol: EasyEffectsStyle.colOnPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.editor.presetName.length > 0 ? EasyEffects.shortName(root.editor.presetName) : Translation.tr("No preset loaded")
                        elide: Text.ElideRight
                        font.family: EasyEffectsStyle.fontTitle
                        font.variableAxes: EasyEffectsStyle.axesDisplay
                        font.pixelSize: EasyEffectsStyle.textBanner - EasyEffectsStyle.gapTiny
                        color: EasyEffectsStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            if (root.editor.error.length > 0)
                                return root.editor.error;
                            if (root.editor.detached && root.editor.presetName.length > 0)
                                return Translation.tr("Saved for a device that isn't playing: edits go to the preset file only.");
                            if (root.editor.presetName.length === 0)
                                return Translation.tr("Load a preset from the Presets tab to see its effects.");
                            if (!EasyEffects.running)
                                return Translation.tr("EasyEffects isn't running: edits are saved to the file only.");
                            return root.chain.length === 1 ? Translation.tr("1 effect")
                                : Translation.tr("%1 effects, in the order the sound goes through them").arg(root.chain.length);
                        }
                        font.pixelSize: EasyEffectsStyle.textNormal - 1
                        color: root.editor.error.length > 0 ? EasyEffectsStyle.colError : EasyEffectsStyle.colSubtext
                    }
                }

                EasyEffectsPill {
                    visible: root.editor.dirty && !root.compact
                    dot: true
                    pillHeight: EasyEffectsStyle.pillHeightLarge
                    label: root.editor.liveApply ? Translation.tr("Unsaved · playing now") : Translation.tr("Unsaved")
                    colContent: EasyEffectsStyle.colOnTertiaryContainer
                    colFill: EasyEffectsStyle.colTertiaryContainer
                }

                EasyEffectsButton {
                    visible: root.editor.dirty
                    symbol: "undo"
                    label: Translation.tr("Revert")
                    iconOnly: root.compact
                    onClicked: root.editor.revert()
                }

                EasyEffectsButton {
                    visible: root.editor.dirty
                    variant: "filled"
                    symbol: "save"
                    filledSymbol: true
                    label: root.editor.saving ? Translation.tr("Saving…") : Translation.tr("Save to preset")
                    iconOnly: root.compact
                    enabled: !root.editor.saving
                    onClicked: root.editor.save()
                }
            }
        }

        // ── What the chain does to the tone ───────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.editor.presetName.length > 0 && root.showResponse
            implicitHeight: EasyEffectsStyle.responseHeight
            radius: EasyEffectsStyle.radiusCard
            color: EasyEffectsStyle.colPane

            ColumnLayout {
                anchors {
                    fill: parent
                    leftMargin: EasyEffectsStyle.heroPadding - 2
                    rightMargin: EasyEffectsStyle.heroPadding - 2
                    topMargin: EasyEffectsStyle.gapLarge
                    bottomMargin: EasyEffectsStyle.gap
                }
                spacing: EasyEffectsStyle.gapTiny

                RowLayout {
                    Layout.fillWidth: true
                    spacing: EasyEffectsStyle.gapSmall + 2

                    StyledText {
                        text: Translation.tr("Frequency response")
                        font.variableAxes: EasyEffectsStyle.axesName
                        font.pixelSize: EasyEffectsStyle.textBody
                        color: EasyEffectsStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: !root.compact
                        text: Translation.tr("what the chain does to the sound")
                        elide: Text.ElideRight
                        font.pixelSize: EasyEffectsStyle.textSmall
                        color: EasyEffectsStyle.colSubtext
                    }

                    Item {
                        Layout.fillWidth: root.compact
                    }

                    EasyEffectsPill {
                        label: `±${root.range} dB`
                        pillHeight: EasyEffectsStyle.pillHeight - EasyEffectsStyle.gapTiny
                        labelSize: EasyEffectsStyle.textCaption
                        colContent: EasyEffectsStyle.colSubtext
                        colFill: EasyEffectsStyle.colField
                    }
                }

                ResponseCurve {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    grid: true
                    range: root.range
                    values: root.response
                }

                Item {
                    id: axis
                    Layout.fillWidth: true
                    implicitHeight: EasyEffectsStyle.textCaption + EasyEffectsStyle.gapTiny

                    Repeater {
                        model: root.axisLabels

                        StyledText {
                            required property var modelData
                            // Where the frequency sits on the log axis, kept inside the card.
                            x: Math.max(0, Math.min(axis.width - width,
                                (Math.log10(modelData[0]) - Math.log10(20)) / 3 * axis.width - width / 2))
                            text: modelData[1]
                            font.pixelSize: EasyEffectsStyle.textCaption
                            color: EasyEffectsStyle.colSubtext
                        }
                    }
                }
            }
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            visible: root.editor.presetName.length === 0
            symbol: "instant_mix"
            title: Translation.tr("No preset loaded")
            subtitle: Translation.tr("Load a preset from the Presets page to edit its effects.")
        }

        ClockEmptyState {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            visible: root.editor.ready && root.chain.length === 0
            symbol: "add_circle"
            shapeSize: ClockStyle.emptyShapeSmall
            title: Translation.tr("No effects")
            subtitle: Translation.tr("The sound passes through untouched. Add an effect to start shaping it.")
        }

        // ── The chain ─────────────────────────────────────────────────────
        StyledFlickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.chain.length > 0
            clip: true
            contentWidth: width
            contentHeight: rows.implicitHeight + EasyEffectsStyle.fabClearance

            ColumnLayout {
                id: rows
                width: flick.width
                spacing: EasyEffectsStyle.gapSmall

                Repeater {
                    model: root.chain

                    Rectangle {
                        id: row
                        required property string modelData
                        required property int index
                        readonly property bool bypassed: root.editor.blockOf(row.modelData)?.bypass === true
                        readonly property bool open: root.openInstance === row.modelData
                        readonly property color colContent: row.open ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colOnSurface
                        readonly property color colSubContent: row.open ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintSubtext) : EasyEffectsStyle.colSubtext

                        Layout.fillWidth: true
                        implicitHeight: EasyEffectsStyle.effectRowHeight
                        radius: EasyEffectsStyle.radiusRow
                        color: row.open ? EasyEffectsStyle.colPrimaryContainer
                            : rowHover.hovered ? EasyEffectsStyle.colRow : EasyEffectsStyle.colPane

                        Behavior on color {
                            animation: EasyEffectsStyle.motionFast.colorAnimation.createObject(row)
                        }

                        HoverHandler {
                            id: rowHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openEffect(row.modelData)
                        }

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: EasyEffectsStyle.gapSmall + 2
                                rightMargin: EasyEffectsStyle.gapLarge + 2
                            }
                            spacing: EasyEffectsStyle.gapSmall + 2

                            StyledText {
                                Layout.preferredWidth: EasyEffectsStyle.gapHuge + 2
                                horizontalAlignment: Text.AlignHCenter
                                text: String(row.index + 1)
                                font.family: EasyEffectsStyle.fontNumbers
                                font.pixelSize: EasyEffectsStyle.textNormal
                                font.weight: Font.Bold
                                color: row.colContent
                                opacity: EasyEffectsStyle.opacityIndex
                            }

                            EasyEffectsBadge {
                                size: EasyEffectsStyle.effectBadge
                                text: Logic.effectIcon(row.modelData)
                                shape: EasyEffectsStyle.shapeFor(Logic.instanceParts(row.modelData).plugin)
                                color: row.bypassed ? EasyEffectsStyle.colField
                                    : row.open ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colPrimaryContainer
                                colSymbol: row.bypassed ? EasyEffectsStyle.colSubtext
                                    : row.open ? EasyEffectsStyle.colPrimaryContainer : EasyEffectsStyle.colOnPrimaryContainer
                                opacity: row.bypassed ? EasyEffectsStyle.dimmed : 1
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 0
                                opacity: row.bypassed ? EasyEffectsStyle.dimmed : 1

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.editor.nameOf(row.modelData)
                                    elide: Text.ElideRight
                                    font.variableAxes: EasyEffectsStyle.axesName
                                    font.pixelSize: EasyEffectsStyle.textName
                                    color: row.colContent
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.bypassed ? Translation.tr("Bypassed") : root.summaryOf(row.modelData)
                                    elide: Text.ElideRight
                                    font.pixelSize: EasyEffectsStyle.textNormal - 1
                                    color: row.colSubContent
                                }
                            }

                            RowLayout {
                                spacing: 2

                                EasyEffectsCardAction {
                                    enabled: row.index > 0
                                    symbol: "arrow_upward"
                                    tip: Translation.tr("Earlier in the chain")
                                    colContent: row.colContent
                                    onClicked: root.editor.moveEffect(row.index, row.index - 1)
                                }

                                EasyEffectsCardAction {
                                    enabled: row.index < root.chain.length - 1
                                    symbol: "arrow_downward"
                                    tip: Translation.tr("Later in the chain")
                                    colContent: row.colContent
                                    onClicked: root.editor.moveEffect(row.index, row.index + 1)
                                }

                                EasyEffectsCardAction {
                                    symbol: "delete"
                                    tip: Translation.tr("Remove from the chain")
                                    colContent: row.colContent
                                    onClicked: {
                                        root.panels.closeNow();
                                        root.editor.removeEffect(row.modelData);
                                    }
                                }
                            }

                            StyledSwitch {
                                checked: !row.bypassed
                                checkable: false
                                activeColor: row.open ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colPrimary
                                activeThumbColor: row.open ? EasyEffectsStyle.colPrimaryContainer : EasyEffectsStyle.colOnPrimary
                                inactiveColor: row.open ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintHover) : EasyEffectsStyle.colField
                                onClicked: root.editor.setBypass(row.modelData, !row.bypassed)
                            }
                        }
                    }
                }
            }
        }
    }

    FloatingActionButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: EasyEffectsStyle.gapTiny
        anchors.bottomMargin: EasyEffectsStyle.gapTiny
        visible: root.editor.ready
        baseSize: root.compact ? EasyEffectsStyle.fabSizeCompact : EasyEffectsStyle.fabSize
        iconSize: root.compact ? EasyEffectsStyle.iconLarge : EasyEffectsStyle.fabIcon
        buttonRadius: EasyEffectsStyle.radiusFab
        buttonRadiusPressed: EasyEffectsStyle.radiusFabPressed
        iconText: "add"
        buttonText: Translation.tr("Add effect")
        expanded: hovered
        colBackground: EasyEffectsStyle.colPrimaryContainer
        colBackgroundHover: EasyEffectsStyle.colPrimaryContainerHover
        colBackgroundActive: EasyEffectsStyle.colPrimaryContainerActive
        colRipple: EasyEffectsStyle.colPrimaryContainerActive
        colOnBackground: EasyEffectsStyle.colOnPrimaryContainer
        onClicked: root.panels.show(addSheet, { editor: root.editor })
    }

    Component {
        id: effectSheet
        EffectSheet {}
    }

    Component {
        id: addSheet
        AddEffectSheet {}
    }
}
