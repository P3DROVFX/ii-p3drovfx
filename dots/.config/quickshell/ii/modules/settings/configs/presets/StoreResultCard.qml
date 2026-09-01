import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * One repository as the search returned it.
 *
 * A search result carries no pictures, only what GitHub knows about the
 * repository, so the card stays deliberately textual and the screenshots wait
 * for the detail sheet where the manifest has actually been read.
 */
Rectangle {
    id: card
    required property var entry

    readonly property string installedAs: card.entry.installedAs ?? ""
    readonly property bool installed: card.installedAs.length > 0
    readonly property bool hasUpdate: card.installed && PresetStore.updateFor(card.installedAs) !== null
    readonly property bool working: card.installed
        ? PresetStore.busyFor(card.installedAs) : PresetStore.busyFor(card.entry.repo)

    height: cardColumn.implicitHeight + 24
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSurfaceContainerLow
    border.width: 2
    border.color: cardButton.down ? Appearance.colors.colPrimaryActive
        : (cardButton.hovered ? Appearance.colors.colPrimary : "transparent")

    signal activated

    Behavior on border.color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
    }

    RippleButton {
        id: cardButton
        anchors.fill: parent
        buttonRadius: Appearance.rounding.normal
        colBackground: "transparent"
        colBackgroundHover: "transparent"
        colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
        onClicked: card.activated()
    }

    ColumnLayout {
        id: cardColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                StyledImage {
                    id: avatar
                    anchors.fill: parent
                    source: card.entry.avatarUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: avatar.width
                            height: avatar.height
                            radius: width / 2
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: card.entry.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("by %1").arg(card.entry.author ?? "")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            text: (card.entry.description ?? "").length > 0
                ? card.entry.description : Translation.tr("No description.")
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "star"
                iconSize: 14
                color: Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                text: String(card.entry.stars ?? 0)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: card.installed
                implicitWidth: stateRow.implicitWidth + 16
                implicitHeight: 24
                radius: Appearance.rounding.full
                color: card.hasUpdate ? Appearance.colors.colTertiaryContainer
                    : Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: stateRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: card.hasUpdate ? "arrow_circle_up" : "check"
                        iconSize: 14
                        color: card.hasUpdate ? Appearance.colors.colOnTertiaryContainer
                            : Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        text: card.hasUpdate ? Translation.tr("Update") : Translation.tr("Installed")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: card.hasUpdate ? Appearance.colors.colOnTertiaryContainer
                            : Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            StyledText {
                visible: card.working
                text: Translation.tr("Working…")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
