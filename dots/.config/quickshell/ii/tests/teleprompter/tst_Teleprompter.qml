import QtQuick
import QtTest
import qs.services
import qs.modules.common

/**
 * The teleprompter engine, offscreen.
 *
 * The service is the real file; Config and Appearance are doubles and the
 * Quickshell module is stubbed just enough for the IpcHandler to exist. The
 * engine's movers — `advance(dtMs)` and `stepCountdown()` — are called
 * directly, so the scroll arithmetic, the countdown, the loop and the clamps
 * are tested without waiting on real time.
 *
 * The session shape under test: buttons load a `ready` session (script on the
 * island, nothing moving); the reader's play runs the countdown and only then
 * scrolls; a finished script holds briefly and gives the island back.
 */
TestCase {
    name: "Teleprompter"

    readonly property var cfg: Config.options.dynamicIsland.widgets.teleprompter

    function init() {
        // Offscreen there is no island surface to push this in; the session
        // gate needs it true.
        Teleprompter.islandEnabled = true;
    }

    function cleanup() {
        Teleprompter.stop();
        cfg.enable = true;
        cfg.lines = 2;
        cfg.expandedLines = 5;
        cfg.width = 520;
        cfg.fontSize = 22;
        cfg.bold = true;
        cfg.speed = 45;
        cfg.loop = false;
        cfg.countdownSeconds = 3;
        cfg.mirror = false;
        cfg.showProgress = true;
        cfg.holdVisible = true;
        cfg.finishHoldSeconds = 4;
        cfg.text = "";
    }

    /** Loads a session the way every entry point does. */
    function load(script) {
        cfg.text = script;
        compare(Teleprompter.start(), true);
        compare(Teleprompter.phase, "ready", "buttons load, they do not launch");
        compare(Teleprompter.scrollY, 0);
    }

    function test_layout_arithmetic() {
        compare(Teleprompter.lines, 2);
        compare(Teleprompter.lineHeightPx, 30);   // round(22 * 1.35)
        compare(Teleprompter.compactBoxHeight, 2 * 30, "the clip has no vertical margin");
        cfg.lines = 4;
        compare(Teleprompter.lines, 4);
        compare(Teleprompter.compactBoxHeight, 4 * 30);
        cfg.fontSize = 40;
        compare(Teleprompter.lineHeightPx, 54);   // round(40 * 1.35)
        // The card outgrows the strip and the hold-to-reveal swell.
        verify(Teleprompter.expandedBoxWidth > Teleprompter.boxWidth * 1.2);
    }

    function test_clamps() {
        cfg.lines = 9;
        compare(Teleprompter.lines, 4);
        cfg.lines = 0;
        compare(Teleprompter.lines, 1);
        cfg.fontSize = 3;
        compare(Teleprompter.fontSize, 12);
        cfg.speed = 0;
        compare(Teleprompter.speed, Teleprompter.speedMin);
        cfg.speed = 900;
        compare(Teleprompter.speed, Teleprompter.speedMax);
        cfg.countdownSeconds = 99;
        compare(Teleprompter.countdownSeconds, 10);
        cfg.width = 10;
        compare(Teleprompter.boxWidth, 280);
        cfg.expandedLines = 1;
        compare(Teleprompter.expandedLines, Teleprompter.lines, "never fewer than the contracted lines");
    }

    function test_start_refuses_without_text_or_island() {
        compare(Teleprompter.start("   "), false);
        compare(Teleprompter.running, false);
        load("a saved script");
        Teleprompter.stop();
        cfg.enable = false;
        compare(Teleprompter.start("anything"), false, "a disabled feature never starts");
    }

    function test_play_runs_countdown_then_scrolls_then_finishes() {
        load("the script");
        Teleprompter.reportLayout(300, 100);
        compare(Teleprompter.scrollExtent, 200);
        compare(Teleprompter.progress, 0, "a ready session shows no progress");
        Teleprompter.togglePause();
        compare(Teleprompter.phase, "countdown");
        compare(Teleprompter.countdownLeft, 3);
        Teleprompter.stepCountdown();
        Teleprompter.stepCountdown();
        compare(Teleprompter.phase, "countdown");
        Teleprompter.stepCountdown();
        compare(Teleprompter.phase, "scrolling");
        compare(Teleprompter.countdownLeft, 0);
        Teleprompter.advance(1000);
        verify(Math.abs(Teleprompter.scrollY - 45) < 3, "one second at 45 px/s");
        Teleprompter.advance(10000);
        compare(Teleprompter.phase, "finished");
        compare(Teleprompter.scrollY, 200, "the end is the extent, never past it");
        compare(Teleprompter.progress, 1);
    }

    function test_loop_wraps_instead_of_finishing() {
        cfg.loop = true;
        load("the script");
        Teleprompter.reportLayout(300, 100);
        Teleprompter.togglePause();
        Teleprompter.stepCountdown();
        Teleprompter.stepCountdown();
        Teleprompter.stepCountdown();
        Teleprompter.advance(100000);
        compare(Teleprompter.phase, "scrolling");
        verify(Teleprompter.scrollY < 200, "wrapped back toward the top");
    }

    function test_script_that_fits_is_read_at_once() {
        cfg.countdownSeconds = 0;
        load("short");
        Teleprompter.reportLayout(50, 100);
        compare(Teleprompter.scrollExtent, 0);
        Teleprompter.togglePause();
        compare(Teleprompter.phase, "finished", "nothing to travel means nothing to wait for");
    }

    function test_script_that_fits_after_countdown_finishes_on_clear() {
        load("short");
        // The face measures while the session is ready: extent is zero before
        // the scroll ever starts.
        Teleprompter.reportLayout(50, 100);
        Teleprompter.togglePause();
        compare(Teleprompter.phase, "countdown");
        Teleprompter.stepCountdown();
        Teleprompter.stepCountdown();
        Teleprompter.stepCountdown();
        compare(Teleprompter.phase, "finished", "nothing to travel means finished at clear");
    }

    function test_nudge_clamps_and_reopens() {
        cfg.countdownSeconds = 0;
        load("the script");
        Teleprompter.reportLayout(300, 100);
        Teleprompter.togglePause();
        compare(Teleprompter.phase, "scrolling");
        Teleprompter.advance(10000);
        compare(Teleprompter.phase, "finished");
        Teleprompter.nudge(500);
        compare(Teleprompter.scrollY, 200, "cannot nudge past the end");
        Teleprompter.nudge(-80);
        compare(Teleprompter.scrollY, 120);
        compare(Teleprompter.phase, "scrolling", "scrolling back up reopens the session");
        Teleprompter.nudge(-5000);
        compare(Teleprompter.scrollY, 0, "cannot nudge before the start");
    }

    function test_pause_resume_and_restart() {
        cfg.countdownSeconds = 0;
        load("the script");
        Teleprompter.reportLayout(300, 100);
        Teleprompter.togglePause();
        compare(Teleprompter.phase, "scrolling");
        Teleprompter.togglePause();
        compare(Teleprompter.paused, true);
        const held = Teleprompter.scrollY;
        Teleprompter.advance(1000);
        compare(Teleprompter.scrollY, held, "a paused script does not move");
        Teleprompter.togglePause();
        compare(Teleprompter.paused, false);
        Teleprompter.advance(10000);
        compare(Teleprompter.phase, "finished");
        cfg.countdownSeconds = 2;
        Teleprompter.togglePause();
        compare(Teleprompter.phase, "countdown", "play on a finished script is a restart");
        compare(Teleprompter.scrollY, 0);
    }

    function test_live_edit_rewrites_the_session() {
        load("first version");
        compare(Teleprompter.text, "first version");
        cfg.text = "second version, edited while reading";
        compare(Teleprompter.text, "second version, edited while reading");
        Teleprompter.stop();
        cfg.text = "edited while idle";
        compare(Teleprompter.text, "", "an idle session keeps no script");
    }

    function test_adjust_speed_persists() {
        const before = cfg.speed;
        Teleprompter.adjustSpeed(5);
        compare(cfg.speed, before + 5);
        Teleprompter.adjustSpeed(-1000);
        compare(cfg.speed, Teleprompter.speedMin, "the persisted speed is clamped too");
    }
}
