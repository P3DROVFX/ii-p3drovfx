pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import "../../../ii/bar/widgets/tray"

Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)
    property bool vertical: false

    readonly property int itemCount: TrayService.pinnedItems.length + TrayService.unpinnedItems.length
    readonly property bool shelfEmpty: itemCount === 0
    readonly property bool detached: Config.options.akebono?.shelf.popupsDetached ?? false
    readonly property bool paddingless: root.style !== "default" || root.detached

    visible: !shelfEmpty
    implicitWidth: shelfEmpty ? 0 : (trayHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 18) + overflowChip.visible * (overflowChip.implicitWidth + 4)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    // The shelf owns tray positioning: the bar SysTray's overflow popup is a
    // window-anchored widget that floats to the screen centre inside the shelf
    // window, so overflow here goes through the shelf's own popup container.
    Component.onCompleted: {
        if (root.shelf)
            root.shelf.registerTrayAnchor(root);
        if (root.shelf && root.itemCount > 0)
            root.shelf.publishTray();
    }
    Component.onDestruction: {
        if (root.shelf && root.shelf.trayAnchor === root)
            root.shelf.unregisterTrayAnchor(root);
    }

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
    }

    RowLayout {
        id: trayRow
        anchors.centerIn: parent
        spacing: 4

        Loader {
            id: trayHolder
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: root.style === "expressive" ? trayExpressive : trayDefault
        }

        Item {
            id: overflowChip
            visible: TrayService.unpinnedItems.length > 0
            Layout.preferredWidth: Math.round(root.pillHeight - 8)
            Layout.preferredHeight: Math.round(root.pillHeight - 8)
            Layout.alignment: Qt.AlignVCenter

            RippleButton {
                anchors.fill: parent
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                toggled: root.shelf?.trayOverflowOpen ?? false
                onClicked: root.shelf?.toggleTrayOverflow()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "expand_more"
                    iconSize: Math.round(parent.height * 0.6)
                    color: parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                }
            }
        }
    }

    Component {
        id: trayDefault
        SysTray {
            height: root.pillHeight
            vertical: false
            showOverflowMenu: false
        }
    }

    Component {
        id: trayExpressive
        ExpressiveSystemTray {
            vertical: false
            showOverflowMenu: false
        }
    }
}