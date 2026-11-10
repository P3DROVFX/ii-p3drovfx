import QtQuick
import QtTest
import qs.services
import qs.modules.common

/**
 * Which picture a phone shows, decided by the shared service: the photo the user
 * attached to the phone's Bluetooth device first, then the drawing generated for
 * the model, then the generic drawing — and, for the popups, the catalog art
 * below the photo.
 *
 * The service, the phone icon index (assets/icons/phone/index.json) and the
 * catalog art paths are the real ones; only FileView, Config, BluetoothStatus
 * and Directories are doubles (qmltestrunner cannot load the Quickshell plugin).
 */
TestCase {
    id: testCase
    name: "BluetoothDeviceImages"
    when: windowShown

    readonly property string photoFile: "device_64_1B_2F_9B_95_CE.png"
    readonly property string photo: "file://" + Directories.shellConfig + "/bluetooth_images/" + photoFile
    readonly property string modelDrawing: "file://" + Directories.assetsPath + "/icons/phone/phone-samsung-galaxy-s23.png"
    readonly property string ultraDrawing: "file://" + Directories.assetsPath + "/icons/phone/phone-samsung-galaxy-s24-ultra.png"
    readonly property string genericDrawing: "file://" + Directories.assetsPath + "/icons/phone/phone-generic-android.png"
    readonly property string catalogArt: "file://" + Directories.assetsPath + "/images/devices/samsung_s23.png"

    // The phone KDE Connect reports: its Android device_name is the Bluetooth
    // name the user gave it, and the photo is attached to that MAC.
    readonly property var s23: ({ name: "S23 de Pedro", alias: "S23 de Pedro", address: "64:1B:2F:9B:95:CE", paired: true, icon: "phone" })
    // Second paired device carrying a photo, with no phone icon.
    readonly property var buds: ({ name: "Pedro's Buds FE", alias: "Pedro's Buds FE", address: "40:35:E6:31:8B:AC", paired: true, icon: "audio-card" })
    readonly property var otherPhone: ({ name: "Galaxy S21", alias: "Galaxy S21", address: "DE:AD:BE:EF:00:01", paired: true, icon: "phone" })

    function setImages(images) {
        Config.options = { bluetoothDeviceImages: images };
    }

    function setDevices(devices) {
        BluetoothStatus.friendlyDeviceList = devices;
    }

    function init() {
        setImages([{ mac: s23.address, image: photoFile }]);
        setDevices([s23, buds]);
    }

    function test_indexLoadsNormalisedKeys() {
        // The index keys are marketing names ("Galaxy S23"), lookups arrive
        // normalised — an unnormalised map silently resolves nothing.
        compare(BluetoothDeviceImages.modelIcons["galaxys23"], "phone-samsung-galaxy-s23.png");
        compare(BluetoothDeviceImages.modelIconFor("Galaxy S23"), modelDrawing);
        compare(BluetoothDeviceImages.modelIconFor("Samsung Galaxy S24 Ultra"), ultraDrawing);
        compare(BluetoothDeviceImages.modelIconFor(""), "");
        compare(BluetoothDeviceImages.modelIconFor("Some Unknown Phone"), "");
    }

    function test_photoMatchesTheBluetoothName() {
        compare(BluetoothDeviceImages.customImageForPhone("S23 de Pedro"), photo);
        compare(BluetoothDeviceImages.customImageForPhone("s23 de pedro"), photo);
        compare(BluetoothDeviceImages.customImageForPhone("S23"), photo);
    }

    function test_photoOfAnotherDeviceIsNotThePhone() {
        // The buds carry a photo, the phone does not: the phone shows no photo,
        // never the buds'.
        setImages([{ mac: buds.address, image: "device_buds.png" }]);
        compare(BluetoothDeviceImages.customImageForPhone("S23 de Pedro"), "");
    }

    function test_photoFallsBackToTheOnlyPairedPhone() {
        // ADB can report a name the Bluetooth device does not carry; the photo of
        // the single paired phone is still that phone's photo.
        compare(BluetoothDeviceImages.customImageForPhone("Galaxy S23"), photo);

        // Two paired phones on file is ambiguous: never guess between them...
        setImages([
            { mac: s23.address, image: photoFile },
            { mac: otherPhone.address, image: "device_other.png" }
        ]);
        setDevices([s23, buds, otherPhone]);
        compare(BluetoothDeviceImages.customImageForPhone("Galaxy S23"), "");

        // ...but a name match is not a guess.
        compare(BluetoothDeviceImages.customImageForPhone("S23 de Pedro"), photo);
    }

    function test_handWrittenEntryMatchedByName() {
        // Entries are normally written as {mac, image}; a hand-written one may
        // carry only a name, which is matched against the queried name.
        setImages([{ name: "S23 de Pedro", image: "device_hand.png" }]);
        setDevices([s23, buds]);
        compare(BluetoothDeviceImages.customImageForPhone("S23 de Pedro"),
            "file://" + Directories.shellConfig + "/bluetooth_images/device_hand.png");
        compare(BluetoothDeviceImages.customImageForPhone("Galaxy A71"), "");
    }

    function test_phoneImagePrefersPhotoThenModelThenGeneric() {
        compare(BluetoothDeviceImages.phoneImageFor("S23 de Pedro", "Galaxy S23"), photo);

        setImages([]);
        compare(BluetoothDeviceImages.phoneImageFor("S23 de Pedro", "Galaxy S23"), modelDrawing);

        compare(BluetoothDeviceImages.phoneImageFor("S23 de Pedro", "Some Unknown Phone"), genericDrawing);
        compare(BluetoothDeviceImages.phoneImageFor("", ""), genericDrawing);
        compare(BluetoothDeviceImages.genericPhoneIcon, genericDrawing);
    }

    function test_sourceForPhonePutsThePhotoOverCatalogArt() {
        // The popups keep the product shot as their fallback...
        setImages([]);
        compare(BluetoothDeviceImages.sourceForPhone("Galaxy S23"), catalogArt);

        // ...and the user's own photo wins over it.
        setImages([{ mac: s23.address, image: photoFile }]);
        compare(BluetoothDeviceImages.sourceForPhone("Galaxy S23"), photo);
        compare(BluetoothDeviceImages.sourceForPhone("S23 de Pedro"), photo);
    }
}