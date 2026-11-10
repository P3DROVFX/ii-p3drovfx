import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * "Translate with AI": locale + model, a progress bar while AiTranslation runs
 * and a banner with the outcome. The run lives in the AiTranslation service,
 * so closing Settings does not stop it.
 */
Rectangle {
    id: root

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    implicitHeight: content.implicitHeight + 40

    readonly property bool running: AiTranslation.state === "running"
    readonly property string runState: AiTranslation.state
    readonly property var modelInfo: AiTranslation.modelInfo(Config.options.language.aiModel)
    readonly property string localeText: localeInput.text.trim()

    function startRun() {
        AiTranslation.start(root.localeText, Config.options.language.aiModel);
    }

    function providerHint(info) {
        return info.provider === "claude"
            ? Translation.tr("Uses your Claude plan through the claude CLI, no API key")
            : Translation.tr("Uses your Gemini API key, billed per token");
    }

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        spacing: 16

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                text: "auto_awesome"
                iconSize: 24
                padding: 12
                shape: root.running ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie7Sided
                color: Appearance.colors.colSecondaryContainer
                colSymbol: Appearance.colors.colOnSecondaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: Translation.tr("Translate with AI")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.running
                        ? Translation.tr("Translating to %1 with %2").arg(AiTranslation.locale).arg(AiTranslation.modelInfo(AiTranslation.model).title)
                        : Translation.tr("Creates or completes a locale file · %1").arg(root.modelInfo.title)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // locale + action
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            FilledField {
                id: localeInput
                Layout.fillWidth: true
                enabled: !root.running
                symbol: "language"
                placeholder: Translation.tr("Locale code, e.g. fr_FR")
                colField: Appearance.colors.colSurfaceContainerHighest
                colFieldHover: Appearance.colors.colSurfaceContainerHighestHover
                colContent: Appearance.colors.colOnSurface
                text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                onAccepted: if (root.localeText.length > 0 && !root.running) root.startRun()
            }

            RippleButton {
                id: actionButton
                implicitHeight: 56
                implicitWidth: actionRow.implicitWidth + 40
                buttonRadius: Appearance.rounding.scale === 0 ? 0 : height / 2
                enabled: root.running || root.localeText.length > 0
                colBackground: root.running ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: root.running ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover
                colRipple: root.running ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive
                onClicked: root.running ? AiTranslation.cancel() : root.startRun()

                contentItem: Item {
                    RowLayout {
                        id: actionRow
                        anchors.centerIn: parent
                        spacing: 8
                        readonly property color colContent: root.running ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                        MaterialSymbol {
                            text: root.running ? "stop" : "auto_awesome"
                            iconSize: Appearance.font.pixelSize.larger
                            color: actionRow.colContent
                        }
                        StyledText {
                            text: root.running ? Translation.tr("Cancel") : Translation.tr("Generate")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: actionRow.colContent
                        }
                    }
                }
            }
        }

        // model
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                Layout.leftMargin: 4
                text: Translation.tr("Model")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            ConfigSelectionArray {
                enabled: !root.running
                currentValue: Config.options.language.aiModel
                onSelected: newValue => Config.options.language.aiModel = newValue
                options: AiTranslation.models.map(m => ({
                    "displayName": m.title,
                    "value": m.value,
                    "icon": m.provider === "claude" ? "workspace_premium" : "key",
                    "tooltip": root.providerHint(m)
                }))
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: root.providerHint(root.modelInfo)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }

        // progress
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.running
            spacing: 6

            StyledProgressBar {
                Layout.fillWidth: true
                valueBarHeight: 6
                value: AiTranslation.progress
                wavy: root.running
                animateWave: root.running
            }
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: AiTranslation.keysTotal > 0
                        ? Translation.tr("%1 of %2 strings").arg(AiTranslation.keysDone).arg(AiTranslation.keysTotal)
                        : Translation.tr("Preparing the source strings…")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    visible: AiTranslation.batches > 0
                    text: Translation.tr("Batch %1/%2").arg(Math.min(AiTranslation.batch + 1, AiTranslation.batches)).arg(AiTranslation.batches)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // outcome banner
        Rectangle {
            id: banner
            Layout.fillWidth: true
            visible: ["success", "partial", "error"].includes(root.runState)
            implicitHeight: bannerRow.implicitHeight + 28
            radius: Appearance.rounding.large

            readonly property var look: ({
                "success": { "bg": Appearance.colors.colTertiaryContainer, "fg": Appearance.colors.colOnTertiaryContainer, "icon": "check_circle" },
                "partial": { "bg": Appearance.colors.colSecondaryContainer, "fg": Appearance.colors.colOnSecondaryContainer, "icon": "warning" },
                "error": { "bg": Appearance.colors.colErrorContainer, "fg": Appearance.colors.colOnErrorContainer, "icon": "error" }
            })[root.runState] ?? { "bg": "transparent", "fg": Appearance.colors.colOnLayer1, "icon": "info" }
            color: look.bg

            RowLayout {
                id: bannerRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 16
                    rightMargin: 10
                }
                spacing: 12

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: banner.look.icon
                    iconSize: Appearance.font.pixelSize.huge
                    fill: 1
                    color: banner.look.fg
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.runState === "success" ? Translation.tr("Translation ready")
                            : root.runState === "partial" ? Translation.tr("Translation incomplete")
                            : Translation.tr("Translation failed")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: banner.look.fg
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.runState === "success"
                            ? (AiTranslation.keysTotal === 0
                                ? Translation.tr("%1 already had every string translated.").arg(AiTranslation.locale)
                                : Translation.tr("%1 strings translated to %2. Pick it above to use it.").arg(AiTranslation.keysTranslated).arg(AiTranslation.locale))
                            : root.runState === "partial"
                                ? Translation.tr("%1 strings are still missing. Generate again to retry only those.").arg(AiTranslation.keysFailed)
                                : AiTranslation.message
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: banner.look.fg
                        wrapMode: Text.Wrap
                    }
                }
                RippleButton {
                    visible: root.runState !== "success"
                    implicitHeight: 36
                    implicitWidth: retryText.implicitWidth + 28
                    buttonRadius: Appearance.rounding.scale === 0 ? 0 : height / 2
                    colBackground: ColorUtils.transparentize(banner.look.fg, 1)
                    colBackgroundHover: ColorUtils.transparentize(banner.look.fg, 0.88)
                    colRipple: ColorUtils.transparentize(banner.look.fg, 0.8)
                    onClicked: AiTranslation.start(AiTranslation.locale, AiTranslation.model)
                    contentItem: StyledText {
                        id: retryText
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Retry")
                        font.weight: Font.DemiBold
                        color: banner.look.fg
                    }
                }
                RippleButton {
                    implicitHeight: 36
                    implicitWidth: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(banner.look.fg, 1)
                    colBackgroundHover: ColorUtils.transparentize(banner.look.fg, 0.88)
                    colRipple: ColorUtils.transparentize(banner.look.fg, 0.8)
                    onClicked: AiTranslation.dismiss()
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: banner.look.fg
                    }

                    StyledToolTip {
                        text: Translation.tr("Dismiss")
                    }
                }
            }
        }
    }
}
