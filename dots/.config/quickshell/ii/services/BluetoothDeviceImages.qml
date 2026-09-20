pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * The picture of a device: the user's own PNG from Settings → Bluetooth device
 * images (`bluetoothDeviceImages`, files living in `<config>/bluetooth_images/`),
 * then the built-in art matched by MAC or name, then nothing.
 *
 * The popups carry older private copies of this lookup; new surfaces use this and
 * the copies retire as those surfaces are touched.
 */
Singleton {
    id: root

    /** Image URL for a BluetoothDevice, or "" when there is no picture for it. */
    function sourceFor(device): string {
        if (!device)
            return "";

        if (Config.options && Config.options.bluetoothDeviceImages) {
            const custom = Config.options.bluetoothDeviceImages.find(d => d.mac === device.address);
            if (custom && custom.image)
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
        }

        const mac = (device.address || "").replace(/:/g, "_").toUpperCase();
        const name = (device.name || device.alias || "").toLowerCase();
        const basePath = Directories.assetsPath ? ("file://" + Directories.assetsPath + "/images/devices/") : "";
        if (basePath === "")
            return "";

        if (mac === "E8_EE_CC_96_31_3A" || name.includes("q30") || name.includes("soundcore life q30") || name.includes("soundcore"))
            return basePath + "anker_q30_.png";
        if (mac === "68_7D_6B_94_0B_C2" || name.includes("buds 3 pro") || name.includes("buds3 pro") || name.includes("galaxy buds 3 pro"))
            return basePath + "galaxy_buds_3_pro.png";
        if (name.includes("galaxy buds 3") || name.includes("buds 3") || name.includes("buds3"))
            return basePath + "galaxy_buds_3.png";
        if (mac === "64_1B_2F_9B_95_CE" || name.includes("s23"))
            return basePath + "samsung_s23.png";
        if (name.includes("s24"))
            return basePath + "samsung_s24_ultra.png";
        if (name.includes("pixel buds") || name.includes("buds pro") || name.includes("buds fe") || name.includes("buds"))
            return basePath + "pixel_buds.png";
        if (name.includes("xbox") || name.includes("elite"))
            return basePath + "xbox_elite_series_2.png";

        return "";
    }
}
