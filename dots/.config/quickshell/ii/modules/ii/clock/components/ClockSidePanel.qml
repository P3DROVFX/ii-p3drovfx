import QtQuick
import qs.modules.common

/**
 * Host for the app's side sheets. One sheet at a time: `show()` builds it from a
 * Component with its initial properties (so its own Component.onCompleted already sees
 * them), `close()` lets the rail slide shut and frees the sheet once it has.
 *
 * The slot around this item owns the width animation (see ClockAppContent); this item
 * keeps a fixed width anchored to the slot's right edge, so the sheet slides in rather
 * than reflowing while it opens.
 */
Item {
    id: root

    property Item current: null
    /// The window's time/date pickers (ClockPickerHost); sheets reach them through here.
    property Item pickers: null
    property bool open: false
    /// The component the open sheet came from, so a caller can tell its own sheet apart.
    property var currentSource: null

    signal closed()

    function show(component: Component, props): Item {
        releaseTimer.stop();
        root.destroyCurrent();
        const initial = Object.assign({}, props ?? {});
        initial.host = root;
        const sheet = component.createObject(frame, initial);
        if (!sheet)
            return null;
        root.current = sheet;
        root.currentSource = component;
        sheet.closeRequested.connect(root.close);
        root.open = true;
        sheet.forceActiveFocus();
        return sheet;
    }

    function close(): void {
        if (!root.open)
            return;
        root.open = false;
        releaseTimer.restart();
        root.closed();
    }

    /// Tab switches drop the sheet at once: it was built in the old tab's context.
    function closeNow(): void {
        releaseTimer.stop();
        root.open = false;
        root.destroyCurrent();
    }

    function isShowing(component: Component): bool {
        return root.open && root.currentSource === component;
    }

    function destroyCurrent(): void {
        if (root.current) {
            root.current.destroy();
            root.current = null;
            root.currentSource = null;
        }
    }

    Timer {
        id: releaseTimer
        interval: ClockStyle.motionDefault.duration + 80
        onTriggered: {
            if (!root.open)
                root.destroyCurrent();
        }
    }

    Item {
        id: frame
        anchors.fill: parent
    }
}
