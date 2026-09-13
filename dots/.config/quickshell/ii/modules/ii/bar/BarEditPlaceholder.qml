import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The body Edit Mode lends a bar widget that is drawing nothing.
 *
 * Several widgets hide themselves when they have nothing to say - the music
 * player with no track, an idle timer, the sports card out of season. To the
 * layout that is indistinguishable from not being on the bar at all, so in the
 * mode they had no drag handle, no remove badge, and no row in the catalogue
 * either (the catalogue only offers what is NOT placed): a widget you could
 * neither see, move nor take off. This chip stands in its place for exactly as
 * long as the mode is on, carrying the widget's own name and icon so the row
 * says what is there rather than that something is.
 */
Item {
    id: root

    property bool vertical: false
    property string widgetId: ""
    readonly property var info: BarComponentRegistry.getComponent(root.widgetId)

    implicitWidth: root.vertical ? 26 : (chip.implicitWidth + 4)
    implicitHeight: root.vertical ? 26 : 26

    Rectangle {
        id: chip
        anchors.centerIn: parent
        implicitWidth: root.vertical ? 26 : (contents.implicitWidth + 18)
        implicitHeight: 26
        radius: Appearance.rounding.full
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        RowLayout {
            id: contents
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: root.info?.icon ?? "widgets"
                iconSize: 16
                color: Appearance.colors.colOnSurfaceVariant
            }
            // The name is the point of the chip on a bar with room for it; on
            // the vertical bar there is none, and the hover label already names
            // whatever the pointer is over.
            StyledText {
                visible: !root.vertical
                text: root.info?.title ?? root.widgetId
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
