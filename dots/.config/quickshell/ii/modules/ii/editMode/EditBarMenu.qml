import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.contextMenu
import QtQuick
import QtQuick.Layouts

/**
 * The bar widget's right-click menu in Edit Mode: its page in the catalogue,
 * the centre split (centre list only), and Remove.
 *
 * Drawn by the chrome surface - the bar's own window is too thin to hold a
 * card - and every layout write goes through the bar's controller. The rows
 * are the shared context menu's (ContextMenuList), arranged by the user under
 * "editBar" in ContextMenus, with the same compact style and motion as every
 * other menu.
 */
Rectangle {
    id: root

    property var controller: null
    property int bucket: -1
    property int index: -1
    property bool centered: false
    signal dismissRequested()

    readonly property bool dense: ContextMenus.compact
    readonly property real padding: root.dense ? ContextMenus.compactPadding : 8
    readonly property string componentId: {
        if (!root.controller || root.bucket < 0 || root.index < 0)
            return "";
        const entry = root.controller.storedList(root.bucket)[root.index];
        return entry && entry.id ? entry.id : "";
    }
    readonly property var info: root.componentId === ""
        ? null : BarComponentRegistry.getComponent(root.componentId)

    readonly property var liveEntries: [
        {
            "id": "appearance",
            "symbol": "palette",
            "title": Translation.tr("Appearance & group"),
            "submenu": true,
            "enabled": root.componentId !== ""
        },
        {
            "id": "center",
            "shown": root.bucket === 1 && !ShellModePolicy.barCenterActive,
            "symbol": "align_horizontal_center",
            "title": Translation.tr("Centre this"),
            "toggle": true,
            "checked": root.centered
        },
        {
            "id": "remove",
            "symbol": "delete",
            "title": Translation.tr("Remove from the bar"),
            "destructive": true
        }
    ].filter(entry => entry.shown !== false)
    readonly property var arranged: ContextMenus.arrange("editBar", root.liveEntries)

    function activate(entry: var): void {
        const id = root.componentId;
        root.dismissRequested();
        if (entry.custom) {
            ContextMenus.runCustom(entry, id);
            return;
        }
        switch (entry.id) {
        case "appearance":
            // The way to this widget's looks and its group, which is a page
            // of the catalogue rather than anything this card could hold.
            GlobalStates.openEditCatalogue("bar", "", "component:" + id);
            break;
        case "center":
            root.controller?.toggleCenter(root.bucket, root.index);
            break;
        case "remove":
            root.controller?.removeAt(root.bucket, root.index);
            break;
        }
    }

    implicitWidth: !root.dense ? 244
        : Math.max(ContextMenus.compactMinWidth, Math.min(ContextMenus.compactMaxWidth,
            Math.ceil(Math.max(list.implicitWidth, bar.implicitWidth) + root.padding * 2)))
    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.windowRounding
    color: Appearance.colors.colSurfaceContainer

    // From the corner the pointer is at: the card belongs to a point.
    ContextMenuMotion {
        id: motion
        Component.onCompleted: motion.playEnter(true)
    }
    opacity: motion.reveal
    scale: motion.scale * ContextMenus.scale
    transformOrigin: Item.TopLeft

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    StyledRectangularShadow {
        target: root
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.dense ? 4 : 3

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.dense ? 6 : 8
            Layout.rightMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: root.dense ? 2 : 4
            spacing: 8

            MaterialSymbol {
                text: root.info?.icon ?? "widgets"
                iconSize: root.dense ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: root.info?.title ?? Translation.tr("Widget")
                font.pixelSize: root.dense ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        ContextMenuIconBar {
            id: bar
            Layout.fillWidth: true
            entries: root.arranged.bar
            hostPadding: root.padding
            onActivated: (entry, button) => root.activate(entry)
        }

        ContextMenuList {
            id: list
            Layout.fillWidth: true
            rows: root.arranged.rows
            dense: root.dense
            separators: root.dense
            hostPadding: root.padding
            onActivated: (entry, row) => root.activate(entry)
        }
    }
}
