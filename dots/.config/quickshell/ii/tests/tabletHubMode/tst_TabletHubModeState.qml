import QtQuick
import QtTest
import "../../modules/tablet/hubMode/TabletHubModeState.js" as HubState

TestCase {
    name: "TabletHubModeState"

    // Hub mode switched on, plugged in, untouched, nothing playing: the state the
    // surface is meant to appear in.
    function docked(overrides) {
        const state = {
            enable: true,
            requireCharging: true,
            batteryAvailable: true,
            pluggedIn: true,
            idle: true,
            dismissed: false,
            pauseWhilePlaying: true,
            mediaPlaying: false,
            screenLocked: false,
            previewRequested: false
        };
        for (const key in (overrides || {}))
            state[key] = overrides[key];
        return state;
    }

    // ── The preview, which is what this feature was missing ───────────────

    function test_a_preview_shows_it_with_the_feature_switched_off() {
        // The circle being broken: you had to turn hub mode on, plug in a cable and
        // wait out the idle timer to find out whether you wanted it on.
        const off = docked({
            enable: false,
            pluggedIn: false,
            idle: false,
            previewRequested: true
        });
        verify(HubState.shouldShow(off));
        verify(HubState.previewing(off));
        // A preview is not the device arming itself; nothing latched.
        verify(!HubState.armed(off));
    }

    function test_a_preview_survives_media_and_a_previous_dismissal() {
        verify(HubState.shouldShow(docked({ previewRequested: true, mediaPlaying: true })));
        verify(HubState.shouldShow(docked({ previewRequested: true, dismissed: true })));
    }

    function test_the_lock_screen_beats_a_preview() {
        // The session lock covers every layer, so a preview underneath it would be a
        // request that silently never draws.
        const locked = docked({ previewRequested: true, screenLocked: true });
        verify(!HubState.previewing(locked));
        verify(!HubState.shouldShow(locked));
    }

    // ── The automatic trigger ─────────────────────────────────────────────

    function test_it_takes_over_when_docked_and_idle() {
        verify(HubState.shouldShow(docked()));
        verify(!HubState.shouldShow(docked({ idle: false })));
        verify(!HubState.shouldShow(docked({ enable: false })));
        verify(!HubState.shouldShow(docked({ dismissed: true })));
    }

    function test_the_charging_requirement() {
        verify(!HubState.shouldShow(docked({ pluggedIn: false })));
        // Dropped on purpose: a desk display has no cable state worth waiting for.
        verify(HubState.shouldShow(docked({ pluggedIn: false, requireCharging: false })));
        // No battery at all is mains power, not "not charging".
        verify(HubState.shouldShow(docked({ pluggedIn: false, batteryAvailable: false })));
    }

    function test_playback_holds_the_screen_only_while_asked_to() {
        verify(!HubState.shouldShow(docked({ mediaPlaying: true })));
        verify(HubState.shouldShow(docked({ mediaPlaying: true, pauseWhilePlaying: false })));
        verify(HubState.mediaHolding(docked({ mediaPlaying: true })));
    }

    function test_nothing_shows_before_config_loads() {
        // What the Scope sees at startup: no options, so `enable` is absent.
        verify(!HubState.shouldShow({}));
        verify(!HubState.armed({}));
    }
}
