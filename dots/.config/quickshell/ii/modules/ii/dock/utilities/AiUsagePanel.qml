import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Every limit of the provider the widget follows (session, week, per-model
 * pools, credit balance) with its reset, a row of the other providers to
 * switch to, refresh and the AI plan usage settings.
 */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var cfg: Config.options.dock.utilities.aiUsage
    readonly property var items: Array.from(panel.tile?.provider?.items ?? [])
    readonly property var providers: AiPlanUsage.displayProviders ?? []
    readonly property date minute: DateTime.clock.date

    spacing: 4

    // ── Providers ───────────────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        visible: panel.providers.length > 1
        spacing: 4
        Repeater {
            model: panel.providers
            delegate: RippleButton {
                id: chip
                required property var modelData
                readonly property string targetId: String(chip.modelData.targetId ?? chip.modelData.id ?? "")
                readonly property bool chosen: (panel.tile?.targetId ?? "") === chip.targetId
                implicitHeight: 34
                implicitWidth: chipLabel.implicitWidth + 28
                buttonRadius: chip.chosen ? ClockStyle.radiusSmall : height / 2
                buttonRadiusPressed: ClockStyle.radiusSmall
                colBackground: chip.chosen ? ClockStyle.colTertiary : ClockStyle.colField
                colBackgroundHover: chip.chosen ? ClockStyle.colTertiary : ClockStyle.colFieldHover
                colRipple: ClockStyle.colSurfaceActive
                opacity: chip.modelData.available === false ? 0.5 : 1
                onClicked: panel.cfg.provider = chip.targetId
                contentItem: StyledText {
                    id: chipLabel
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: String(chip.modelData.name ?? AiPlanUsage.providerName(chip.targetId))
                    color: chip.chosen ? ClockStyle.colOnTertiary : ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // ── Limits ──────────────────────────────────────────────────────────
    Repeater {
        model: panel.items
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool credits: row.modelData.metricKind === "credits"
            readonly property real used: Math.max(0, Math.min(100, Number(row.modelData.usedPercent) || 0))
            readonly property bool low: AiPlanUsage.isLow(row.modelData)
            Layout.fillWidth: true
            implicitHeight: row.credits ? 64 : 76
            radius: row.index === 0 ? ClockStyle.radiusNormal : ClockStyle.radiusSmall
            color: ClockStyle.colField

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: String(row.modelData.groupName ?? "").length > 0
                                ? row.modelData.groupName + " · " + String(row.modelData.windowLabel ?? "")
                                : String(row.modelData.windowLabel ?? "")
                            color: ClockStyle.colOnSurface
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: !row.credits
                            text: { panel.minute; return AiPlanUsage.formatReset(row.modelData.resetsAt); }
                            color: ClockStyle.colOnSurfaceVariant
                            opacity: 0.8
                            font.pixelSize: ClockStyle.textSmall
                            elide: Text.ElideRight
                        }
                    }
                    StyledText {
                        text: row.credits ? AiPlanUsage.creditAmountText(row.modelData, false) : Math.round(row.used) + "%"
                        color: row.low ? ClockStyle.colError : ClockStyle.colOnSurface
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: 28
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: !row.credits
                    implicitHeight: 8
                    radius: 4
                    color: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.1)
                    Rectangle {
                        height: parent.height
                        width: Math.max(height, parent.width * row.used / 100)
                        radius: height / 2
                        color: row.low ? ClockStyle.colError : ClockStyle.colTertiary
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.items.length === 0
        implicitHeight: 72
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        StyledText {
            anchors.fill: parent
            anchors.margins: 14
            verticalAlignment: Text.AlignVCenter
            text: AiPlanUsage.errorMessage || Translation.tr("No data for %1 yet. Sign in to it, or enable it in AI plan usage.").arg(panel.tile?.providerName ?? "")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
            wrapMode: Text.WordWrap
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6
        ClockButton {
            Layout.fillWidth: true
            symbol: "refresh"
            label: AiPlanUsage.refreshing ? Translation.tr("Checking…") : Translation.tr("Refresh")
            enabled: !AiPlanUsage.refreshing
            onClicked: AiPlanUsage.refresh(true)
        }
        ClockButton {
            Layout.fillWidth: true
            symbol: "settings"
            label: Translation.tr("Settings")
            onClicked: {
                panel.host?.closePanel();
                GlobalStates.openSettingsPage("dock", "widgets/DockUtilitiesConfig.qml");
            }
        }
    }
}
