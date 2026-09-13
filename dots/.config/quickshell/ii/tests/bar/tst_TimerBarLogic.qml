import QtQuick 2.15
import QtTest 1.3
import "../../modules/ii/bar/widgets/timer/TimerBarLogic.js" as TimerBarLogic

TestCase {
    name: "TimerBarLogic"

    function secondsLeft(countdown) {
        return Number((countdown && countdown.left) || 0);
    }

    function test_prioritizes_running_timer_with_nearest_deadline() {
        const countdowns = [
            { id: "paused", paused: true, left: 5, endsAt: 5 },
            { id: "later", paused: false, left: 120, endsAt: 120 },
            { id: "done", notified: true, left: 1, endsAt: 1 },
            { id: "next", paused: false, left: 30, endsAt: 30 }
        ];

        const result = TimerBarLogic.prioritizedCountdowns(countdowns, secondsLeft);

        compare(result.length, 3);
        compare(result[0].id, "next");
        compare(result[1].id, "later");
        compare(result[2].id, "paused");
    }

    function test_deadline_breaks_equal_remaining_time() {
        const countdowns = [
            { id: "second", paused: false, left: 30, endsAt: 200 },
            { id: "first", paused: false, left: 30, endsAt: 100 }
        ];

        const result = TimerBarLogic.prioritizedCountdowns(countdowns, secondsLeft);
        compare(result[0].id, "first");
    }

    function test_formats_timer_values_with_stable_width() {
        compare(TimerBarLogic.formatClock(65), "01:05");
        compare(TimerBarLogic.formatStopwatch(12345), "02:03.45");
        compare(TimerBarLogic.formatCountdown(65, 300), "01:05");
        compare(TimerBarLogic.formatCountdown(3599, 3599), "59:59");
        compare(TimerBarLogic.formatCountdown(3600, 3600), "1:00:00");
        compare(TimerBarLogic.formatCountdown(3599, 3600), "0:59:59");
        compare(TimerBarLogic.formatCountdown(-4, 300), "00:00");
    }
}
