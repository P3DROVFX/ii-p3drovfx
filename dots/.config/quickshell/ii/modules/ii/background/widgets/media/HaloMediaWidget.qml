import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.background.widgets

/*
 * Halo Media (1x1). The cover inside the shell's M3E wavy progress ring: the
 * ring fills with the track and flattens on pause, and the cover's cut morphs
 * from a circle into a scalloped cookie while music plays. A tall play key and
 * a "next" key stand beside it; the title and artist sit underneath.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "media_halo"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "media_halo")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.media_halo ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    implicitWidth: root.designSize * contentScale
    implicitHeight: root.designSize * contentScale

    // -- Geometry (design units) --
    readonly property real designSize: 240
    readonly property real padding: 14
    readonly property real ringSize: 156
    readonly property real ringThickness: 8
    readonly property real artInset: 20
    readonly property real gap: 10
    readonly property real keyWidth: root.designSize - root.padding * 2 - root.ringSize - root.gap
    readonly property real nextKeyHeight: 50

    readonly property bool morphArt: root.options?.morphArt ?? true
    readonly property bool wavyRing: root.options?.wavyRing ?? true

    MediaPlayerSource {
        id: media
        dynamicColors: root.options?.dynamicAlbumColors ?? false
        active: root.visible && root.opacity > 0
        ignoreWindows: root.isPreview
    }

    Item {
        anchors.centerIn: parent
        width: root.designSize
        height: root.designSize
        scale: root.contentScale

        StyledRectangularShadow {
            target: card
            visible: Config.options.background.widgets.enableShadows ?? true
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(media.colCard)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            ClockProgressRing {
                id: ring
                x: root.padding
                y: root.padding
                width: root.ringSize
                height: root.ringSize
                value: media.hasLength ? media.progress : 0
                thickness: root.ringThickness
                wavy: root.wavyRing && media.isPlaying
                waves: 12
                tickDuration: 1000
                animateWave: media.animate
                colIndicator: media.colAccent
                colTrack: media.colTrack
            }

            MediaShapedArt {
                anchors.centerIn: ring
                width: root.ringSize - root.artInset * 2
                height: width
                source: media.artSource
                shape: root.morphArt && media.isPlaying ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Circle
                placeholderColor: media.colInner
                placeholderIconColor: media.colText
            }

            MediaControlButton {
                id: playKey
                anchors.left: ring.right
                anchors.leftMargin: root.gap
                anchors.top: ring.top
                width: root.keyWidth
                height: root.ringSize - root.nextKeyHeight - root.gap
                enabled: media.hasPlayer
                symbol: media.isPlaying ? "pause" : "play_arrow"
                symbolSize: 28
                colFill: media.colAccent
                colContent: media.colOnAccent
                restRadius: media.isPlaying ? Appearance.rounding.normal : Appearance.rounding.full
                onClicked: media.togglePlaying()
            }

            MediaControlButton {
                anchors.left: playKey.left
                anchors.bottom: ring.bottom
                width: root.keyWidth
                height: root.nextKeyHeight
                enabled: media.player?.canGoNext ?? false
                symbol: "skip_next"
                symbolSize: 22
                colFill: media.colTonal
                colContent: media.colOnTonal
                onClicked: media.next()
            }

            StyledText {
                id: title
                anchors.top: ring.bottom
                anchors.topMargin: root.gap
                anchors.left: parent.left
                anchors.leftMargin: root.padding + 2
                anchors.right: parent.right
                anchors.rightMargin: root.padding + 2
                text: media.title
                color: media.colText
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.larger
                font.variableAxes: ({ "wght": 740, "wdth": 75, "ROND": 100 })
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                anchors.top: title.bottom
                anchors.left: title.left
                anchors.right: title.right
                text: media.artist
                color: media.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }
}
