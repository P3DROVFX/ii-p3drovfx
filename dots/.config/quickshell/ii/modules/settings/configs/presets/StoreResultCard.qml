import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * One repository/preset card in the Store, styled consistently with My Presets.
 */
Rectangle {
    id: card
    required property var entry

    readonly property string installedAs: card.entry.installedAs ?? ""
    readonly property bool installed: card.installedAs.length > 0
    readonly property bool hasUpdate: card.installed && PresetStore.updateFor(card.installedAs) !== null
    readonly property bool working: card.installed
        ? PresetStore.busyFor(card.installedAs) : PresetStore.busyFor(card.entry.repo)

    readonly property string repoSlug: (card.entry.repo ?? "").split(":")[0]
    readonly property string repoBranch: card.entry.defaultBranch ?? "main"
    readonly property string fallbackWallpaperUrl: (card.entry.wallpaperUrl && card.entry.wallpaperUrl.length > 0)
        ? card.entry.wallpaperUrl
        : (repoSlug.length > 0 ? `https://raw.githubusercontent.com/${repoSlug}/${repoBranch}/wallpaper.png` : "")

    property string effectiveImageSource: (card.entry.imageUrl && card.entry.imageUrl.length > 0)
        ? card.entry.imageUrl
        : (fallbackWallpaperUrl.length > 0 ? fallbackWallpaperUrl : `${Directories.assetsPath}/images/default_wallpaper.png`)

    height: width * 0.82
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSurfaceContainerLow
    border.width: 2
    border.color: cardButton.down ? Appearance.colors.colPrimaryActive
        : (cardButton.hovered ? Appearance.colors.colPrimary : "transparent")
    scale: cardButton.down ? 0.96 : 1

    signal activated

    Behavior on border.color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
    }
    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
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
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Preset Preview Image
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Layer 1 placeholder underneath image
            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "wallpaper"
                    iconSize: 32
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }

            StyledImage {
                id: previewImage
                anchors.fill: parent
                sourceSize: Qt.size(400, 400)
                source: card.effectiveImageSource
                fillMode: Image.PreserveAspectCrop
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: previewImage.width
                        height: previewImage.height
                        radius: Appearance.rounding.small
                    }
                }

                onStatusChanged: {
                    if (status === Image.Error) {
                        if (card.effectiveImageSource !== card.fallbackWallpaperUrl && card.fallbackWallpaperUrl.length > 0) {
                            card.effectiveImageSource = card.fallbackWallpaperUrl;
                        } else if (card.effectiveImageSource !== `${Directories.assetsPath}/images/default_wallpaper.png`) {
                            card.effectiveImageSource = `${Directories.assetsPath}/images/default_wallpaper.png`;
                        }
                    }
                }
            }

            // Top-left: Stars Badge
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 6
                implicitHeight: 22
                implicitWidth: starRow.implicitWidth + 12
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.35)
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    id: starRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: "star"
                        iconSize: 12
                        color: Appearance.colors.colTertiary
                    }

                    StyledText {
                        text: String(card.entry.stars ?? 0)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            // Top-right: Status Badge (Installed / Update / Working)
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                visible: card.installed || card.working
                implicitHeight: 22
                implicitWidth: statusRow.implicitWidth + 12
                radius: Appearance.rounding.full
                color: card.working
                    ? Appearance.colors.colSecondaryContainer
                    : (card.hasUpdate ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer)

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: card.working ? "sync" : (card.hasUpdate ? "arrow_circle_up" : "check")
                        iconSize: 12
                        color: card.working
                            ? Appearance.colors.colOnSecondaryContainer
                            : (card.hasUpdate ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer)
                    }

                    StyledText {
                        text: card.working
                            ? Translation.tr("Working…")
                            : (card.hasUpdate ? Translation.tr("Update") : Translation.tr("Installed"))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: card.working
                            ? Appearance.colors.colOnSecondaryContainer
                            : (card.hasUpdate ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer)
                    }
                }
            }

            // Bottom-left avatar overlay on image
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 6
                width: 24
                height: 24
                radius: width / 2
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                visible: (card.entry.avatarUrl ?? "").length > 0

                StyledImage {
                    id: authorAvatar
                    anchors.fill: parent
                    source: card.entry.avatarUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: authorAvatar.width
                            height: authorAvatar.height
                            radius: width / 2
                        }
                    }
                }
            }
        }

        // Bottom Bar: Title, Author & Action Button
        Item {
            Layout.fillWidth: true
            implicitHeight: 32

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: actionButton.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 6
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: card.entry.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("by %1").arg(card.entry.author ?? "")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            RippleButton {
                id: actionButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: card.installed ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimaryContainer
                colBackgroundHover: card.installed ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: card.installed ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryContainerActive
                onClicked: card.activated()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: card.hasUpdate ? "download" : (card.installed ? "visibility" : "arrow_forward")
                    iconSize: Appearance.font.pixelSize.smaller
                    color: card.installed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }
}
