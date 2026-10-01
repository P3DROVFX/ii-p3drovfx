import QtQuick
import QtTest
import "../../modules/ii/dock/DockMagnification.js" as DockMagnification

// The dock's lens is one shared pointer spring plus one shared grow-in spring,
// and every item's slot on the dock is derived from its weight in the field.
// Both halves are pure math in DockMagnification.js because DockContent.qml is
// far too large to instantiate here; the properties this file pins down are the
// ones a user can feel with the mouse:
//   - the lens glides instead of snapping,
//   - its trailing is the configured lag, not an accident of frame times,
//   - a magnifying item pushes its neighbours by exactly the room it takes,
//   - a wide widget moves less than an icon without ever being drawn over.
TestCase {
    name: "DockMagnification"

    // ── Lens dynamics ─────────────────────────────────────────────────────

    // The whole point of the spring: it approaches from one side. An overshoot
    // at icon scale is a snap, not physics — the icon grows past the cursor and
    // comes back, which is exactly what the old behaviour was complained about.
    function test_spring_approaches_without_overshoot() {
        const omega = DockMagnification.trackingOmega(90);
        const target = 120;
        let position = 0;
        let velocity = 0;
        let previous = 0;
        for (let i = 0; i < 600; i++) {
            const step = DockMagnification.springStep(position, velocity, target, omega, 1 / 60);
            position = step.position;
            velocity = step.velocity;
            verify(position >= previous - 0.0001, "went backwards at frame " + i);
            verify(position <= target + 0.0001, "overshot to " + position + " at frame " + i);
            previous = position;
        }
        verify(Math.abs(position - target) < 0.01, "settled at " + position);
    }

    // The profile value has to be the real trailing: a tracking spring settles
    // at 2v/w behind its target, so trackingOmega(lag) means the cursor leads
    // the lens by lag * speed. This is what "the lens is slower now" means
    // numerically. Each step holds the target still for one frame, which at
    // this speed reads as half a frame less trailing — expected, not a bug.
    function test_trailing_matches_the_configured_lag() {
        const lagMs = 100;
        const speed = 1000; // main-axis units per second
        const omega = DockMagnification.trackingOmega(lagMs);
        const dt = 1 / 60;
        let position = 0;
        let velocity = 0;
        let time = 0;
        for (let i = 0; i < 1200; i++) {
            time += dt;
            const step = DockMagnification.springStep(position, velocity, speed * time, omega, dt);
            position = step.position;
            velocity = step.velocity;
        }
        const trailing = speed * time - position;
        const expected = speed * (lagMs / 1000) - speed * dt / 2;
        verify(Math.abs(trailing - expected) < 1, "trailed by " + trailing + ", expected " + expected);
    }

    // The spring is integrated exactly, so a stalled frame is absorbed instead
    // of throwing the lens (and with it every icon's geometry) past the cursor.
    function test_frame_time_cannot_launch_the_lens() {
        const omega = DockMagnification.trackingOmega(90);
        const target = 250;
        const long = DockMagnification.springStep(0, 0, target, omega, 0.1);
        verify(long.position > 0 && long.position <= target);
        // A frame time beyond the clamp behaves as the clamp, not as a leap.
        const absurd = DockMagnification.springStep(0, 0, target, omega, 4);
        verify(Math.abs(absurd.position - long.position) < 0.0001);
    }

    // Settling is bounded by the profile too: a step is within 2% of its target
    // at `settleMs`, which is what makes the enter/exit feel deliberate rather
    // than instant — and it is genuinely not there yet halfway through.
    function test_settle_time_is_the_configured_one() {
        const settleMs = 240;
        const omega = DockMagnification.settleOmega(settleMs);
        const dt = 1 / 480;
        let position = 0;
        let velocity = 0;
        let halfway = 0;
        const steps = Math.round((settleMs / 1000) / dt);
        for (let i = 0; i < steps; i++) {
            const step = DockMagnification.springStep(position, velocity, 1, omega, dt);
            position = step.position;
            velocity = step.velocity;
            if (i === Math.floor(steps / 2))
                halfway = position;
        }
        verify(position >= 0.98, "only grew to " + position);
        verify(position <= 1);
        verify(halfway < 0.95, "was already at " + halfway + " halfway through");
    }

    // ── Influence field ───────────────────────────────────────────────────

    // An item enters the field from nothing. Cosine is the default curve, and
    // it has to reach exactly zero at the radius so an item is not already
    // magnified when the lens arrives.
    function test_field_ends_at_the_radius() {
        compare(DockMagnification.factorForDistance(0, 200, "cosine"), 1);
        compare(DockMagnification.factorForDistance(200, 200, "cosine"), 0);
        compare(DockMagnification.factorForDistance(2000, 200, "cosine"), 0);
        verify(Math.abs(DockMagnification.factorForDistance(100, 200, "cosine") - 0.5) < 0.0001);
        compare(DockMagnification.factorForDistance(0, 200, "gaussian"), 1);
        compare(DockMagnification.factorForDistance(200, 200, "gaussian"), 0);
        verify(DockMagnification.factorForDistance(199, 200, "gaussian") < 0.05);
    }

    // The lens holds its items with its own strength: an item in front of the
    // pointer is not fully magnified until the lens has grown in.
    function test_weight_carries_the_lens_strength() {
        compare(DockMagnification.weightForDistance(0, 200, "cosine", 1), 1);
        compare(DockMagnification.weightForDistance(0, 200, "cosine", 0), 0);
        compare(DockMagnification.weightForDistance(0, 200, "cosine", 0.5), 0.5);
        compare(DockMagnification.weightForDistance(200, 200, "cosine", 1), 0);
    }

    // ── Layout ────────────────────────────────────────────────────────────

    // The one invariant the dock layout depends on: a slot grows by exactly the
    // amount its content grows. Less and the magnified item is drawn over its
    // neighbours; more and a gap opens under the cursor.
    function test_slot_growth_matches_content_growth() {
        const cases = [
            { extent: 48, factor: 1.0 },      // an app icon
            { extent: 3 * 66, factor: 0.5 },  // the media/weather card
            { extent: 4 * 66, factor: 0.4 }   // the sports card
        ];
        for (const entry of cases) {
            for (const weight of [0, 0.25, 0.5, 1]) {
                const grown = entry.extent * (DockMagnification.contentScale(weight, 1.5, entry.factor) - 1);
                const extra = DockMagnification.layoutExtra(weight, 1.5, entry.extent, entry.factor, true);
                verify(Math.abs(extra - grown) < 0.0001, "extent " + entry.extent + " weight " + weight);
            }
        }
    }

    // A single icon keeps the geometry the dock had before widgets joined the
    // lens: dockButtonSize * (scale - 1) * weight.
    function test_single_icon_keeps_its_geometry() {
        compare(DockMagnification.layoutExtra(1, 1.5, 48, 1, true), 24);
        compare(DockMagnification.layoutExtra(0.5, 1.5, 48, 1, true), 12);
        compare(DockMagnification.contentScale(0.5, 1.5, 1), 1.25);
    }

    // A widget body is magnified, but at a muted share: the same linear factor
    // on a 3-slot card would sweep the neighbours several times as far as an
    // icon does.
    function test_widget_bodies_stay_muted() {
        compare(DockMagnification.contentScale(1, 1.5, 0.5), 1.25);
        compare(DockMagnification.contentScale(1, 1.5, 0), 1);
        verify(DockMagnification.contentScale(1, 1.5, 0.5) < DockMagnification.contentScale(1, 1.5, 1));
    }

    // The spacing switch only turns the layout room off; the content still
    // follows the lens (used by the reserve, and by a dock with fixed spacing).
    function test_dynamic_spacing_only_gates_the_extra() {
        compare(DockMagnification.layoutExtra(1, 1.5, 48, 1, false), 0);
        compare(DockMagnification.contentScale(1, 1.5, 1), 1.5);
    }

    // A frozen lens or a stale sample must never scale an item past the
    // configured maximum.
    function test_weight_is_clamped() {
        compare(DockMagnification.contentScale(4, 1.5, 1), 1.5);
        compare(DockMagnification.contentScale(-1, 1.5, 1), 1);
        compare(DockMagnification.layoutExtra(-1, 1.5, 48, 1, true), 0);
        compare(DockMagnification.weightForDistance(0, 200, "cosine", 3), 1);
    }
}
