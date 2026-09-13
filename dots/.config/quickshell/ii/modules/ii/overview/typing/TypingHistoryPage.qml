pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Stored scores: the personal best per test setup on top, then the log.
 * Reading it never touches the engine, so it can be opened mid-session.
 */
Item {
    id: root

    readonly property var results: TypingHistory.results
    readonly property var bests: TypingHistory.personalBests
    readonly property real averageWpm: {
        if (root.results.length === 0)
            return 0;
        return Array.from(root.results).reduce((total, entry) => total + (entry.wpm ?? 0), 0) / root.results.length;
    }

    function formatWhen(timestamp) {
        const date = new Date(Number(timestamp ?? 0));
        return Qt.formatDateTime(date, "dd MMM HH:mm");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.sizes.elevationMargin

        RowLayout {
            Layout.fillWidth: true
            visible: root.results.length > 0
            spacing: Appearance.sizes.elevationMargin * 3

            Repeater {
                model: [
                    { label: Translation.tr("tests"), value: String(root.results.length) },
                    { label: Translation.tr("average wpm"), value: String(Math.round(root.averageWpm)) },
                    { label: Translation.tr("best wpm"), value: String(Math.round(Math.max(0,
                        ...Array.from(root.bests).map(best => best.wpm ?? 0), 0))) }
                ]

                delegate: ColumnLayout {
                    id: summaryStat
                    required property var modelData
                    spacing: -2

                    StyledText {
                        text: summaryStat.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: summaryStat.modelData.value
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.results.length === 0
            spacing: 4

            Item { Layout.fillHeight: true }

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "history"
                iconSize: Appearance.font.pixelSize.hugeass * 2
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Config.options.search.typingTest.history.enable
                    ? Translation.tr("No results yet — finish a test to fill this in")
                    : Translation.tr("Score history is switched off in the settings page")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Item { Layout.fillHeight: true }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.results.length > 0

            // The fade has to be a sibling of what it fades: it anchors to
            // its target.
            TypingStageFade {
                target: historyList
                fadeSize: 32
            }

            StyledListView {
                id: historyList
                anchors.fill: parent
                clip: true
                spacing: 3
                model: root.results

                delegate: Rectangle {
                    id: historyRow
                    required property var modelData
                    readonly property bool isBest: Array.from(root.bests).some(best =>
                        best.key === TypingHistory.keyOf(historyRow.modelData) && best.timestamp === historyRow.modelData.timestamp)

                    width: historyList.width
                    implicitHeight: 40
                    radius: Appearance.rounding.small
                    color: isBest ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSurfaceContainerLow

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: Appearance.sizes.elevationMargin

                        MaterialSymbol {
                            visible: historyRow.isBest
                            text: "trophy"
                            iconSize: Appearance.font.pixelSize.normal
                            fill: 1
                            color: Appearance.colors.colOnTertiaryContainer
                        }

                        StyledText {
                            Layout.preferredWidth: 64
                            text: String(Math.round(historyRow.modelData.wpm ?? 0)) + " " + Translation.tr("wpm")
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: historyRow.isBest ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.preferredWidth: 54
                            text: String(Math.round(historyRow.modelData.accuracy ?? 0)) + "%"
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            Layout.preferredWidth: 70
                            text: Translation.tr("raw %1").arg(String(Math.round(historyRow.modelData.raw ?? 0)))
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: [TypingHistory.describe(historyRow.modelData),
                                historyRow.modelData.language,
                                historyRow.modelData.punctuation ? Translation.tr("punctuation") : "",
                                historyRow.modelData.numbers ? Translation.tr("numbers") : ""]
                                .filter(part => String(part).length > 0).join(" · ")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: root.formatWhen(historyRow.modelData.timestamp)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
