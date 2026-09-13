.pragma library

/*
 * Pure height allocation for the two sibling surfaces in Media Mode's right
 * column. QML owns the intent and animation; this function only guarantees
 * non-negative target heights that fit the available column.
 */

function _number(value) {
    const numeric = Number(value);
    return isFinite(numeric) ? Math.max(0, numeric) : 0;
}

function resolve(availableHeight, gap, lyricsVisible, queueVisible,
                 lyricsExpanded, queueExpanded, lyricsHeaderHeight,
                 queueHeaderHeight) {
    const height = _number(availableHeight);
    const lyricsHeader = _number(lyricsHeaderHeight);
    const queueHeader = _number(queueHeaderHeight);
    const hasLyrics = Boolean(lyricsVisible);
    const hasQueue = Boolean(queueVisible);

    if (!hasLyrics && !hasQueue)
        return { lyricsHeight: 0, queueHeight: 0, gap: 0 };
    if (hasLyrics && !hasQueue)
        return { lyricsHeight: height, queueHeight: 0, gap: 0 };
    if (!hasLyrics && hasQueue)
        return { lyricsHeight: 0, queueHeight: height, gap: 0 };

    const interGap = Math.min(_number(gap), height);
    const surfaceSpace = Math.max(0, height - interGap);
    const requestedHeaders = lyricsHeader + queueHeader;
    if (requestedHeaders >= surfaceSpace) {
        const lyricsRatio = requestedHeaders > 0 ? lyricsHeader / requestedHeaders : 0.5;
        const compactLyrics = surfaceSpace * lyricsRatio;
        return {
            lyricsHeight: compactLyrics,
            queueHeight: surfaceSpace - compactLyrics,
            gap: interGap,
        };
    }

    const remaining = surfaceSpace - requestedHeaders;
    let effectiveLyrics = Boolean(lyricsExpanded);
    let effectiveQueue = Boolean(queueExpanded);

    // Prevent both panels from being contracted at the same time
    if (!effectiveLyrics && !effectiveQueue) {
        effectiveQueue = true;
    }

    let lyricsBody = 0;
    let queueBody = 0;
    if (effectiveLyrics && effectiveQueue) {
        lyricsBody = remaining * 0.58;
        queueBody = remaining - lyricsBody;
    } else if (effectiveLyrics) {
        lyricsBody = remaining;
    } else if (effectiveQueue) {
        queueBody = remaining;
    }

    return {
        lyricsHeight: lyricsHeader + lyricsBody,
        queueHeight: queueHeader + queueBody,
        gap: interGap,
    };
}
