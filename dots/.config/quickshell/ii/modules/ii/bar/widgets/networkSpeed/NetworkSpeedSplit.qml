import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Split — two connected segments, one per direction.
 *
 * Download sits on the palette's main surface and upload on its inner variant,
 * so the two directions read as two different things even with the arrows
 * covered. The meeting corners are small and open up to full pills on hover,
 * the same connected-group motion the Material 3 Expressive buttons use. With a
 * single direction the segment is one plain pill.
 */
Item {
    id: root

    property var net
    property var palette
    property bool vertical: false
    property real thickness: 32
    property real pillRadius: Appearance.rounding.full
    property bool hovered: false

    // `full` is 9999; animating a corner towards that is a jump, so every
    // radius here is capped at what the short axis can actually show.
    readonly property real outer: Math.min(root.pillRadius, root.thickness / 2)
    // The corners where two segments meet.
    readonly property real seam: root.hovered ? root.outer : Appearance.rounding.verysmall

    implicitWidth: root.vertical ? root.thickness : layout.implicitWidth
    implicitHeight: root.vertical ? layout.implicitHeight : root.thickness

    GridLayout {
        id: layout

        anchors.fill: parent
        columns: root.vertical ? 1 : 2
        columnSpacing: root.net.tight(3, 2)
        rowSpacing: root.net.tight(3, 2)

        NetworkSpeedSegment {
            visible: root.net.showDown
            net: root.net
            rate: root.net.down
            vertical: root.vertical
            thickness: root.thickness
            iconName: "arrow_downward"
            startRadius: root.outer
            endRadius: root.net.showBoth ? root.seam : root.outer
            color: root.hovered ? root.palette.colBackgroundHover : root.palette.colBackground
            fg: root.palette.colOnBackground
            Layout.fillWidth: !root.vertical
            Layout.fillHeight: root.vertical
        }

        NetworkSpeedSegment {
            visible: root.net.showUp
            net: root.net
            rate: root.net.up
            vertical: root.vertical
            thickness: root.thickness
            iconName: "arrow_upward"
            startRadius: root.net.showBoth ? root.seam : root.outer
            endRadius: root.outer
            color: root.net.showBoth
                ? (root.hovered ? root.palette.colBackgroundVariantHover : root.palette.colBackgroundVariant)
                : (root.hovered ? root.palette.colBackgroundHover : root.palette.colBackground)
            fg: root.net.showBoth ? root.palette.colOnBackgroundVariant : root.palette.colOnBackground
            Layout.fillWidth: !root.vertical
            Layout.fillHeight: root.vertical
        }
    }
}
