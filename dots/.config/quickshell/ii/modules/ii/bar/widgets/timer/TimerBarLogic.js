.pragma library

function prioritizedCountdowns(countdowns, secondsLeft) {
    const active = Array.from(countdowns || [])
        .filter(countdown => !(countdown && countdown.notified));
    active.sort((a, b) => {
        const aPaused = Boolean(a && a.paused);
        const bPaused = Boolean(b && b.paused);
        if (aPaused !== bPaused)
            return aPaused ? 1 : -1;

        const aLeft = secondsLeft(a);
        const bLeft = secondsLeft(b);
        if (aLeft !== bLeft)
            return aLeft - bLeft;
        return Number((a && a.endsAt) || 0) - Number((b && b.endsAt) || 0);
    });
    return active;
}

function formatClock(seconds) {
    const safe = Math.max(0, Math.floor(Number(seconds) || 0));
    return String(Math.floor(safe / 60)).padStart(2, "0")
        + ":" + String(safe % 60).padStart(2, "0");
}

function formatStopwatch(time) {
    const safe = Math.max(0, Math.floor(Number(time) || 0));
    const seconds = Math.floor(safe / 100);
    return String(Math.floor(seconds / 60)).padStart(2, "0")
        + ":" + String(seconds % 60).padStart(2, "0")
        + "." + String(safe % 100).padStart(2, "0");
}

function formatCountdown(seconds, originalDuration) {
    const safe = Math.max(0, Math.floor(Number(seconds) || 0));
    const duration = Math.max(0, Math.floor(Number(originalDuration) || 0));
    if (duration < 3600)
        return formatClock(safe);

    const hours = Math.floor(safe / 3600);
    const minutes = Math.floor((safe % 3600) / 60);
    const secs = safe % 60;
    return String(hours) + ":" + String(minutes).padStart(2, "0")
        + ":" + String(secs).padStart(2, "0");
}
