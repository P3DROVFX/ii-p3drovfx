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
 *
 * The same hero is the desktop widget (see EasyEffectsPresetWidget): there it can also be
 * `landscape` (the art on the left, the rest beside it), and every part can be switched
 * off — the texture, the art (or swapped for the tone curve), the pills, the wave, the
 * name, the chain, the buttons — down to the texture alone.
 */
Rectangle {
    id: root

    required property var editor
    /// True when the page has no room beside the grid: one row instead of a column.
    property bool strip: false
    /// A narrow window: the strip drops its caption line to fit a shorter row.
    property bool compact: false
    /// Art on the left, everything else in a column beside it (a wide, short surface).
    property bool landscape: false

    // What is shown. Everything on is the app's hero.
    property bool showTopography: true
    /// Let the music drive the texture (see TopographyField).
    property bool topographyReactive: true
    /// Hold the texture still (a desktop widget under open windows has nobody watching it).
    property bool topographyPaused: false
    /// How strong the lines are, as a multiple of the usual opacity.
    property real topographyStrength: 1
    /// "shape" (the preset's badge), "curve" (what the chain does to the tone) or "none".
    property string art: "shape"
    property bool showDevice: true
    property bool showState: true
    /// The pill with the device's default preset.
    property bool showDefault: true
    property bool showWave: true
    property bool showCaption: true
    property bool showName: true
    property bool showEffects: true
    property bool showButtons: true

    /// Looking at a device that is not the one playing: its node, and `detached`. The hero
    /// then shows what that device starts with, in the quiet colours, and offers to make it
    /// the output instead of the effects switch.
    property var deviceNode: null
    property bool detached: false

    signal editRequested()
    signal useDeviceRequested()

    readonly property string pipeline: root.editor.pipeline
    readonly property string preset: root.editor.presetName
    readonly property bool loaded: root.preset.length > 0
    readonly property bool lit: root.loaded && EasyEffects.active && !root.detached
    readonly property var device: root.detached && root.deviceNode ? root.deviceNode
        : (root.pipeline === "input" ? EasyEffects.inputDevice : EasyEffects.outputDevice)
    readonly property string deviceDefault: root.pipeline === "input" ? EasyEffects.inputDeviceDefault : EasyEffects.outputDeviceDefault
    readonly property string family: EasyEffects.familyOf(root.preset)
    readonly property string shortName: EasyEffects.shortName(root.preset)

    readonly property color colContent: root.lit ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colOnSurface
    readonly property color colSubContent: root.lit ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintSubtext) : EasyEffectsStyle.colSubtext
    readonly property color colCore: root.lit ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colSecondaryContainer
    readonly property color colOnCore: root.lit ? EasyEffectsStyle.colPrimaryContainer : EasyEffectsStyle.colOnSecondaryContainer

    readonly property string stateLabel: {
        if (root.detached)
            return root.loaded ? Translation.tr("Starts with this") : Translation.tr("No preset");
        if (!EasyEffects.running)
            return Translation.tr("Not running");
        if (!root.loaded)
            return Translation.tr("No preset");
        return EasyEffects.bypassed ? Translation.tr("Bypassed") : Translation.tr("Playing now");
    }

    readonly property bool defaultDiffers: root.deviceDefault.length > 0 && root.deviceDefault !== root.preset
    readonly property string defaultLabel: {
        if (root.deviceDefault.length === 0)
            return Translation.tr("No default preset");
        return root.defaultDiffers ? Translation.tr("Default: %1").arg(EasyEffects.shortName(root.deviceDefault))
            : Translation.tr("Device default");
    }

    readonly property string caption: {
        const parts = [];
        if (root.family.length > 0)
            parts.push(root.family);
        if (!root.showDefault && root.loaded && root.preset === root.deviceDefault)
            parts.push(Translation.tr("device default"));
        return parts.join(" · ");
    }

    readonly property var chips: root.loaded ? root.editor.chain.map(id => ({ icon: Logic.effectIcon(id), name: root.editor.nameOf(id) })) : []

    readonly property var curveFrequencies: Logic.logFrequencies(96, 20, 20000)
    readonly property var curve: root.art === "curve" && root.editor.ready
        ? Logic.chainResponse(root.editor.data, root.pipeline, root.curveFrequencies) : root.curveFrequencies.map(() => 0)
    readonly property real curveRange: Math.min(36, Math.max(12, Math.ceil((root.curve.reduce((peak, db) => Math.max(peak, Math.abs(db)), 0) + 3) / 6) * 6))

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
        visible: root.showTopography
        running: root.lit && !root.topographyPaused
        reactive: root.topographyReactive
        baseColor: root.colContent
        lineOpacity: (root.lit ? EasyEffectsStyle.opacityTopography : EasyEffectsStyle.opacityTopographyIdle) * root.topographyStrength
        cornerRadius: root.radius
    }

    component StatePills: Flow {
        visible: root.showDevice || root.showState || root.showDefault
        spacing: EasyEffectsStyle.gapSmall

        EasyEffectsPill {
            visible: root.showDevice
            symbol: root.pipeline === "input" ? "mic" : "speaker"
            label: Audio.friendlyDeviceName(root.device)
            colContent: root.colContent
            maxWidth: Math.max(EasyEffectsStyle.heroWidthMin / 2, root.width / 2)
        }

        EasyEffectsPill {
            visible: root.showState
            label: root.stateLabel
            dot: root.lit
            colContent: root.colContent
        }

        // What this device starts with, and, when that is not what is loaded, a way to
        // load it. Per-device presets are the point of the Devices page; this keeps them
        // in sight on the page that shows the preset in use.
        EasyEffectsPill {
            visible: root.showDefault && EasyEffects.running && !root.detached
            symbol: "star"
            label: root.defaultLabel
            colContent: root.defaultDiffers ? EasyEffectsStyle.colOnTertiaryContainer : root.colContent
            colFill: root.defaultDiffers ? EasyEffectsStyle.colTertiaryContainer
                : EasyEffectsStyle.tint(root.colContent, EasyEffectsStyle.tintPill)
            maxWidth: Math.max(EasyEffectsStyle.heroWidthMin / 2, root.width - EasyEffectsStyle.heroPadding * 2)

            MouseArea {
                anchors.fill: parent
                enabled: root.defaultDiffers
                cursorShape: Qt.PointingHandCursor
                onClicked: EasyEffects.loadPreset(root.deviceDefault, root.pipeline, true)
            }
        }
    }

    /// The big piece: the preset's shape, or the tone curve, or nothing.
    component HeroArt: Item {
        id: art
        visible: root.art !== "none"
        readonly property real big: Math.min(EasyEffectsStyle.heroShape, art.width, art.height)

        MaterialShape {
            visible: root.art === "shape"
            anchors.centerIn: parent
            implicitSize: art.big
            shape: root.lit ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
            color: EasyEffectsStyle.tint(root.colContent, root.lit ? EasyEffectsStyle.tintShape : EasyEffectsStyle.tintIdle)
        }

        EasyEffectsBadge {
            visible: root.art === "shape"
            anchors.centerIn: parent
            size: art.big * EasyEffectsStyle.heroShapeCore / EasyEffectsStyle.heroShape
            text: root.loaded ? EasyEffects.iconFor(root.preset) : "graphic_eq"
            shape: EasyEffectsStyle.shapeFor(root.preset)
            color: root.colCore
            colSymbol: root.colOnCore
        }

        ResponseCurve {
            visible: root.art === "curve"
            anchors.fill: parent
            anchors.margins: EasyEffectsStyle.gapSmall
            grid: true
            lineWidth: EasyEffectsStyle.gapTiny + 1
            range: root.curveRange
            values: root.curve
            colLine: root.colContent
            colFill: EasyEffectsStyle.tint(root.colContent, EasyEffectsStyle.tintHover)
            colGrid: EasyEffectsStyle.tint(root.colContent, EasyEffectsStyle.tintPill)
        }
    }

    component HeroWave: WavyLine {
        visible: root.showWave
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

    component HeroName: StyledText {
        visible: root.showName
        text: root.loaded ? root.shortName : Translation.tr("No preset loaded")
        elide: Text.ElideRight
        font.family: EasyEffectsStyle.fontTitle
        font.variableAxes: EasyEffectsStyle.axesDisplay
        font.pixelSize: root.loaded ? EasyEffectsStyle.textHero : EasyEffectsStyle.textBanner
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: EasyEffectsStyle.textBanner
        color: root.colContent
    }

    /// The effects of the chain, as many rows as `rows` allows.
    component HeroChips: Item {
        property int rows: 2
        visible: root.showEffects && root.chips.length > 0
        implicitHeight: Math.min(chipFlow.implicitHeight, EasyEffectsStyle.pillHeightLarge * rows + EasyEffectsStyle.gapSmall * (rows - 1) - 2 * (rows - 1))
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

    component HeroButtons: RowLayout {
        visible: root.showButtons
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
            visible: EasyEffects.running && !root.detached
            variant: root.lit ? "ghost" : "tonal"
            buttonHeight: EasyEffectsStyle.heroButtonHeight
            symbol: EasyEffects.bypassed ? "graphic_eq" : "do_not_disturb_on"
            label: EasyEffects.bypassed ? Translation.tr("Turn on") : Translation.tr("Bypass")
            iconOnly: root.strip
            onClicked: EasyEffects.toggleBypass()
        }

        // Another device: the way to hear its preset is to play through it.
        EasyEffectsButton {
            visible: root.detached
            variant: "tonal"
            buttonHeight: EasyEffectsStyle.heroButtonHeight
            symbol: root.pipeline === "input" ? "mic" : "speaker"
            label: Translation.tr("Use this device")
            iconOnly: root.strip
            onClicked: root.useDeviceRequested()
        }
    }

    // ── A column, beside the grid ───────────────────────────────────────
    ColumnLayout {
        anchors {
            fill: parent
            margins: EasyEffectsStyle.heroPadding
        }
        visible: !root.strip && !root.landscape
        spacing: 0

        StatePills {
            Layout.fillWidth: true
        }

        HeroArt {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: EasyEffectsStyle.heroShapeCore / 2
        }

        // Without art the rest still sinks to the bottom.
        Item {
            Layout.fillHeight: true
            visible: root.art === "none"
        }

        HeroWave {
            Layout.fillWidth: true
            Layout.topMargin: EasyEffectsStyle.gapSmall
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: EasyEffectsStyle.gapSmall
            visible: root.showCaption && root.caption.length > 0
            text: root.caption
            elide: Text.ElideRight
            font.pixelSize: EasyEffectsStyle.textNormal - 1
            font.weight: Font.Medium
            color: root.colSubContent
        }

        HeroName {
            Layout.fillWidth: true
        }

        HeroChips {
            Layout.fillWidth: true
            Layout.topMargin: EasyEffectsStyle.gap
            Layout.bottomMargin: EasyEffectsStyle.gap
            rows: 2
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: EasyEffectsStyle.gap
            visible: !root.showEffects || root.chips.length === 0
        }

        HeroButtons {
            Layout.fillWidth: true
        }
    }

    // ── Landscape: the art left, the rest in a column beside it ─────────
    RowLayout {
        anchors {
            fill: parent
            margins: EasyEffectsStyle.heroPadding
        }
        visible: !root.strip && root.landscape
        spacing: EasyEffectsStyle.gapHuge

        HeroArt {
            Layout.preferredWidth: Math.min(parent.height, parent.width * 0.38)
            Layout.fillHeight: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            spacing: 0

            StatePills {
                Layout.fillWidth: true
            }

            Item {
                Layout.fillHeight: true
            }

            HeroWave {
                Layout.fillWidth: true
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.showCaption && root.caption.length > 0
                text: root.caption
                elide: Text.ElideRight
                font.pixelSize: EasyEffectsStyle.textNormal - 1
                font.weight: Font.Medium
                color: root.colSubContent
            }

            HeroName {
                Layout.fillWidth: true
            }

            HeroChips {
                Layout.fillWidth: true
                Layout.topMargin: EasyEffectsStyle.gapSmall
                Layout.bottomMargin: EasyEffectsStyle.gapSmall
                rows: 1
            }

            HeroButtons {
                Layout.fillWidth: true
                Layout.topMargin: EasyEffectsStyle.gapSmall
            }
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
