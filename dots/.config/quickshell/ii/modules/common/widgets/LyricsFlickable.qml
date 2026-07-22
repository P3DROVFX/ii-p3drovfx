import Qt5Compat.GraphicalEffects
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Services.Mpris

// Shows Genius lyrics in a scrollable, syncable view. Syncing is based on the current position of the track and the total length, so it's not perfect but it's something.

Item {
    id: root

    property var player: MprisController.activePlayer
    property string plainLyricsString: LyricsService.plainLyrics
    property bool hasPlainLyrics: plainLyricsString.trim().length > 0
    property string geniusLyricsString: plainLyricsString

    property bool hasSyncedLines: LyricsService.syncedLines.length > 0
    property real fontPixelSize: Appearance.font.pixelSize.hugeass * 1.2
    property color textColor: Appearance.colors.colOnLayer0
    property real loadingIndicatorSize: 96
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color shapeColor: Appearance.colors.colOnPrimaryContainer

    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing && hasSyncedLines
        interval: 250
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    MaterialLoadingIndicator {
        anchors.centerIn: parent
        loading: !root.hasPlainLyrics && !hasSyncedLines
        visible: loading
        implicitSize: root.loadingIndicatorSize
        color: root.indicatorColor
        shapeColor: root.shapeColor
    }

    Flickable {
        id: geniusFlickable
        anchors.fill: parent
        
        opacity: !hasSyncedLines && root.hasPlainLyrics ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        

        clip: true
        contentHeight: geniusText.implicitHeight
        interactive: true

        property bool isSyncing: true

        readonly property real rawTargetY: {
            var lines = root.geniusLyricsString.split('\n')
            var totalLines = lines.length
            
            var currentLineIndex = ((root.player?.position ?? 0) / (root.player?.length || 1)) * totalLines
            
            var averageLineHeight = contentHeight / totalLines
            var targetY = (currentLineIndex * averageLineHeight)
            
            return Math.max(0, targetY - (geniusFlickable.height / 2))
        }

        property real userScrollOffset: Persistent.states.background.mediaMode.userScrollOffset
        onUserScrollOffsetChanged: {
            updateScrolling()
        }

        onMovementEnded: {
            Persistent.states.background.mediaMode.userScrollOffset = contentY - rawTargetY
            isSyncing = true 
        }

        onMovementStarted: isSyncing = false

        onRawTargetYChanged: {
            updateScrolling()
        }

        function updateScrolling() {
            if (isSyncing && !dragging && !flicking) {
                contentY = Math.min(contentHeight - height, rawTargetY + Persistent.states.background.mediaMode.userScrollOffset)
            }
        }

        Behavior on contentY {
            enabled: geniusFlickable.isSyncing
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        layer.enabled: true
            layer.effect: OpacityMask {
                source: geniusFlickable
                maskSource: Rectangle {
                    width: geniusFlickable.width
                    height: geniusFlickable.height
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.3; color: "black" }
                        GradientStop { position: 0.7; color: "black" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }


        StyledText {
            id: geniusText
            width: parent.width
            text: root.geniusLyricsString
            color: root.textColor
            font.pixelSize: root.fontPixelSize
            font.weight: Font.Medium
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignTop
            lineHeight: 1.6
        }
    }
}
