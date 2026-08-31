pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The finished test: two dominant numbers, the pace over time, and the detail
 * that explains them. Flat by design — six separate cards would read as six
 * separate results.
 */
Item {
    id: root

    required property var engine
    property bool personalBest: false

    signal restart
    signal repeat

    readonly property var samples: root.engine?.samples ?? []
    readonly property var breakdown: root.engine?.characterBreakdown ?? ({ correct: 0, incorrect: 0, extra: 0, missed: 0 })
    readonly property bool hasTarget: Boolean(root.engine?.hasTarget)
    // A zero-based axis turns a steady 106 wpm into a solid block. The band is
    // fitted around the run instead, so the shape shows the pace, not the
    // distance from standing still.
    readonly property real chartCeiling: {
        let peak = 1;
        for (const sample of root.samples)
            peak = Math.max(peak, sample.raw ?? 0, sample.wpm ?? 0);
        return peak * 1.08;
    }
    readonly property real chartFloor: {
        let trough = root.chartCeiling;
        for (const sample of root.samples)
            trough = Math.min(trough, sample.wpm ?? 0);
        return Math.max(0, trough * 0.88);
    }

    function normalized(key) {
        const span = Math.max(1, root.chartCeiling - root.chartFloor);
        return Array.from(root.samples).map(sample =>
            Math.max(0, Math.min(1, ((sample[key] ?? 0) - root.chartFloor) / span)));
    }

    component StatChip: ColumnLayout {
        id: statChip
        property string label: ""
        property string value: ""
        spacing: 0

        StyledText {
            text: statChip.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: statChip.value
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurface
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.sizes.elevationMargin

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.sizes.elevationMargin * 3

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: Appearance.sizes.elevationMargin

                ColumnLayout {
                    spacing: -6

                    RowLayout {
                        spacing: 6

                        StyledText {
                            text: Translation.tr("wpm")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }

                        Rectangle {
                            visible: root.personalBest
                            implicitWidth: bestRow.implicitWidth + 14
                            implicitHeight: bestRow.implicitHeight + 6
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colTertiaryContainer

                            RowLayout {
                                id: bestRow
                                anchors.centerIn: parent
                                spacing: 3

                                MaterialSymbol {
                                    text: "trophy"
                                    iconSize: Appearance.font.pixelSize.small
                                    fill: 1
                                    color: Appearance.colors.colOnTertiaryContainer
                                }
                                StyledText {
                                    text: Translation.tr("personal best")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnTertiaryContainer
                                }
                            }
                        }
                    }

                    StyledText {
                        text: String(Math.round(root.engine?.wpm ?? 0))
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.hugeass * 3
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    visible: root.hasTarget
                    spacing: -4

                    StyledText {
                        text: Translation.tr("accuracy")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: String(Math.round(root.engine?.accuracy ?? 0)) + "%"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.hugeass * 1.7
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 132

                // A flat rule under the curve gives the shape a floor to be
                // read against, which an axis-less sparkline otherwise lacks.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.samples.length < 2
                    text: Translation.tr("Too short to graph")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                // Raw sits behind the net speed, so the gap between them reads
                // as the cost of the mistakes without needing a legend.
                Graph {
                    anchors.fill: parent
                    visible: root.samples.length >= 2
                    values: root.normalized("raw")
                    color: Appearance.colors.colSecondary
                    fillOpacity: 0.10
                }

                Graph {
                    anchors.fill: parent
                    visible: root.samples.length >= 2
                    values: root.normalized("wpm")
                    color: Appearance.colors.colPrimary
                    fillOpacity: 0.18
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin * 2.4

            StatChip {
                label: Translation.tr("raw")
                value: String(Math.round(root.engine?.rawWpm ?? 0))
            }
            StatChip {
                visible: root.hasTarget
                label: Translation.tr("consistency")
                value: String(Math.round(root.engine?.consistency() ?? 0)) + "%"
            }
            StatChip {
                label: Translation.tr("time")
                value: String(Math.round(root.engine?.elapsedSeconds ?? 0)) + "s"
            }
            StatChip {
                visible: root.hasTarget
                label: Translation.tr("characters")
                value: [root.breakdown.correct, root.breakdown.incorrect,
                    root.breakdown.extra, root.breakdown.missed].join("/")
            }
            StatChip {
                label: Translation.tr("test")
                value: root.engine?.mode === "time"
                    ? String(root.engine?.timeLimitSeconds) + "s"
                    : (root.engine?.mode === "words"
                        ? String(root.engine?.wordLimit) + " " + Translation.tr("words")
                        : (root.engine?.zenGuided ? Translation.tr("guided zen") : Translation.tr("zen")))
            }
            StatChip {
                label: Translation.tr("language")
                value: String(root.engine?.languagePack?.name ?? "—")
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                implicitWidth: repeatContent.implicitWidth + 30
                implicitHeight: 38
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.repeat()

                RowLayout {
                    id: repeatContent
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "replay"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        text: Translation.tr("Repeat")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            RippleButton {
                implicitWidth: restartContent.implicitWidth + 30
                implicitHeight: 38
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: root.restart()

                RowLayout {
                    id: restartContent
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "restart_alt"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        text: Translation.tr("Next test")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }
        }
    }
}
