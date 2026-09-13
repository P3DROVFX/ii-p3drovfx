pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Input -> Per device -> one device.
 *
 * The settings for a single keyboard, mouse, tablet or touch device. Which device it is comes
 * from HyprlandDevices, because a sub-page is opened by URL and a URL cannot carry a device.
 *
 * A device override is all or nothing in Lua - `hl.device{}` either exists for a name or it does
 * not - so the page is one switch and, behind it, the fields that make sense for what this
 * device is.
 */
HyprSubPage {
    id: page

    readonly property var device: HyprlandDevices.editing
    readonly property string deviceName: HyprlandDevices.editName
    readonly property bool overridden: HyprlandGui.deviceSpec(page.deviceName) !== null

    title: page.deviceName
    subtitle: page.overridden
        ? Translation.tr("Settings of its own, on top of the Input tab")
        : Translation.tr("Following the settings on the Input tab")

    ContentSection {
        title: Translation.tr("This device")
        icon: {
            if (HyprlandDevices.editKind === "keyboard") return "keyboard";
            if (HyprlandDevices.editKind === "tablet") return "stylus";
            if (HyprlandDevices.editKind === "touch") return "touch_app";
            return HyprlandDevices.isTouchpad(page.device) ? "touchpad_mouse" : "mouse";
        }

        HyprDeviceCard {
            visible: page.device !== null
            showHeader: false
            device: page.device ?? ({ "name": page.deviceName })
            kind: HyprlandDevices.editKind === "" ? "pointer" : HyprlandDevices.editKind
        }

        StyledText {
            Layout.fillWidth: true
            visible: page.device === null
            text: Translation.tr("This device is no longer plugged in.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
