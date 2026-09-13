import QtQuick

/*
 * Raster content — a Canvas, or anything behind `layer.enabled` — rasterises at
 * its own item size and is then stretched by the ancestor Item.scale that makes
 * a desktop widget bigger. That stretch is a bilinear upsample of a finished
 * bitmap, which is where the jagged edges on scaled-up clock dials come from.
 *
 * This wrapper keeps its own layout box at the natural size, but hands its
 * child a box `factor` times larger and scales that back down. The child's paint
 * code is untouched — it still draws in terms of its own width/height — so it
 * simply produces the same picture at the resolution it will really be shown at.
 *
 *   Supersampled {
 *       anchors.fill: parent
 *       factor: root.renderScale
 *       MonthClock { anchors.fill: parent }
 *   }
 *
 * factor 1 is a no-op: the inner item matches the outer box and the scale is 1.
 */
Item {
    id: root

    // Usually bound to AbstractBackgroundWidget.renderScale.
    property real factor: 1
    readonly property real _f: Math.max(1, root.factor)

    default property alias content: holder.data

    Item {
        id: holder
        width: root.width * root._f
        height: root.height * root._f
        // Top-left origin so the shrink lands the child exactly back on the
        // wrapper's box instead of around its centre.
        transformOrigin: Item.TopLeft
        scale: 1 / root._f
    }
}
