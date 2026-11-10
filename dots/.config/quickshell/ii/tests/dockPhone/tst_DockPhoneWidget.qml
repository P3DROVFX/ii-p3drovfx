import QtQuick
import QtTest
import qs.modules.common
import qs.services
import "dock"

/**
 * The dock phone shortcut's picture, driven end to end: the real widget and the
 * real BluetoothDeviceImages service, with doubles only for the services the
 * widget reads and for the pieces that need a Wayland session.
 *
 * Covered contracts:
 *   - a photo attached to the phone's Bluetooth device replaces the drawing
 *   - without one, the drawing of the model KDE Connect reports is used
 *   - an unknown model falls back to the generic drawing
 *   - a drawing takes the full app-tile button, a photo the tighter box
 */
TestCase {
    id: testCase
    name: "DockPhoneWidget"
    when: windowShown
    width: 200
    height: 200

    readonly property string photoFile: "device_64_1B_2F_9B_95_CE.png"
    readonly property string photo: "file://" + Directories.shellConfig + "/bluetooth_images/" + photoFile
    readonly property string modelDrawing: "file://" + Directories.assetsPath + "/icons/phone/phone-samsung-galaxy-s23.png"
    readonly property string genericDrawing: "file://" + Directories.assetsPath + "/icons/phone/phone-generic-android.png"
    readonly property real buttonSize: Appearance.sizes.dockButtonSize

    // The phone KDE Connect reports: Android's device_name is the Bluetooth
    // name the user gave it, and the photo is attached to that MAC.
    readonly property var s23: ({ name: "S23 de Pedro", alias: "S23 de Pedro", address: "64:1B:2F:9B:95:CE", paired: true, icon: "phone" })
    readonly property var buds: ({ name: "Pedro's Buds FE", alias: "Pedro's Buds FE", address: "40:35:E6:31:8B:AC", paired: true, icon: "audio-card" })

    Component {
        id: widgetComponent
        DockPhoneWidget {
            dockContent: null
        }
    }

    function setImages(images) {
        Config.options = {
            dock: { height: 60, enableAppTooltip: false, launchAnimation: "bounce" },
            bluetoothDeviceImages: images
        };
    }

    function setKdeDevice(name) {
        KdeConnectService.activeDeviceId = "kde-s23";
        KdeConnectService.activeReachable = true;
        KdeConnectService.activeDevice = { name: name, charge: 64 };
        KdeConnectService.activeDeviceDisplayName = "S23 de Pedro";
    }

    function init() {
        setImages([{ mac: s23.address, image: photoFile }]);
        BluetoothStatus.friendlyDeviceList = [s23, buds];
        setKdeDevice("Galaxy S23");
    }

    function findPhoneIcon(item) {
        if (item.source !== undefined && item.fillMode !== undefined)
            return item;
        for (const child of item.children ?? []) {
            const found = findPhoneIcon(child);
            if (found)
                return found;
        }
        return null;
    }

    function test_photoReplacesTheDrawing() {
        const widget = createTemporaryObject(widgetComponent, testCase);
        verify(widget);

        compare(widget.deviceImageSource, photo);
        compare(widget.generatedIcon, false);

        const icon = findPhoneIcon(widget);
        verify(icon);
        compare(icon.source, photo);
        tryCompare(icon, "status", Image.Ready);
        // The photo keeps the tighter box; the drawing takes the whole button.
        compare(icon.parent.width, buttonSize * 0.86);
        compare(icon.parent.height, buttonSize * 0.92);
    }

    function test_drawingOfTheReportedModel() {
        setImages([]);
        const widget = createTemporaryObject(widgetComponent, testCase);
        verify(widget);

        compare(widget.deviceImageSource, modelDrawing);
        compare(widget.generatedIcon, true);

        const icon = findPhoneIcon(widget);
        compare(icon.source, modelDrawing);
        tryCompare(icon, "status", Image.Ready);
        compare(icon.parent.width, buttonSize);
        compare(icon.parent.height, buttonSize);
    }

    function test_genericDrawingForAnUnknownModel() {
        setImages([]);
        setKdeDevice("Some Unknown Phone");
        const widget = createTemporaryObject(widgetComponent, testCase);
        verify(widget);

        compare(widget.deviceImageSource, genericDrawing);
        compare(widget.generatedIcon, true);
        compare(findPhoneIcon(widget).source, genericDrawing);
    }
}