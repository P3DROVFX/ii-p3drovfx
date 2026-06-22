import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Revealer { // Scroll hint
    id: root
    property string icon
    property string side: "left"
    property string tooltipText: ""
    
    Item {
        id: container
        anchors.right: root.side === "left" ? parent.right : undefined
        anchors.left: root.side === "right" ? parent.left : undefined
        width: contentColumn.width
        height: contentColumn.height

        Column {
            id: contentColumn
            spacing: -5
            MaterialSymbol {
                text: "keyboard_arrow_up"
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                text: root.icon
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
        }
    }
}