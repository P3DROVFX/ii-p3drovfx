import QtQuick

/**
 * The wallpaper plane's item structure, rebuilt in the widgets window from the
 * screen's live WallpaperImage (see DepthCutoutLayer.qml for why every number
 * is read rather than recomputed). Children land in the framed picture's own
 * box, where the file is drawn PreserveAspectCrop and centred.
 *
 *   window ── [correction] ── content (W×H, Scale about centre, Translate)
 *                               └── framed (x, y, w, h, rotation, mirror)
 *                                     └── children
 *
 * The wallpaper sits under `G · Edit · OverviewScale`, the widget container
 * under `Edit · OverviewTranslate · OverviewScale(if followed) · G` (G = the
 * Gnome-like style's root ratio). They agree at rest but not mid-overview, so
 * the root carries the exact difference, `container⁻¹ · wallpaper`.
 */
Item {
    id: root

    required property var plane
    required property var overviewController
    required property matrix4x4 containerEditMatrix
    required property real containerScale

    default property alias content: framedBox.data
    readonly property real frameWidth: framedBox.width
    readonly property real frameHeight: framedBox.height

    readonly property Item contentItem: root.plane ? root.plane.depthContentItem : null
    readonly property var parallaxTranslate: root.plane ? root.plane.depthParallaxTranslate : null
    readonly property Item framedItem: root.plane ? root.plane.depthFramedItem : null

    function scaleAbout(m, cx, cy, s) {
        const t = Qt.matrix4x4(1, 0, 0, cx, 0, 1, 0, cy, 0, 0, 1, 0, 0, 0, 0, 1);
        const k = Qt.matrix4x4(s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        const b = Qt.matrix4x4(1, 0, 0, -cx, 0, 1, 0, -cy, 0, 0, 1, 0, 0, 0, 0, 1);
        return m.times(t).times(k).times(b);
    }
    readonly property matrix4x4 correction: {
        const identity = Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
        const p = root.plane;
        if (!p)
            return identity;
        const c = root.overviewController;
        const s = c ? c.scale : 1;
        const ox = c ? c.scaleOriginX : root.width / 2;
        const oy = c ? c.scaleOriginY : root.height / 2;
        const g = p.scale;
        // The wallpaper: G · Edit · OverviewScale.
        const wallpaper = root.scaleAbout(root.scaleAbout(identity, p.width / 2, p.height / 2, g)
            .times(p.editMatrix), ox, oy, s);
        // The container: Edit · OverviewTranslate · OverviewScale(followed) · G.
        let container = root.containerEditMatrix;
        if (c && c.followWidgetsTranslation)
            container = container.times(Qt.matrix4x4(1, 0, 0, c.translateX, 0, 1, 0, c.translateY, 0, 0, 1, 0, 0, 0, 0, 1));
        if (c && c.followWidgetsScale)
            container = root.scaleAbout(container, ox, oy, s);
        container = root.scaleAbout(container, root.width / 2, root.height / 2, root.containerScale);
        return container.inverted().times(wallpaper);
    }

    Item {
        anchors.fill: parent
        transform: Matrix4x4 {
            matrix: root.correction
        }

        // wallpaperContent: the plane, scaled about its centre, then the parallax.
        Item {
            id: contentBox
            width: root.contentItem ? root.contentItem.width : 0
            height: root.contentItem ? root.contentItem.height : 0
            transform: [
                Scale {
                    origin.x: contentBox.width / 2
                    origin.y: contentBox.height / 2
                    xScale: root.contentItem ? root.contentItem.contentScale : 1
                    yScale: root.contentItem ? root.contentItem.contentScale : 1
                },
                Translate {
                    x: root.parallaxTranslate ? root.parallaxTranslate.x : 0
                    y: root.parallaxTranslate ? root.parallaxTranslate.y : 0
                }
            ]

            // framedContent: placed, turned and mirrored inside the plane.
            Item {
                id: framedBox
                readonly property bool framed: root.plane ? root.plane.framed : false
                readonly property var frame: root.framedItem ? root.framedItem.frame : null
                x: root.framedItem ? root.framedItem.x : 0
                y: root.framedItem ? root.framedItem.y : 0
                width: root.framedItem ? root.framedItem.width : 0
                height: root.framedItem ? root.framedItem.height : 0
                rotation: root.framedItem ? root.framedItem.rotation : 0
                transform: Scale {
                    origin.x: framedBox.width / 2
                    origin.y: framedBox.height / 2
                    xScale: framedBox.framed && framedBox.frame ? framedBox.frame.scaleX : 1
                    yScale: framedBox.framed && framedBox.frame ? framedBox.frame.scaleY : 1
                }
            }
        }
    }
}
