pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/bar/widgets/indicators"

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    readonly property string style: Config.options.bar.styles.recordIndicator ?? "default"
    readonly property bool styled: root.style === "expressive" || root.style === "neural"

    // The preview runs its own clock so the rolling digits can actually be seen
    // rolling. It is the only way to judge the animation without starting a
    // real capture, and it stops the moment the page is not on screen.
    property int previewSeconds: 84
    readonly property string previewTime: {
        const m = Math.floor(root.previewSeconds / 60);
        const s = root.previewSeconds % 60;
        return String(m).padStart(2, '0') + ":" + String(s).padStart(2, '0');
    }

    Timer {
        running: root.visible
        interval: 1000
        repeat: true
        onTriggered: root.previewSeconds = (root.previewSeconds + 1) % 3600
    }

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Record indicator")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "preview"
        title: Translation.tr("Live preview")

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                // The default design owns no surface, so the honest preview is
                // the one that puts the bar's own chip behind it.
                Rectangle {
                    anchors.centerIn: parent
                    visible: root.style === "default"
                    implicitWidth: horizontalPreview.implicitWidth + 10
                    implicitHeight: Appearance.sizes.baseBarHeight - 8
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                }

                Loader {
                    id: horizontalPreview
                    anchors.centerIn: parent
                    sourceComponent: {
                        if (root.style === "neural")
                            return neuralHorizontalPreview;
                        if (root.style === "expressive")
                            return expressiveHorizontalPreview;
                        return defaultHorizontalPreview;
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: Appearance.sizes.verticalBarWidth + 28
                Layout.fillHeight: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Rectangle {
                    anchors.centerIn: parent
                    visible: root.style === "default"
                    implicitWidth: Appearance.sizes.verticalBarWidth - 8
                    implicitHeight: verticalPreview.implicitHeight + 10
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                }

                Loader {
                    id: verticalPreview
                    anchors.centerIn: parent
                    sourceComponent: {
                        if (root.style === "neural")
                            return neuralVerticalPreview;
                        if (root.style === "expressive")
                            return expressiveVerticalPreview;
                        return defaultVerticalPreview;
                    }
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "swap_horiz"
            text: Translation.tr("Left is the horizontal bar, right is the vertical one. Every variant is drawn for both — the vertical form re-stacks the clock rather than rotating it.")
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Design")

        ContentSubsection {
            title: Translation.tr("Visual style")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.recordIndicator
                onSelected: newValue => Config.options.bar.styles.recordIndicator = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Neural"), icon: "neurology", value: "neural" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "expressive"
            title: Translation.tr("Expressive variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.indicators.record.expressiveVariant
                onSelected: newValue => Config.options.bar.indicators.record.expressiveVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Capsule"), icon: "pill", value: "capsule" },
                    { displayName: Translation.tr("Badge"), icon: "workspace_premium", value: "badge" },
                    { displayName: Translation.tr("Ribbon"), icon: "view_week", value: "ribbon" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "neural"
            title: Translation.tr("Neural variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.indicators.record.neuralVariant
                onSelected: newValue => Config.options.bar.indicators.record.neuralVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Duo"), icon: "join_left", value: "duo" },
                    { displayName: Translation.tr("Slab"), icon: "rectangle", value: "slab" },
                    { displayName: Translation.tr("Meter"), icon: "straighten", value: "meter" }
                ]
            }
        }

        ContentSubsection {
            visible: root.styled
            title: Translation.tr("Colour treatment")

            ConfigSelectionArray {
                currentValue: Config.options.bar.indicators.record.colorMode
                onSelected: newValue => Config.options.bar.indicators.record.colorMode = String(newValue)
                options: [
                    { displayName: Translation.tr("Alert"), icon: "emergency_recording", value: "alert" },
                    { displayName: Translation.tr("Tonal"), icon: "colors", value: "tonal" },
                    { displayName: Translation.tr("Vibrant"), icon: "auto_awesome", value: "vibrant" },
                    { displayName: Translation.tr("Neutral"), icon: "contrast", value: "neutral" }
                ]
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.style === "default"
            materialIcon: "info"
            text: Translation.tr("The default design has no variants on purpose: it borrows the bar's own chip and type, so it always matches whatever the rest of your widgets are doing.")
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Content")

        ConfigSwitch {
            buttonIcon: "check_indeterminate_small"
            text: Translation.tr("Minimal mode")
            checked: Config.options.bar.indicators.record.minimal
            onCheckedChanged: Config.options.bar.indicators.record.minimal = checked
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Minimal keeps the mark and drops the elapsed time, in every design. The full clock stays one hover away, in the popup.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        ConfigSwitch {
            // Only the variants that actually carry the word: `badge`, `slab`
            // and `duo` are shapes and numerals, by design.
            visible: root.style === "expressive"
                ? Config.options.bar.indicators.record.expressiveVariant !== "badge"
                : (root.style === "neural"
                    && Config.options.bar.indicators.record.neuralVariant === "meter")
            buttonIcon: "text_fields"
            text: Translation.tr("Show the REC wordmark")
            checked: Config.options.bar.indicators.record.showLabel
            onCheckedChanged: Config.options.bar.indicators.record.showLabel = checked
        }

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Roll each digit as it changes")
            checked: Config.options.bar.indicators.record.animateDigits
            onCheckedChanged: Config.options.bar.indicators.record.animateDigits = checked
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The clock is the only thing that moves: the digit that just changed slides in, and everything else stands still. A paused recording is therefore completely motionless.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        icon: "videocam"
        title: Translation.tr("Right now")

        StyledText {
            Layout.fillWidth: true
            text: {
                if (Persistent.states.screenRecord?.loading)
                    return Translation.tr("Waiting for the screen sharing portal.");
                if (!Persistent.states.screenRecord?.active)
                    return Translation.tr("Nothing is being recorded, so the widget is collapsed out of the bar entirely.");
                if (Persistent.states.screenRecord?.paused)
                    return Translation.tr("Recording paused at %1.").arg(root.liveTime);
                return Translation.tr("Recording for %1.").arg(root.liveTime);
            }
            color: Appearance.colors.colOnLayer1
            opacity: 0.85
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Recording quality, audio sources and the save location live in Screen Recording.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
    }

    readonly property string liveTime: {
        const total = Persistent.states.screenRecord?.seconds ?? 0;
        const m = Math.floor(total / 60);
        const s = total % 60;
        return String(m).padStart(2, '0') + ":" + String(s).padStart(2, '0');
    }

    // ── Previews ─────────────────────────────────────────────────────────────
    Component {
        id: defaultHorizontalPreview
        DefaultRecordIndicator {
            vertical: false
            live: true
            minimal: Config.options.bar.indicators.record.minimal
            animateDigits: Config.options.bar.indicators.record.animateDigits
            timeText: root.previewTime
            stateIcon: "videocam"
            colContent: Appearance.colors.colOnPrimary
        }
    }

    Component {
        id: defaultVerticalPreview
        DefaultRecordIndicator {
            vertical: true
            live: true
            minimal: Config.options.bar.indicators.record.minimal
            animateDigits: Config.options.bar.indicators.record.animateDigits
            timeText: root.previewTime
            stateIcon: "videocam"
            colContent: Appearance.colors.colOnPrimary
        }
    }

    Component {
        id: expressiveHorizontalPreview
        ExpressiveRecordIndicator {
            vertical: false
            thickness: Appearance.sizes.baseBarHeight - 8
            live: true
            minimal: Config.options.bar.indicators.record.minimal
            showLabel: Config.options.bar.indicators.record.showLabel
            animateDigits: Config.options.bar.indicators.record.animateDigits
            timeText: root.previewTime
            label: Translation.tr("REC")
            stateIcon: "videocam"
        }
    }

    Component {
        id: expressiveVerticalPreview
        ExpressiveRecordIndicator {
            vertical: true
            thickness: Appearance.sizes.verticalBarWidth - 8
            live: true
            minimal: Config.options.bar.indicators.record.minimal
            showLabel: Config.options.bar.indicators.record.showLabel
            animateDigits: Config.options.bar.indicators.record.animateDigits
            timeText: root.previewTime
            label: Translation.tr("REC")
            stateIcon: "videocam"
        }
    }

    Component {
        id: neuralHorizontalPreview
        NeuralRecordIndicator {
            vertical: false
            thickness: Appearance.sizes.baseBarHeight - 8
            live: true
            minimal: Config.options.bar.indicators.record.minimal
            showLabel: Config.options.bar.indicators.record.showLabel
            animateDigits: Config.options.bar.indicators.record.animateDigits
            timeText: root.previewTime
            label: Translation.tr("REC")
            stateIcon: "videocam"
            minuteProgress: (root.previewSeconds % 60) / 60
        }
    }

    Component {
        id: neuralVerticalPreview
        NeuralRecordIndicator {
            vertical: true
            thickness: Appearance.sizes.verticalBarWidth - 8
            live: true
            minimal: Config.options.bar.indicators.record.minimal
            showLabel: Config.options.bar.indicators.record.showLabel
            animateDigits: Config.options.bar.indicators.record.animateDigits
            timeText: root.previewTime
            label: Translation.tr("REC")
            stateIcon: "videocam"
            minuteProgress: (root.previewSeconds % 60) / 60
        }
    }
}
