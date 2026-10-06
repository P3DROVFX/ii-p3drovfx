import QtQuick
import qs.modules.ii.background.blur

/**
 * The wallpaper, painted in the widgets window under the widgets while a
 * parallax slide moves the plane (DepthCutoutLayer.copyActive).
 *
 * Two layer surfaces never present their frames together, so a cutout drawn
 * over a wallpaper in another surface drifts a tick off it mid-slide. With
 * this opaque copy under the canvas, the screen during the slide is one
 * surface - copy, widgets and cutout all in step. At rest the copy is hidden,
 * and since it is the same file through the same item structure, decode size
 * and filtering, the hand-over back to the real wallpaper changes no pixel.
 *
 * Only for a plane nothing else treats: BarGradientOverlay, the one treatment
 * that stays on through a slide, is reproduced on top of it, from the same
 * component. The decode is shared with the wallpaper window through the pixmap
 * cache (same source, size and fill mode); only the GPU texture is a second
 * copy, kept while parallax is on so a slide never waits for an upload twice.
 */
Item {
    id: root

    required property var plane
    required property var overviewController
    required property matrix4x4 containerEditMatrix
    required property real containerScale

    DepthPlaneChain {
        id: chain
        anchors.fill: parent
        plane: root.plane
        overviewController: root.overviewController
        containerEditMatrix: root.containerEditMatrix
        containerScale: root.containerScale

        // As WallpaperImage's TransitionImage draws it.
        Image {
            anchors.fill: parent
            source: root.plane ? root.plane.committedWallpaperSource : ""
            sourceSize: root.plane ? root.plane.stableDecodeSize : Qt.size(-1, -1)
            fillMode: Image.PreserveAspectCrop
            mipmap: root.plane ? !root.plane.decodeCapped : true
            cache: true
            asynchronous: true
            smooth: true
            antialiasing: true
        }
    }

    BarGradientOverlay {
        sourceItem: chain
        screenWidth: root.width
        screenHeight: root.height
    }
}
