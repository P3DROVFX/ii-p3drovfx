pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import qs
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    property bool isMaterial: true
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    property int customSize: Config.options.bar.mediaPlayer.customSize
    property bool useFixedSize: Config.options.bar.mediaPlayer.useFixedSize

    // DockMedia-like properties
    property var artUrl: MprisController.artUrl
    property string trackTitle: activePlayer?.trackTitle ?? ""
    property string trackArtist: activePlayer?.trackArtist ?? ""
    property bool isPlaying: activePlayer?.isPlaying ?? false
    property bool hasTrack: trackTitle.length > 0

    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    property string displayedArtFilePath: {
        if (!root.artDownloaded)
            return "";
        if (root.artUrl.startsWith("file://"))
            return root.artUrl;
        return Qt.resolvedUrl(artFilePath);
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDownloaded = false;
            return;
        }
        if (root.artUrl.startsWith("file://")) {
            root.artDownloaded = true;
            return;
        }
        artDownloader.targetFile = root.artUrl;
        artDownloader.artFilePath = root.artFilePath;
        artDownloader.artTempPath = root.artFilePath + ".tmp";
        root.artDownloaded = false;
        artDownloader.running = true;
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        property string artTempPath: root.artFilePath + ".tmp"
        command: ["bash", "-c", `[ -f ${artFilePath} ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
        onExited: {
            root.artDownloaded = true;
        }
    }

    Layout.fillHeight: true
    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (useFixedSize ? customSize : (isMaterial ? materialRow.implicitWidth : Math.min(rowLayout.implicitWidth + 8, 280)))
    implicitHeight: vertical ? (isMaterial ? materialCol.implicitHeight : mediaCircProg.implicitHeight + 6) : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    width: implicitWidth
    height: implicitHeight

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        onPressed: event => {
            if (event.button === Qt.MiddleButton)
                activePlayer.togglePlaying();
            else if (event.button === Qt.BackButton)
                activePlayer.previous();
            else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton)
                activePlayer.next();
            else if (event.button === Qt.LeftButton) {
                var globalPos = root.mapToItem(null, 0, 0);
                GlobalStates.mediaPopupRect = Qt.rect(globalPos.x, globalPos.y, root.width, root.height);
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            }
        }
    }

    // Vertical default
    Loader {
        id: mediaCircProg
        active: root.vertical && !root.isMaterial
        visible: active
        anchors.centerIn: parent
        sourceComponent: ClippedFilledCircularProgress {
            implicitSize: 20
            lineWidth: Appearance.rounding.unsharpen
            value: root.activePlayer?.position / root.activePlayer?.length
            colPrimary: Appearance.colors.colOnSecondaryContainer
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }
    }

    // Vertical Material
    Loader {
        id: materialCol
        active: root.vertical && root.isMaterial
        visible: active
        anchors.centerIn: parent
        sourceComponent: Rectangle {
            id: cardVert
            color: Appearance.colors.colSecondaryContainer
            radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
            implicitWidth: Appearance.sizes.verticalBarWidth - 8
            implicitHeight: 120 // Increased to fit all elements properly
            
            ColumnLayout {
                id: innerCol
                anchors.centerIn: parent
                width: parent.width - 8
                spacing: 6

                // Art
                Rectangle {
                    id: artVertRect
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: innerCol.width - 4
                    implicitHeight: innerCol.width - 4
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer
                    
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artVertRect.width
                            height: artVertRect.height
                            radius: artVertRect.radius
                        }
                    }

                    StyledImage {
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        sourceSize.width: parent.width
                        sourceSize.height: parent.height
                        visible: root.displayedArtFilePath !== ""
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: "music_note"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSecondaryContainer
                        visible: root.displayedArtFilePath === ""
                    }
                }

                // Play/Pause
                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 28
                    implicitHeight: 32
                    buttonRadius: root.isPlaying ? Appearance.rounding.small : height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    downAction: () => root.activePlayer?.togglePlaying()
                    
                    Behavior on buttonRadius {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutQuint
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "pause" : "play_arrow"
                        iconSize: parent.width * 0.6
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnPrimary
                    }
                }

                // Next
                RippleButton {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: innerCol.width - 4
                    implicitHeight: innerCol.width - 4
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colTertiaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    downAction: () => root.activePlayer?.next()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "skip_next"
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnTertiaryContainer
                    }
                }
            }
        }
    }

    // Horizontal default
    Loader {
        id: rowLayout
        active: !root.vertical && !root.isMaterial
        visible: active
        anchors.fill: parent
        sourceComponent: RowLayout {
            spacing: 4
            ClippedFilledCircularProgress {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 3
                implicitSize: 20
                lineWidth: Appearance.rounding.unsharpen
                value: root.activePlayer?.position / root.activePlayer?.length
                colPrimary: Appearance.colors.colOnSecondaryContainer
                enableAnimation: false
                Item {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }
            StyledText {
                visible: Config.options.bar.verbose
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.rightMargin: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
                text: `${root.cleanedTitle}${root.activePlayer?.trackArtist ? ' • ' + root.activePlayer.trackArtist : ''}`
            }
        }
    }

    // Horizontal Material
    Loader {
        id: materialRow
        active: !root.vertical && root.isMaterial
        visible: active
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Rectangle {
            id: card
            color: Appearance.colors.colSecondaryContainer
            radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
            implicitHeight: Appearance.sizes.baseBarHeight - 8
            height: implicitHeight
            implicitWidth: innerRow.implicitWidth + 8
            width: parent.width

            RowLayout {
                id: innerRow
                anchors.fill: parent
                height: parent.height
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 6

                // Art
                Rectangle {
                    id: artRect
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: card.height - 6
                    implicitHeight: card.height - 6
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer

                    visible: root.hasTrack
                    scale: visible ? 1 : 0
                    opacity: visible ? 1 : 0
                    Layout.preferredWidth: visible ? implicitWidth : 0
                    
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artRect.width
                            height: artRect.height
                            radius: artRect.radius
                        }
                    }

                    StyledImage {
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        sourceSize.width: artRect.width
                        sourceSize.height: artRect.height
                        visible: root.displayedArtFilePath !== ""
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: "music_note"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSecondaryContainer
                        visible: root.displayedArtFilePath === ""
                    }
                }

                // Title + Artist
                ColumnLayout {
                    id: titleArtistCol
                    spacing: -4
                    Layout.alignment: Qt.AlignVCenter
                    Layout.topMargin: 2
                    Layout.fillWidth: true

                    visible: root.hasTrack
                    opacity: visible ? 1 : 0
                    Layout.preferredWidth: visible ? -1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                    StyledText {
                        id: artistText
                        text: root.trackArtist
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation {
                                    target: artistText
                                    property: "x"
                                    to: -artistText.width
                                    duration: 150
                                    easing.type: Easing.InQuad
                                }
                                PropertyAction {
                                    target: artistText
                                    property: "text"
                                }
                                NumberAnimation {
                                    target: artistText
                                    property: "x"
                                    from: artistText.width
                                    to: 0
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                    }
                    StyledText {
                        id: titleText
                        Layout.topMargin: !root.activePlayer ? -13 : 0
                        text: StringUtils.cleanMusicTitle(root.trackTitle) || Translation.tr("No media")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                        opacity: 0.7
                        Layout.fillWidth: true
                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation {
                                    target: titleText
                                    property: "x"
                                    to: -artistText.width
                                    duration: 150
                                    easing.type: Easing.InQuad
                                }
                                PropertyAction {
                                    target: titleText
                                    property: "text"
                                }
                                NumberAnimation {
                                    target: titleText
                                    property: "x"
                                    from: artistText.width
                                    to: 0
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                    }
                }

                // Play/Pause
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: card.height + 8
                    implicitHeight: card.height - 6
                    buttonRadius: root.isPlaying ? Appearance.rounding.small : height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    downAction: () => root.activePlayer?.togglePlaying()

                    Behavior on buttonRadius {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutQuint
                        }
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: root.isPlaying ? "pause" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: Appearance.colors.colOnPrimary
                    }
                }

                // Next
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: card.height - 6
                    implicitHeight: card.height - 6
                    Layout.leftMargin: -2
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colTertiaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    downAction: () => root.activePlayer?.next()

                    visible: root.hasTrack
                    scale: visible ? 1 : 0
                    opacity: visible ? 1 : 0
                    Layout.preferredWidth: visible ? implicitWidth : 0
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "skip_next"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: Appearance.colors.colOnTertiaryContainer
                    }
                }
            }
        }
    }
}
