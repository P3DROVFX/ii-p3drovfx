pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.akebono.menu
import QtQuick
import Quickshell

Item {
    id: root
    property real boundsWidth: 0
    property real boundsHeight: 0
    property bool anchorAbove: true
    readonly property bool showing: menu.showing
    z: 100

    property var trayItem: null
    readonly property string trayItemId: root.trayItem?.id ?? ""

    function show(item, x, y) {
        root.trayItem = item;
        menu.open(x, y);
    }
    function dismiss() {
        menu.dismiss();
    }

    function convert(e) {
        return {
            "label": e.text,
            "icon": (e.buttonType === QsMenuButtonType.CheckBox && e.checkState !== Qt.Unchecked) ? "check"
                : (e.buttonType === QsMenuButtonType.RadioButton && e.checkState === Qt.Checked) ? "radio_button_checked"
                : "",
            "iconSource": e.icon ?? "",
            "enabled": e.enabled,
            "separator": e.isSeparator,
            "hasSubmenu": e.hasChildren,
            "handle": e,
            "action": e.hasChildren ? null : (() => e.triggered())
        };
    }

    readonly property var menuItems: {
        const out = [];
        if (root.trayItemId.length > 0) {
            out.push({
                "icon": "push_pin",
                "label": TrayService.isPinned(root.trayItemId) ? Translation.tr("Unpin") : Translation.tr("Pin"),
                "action": () => {
                    TrayService.togglePin(root.trayItemId);
                    root.dismiss();
                }
            });
            if (rootOpener.children.values.length > 0)
                out.push({ "separator": true });
        }
        for (const e of rootOpener.children.values)
            out.push(root.convert(e));
        return out;
    }

    QsMenuOpener {
        id: rootOpener
        menu: root.trayItem?.menu ?? null
    }
    QsMenuOpener {
        id: subOpener
        menu: (menu.submenuIndex >= 0 && menu.items[menu.submenuIndex]) ? (menu.items[menu.submenuIndex].handle ?? null) : null
    }

    SdfContextMenu {
        id: menu
        anchors.fill: parent
        anchorAbove: root.anchorAbove
        boundsWidth: root.boundsWidth
        boundsHeight: root.boundsHeight
        items: root.menuItems
        subItems: subOpener.menu ? subOpener.children.values.map(root.convert) : []
    }
}
