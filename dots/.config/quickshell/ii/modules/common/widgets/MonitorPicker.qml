import QtQuick
import Quickshell

/**
 * Monitor selection row: a ConfigSelectionArray listing every connected
 * screen by name. Bind `currentValue` to the stored monitor name and handle
 * `onSelected` to persist it — replaces the ad-hoc screen lists built inline
 * in Bar / Dynamic Island / Notifications / Background configs.
 */
ConfigSelectionArray {
    id: root

    // Extra entry prepended before the screens, e.g. { displayName:
    // Translation.tr("All"), icon: "select_all", value: "" }. Null = none.
    property var extraOption: null

    options: {
        let list = [];
        if (root.extraOption !== null)
            list.push(root.extraOption);

        for (let i = 0; i < Quickshell.screens.length; i++) {
            const name = Quickshell.screens[i].name;
            list.push({
                "displayName": name,
                "icon": "desktop_windows",
                "value": name
            });
        }
        return list;
    }
}
