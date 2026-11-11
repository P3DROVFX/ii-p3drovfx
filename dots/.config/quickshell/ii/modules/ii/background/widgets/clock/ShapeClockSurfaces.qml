import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/*
 * The filled shapes of a card-less clock (Hour Shape, Tide, Ruler, Pebbles,
 * Totem), with the widgets' shadow cast by all of them at once. Text goes
 * after this item, so it never casts a shadow of its own.
 */
Item {
    id: root

    default property alias surfaces: holder.data
    readonly property bool shadows: Config.options.background.widgets.enableShadows ?? true

    Item {
        id: holder
        anchors.fill: parent
        // The shadow draws its source; showing both would paint it twice.
        visible: !root.shadows
    }

    StyledDropShadow {
        target: holder
        visible: root.shadows
    }
}
