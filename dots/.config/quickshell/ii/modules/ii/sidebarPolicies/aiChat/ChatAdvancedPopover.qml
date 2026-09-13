pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The knobs that used to be commands: temperature, how long an answer may run,
 * and how full the context is.
 *
 * Temperature is not hidden on models that ignore it. A control that vanishes
 * reads as a bug; one that says "managed by model" reads as an answer.
 */
Item {
    id: root

    readonly property var model: Ai.currentModelEntry
    readonly property bool samplingHonoured: root.model?.samplingParams ?? true
    readonly property int contextWindow: root.model?.contextWindow ?? 0
    readonly property int modelMaxOutput: root.model?.maxOutput ?? 0
    readonly property int usedTokens: Math.max(0, Ai.tokenCount.total)

    readonly property real defaultTemperature: 0.5

    implicitHeight: contentColumnLayout.implicitHeight

    function formatTokens(tokens: int): string {
        return String(tokens).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
    }

    /**
     * Section metrics. This used to be a popover a few pixels wider than its
     * text; as a canvas view it carries the same weight as the dashboard's
     * dialogs, so the labels are titles rather than captions.
     */
    readonly property real sectionSpacing: Appearance.rounding.large
    readonly property real sectionInset: Appearance.rounding.large

    component SectionLabel: RowLayout {
        id: sectionLabel

        property string label: ""
        property string valueText: ""

        Layout.fillWidth: true
        spacing: 12

        StyledText {
            Layout.fillWidth: true
            text: sectionLabel.label
            font.pixelSize: Appearance.font.pixelSize.larger
            font.bold: true
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            visible: sectionLabel.valueText.length > 0
            text: sectionLabel.valueText
            font.pixelSize: Appearance.font.pixelSize.larger
            font.bold: true
            font.family: Appearance.font.family.numbers
            color: Appearance.colors.colOnLayer1
        }
    }

    ColumnLayout {
        id: contentColumnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: root.sectionSpacing

        SectionLabel {
            label: Translation.tr("Temperature")
            valueText: root.samplingHonoured ? Ai.temperature.toFixed(2) : ""
        }

        Loader {
            Layout.fillWidth: true
            active: root.samplingHonoured
            visible: active

            sourceComponent: RowLayout {
                spacing: 12

                StyledSlider {
                    id: temperatureSlider
                    Layout.fillWidth: true
                    from: 0
                    to: Ai.maxTemperature
                    stepSize: 0.05
                    value: Ai.temperature
                    usePercentTooltip: false
                    onMoved: Ai.setTemperature(Math.round(value * 100) / 100, false)
                }

                RippleButton {
                    implicitWidth: Math.round(Appearance.font.pixelSize.huge * 1.8)
                    implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.8)
                    buttonRadius: height / 2
                    enabled: Math.abs(Ai.temperature - root.defaultTemperature) > 0.001
                    opacity: enabled ? 1 : 0.4
                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Ai.setTemperature(root.defaultTemperature, false)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "restart_alt"
                        fill: 1
                        iconSize: 24
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledToolTip {
                        text: Translation.tr("Back to %1").arg(root.defaultTemperature)
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: !root.samplingHonoured
            visible: active

            sourceComponent: RowLayout {
                spacing: 8

                MaterialSymbol {
                    text: "auto_awesome"
                    fill: 1
                    iconSize: 24
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Managed by model — %1 picks its own sampling and rejects a temperature.").arg(root.model?.title ?? "")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }
        }

        SectionLabel {
            Layout.topMargin: root.sectionSpacing
            label: Translation.tr("Longest answer")
            valueText: Config.options.ai.maxOutputTokens > 0 ? root.formatTokens(Config.options.ai.maxOutputTokens) : Translation.tr("Model default")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledSlider {
                id: outputSlider
                Layout.fillWidth: true
                from: 0
                to: root.modelMaxOutput > 0 ? root.modelMaxOutput : 32768
                stepSize: 1024
                snapMode: Slider.SnapAlways
                value: Math.min(Config.options.ai.maxOutputTokens, to)
                usePercentTooltip: false
                onMoved: Config.options.ai.maxOutputTokens = Math.round(value)
            }

            RippleButton {
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: height / 2
                enabled: Config.options.ai.maxOutputTokens !== 0
                opacity: enabled ? 1 : 0.4
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: Config.options.ai.maxOutputTokens = 0

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "restart_alt"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: Translation.tr("Let the model decide")
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.modelMaxOutput > 0
            text: Translation.tr("%1 can write up to %2 tokens in one answer.").arg(root.model?.title ?? "").arg(root.formatTokens(root.modelMaxOutput))
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }

        SectionLabel {
            Layout.topMargin: 10
            label: Translation.tr("Context used")
            valueText: root.contextWindow > 0 ? Translation.tr("%1%").arg(Math.min(100, Math.round(root.usedTokens / root.contextWindow * 100))) : ""
        }

        StyledProgressBar {
            Layout.fillWidth: true
            visible: root.contextWindow > 0
            value: root.contextWindow > 0 ? Math.min(1, root.usedTokens / root.contextWindow) : 0
        }

        StyledText {
            Layout.fillWidth: true
            text: {
                if (root.contextWindow <= 0)
                    return Translation.tr("%1 tokens so far. This model does not state a context window.").arg(root.formatTokens(root.usedTokens));
                return Translation.tr("%1 of %2 tokens").arg(root.formatTokens(root.usedTokens)).arg(root.formatTokens(root.contextWindow));
            }
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
}
