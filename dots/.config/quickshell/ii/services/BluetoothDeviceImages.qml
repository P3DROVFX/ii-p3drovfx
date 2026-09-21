pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
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

    readonly property string phoneIconDir: Directories.assetsPath ? (Directories.assetsPath + "/icons/phone") : ""
    property var modelIcons: ({})

    FileView {
        path: root.phoneIconDir ? (root.phoneIconDir + "/index.json") : ""
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                root.modelIcons = JSON.parse(text);
            } catch (e) {
                root.modelIcons = {};
            }
        }
    }

    function normaliseModel(name: string): string {
        return (name || "").toLowerCase().replace(/[^a-z0-9+]/g, "").replace(/5g$/, "");
    }

    function modelIconFor(name: string): string {
        const model = normaliseModel(name);
        if (model === "" || !modelIcons)
            return "";
        const exact = modelIcons[model];
        if (exact)
            return "file://" + phoneIconDir + "/" + exact;
        let best = "";
        for (const key in modelIcons) {
            if (key.length < 5 || key.length <= best.length)
                continue;
            if (model.endsWith(key) || key.endsWith(model))
                best = key;
        }
        return best !== "" ? ("file://" + phoneIconDir + "/" + modelIcons[best]) : "";
    }

    /**
     * Dynamically resolves an image for a phone:
     * 1. User's custom image in Config.options.bluetoothDeviceImages (matched to paired Bluetooth phone or name)
     * 2. Built-in device catalog (sourceFor)
     * 3. Model icon from phone icon catalog (index.json)
     */
    function sourceForPhone(displayName): string {
        const name = (displayName || "").toLowerCase();
        const images = Config.options?.bluetoothDeviceImages || [];
        const devices = BluetoothStatus.friendlyDeviceList || [];

        const imageForMac = mac => {
            for (let i = 0; i < images.length; i++) {
                if (images[i].mac === mac && images[i].image)
                    return "file://" + Directories.shellConfig + "/bluetooth_images/" + images[i].image;
            }
            return "";
        };

        // 1. Check friendly Bluetooth devices for match by name, or paired phone
        let pairedPhone = null;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            const btName = (d.name || d.alias || "").toLowerCase();
            const isPhone = (d.icon || "").startsWith("phone");
            const nameMatch = name !== "" && btName !== "" && (btName === name || btName.includes(name) || name.includes(btName));

            if (nameMatch) {
                const custom = imageForMac(d.address);
                if (custom !== "")
                    return custom;
                const builtIn = sourceFor(d);
                if (builtIn !== "")
                    return builtIn;
            } else if (isPhone && d.paired) {
                pairedPhone = d;
            }
        }

        // If not matched by exact name, but there is a paired phone with a custom image
        if (pairedPhone) {
            const custom = imageForMac(pairedPhone.address);
            if (custom !== "")
                return custom;
            const builtIn = sourceFor(pairedPhone);
            if (builtIn !== "")
                return builtIn;
        }

        // 2. Check if any custom image in config has a matching name
        for (let i = 0; i < images.length; i++) {
            if (images[i].image && images[i].name && name !== "" && images[i].name.toLowerCase().includes(name))
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + images[i].image;
        }

        // 3. Built-in device catalog by display name
        if (name !== "") {
            const direct = sourceFor({ name: displayName });
            if (direct !== "")
                return direct;
        }

        // 4. Model icon from dynamic phone catalog (assets/icons/phone/index.json)
        if (name !== "") {
            const modelIcon = modelIconFor(displayName);
            if (modelIcon !== "")
                return modelIcon;
        }

        return "";
    }

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
