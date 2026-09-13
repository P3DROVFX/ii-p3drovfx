import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

MouseArea {
    id: root
    required property var fileModelData
    property bool isDirectory: fileModelData.fileIsDir

    property bool shouldLoad: true
    property bool isApplied: false
    property string appliedLabel: ""

    property bool isVideo: {
        const path = fileModelData.fileName.toLowerCase();
        return path.endsWith('.mp4') || path.endsWith('.webm') || path.endsWith('.mkv') || path.endsWith('.avi') || path.endsWith('.mov') || path.endsWith('.m4v') || path.endsWith('.ogv');
    }
    property bool isApi: fileModelData.isApi || false
    property bool useThumbnail: (Images.isValidImageByName(fileModelData.fileName) || root.isVideo) && !root.isApi
    readonly property bool thumbnailLoadFailed: root.shouldLoad && root.useThumbnail && !root.isApi
        && thumbnailImageLoader.active
        && thumbnailImageLoader.item !== null
        && !thumbnailImageLoader.item.thumbnailGenerationRunning
        && thumbnailImageLoader.item.status === Image.Error
    property bool showLoadingIndicator: false

    property alias colBackground: background.color
    property alias colText: wallpaperItemName.color
    property alias radius: background.radius
    property alias margins: background.anchors.margins
    property alias padding: wallpaperItemColumnLayout.anchors.margins
    margins: Appearance.sizes.wallpaperSelectorItemMargins
    padding: Appearance.sizes.wallpaperSelectorItemPadding

    signal activated
    signal searchSimilarRequested(string filePath, string wallhavenId)
    signal moreOptionsRequested(var modelData)
    signal thumbnailLoadStateChanged

    onThumbnailLoadFailedChanged: root.thumbnailLoadStateChanged()

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    scale: containsMouse ? 1.04 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutBack
            easing.overshoot: 1.4
        }
    }

    onClicked: (event) => {
        if (event.button === Qt.LeftButton) {
            root.activated()
        } else if (event.button === Qt.RightButton) {
            root.moreOptionsRequested(fileModelData)
        }
    }
    

    function getWallhavenId(url) {
        const urlStr = url.toString();
        const fileName = urlStr.split('/').pop();
        const fileNameWithoutExt = fileName.split('.')[0];
        const match = fileNameWithoutExt.match(/^wallhaven-([a-zA-Z0-9]{6})$/i);
        return match ? match[1] : null;
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Appearance.rounding.normal
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            id: wallpaperItemColumnLayout
            anchors.fill: parent
            spacing: 4

            Item {
                id: wallpaperItemImageContainer
                Layout.fillHeight: true
                Layout.fillWidth: true

                Loader {
                    id: thumbnailShadowLoader
                    active: thumbnailImageLoader.active && thumbnailImageLoader.item && thumbnailImageLoader.item.status === Image.Ready && root.shouldLoad
                    anchors.fill: thumbnailImageLoader
                    sourceComponent: StyledRectangularShadow {
                        target: thumbnailImageLoader
                        anchors.fill: undefined
                        radius: Appearance.rounding.small
                    }
                }

                Loader {
                    id: thumbnailImageLoader
                    anchors.fill: parent
                    active: root.useThumbnail && root.shouldLoad
                    sourceComponent: ThumbnailImage {
                        id: thumbnailImage
                        generateThumbnail: root.isVideo
                        sourcePath: String(fileModelData.filePath || "")
                        thumbnailService: Wallpapers

                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        clip: true

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: wallpaperItemImageContainer.width
                                height: wallpaperItemImageContainer.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }
                }

                Loader {
                    id: videoThumbnailFallbackLoader
                    anchors.fill: thumbnailImageLoader
                    active: root.isVideo && root.shouldLoad && thumbnailImageLoader.active && thumbnailImageLoader.item && thumbnailImageLoader.item.status === Image.Error
                    sourceComponent: StyledImage {
                        source: `${Directories.assetsPath}/images/default_wallpaper.png`
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: videoThumbnailFallbackLoader.width
                                height: videoThumbnailFallbackLoader.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }
                }

                Loader {
                    id: videoIconLoader
                    active: root.isVideo && root.useThumbnail && root.shouldLoad
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 8
                    sourceComponent: MaterialSymbol {
                        text: "video_library"
                        color: Appearance.colors.colPrimary
                        font.pixelSize: Appearance.font.pixelSize.large
                        fill: 1
                    }
                }

                Loader {
                    z: 1
                    id: moreOptionsButtonLoader
                    active: root.containsMouse && !root.isDirectory && root.shouldLoad
                    
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8

                    asynchronous: true
                    sourceComponent: WallpaperActionButton {
                        id: button
                        buttonIcon: "more_vert"
                        buttonFill: 1

                        onClicked: {
                            root.moreOptionsRequested(fileModelData);
                        }
                    }
                }

                Pill {
                    id: appliedBadge
                    z: 2
                    visible: root.isApplied && !root.isDirectory
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: Appearance.sizes.wallpaperSelectorItemMargins
                    implicitHeight: Appearance.font.pixelSize.huge + Appearance.sizes.wallpaperSelectorItemPadding * 2
                    implicitWidth: appliedBadgeContent.implicitWidth + Appearance.sizes.wallpaperSelectorItemPadding * 2
                    color: Appearance.colors.colPrimary

                    RowLayout {
                        id: appliedBadgeContent
                        anchors.centerIn: parent
                        spacing: Appearance.sizes.wallpaperSelectorItemPadding / 2

                        MaterialSymbol {
                            text: "check_circle"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            text: root.appliedLabel
                            color: Appearance.colors.colOnPrimary
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }
                    }
                }

                Loader {
                    id: iconLoader
                    active: !root.useThumbnail && !root.isApi && root.shouldLoad
                    anchors.fill: parent
                    sourceComponent: DirectoryIcon {
                        fileModelData: root.fileModelData
                    }
                }

                Loader {
                    id: apiImageLoader
                    active: root.isApi && root.shouldLoad
                    anchors.fill: parent
                    sourceComponent: StyledImage {
                        source: fileModelData.filePath
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        sourceSize.width: wallpaperItemColumnLayout.width
                        sourceSize.height: wallpaperItemColumnLayout.height - wallpaperItemColumnLayout.spacing - wallpaperItemName.height

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: apiImageLoader.width
                                height: apiImageLoader.height
                                radius: Appearance.rounding.small
                            }
                        }
                    }
                }
            }

            StyledText {
                id: wallpaperItemName
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                text: fileModelData.fileName
            }
        }
    }

    component WallpaperActionButton: RippleButton {
        id: button

        property alias buttonIcon: materialSymbol.text
        property alias buttonFill: materialSymbol.fill

        implicitWidth: 30
        implicitHeight: 30

        colBackground: root.containsMouse ? Appearance.colors.colSecondaryContainerHover : "transparent"
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive

        MaterialSymbol {
            id: materialSymbol

            text: button.buttonIcon
            fill: button.buttonFill

            anchors.centerIn: parent
            color: Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.large
        }

    }
}
