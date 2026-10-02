pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.easyEffects.components
import "../../../../services/easyEffects/EasyEffectsLogic.js" as Logic

/**
 * The preset the pipeline is running, as the page's hero: the device it plays through
 * and whether it is on, a big shape carrying the preset, its name, the effects in its
 * chain and the two things you do next (edit it, switch the effects off).
 *
 * Primary container while the effects are on, a plain pane while they are not, so the
 * state of the whole page is readable from the hero alone. In `strip` form (a page too
 * narrow to give it a column) it is one row: the shape, the name and the buttons.
 */
Rectangle {
    id: root

    required property var editor
    /// True when the page has no room beside the grid: one row instead of a column.
    property bool strip: false
    /// A narrow window: the strip drops its caption line to fit a shorter row.
    property bool compact: false

    signal editRequested()

    readonly property string pipeline: root.editor.pipeline
    readonly property string preset: root.editor.presetName
    readonly property bool loaded: root.preset.length > 0
    readonly property bool lit: root.loaded && EasyEffects.active
    readonly property var device: root.pipeline === "input" ? EasyEffects.inputDevice : EasyEffects.outputDevice
    readonly property string deviceDefault: root.pipeline === "input" ? EasyEffects.inputDeviceDefault : EasyEffects.outputDeviceDefault
    readonly property string family: EasyEffects.familyOf(root.preset)
    readonly property string shortName: EasyEffects.shortName(root.preset)

    readonly property color colContent: root.lit ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colOnSurface
    readonly property color colSubContent: root.lit ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintSubtext) : EasyEffectsStyle.colSubtext
    readonly property color colCore: root.lit ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colSecondaryContainer
    readonly property color colOnCore: root.lit ? EasyEffectsStyle.colPrimaryContainer : EasyEffectsStyle.colOnSecondaryContainer

    readonly property string stateLabel: {
        if (!EasyEffects.running)
            return Translation.tr("Not running");
        if (!root.loaded)
            return Translation.tr("No preset");
        return EasyEffects.bypassed ? Translation.tr("Bypassed") : Translation.tr("Playing now");
    }

    readonly property string caption: {
        const parts = [];
        if (root.family.length > 0)
            parts.push(root.family);
        if (root.loaded && root.preset === root.deviceDefault)
            parts.push(Translation.tr("device default"));
        return parts.join(" · ");
    }

    readonly property var chips: root.loaded ? root.editor.chain.map(id => ({ icon: Logic.effectIcon(id), name: root.editor.nameOf(id) })) : []

    radius: EasyEffectsStyle.radiusPane
    color: root.lit ? EasyEffectsStyle.colPrimaryContainer : EasyEffectsStyle.colPane
    clip: true

    Behavior on color {
        animation: EasyEffectsStyle.motionFast.colorAnimation.createObject(this)
    }

    // The hero's texture: contour lines that drift while the preset is playing and hold
    // still, fainter, when it is not.
    TopographyField {
        anchors.fill: parent
        running: root.lit
        baseColor: root.colContent
        lineOpacity: root.lit ? EasyEffectsStyle.opacityTopography : EasyEffectsStyle.opacityTopographyIdle
        cornerRadius: root.radius
    }

    component StatePills: RowLayout {
        spacing: EasyEffectsStyle.gapSmall

        EasyEffectsPill {
            symbol: root.pipeline === "input" ? "mic" : "speaker"
            label: Audio.friendlyDeviceName(root.device)
            colContent: root.colContent
            maxWidth: Math.max(EasyEffectsStyle.heroWidthMin / 2, root.width / 2)
        }

        EasyEffectsPill {
            label: root.stateLabel
            dot: root.lit
            colContent: root.colContent
        }
    }

    component HeroButtons: RowLayout {
        spacing: EasyEffectsStyle.gapSmall

        EasyEffectsButton {
            Layout.fillWidth: !root.strip
            variant: root.lit ? "onHero" : "filled"
            buttonHeight: EasyEffectsStyle.heroButtonHeight
            symbol: "tune"
            label: Translation.tr("Edit effects")
            enabled: root.loaded
            onClicked: root.editRequested()
        }

        EasyEffectsButton {
            visible: EasyEffects.running
            variant: root.lit ? "ghost" : "tonal"
            buttonHeight: EasyEffectsStyle.heroButtonHeight
            symbol: EasyEffects.bypassed ? "graphic_eq" : "do_not_disturb_on"
            label: EasyEffects.bypassed ? Translation.tr("Turn on") : Translation.tr("Bypass")
            iconOnly: root.strip
            onClicked: EasyEffects.toggleBypass()
        }
    }

    // ── A column, beside the grid ───────────────────────────────────────
    ColumnLayout {
        anchors {
            fill: parent
            margins: EasyEffectsStyle.heroPadding
        }
        visible: !root.strip
        spacing: 0

        StatePills {
            Layout.fillWidth: true
        }

        Item {
            id: art
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: EasyEffectsStyle.heroShapeCore / 2
            readonly property real big: Math.min(EasyEffectsStyle.heroShape, art.width, art.height)

            MaterialShape {
                anchors.centerIn: parent
                implicitSize: art.big
                shape: root.lit ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                color: EasyEffectsStyle.tint(root.colContent, root.lit ? EasyEffectsStyle.tintShape : EasyEffectsStyle.tintIdle)
            }

            EasyEffectsBadge {
                anchors.centerIn: parent
                size: art.big * EasyEffectsStyle.heroShapeCore / EasyEffectsStyle.heroShape
                text: root.loaded ? EasyEffects.iconFor(root.preset) : "graphic_eq"
                shape: EasyEffectsStyle.shapeFor(root.preset)
                color: root.colCore
                colSymbol: root.colOnCore
            }
        }

        WavyLine {
            Layout.fillWidth: true
            Layout.topMargin: EasyEffectsStyle.gapSmall
            implicitHeight: EasyEffectsStyle.pillHeight + EasyEffectsStyle.gapSmall
            lineWidth: EasyEffectsStyle.gapTiny
            color: root.colContent
            opacity: EasyEffectsStyle.opacityWave
            amplitudeMultiplier: root.lit ? 1.6 : 0

            Behavior on amplitudeMultiplier {
                enabled: !EasyEffectsStyle.reducedMotion
                animation: EasyEffectsStyle.motionDefault.numberAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: EasyEffectsStyle.gapSmall
            visible: root.caption.length > 0
            text: root.caption
            elide: Text.ElideRight
            font.pixelSize: EasyEffectsStyle.textNormal - 1
            font.weight: Font.Medium
            color: root.colSubContent
        }

        StyledText {
            Layout.fillWidth: true
            text: root.loaded ? root.shortName : Translation.tr("No preset loaded")
            elide: Text.ElideRight
            font.family: EasyEffectsStyle.fontTitle
            font.variableAxes: EasyEffectsStyle.axesDisplay
            font.pixelSize: root.loaded ? EasyEffectsStyle.textHero : EasyEffectsStyle.textBanner
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: EasyEffectsStyle.textBanner
            color: root.colContent
        }

        // The effects, as many rows as fit; the Effects page lists them all.
        Item {
            Layout.fillWidth: true
            Layout.topMargin: EasyEffectsStyle.gap
            Layout.bottomMargin: EasyEffectsStyle.gap
            visible: root.chips.length > 0
            implicitHeight: Math.min(chipFlow.implicitHeight, EasyEffectsStyle.pillHeightLarge * 2 + EasyEffectsStyle.gapSmall - 2)
            clip: true

            Flow {
                id: chipFlow
                width: parent.width
                spacing: EasyEffectsStyle.gapSmall - 2

                Repeater {
                    model: root.chips

                    EasyEffectsPill {
                        required property var modelData
                        symbol: modelData.icon
                        filledSymbol: false
                        label: modelData.name
                        pillHeight: EasyEffectsStyle.pillHeightLarge
                        labelSize: EasyEffectsStyle.textNormal - 1
                        colContent: root.colContent
                        colFill: EasyEffectsStyle.tint(root.colContent, root.lit ? EasyEffectsStyle.tintHover : EasyEffectsStyle.tintIdle)
                        maxWidth: chipFlow.width
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: EasyEffectsStyle.gap
            visible: root.chips.length === 0
        }

        HeroButtons {
            Layout.fillWidth: true
        }
    }

    // ── A strip, when the page is too narrow for a column ───────────────
    RowLayout {
        anchors {
            fill: parent
            margins: root.compact ? EasyEffectsStyle.gap : EasyEffectsStyle.cardPadding
        }
        visible: root.strip
        spacing: EasyEffectsStyle.gapLarge

        EasyEffectsBadge {
            size: Math.min(EasyEffectsStyle.heroButtonHeight + EasyEffectsStyle.gapHuge, root.height - (root.compact ? EasyEffectsStyle.gap : EasyEffectsStyle.cardPadding) * 2)
            text: root.loaded ? EasyEffects.iconFor(root.preset) : "graphic_eq"
            shape: EasyEffectsStyle.shapeFor(root.preset)
            color: root.colCore
            colSymbol: root.colOnCore
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                visible: root.caption.length > 0 && !root.compact
                text: root.caption
                elide: Text.ElideRight
                font.pixelSize: EasyEffectsStyle.textSmall
                color: root.colSubContent
            }

            StyledText {
                Layout.fillWidth: true
                text: root.loaded ? root.shortName : Translation.tr("No preset loaded")
                elide: Text.ElideRight
                font.family: EasyEffectsStyle.fontTitle
                font.variableAxes: EasyEffectsStyle.axesDisplay
                font.pixelSize: EasyEffectsStyle.textBanner
                color: root.colContent
            }

            StyledText {
                Layout.fillWidth: true
                text: `${Audio.friendlyDeviceName(root.device)} · ${root.stateLabel}`
                elide: Text.ElideRight
                font.pixelSize: EasyEffectsStyle.textSmall
                color: root.colSubContent
            }
        }

        HeroButtons {
        }
    }
}
