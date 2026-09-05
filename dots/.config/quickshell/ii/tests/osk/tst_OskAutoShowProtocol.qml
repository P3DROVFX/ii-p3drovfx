import QtQuick
import QtTest
import "../../services/OskAutoShowProtocol.js" as OskProtocol

TestCase {
    name: "OskAutoShowProtocol"

    // ── Parsing the daemon's lines ────────────────────────────────────────

    function test_focus_lines() {
        compare(OskProtocol.parseLine("activate").kind, "activate");
        compare(OskProtocol.parseLine("deactivate").kind, "deactivate");
        compare(OskProtocol.parseLine("key").kind, "key");
        compare(OskProtocol.parseLine("unavailable").kind, "unavailable");
        // SplitParser hands lines over without their newline, but not always without
        // trailing whitespace.
        compare(OskProtocol.parseLine("  activate \n").kind, "activate");
    }

    function test_pointer_lines_carry_their_kind_and_position() {
        const touch = OskProtocol.parseLine("touch 0.5000 0.8125");
        compare(touch.kind, "pointer");
        compare(touch.pointer, "touch");
        compare(touch.x, 0.5);
        compare(touch.y, 0.8125);

        compare(OskProtocol.parseLine("pen 0.1 0.2").pointer, "pen");

        // A relative pointer has no position; -1 is the daemon's "unknown".
        const mouse = OskProtocol.parseLine("mouse -1 -1");
        compare(mouse.pointer, "mouse");
        compare(mouse.x, -1);
    }

    function test_the_inventory_line() {
        const report = OskProtocol.parseLine("devices 1 1 2");
        compare(report.kind, "devices");
        compare(report.touch, 1);
        compare(report.pen, 1);
        compare(report.mouse, 2);

        // A machine with no touch panel: the case the feature used to fail silently in.
        compare(OskProtocol.parseLine("devices 0 0 6").touch, 0);
        // Truncated or malformed counts read as zero rather than NaN.
        compare(OskProtocol.parseLine("devices").touch, 0);
    }

    function test_permission_and_unknown_lines() {
        compare(OskProtocol.parseLine("denied").kind, "denied");
        compare(OskProtocol.parseLine("").kind, "unknown");
        compare(OskProtocol.parseLine("something else entirely").kind, "unknown");
        compare(OskProtocol.parseLine(null).kind, "unknown");
    }

    // ── Which pointers are allowed to raise the keyboard ──────────────────

    function test_touch_and_pen_default_on_and_the_mouse_defaults_off() {
        // What the service sees before Config.options.osk exists.
        verify(OskProtocol.pointerAllowed("touch", null));
        verify(OskProtocol.pointerAllowed("pen", null));
        verify(!OskProtocol.pointerAllowed("mouse", null));
        verify(!OskProtocol.pointerAllowed("keyboard", null));
    }

    function test_each_kind_answers_to_its_own_switch() {
        const opts = { allowTouch: false, allowPen: false, allowMouse: true };
        verify(!OskProtocol.pointerAllowed("touch", opts));
        verify(!OskProtocol.pointerAllowed("pen", opts));
        verify(OskProtocol.pointerAllowed("mouse", opts));
    }

    // ── Whether anything on this machine can trigger it ───────────────────

    function test_a_tablet_can_trigger_it() {
        verify(OskProtocol.anyTriggerDevice({ touch: 1, pen: 1, mouse: 0 }, {}));
        verify(OskProtocol.anyTriggerDevice({ touch: 0, pen: 1, mouse: 0 }, {}));
    }

    function test_a_machine_with_only_mice_cannot_unless_asked() {
        // Exactly what this laptop reports, and exactly why turning the switch on
        // appeared to do nothing at all.
        const desktop = { touch: 0, pen: 0, mouse: 6 };
        verify(!OskProtocol.anyTriggerDevice(desktop, {}));
        verify(OskProtocol.anyTriggerDevice(desktop, { allowMouse: true }));
    }

    function test_switching_every_kind_off_is_the_same_as_having_no_device() {
        const tablet = { touch: 1, pen: 1, mouse: 1 };
        verify(!OskProtocol.anyTriggerDevice(tablet,
            { allowTouch: false, allowPen: false, allowMouse: false }));
        verify(!OskProtocol.anyTriggerDevice({ touch: 0, pen: 0, mouse: 0 }, { allowMouse: true }));
        verify(!OskProtocol.anyTriggerDevice(null, {}));
    }
}
