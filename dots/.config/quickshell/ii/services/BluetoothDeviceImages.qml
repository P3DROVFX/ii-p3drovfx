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
 * Telephones get their own two chains, both starting with the user's photo:
 * `phoneImageFor` (photo → model drawing → generic drawing) for surfaces that
 * draw the phone itself, and `sourceForPhone` (photo → built-in catalog art →
 * model drawing) for the popups, which show a product shot.
 *
 * The popups carry older private copies of this lookup; new surfaces use this and
 * the copies retire as those surfaces are touched.
 */
Singleton {
    id: root

    readonly property string phoneIconDir: Directories.assetsPath ? (Directories.assetsPath + "/icons/phone") : ""
    readonly property string genericPhoneIcon: phoneIconDir ? ("file://" + phoneIconDir + "/phone-generic-android.png") : ""
    property var modelIcons: ({})

    FileView {
        path: root.phoneIconDir ? (root.phoneIconDir + "/index.json") : ""
        // Only rewritten by assets/icons/phone/generate_phones.py; a shell reload
        // picks up a new index.
        watchChanges: false
        printErrors: false
        onLoaded: {
            // The index keys are marketing names ("Galaxy S24 Ultra"); lookups come
            // in normalised, so the map is keyed normalised too.
            let map = {};
            try {
                const index = JSON.parse(text());
                for (const name in index)
                    map[root.normaliseModel(name)] = index[name];
            } catch (e) {
                console.warn("[BluetoothDeviceImages] bad phone icon index:", e);
            }
            root.modelIcons = map;
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

    /** The user's own photo for a Bluetooth address, or "" when there is none. */
    function customPhotoForMac(mac): string {
        const images = Config.options?.bluetoothDeviceImages || [];
        for (let i = 0; i < images.length; i++) {
            if (images[i].mac === mac && images[i].image)
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + images[i].image;
        }
        return "";
    }

    /**
     * The user's own photo for a phone, or "" when they never attached one. The
     * Bluetooth device is matched by name (either side containing the other);
     * failing that, the photo of the paired phone is used only when exactly one
     * paired phone carries one — never a guess between two. A hand-written
     * entry's optional `name` is honoured last.
     */
    function customImageForPhone(displayName): string {
        const name = (displayName || "").toLowerCase();
        const devices = BluetoothStatus.friendlyDeviceList || [];
        let pairedPhoto = "";
        let pairedPhones = 0;

        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            const photo = customPhotoForMac(d.address);
            if (photo === "")
                continue;
            const btName = (d.name || d.alias || "").toLowerCase();
            if (name !== "" && btName !== "" && (btName === name || btName.includes(name) || name.includes(btName)))
                return photo;
            if (d.paired && (d.icon || "").startsWith("phone")) {
                pairedPhones++;
                pairedPhoto = photo;
            }
        }

        if (pairedPhones === 1)
            return pairedPhoto;

        const images = Config.options?.bluetoothDeviceImages || [];
        for (let i = 0; i < images.length; i++) {
            if (images[i].image && images[i].name && name !== "" && images[i].name.toLowerCase().includes(name))
                return "file://" + Directories.shellConfig + "/bluetooth_images/" + images[i].image;
        }

        return "";
    }

    /**
     * The picture of a phone for a surface that draws the phone itself: the
     * user's own photo first, then the generated drawing of the model, then the
     * generic Android drawing. Both drawings live in assets/icons/phone and
     * share the app tiles' 64-grid, so the caller can size them like an app
     * icon; the catalog art of `sourceFor` stays out of this chain because it is
     * a product shot, not a tile-sized drawing.
     */
    function phoneImageFor(displayName, modelName): string {
        const custom = customImageForPhone(displayName);
        if (custom !== "")
            return custom;
        const model = modelIconFor(modelName);
        if (model !== "")
            return model;
        return genericPhoneIcon;
    }

    /**
     * Dynamically resolves an image for a phone:
     * 1. User's custom image in Config.options.bluetoothDeviceImages (matched to paired Bluetooth phone or name)
     * 2. Built-in device catalog (sourceFor)
     * 3. Model icon from phone icon catalog (index.json)
     */
    function sourceForPhone(displayName): string {
        const name = (displayName || "").toLowerCase();
        const devices = BluetoothStatus.friendlyDeviceList || [];

        // 1. The user's own photo for this phone wins over any built-in art
        const custom = customImageForPhone(displayName);
        if (custom !== "")
            return custom;

        // 2. Built-in catalog art for the device the name matches, else for the
        //    paired phone
        let pairedPhone = null;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            const btName = (d.name || d.alias || "").toLowerCase();
            const isPhone = (d.icon || "").startsWith("phone");
            const nameMatch = name !== "" && btName !== "" && (btName === name || btName.includes(name) || name.includes(btName));

            if (nameMatch) {
                const builtIn = sourceFor(d);
                if (builtIn !== "")
                    return builtIn;
            } else if (isPhone && d.paired) {
                pairedPhone = d;
            }
        }

        if (pairedPhone) {
            const builtIn = sourceFor(pairedPhone);
            if (builtIn !== "")
                return builtIn;
        }

        // 3. Built-in device catalog by display name, then the model drawing
        if (name !== "") {
            const direct = sourceFor({ name: displayName });
            if (direct !== "")
                return direct;
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
