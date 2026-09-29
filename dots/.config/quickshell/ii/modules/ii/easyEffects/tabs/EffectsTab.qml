pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * The loaded preset's chain, in the order the sound goes through it.
 *
 * Each effect can be switched off, moved, removed or opened in the side sheet; the page
 * FAB adds one. Moving, adding and removing save the preset at once (EasyEffects can
 * only rebuild a chain from its file); knob edits wait for "Save to preset", and are
 * heard meanwhile when live apply is on.
 */
Item {
    id: root

    required property var editor
    required property var panels
    property bool compact: false
    property bool wide: false

    readonly property var chain: root.editor.chain
    readonly property string firstEqualizer: root.chain.find(id => /^(midside_)?equalizer#/.test(id)) ?? ""

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

    function summaryOf(instance: string): string {
        const spec = root.editor.specOf(instance);
        if (!spec)
            return Translation.tr("Edited in EasyEffects");
        const plugin = Logic.instanceParts(instance).plugin;
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

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.fabClearance

        ColumnLayout {
            id: column
            x: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
            y: ClockStyle.gapSmall
            width: flick.width - x * 2
            spacing: ClockStyle.gap

            // ── The preset and its unsaved edits ──────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight + ClockStyle.gapLarge * 2
                radius: ClockStyle.radiusLarge
                color: root.editor.dirty ? ClockStyle.colTertiaryContainer : ClockStyle.colPane

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: headerRow
                    anchors {
                        fill: parent
                        margins: ClockStyle.gapLarge
                    }
                    spacing: ClockStyle.gap

                    MaterialSymbol {
                        text: root.editor.dirty ? "edit_note" : EasyEffects.iconFor(root.editor.presetName)
                        iconSize: ClockStyle.iconLarge
                        color: root.editor.dirty ? ClockStyle.colOnTertiaryContainer : ClockStyle.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.editor.presetName.length > 0 ? root.editor.presetName : Translation.tr("No preset loaded")
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textLarge
                            font.weight: Font.DemiBold
                            color: root.editor.dirty ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: {
                                if (root.editor.error.length > 0)
                                    return root.editor.error;
                                if (root.editor.dirty)
                                    return root.editor.liveApply ? Translation.tr("Unsaved changes, playing now. Save them to the preset to keep them.")
                                        : Translation.tr("Unsaved changes. Save them to hear and keep them.");
                                if (root.editor.presetName.length === 0)
                                    return Translation.tr("Load a preset from the Presets tab to see its effects.");
                                if (!EasyEffects.running)
                                    return Translation.tr("EasyEffects isn't running: edits are saved to the file only.");
                                return root.chain.length === 1 ? Translation.tr("1 effect")
                                    : Translation.tr("%1 effects, in the order the sound goes through them").arg(root.chain.length);
                            }
                            font.pixelSize: ClockStyle.textSmall
                            color: root.editor.dirty ? ClockStyle.colOnTertiaryContainer : ClockStyle.colSubtext
                        }
                    }

                    ClockButton {
                        visible: root.editor.dirty
                        variant: "text"
                        symbol: "undo"
                        label: Translation.tr("Revert")
                        iconOnly: root.compact
                        onClicked: root.editor.revert()
                    }

                    ClockButton {
                        visible: root.editor.dirty
                        variant: "filled"
                        symbol: "save"
                        label: root.editor.saving ? Translation.tr("Saving…") : Translation.tr("Save to preset")
                        iconOnly: root.compact
                        enabled: !root.editor.saving
                        onClicked: root.editor.save()
                    }
                }
            }

            ClockEmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: ClockStyle.gapHuge
                visible: root.editor.presetName.length === 0
                symbol: "instant_mix"
                title: Translation.tr("No preset loaded")
                subtitle: Translation.tr("Load a preset from the Presets page to edit its effects.")
            }

            // ── The equalizer's shape, when the chain has one ─────────────
            Rectangle {
                Layout.fillWidth: true
                visible: root.firstEqualizer.length > 0
                implicitHeight: 176
                radius: ClockStyle.radiusLarge
                color: ClockStyle.colPane

                EqualizerCurve {
                    anchors {
                        fill: parent
                        margins: ClockStyle.gap
                    }
                    block: root.firstEqualizer.length > 0 ? root.editor.blockOf(root.firstEqualizer) : null
                    channels: root.editor.specOf(root.firstEqualizer)?.channels ?? ["left", "right"]
                    opacity: root.editor.blockOf(root.firstEqualizer)?.bypass === true ? 0.4 : 1
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openEffect(root.firstEqualizer)
                }
            }

            ClockEmptyState {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: ClockStyle.gapHuge
                visible: root.editor.ready && root.chain.length === 0
                symbol: "add_circle"
                shapeSize: ClockStyle.emptyShapeSmall
                title: Translation.tr("No effects")
                subtitle: Translation.tr("The sound passes through untouched. Add an effect to start shaping it.")
            }

            // ── The chain ─────────────────────────────────────────────────
            Repeater {
                model: root.chain

                Rectangle {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property bool bypassed: root.editor.blockOf(row.modelData)?.bypass === true

                    Layout.fillWidth: true
                    implicitHeight: 72
                    topLeftRadius: row.index === 0 ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: row.index === root.chain.length - 1 ? ClockStyle.radiusLarge : ClockStyle.radiusSmall / 2
                    bottomRightRadius: bottomLeftRadius
                    color: rowHover.hovered ? ClockStyle.colIdleCardHover : ClockStyle.colPane

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
                            leftMargin: ClockStyle.gapLarge
                            rightMargin: ClockStyle.gapSmall
                        }
                        spacing: ClockStyle.gap

                        MaterialShapeWrappedMaterialSymbol {
                            text: Logic.effectIcon(row.modelData)
                            iconSize: 20
                            padding: 10
                            shape: MaterialShape.Shape.Cookie7Sided
                            color: row.bypassed ? ClockStyle.colSurfaceHigh : ClockStyle.colPrimaryContainer
                            colSymbol: row.bypassed ? ClockStyle.colOnSurfaceVariant : ClockStyle.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            opacity: row.bypassed ? 0.55 : 1

                            StyledText {
                                Layout.fillWidth: true
                                text: root.editor.nameOf(row.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textNormal + 1
                                font.weight: Font.DemiBold
                                color: ClockStyle.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: row.bypassed ? Translation.tr("Bypassed") : root.summaryOf(row.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colSubtext
                            }
                        }

                        RowLayout {
                            spacing: 0
                            opacity: rowHover.hovered || root.compact ? 1 : 0
                            visible: opacity > 0

                            Behavior on opacity {
                                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                            }

                            ClockIconButton {
                                size: 34
                                iconSize: ClockStyle.iconSmall + 2
                                symbol: "arrow_upward"
                                enabled: row.index > 0
                                opacity: enabled ? 1 : 0.35
                                tooltip: Translation.tr("Earlier in the chain")
                                onClicked: root.editor.moveEffect(row.index, row.index - 1)
                            }

                            ClockIconButton {
                                size: 34
                                iconSize: ClockStyle.iconSmall + 2
                                symbol: "arrow_downward"
                                enabled: row.index < root.chain.length - 1
                                opacity: enabled ? 1 : 0.35
                                tooltip: Translation.tr("Later in the chain")
                                onClicked: root.editor.moveEffect(row.index, row.index + 1)
                            }

                            ClockIconButton {
                                size: 34
                                iconSize: ClockStyle.iconSmall + 2
                                symbol: "delete"
                                tooltip: Translation.tr("Remove from the chain")
                                onClicked: {
                                    root.panels.closeNow();
                                    root.editor.removeEffect(row.modelData);
                                }
                            }
                        }

                        StyledSwitch {
                            checked: !row.bypassed
                            checkable: false
                            onClicked: root.editor.setBypass(row.modelData, !row.bypassed)
                        }
                    }
                }
            }
        }
    }

    FloatingActionButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: ClockStyle.gapLarge
        anchors.bottomMargin: ClockStyle.gapLarge
        visible: root.editor.ready
        baseSize: ClockStyle.fabSizeLarge
        iconSize: 34
        buttonRadius: Appearance.rounding.large
        buttonRadiusPressed: Appearance.rounding.normal
        iconText: "add"
        buttonText: Translation.tr("Add effect")
        expanded: hovered
        colBackground: Appearance.colors.colPrimaryContainer
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        colBackgroundActive: Appearance.colors.colPrimaryContainerActive
        colRipple: Appearance.colors.colPrimaryContainerActive
        colOnBackground: Appearance.colors.colOnPrimaryContainer
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
