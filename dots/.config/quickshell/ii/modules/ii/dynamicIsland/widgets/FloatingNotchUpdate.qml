pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A shell update on the Dynamic Island:
 * - Contracted: the announcement, shown once when an update turns up.
 * - Expanded: one line saying how far behind, and the button that fixes it.
 *
 * Deliberately no commit list or changelog: Settings > About and the bar indicator's
 * popup have those, and this card is what opens from a glance the size of a coin.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false
    /** The header icon, handed over from the bubble's glance (see AuxiliaryBubble's hero). */
    readonly property var heroItems: root.isExpanded ? [headerIcon] : []
    /** The card is one row and one button; see AuxiliaryBubble.facePreferredHeight. */
    readonly property real preferredExpandedHeight: 108

    // 0 is "unknown" (offline, rate-limited, not a GitHub remote), not "level".
    readonly property int behind: ShellUpdates.commitsBehind
    readonly property string target: "%1 · %2".arg(ShellUpdates.forkLabel(ShellUpdates.activeFork))
        .arg(ShellUpdates.activeBranch)
    readonly property string headline: root.behind > 0
        ? (root.behind === 1 ? Translation.tr("1 new commit") : Translation.tr("%1 new commits").arg(root.behind))
        : Translation.tr("Update available")

    // ── Contracted: the announcement ─────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 10
        visible: !root.isExpanded

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "deployed_code_update"
            iconSize: Math.max(14, Math.min(20, root.height - 12))
            color: Appearance.colors.colPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2

            StyledText {
                Layout.fillWidth: true
                text: root.headline
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                text: root.target
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ── Expanded: the card ───────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        visible: root.isExpanded

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialSymbol {
                id: headerIcon
                Layout.alignment: Qt.AlignVCenter
                text: "deployed_code_update"
                iconSize: 26
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.headline
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.target
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colBackgroundActive: Appearance.colors.colPrimaryActive
            colRipple: Appearance.colors.colPrimaryActive
            // The script asks in its terminal before it touches anything.
            onClicked: ShellUpdates.launchUpdate()

            contentItem: Item {
                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "download"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Update now")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }
}
