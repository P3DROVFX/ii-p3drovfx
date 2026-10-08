import QtQuick
import QtTest
import qs
import qs.modules.common
import qs.services
import Harness
import "overlay"

/**
 * The screenshot overlay's "Send to <phone>" button, driven through the real
 * ScreenshotOverlayContent with doubles for the shell services it reads.
 *
 * Covered contracts:
 *   - the button shows only with KDE Connect on, a paired reachable phone and
 *     the share plugin
 *   - it sits last in the toolbar, with the phone icon and "Send to <phone>"
 *   - a click copies the region (or the whole capture) and shares that copy
 *   - the overlay stays open until the copy has run, then closes
 *   - a failed copy shares nothing
 */
TestCase {
    id: testCase
    name: "ScreenshotPhoneShare"
    when: windowShown
    visible: true
    width: 800
    height: 400

    readonly property string sourcePath: Directories.assetsPath + "/icons/phone/phone-generic-android.png"
    readonly property string shareDir: Directories.phoneShare

    Component {
        id: overlayComponent
        ScreenshotOverlayContent {}
    }

    SignalSpy {
        id: dismissed
        signalName: "dismissed"
    }

    function init() {
        Harness.reset();
        GlobalStates.screenshotOverlayRegionX = 0;
        GlobalStates.screenshotOverlayRegionY = 0;
        GlobalStates.screenshotOverlayRegionW = 0;
        GlobalStates.screenshotOverlayRegionH = 0;
        KdeConnectService.serviceEnabled = true;
        KdeConnectService.activeReachable = true;
        KdeConnectService.activeDeviceId = "dev-s23";
        KdeConnectService.activeDeviceDisplayName = "S23 de Pedro";
        KdeConnectService.activeDevice = ({ id: "dev-s23", name: "Galaxy S23", paired: true, reachable: true, supportedPlugins: ["kdeconnect_share"] });
    }

    function open(x, y, w, h) {
        GlobalStates.screenshotOverlayRegionX = x;
        GlobalStates.screenshotOverlayRegionY = y;
        GlobalStates.screenshotOverlayRegionW = w;
        GlobalStates.screenshotOverlayRegionH = h;
        GlobalStates.screenshotOverlayImagePath = sourcePath;
        const content = createTemporaryObject(overlayComponent, testCase, { x: 20, y: 20 });
        verify(content !== null);
        // The toolbar slides in from off-window; a click before it lands misses.
        tryCompare(content, "toolbarOffset", 0);
        dismissed.target = content;
        return content;
    }

    function findNamed(item, name) {
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; ++i) {
            const hit = findNamed(item.children[i], name);
            if (hit)
                return hit;
        }
        return null;
    }

    function phoneButton(content) {
        const button = findNamed(content, "phoneShareButton");
        verify(button !== null, "phone button missing from the overlay");
        return button;
    }

    function lastCommand() {
        compare(Harness.started.length, 1);
        return Harness.started[0].command[2];
    }

    function test_hiddenWithoutKdeConnectService() {
        KdeConnectService.serviceEnabled = false;
        const content = open(0, 0, 0, 0);
        verify(!phoneButton(content).visible);
    }

    function test_hiddenWhenPhoneUnreachable() {
        KdeConnectService.activeReachable = false;
        const content = open(0, 0, 0, 0);
        verify(!phoneButton(content).visible);
    }

    function test_hiddenWithoutSharePlugin() {
        KdeConnectService.activeDevice = ({ id: "dev-s23", name: "Galaxy S23", paired: true, reachable: true, supportedPlugins: [] });
        const content = open(0, 0, 0, 0);
        verify(!phoneButton(content).visible);
    }

    function test_shownLastWithPhoneIconAndName() {
        const content = open(0, 0, 0, 0);
        const button = phoneButton(content);
        verify(button.visible);
        compare(button.symbol, "smartphone");
        compare(button.label, "Send to S23 de Pedro");
        const row = button.parent;
        compare(row.children[row.children.length - 1], button);
    }

    function test_clickCropsRegionThenSharesTheCopy() {
        const content = open(40, 30, 320, 180);
        mouseClick(phoneButton(content));

        const cmd = lastCommand();
        verify(cmd.indexOf("magick '" + sourcePath + "' -crop 320x180+40+30 +repage '" + shareDir + "/screenshot-") >= 0, cmd);
        verify(cmd.endsWith(".png'"), cmd);

        // The copy is still running: nothing is shared and the overlay stays up.
        compare(Harness.shares.length, 0);
        compare(dismissed.count, 0);

        Harness.started[0].finish(0);
        compare(Harness.shares.length, 1);
        compare(Harness.shares[0].devId, "dev-s23");
        verify(Harness.shares[0].url.indexOf("file://" + shareDir + "/screenshot-") === 0, Harness.shares[0].url);
        tryCompare(dismissed, "count", 1);
    }

    function test_wholeCaptureIsCopiedWithoutRegion() {
        const content = open(0, 0, 0, 0);
        mouseClick(phoneButton(content));

        const cmd = lastCommand();
        verify(cmd.indexOf(" && cp '" + sourcePath + "' '" + shareDir + "/screenshot-") >= 0, cmd);
        verify(cmd.indexOf("magick") < 0, cmd);
    }

    function test_secondClickWhileCopyingIsIgnored() {
        const content = open(40, 30, 320, 180);
        mouseClick(phoneButton(content));
        mouseClick(phoneButton(content));
        compare(Harness.started.length, 1);
    }

    function test_failedCopyShowsErrorAndSharesNothing() {
        const content = open(40, 30, 320, 180);
        mouseClick(phoneButton(content));
        Harness.started[0].finish(1);

        compare(Harness.shares.length, 0);
        const notice = Harness.execs[Harness.execs.length - 1];
        compare(notice[0], "notify-send");
        verify(notice.indexOf("Could not prepare the screenshot") >= 0, JSON.stringify(notice));
        tryCompare(dismissed, "count", 1);
    }
}
