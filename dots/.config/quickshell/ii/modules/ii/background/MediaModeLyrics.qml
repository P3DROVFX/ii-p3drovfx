import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

// Focused five-row lyrics presentation used exclusively by the background Media Mode.
// Blur follows physical distance from the viewport center, keeping retargets coherent.
// Row motion follows PixelPlayer's animated lyrics: cubic parallax, and a verse change
// that ripples through the rows as a slow chain with a soft bounce.
Item {
    id: root

    clip: true

    // Size of a *resting* line. The centred line is this scaled by
    // focusedFontSizeMultiplier, so the gap between the two is the transition.
    property var player: null
    property real largeFontSize: Appearance.font.pixelSize.hugeass * 1.3
    property color activeColor: Appearance.colors.colPrimary
    // Immersive draws over artwork and passes a fixed light palette.
    property color textColor: Appearance.colors.colOnLayer0
    property color dimTextColor: Appearance.colors.colSubtext
    // Upper clamp only: the effective duration is derived per line from the
    // song's own cadence, so fast tracks stop dragging through a fixed 2s scroll.
    property int rowTransitionDuration: 1400
    property int minimumRowTransitionDuration: 320
    // Share of a line's on-screen time the scroll into it is allowed to consume.
    property real rowTransitionPaceFactor: 0.7
    property real nearBlurRadius: 10
    property real farBlurRadius: 32
    property real rowSpacingFactor: 1.0
    property real focusedFontSizeMultiplier: 1.0
    property int maximumLyricLines: 3
    property real baseFontWeight: 700
    property real focusedFontWeight: 700
    property real focusedFontGrade: 100
    property real minimumRowOpacity: 0.24
    property real rowOpacityFalloff: 0.34
    // Top/bottom fade: how much of the viewport each edge dissolves over.
    property real edgeFadeFraction: 0.16
    property real focusReveal: hasCurrentLine ? 1 : 0
    // Verse change: every row travels its own offset back to rest, starting a
    // little after the row before it (the chain), and settles with a soft overshoot.
    property int chainStaggerMs: 80
    property int chainMaximumRank: 6
    property int chainMinimumDuration: 900
    property int chainMaximumDuration: 1800
    property real chainDurationFactor: 1.15
    // Ease in and out, almost linear in between. The second control point sits a
    // little above 1, which is the whole bounce: the row overshoots, then settles.
    property real bounceLevel: 1.08
    // Words not yet sung keep this share of the line colour.
    property real unsungWordOpacity: 0.38

    readonly property int halfVisibleLines: 2
    readonly property int visibleLineCount: halfVisibleLines * 2 + 1
    readonly property int currentIndex: LyricsService.currentIndex
    readonly property bool hasCurrentLine: currentIndex >= 0
    readonly property real layoutFontSize: largeFontSize * focusedFontSizeMultiplier
    // A row only decides spacing. Text is laid out inside a centered box so
    // that rows distribute naturally and never clip or overlap.
    readonly property real rowContentHeight: Math.ceil(layoutFontSize * 1.3) * maximumLyricLines
    // Vertical spacing with compact, elegant rhythm for both single and multi-line lyrics.
    readonly property real rowHeight: {
        if (root.height <= 0) return layoutFontSize * 2.4;
        const target = (height / visibleLineCount) * (root.height < 460 ? 1.18 : 0.95);
        return Math.max(layoutFontSize * 2.2, Math.min(layoutFontSize * 3.6, target));
    }
    readonly property real viewportEdgePadding: Math.max(0, height / 2 - rowHeight / 2)
    readonly property real playbackRate: Math.max(0.25, player?.rate ?? 1)
    // Median gap between synced lines, i.e. this track's own lyric cadence.
    readonly property real songPaceMs: {
        const lines = LyricsService.syncedLines;
        if (!lines || lines.length < 3)
            return 0;

        const gaps = [];
        for (let i = 1; i < lines.length; i++) {
            const gap = (lines[i].time - lines[i - 1].time) * 1000;
            if (isFinite(gap) && gap > 120 && gap < 20000)
                gaps.push(gap);
        }
        if (gaps.length === 0)
            return 0;

        gaps.sort((a, b) => a - b);
        return gaps[Math.floor(gaps.length / 2)];
    }
    readonly property real parallaxMaximum: Appearance.font.pixelSize.hugeass * 1.75
    // Verse-change state shared with the rows. chainDelta is the distance the
    // list jumped (rows start displaced by it); chainActive covers rows that are
    // created while the ripple is still travelling.
    property real chainDelta: 0
    property int chainDirection: 1
    property bool chainActive: false
    property double chainStartMs: 0
    property int chainDuration: chainMinimumDuration
    signal chainStarted()
    signal chainCancelled()
    readonly property int blurMaximum: Math.max(2, Math.ceil(farBlurRadius))
    readonly property color focusedTextColor: ColorUtils.mix(
        root.textColor,
        activeColor,
        0.82
    )

    readonly property var currentLineData: hasCurrentLine && LyricsService.syncedLines[currentIndex]
        ? LyricsService.syncedLines[currentIndex] : null
    readonly property var nextLineData: (hasCurrentLine && currentIndex + 1 < LyricsService.syncedLines.length)
        ? LyricsService.syncedLines[currentIndex + 1] : null
    readonly property var currentWordRanges: {
        if (!hasCurrentLine || !currentLineData)
            return [];
        return root.computeWordRanges(
            currentLineData.text,
            currentLineData.words,
            currentLineData.time,
            currentLineData.endTime,
            nextLineData?.time
        );
    }
    readonly property bool currentLineHasWords: Boolean(currentWordRanges && currentWordRanges.length > 0)
    // Rich text for the line being sung. Words flip colour as they are reached, so
    // the string only changes at word boundaries (and a few steps within a word).
    readonly property string currentLineHtml: currentLineHasWords
        ? root.karaokeHtml(currentLineData.text, currentWordRanges, LyricsService.syncPosition)
        : ""

    function computeWordRanges(lineText, words, lineStartTime, lineEndTime, nextLineStartTime) {
        if (!lineText || !lineText.trim())
            return [];

        const totalChars = lineText.length;
        if (totalChars === 0)
            return [];

        // 1. If explicit word/syllable timestamps exist (e.g. BetterLyrics syllable TTML):
        if (words && words.length > 0) {
            const ranges = [];
            let searchPos = 0;

            for (let i = 0; i < words.length; i++) {
                const w = words[i];
                const wText = (w.text || "").trim();
                if (!wText)
                    continue;

                let idx = lineText.indexOf(wText, searchPos);
                if (idx === -1) {
                    idx = lineText.indexOf(wText);
                }

                const begin = w.begin !== undefined ? w.begin : (w.startTime || 0);
                const end = w.end !== undefined ? w.end : (w.endTime || begin + 0.3);

                if (idx !== -1) {
                    const startFrac = idx / totalChars;
                    const endFrac = (idx + wText.length) / totalChars;
                    ranges.push({
                        begin: begin,
                        end: end,
                        startFrac: startFrac,
                        endFrac: endFrac
                    });
                    searchPos = idx + wText.length;
                } else {
                    const prevEnd = ranges.length > 0 ? ranges[ranges.length - 1].endFrac : 0;
                    const remainingWords = words.length - i;
                    const step = (1.0 - prevEnd) / remainingWords;
                    ranges.push({
                        begin: begin,
                        end: end,
                        startFrac: prevEnd,
                        endFrac: prevEnd + step
                    });
                    searchPos = Math.round((prevEnd + step) * totalChars);
                }
            }

            if (ranges.length > 0)
                return ranges;
        }

        // 2. Synthesize word ranges from line timing (for line-synced lyrics from LRCLib or line-only TTML)
        const lineStart = (lineStartTime !== undefined && !isNaN(lineStartTime)) ? lineStartTime : 0;
        let lineEnd = (lineEndTime !== undefined && !isNaN(lineEndTime) && lineEndTime > lineStart) ? lineEndTime : 0;

        if (lineEnd <= lineStart) {
            if (nextLineStartTime !== undefined && !isNaN(nextLineStartTime) && nextLineStartTime > lineStart) {
                const gap = nextLineStartTime - lineStart;
                lineEnd = lineStart + Math.max(0.6, Math.min(gap * 0.85, gap - 0.25));
            } else {
                lineEnd = lineStart + Math.max(2.5, lineText.length * 0.16);
            }
        }

        const lineDuration = Math.max(0.4, lineEnd - lineStart);
        const ranges = [];
        const wordRegex = /\S+/g;
        const matches = [];
        let totalWordChars = 0;
        let m;
        while ((m = wordRegex.exec(lineText)) !== null) {
            matches.push({ text: m[0], index: m.index });
            totalWordChars += m[0].length;
        }

        if (matches.length > 0 && totalWordChars > 0) {
            let currentOffset = lineStart;
            for (let i = 0; i < matches.length; i++) {
                const wordMatch = matches[i];
                const charShare = wordMatch.text.length / totalWordChars;
                const wordDur = lineDuration * charShare;
                const bTime = currentOffset;
                const eTime = (i === matches.length - 1) ? lineEnd : (bTime + wordDur);
                ranges.push({
                    begin: bTime,
                    end: eTime,
                    startFrac: wordMatch.index / totalChars,
                    endFrac: (wordMatch.index + wordMatch.text.length) / totalChars
                });
                currentOffset = eTime;
            }
        }

        return ranges;
    }

    function colorHex(c) {
        const q = Qt.color(c);
        const h = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
        return "#" + h(q.a) + h(q.r) + h(q.g) + h(q.b);
    }

    function escapeHtml(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function karaokeHtml(lineText, wordRanges, pos) {
        const total = lineText.length;
        const steps = 6;
        const base = root.focusedTextColor;
        let html = "";
        let cursor = 0;

        for (let i = 0; i < wordRanges.length; i++) {
            const r = wordRanges[i];
            const start = Math.max(cursor, Math.round(r.startFrac * total));
            const end = Math.max(start, Math.min(total, Math.round(r.endFrac * total)));

            if (start > cursor)
                html += root.escapeHtml(lineText.slice(cursor, start));

            const span = Math.max(0.001, r.end - r.begin);
            const progress = Math.max(0, Math.min(1, (pos - r.begin) / span));
            const level = Math.round(progress * steps) / steps;
            const color = root.colorHex(Qt.rgba(base.r, base.g, base.b,
                root.unsungWordOpacity + (1 - root.unsungWordOpacity) * level));

            html += "<font color=\"" + color + "\">"
                + root.escapeHtml(lineText.slice(start, end)) + "</font>";
            cursor = end;
        }

        if (cursor < total)
            html += "<font color=\"" + root.colorHex(base) + "\">"
                + root.escapeHtml(lineText.slice(cursor)) + "</font>";

        return html;
    }

    // High-frequency position ticker for fluid word-by-word swipe synchronization.
    // Only ticks while media is playing and the current line has word timestamps.
    Timer {
        id: karaokePositionTimer
        interval: 50
        repeat: true
        running: Boolean(((root.player?.isPlaying ?? LyricsService.activePlayer?.isPlaying)
                || ((root.player ?? LyricsService.activePlayer)?.playbackState == MprisPlaybackState.Playing))
            && root.hasCurrentLine
            && root.currentLineHasWords)
        onTriggered: {
            const p = root.player ?? LyricsService.activePlayer;
            if (p) {
                p.positionChanged();
            }
        }
    }

    function blurForDistance(distanceInRows) {
        const distance = Math.max(0, distanceInRows);
        if (distance <= 1)
            return root.nearBlurRadius * distance;
        if (distance <= 2)
            return root.nearBlurRadius
                + (root.farBlurRadius - root.nearBlurRadius) * (distance - 1);
        return root.farBlurRadius;
    }

    function targetContentY(index) {
        if (index < 0 || root.rowHeight <= 0)
            return lyricsList.originY;

        const lastIndex = Math.max(0, LyricsService.syncedLines.length - 1);
        return lyricsList.originY + Math.min(lastIndex, index) * root.rowHeight;
    }

    // The scroll has to land well before the line it reveals is over, so the
    // budget is a fraction of that line's own on-screen time. One long gap (an
    // instrumental break) must not slow the song back down, so the track's median
    // cadence caps it; playback rate compresses it further.
    function transitionDurationForIndex(index) {
        const lines = LyricsService.syncedLines;
        const line = lines[index];
        const nextLine = lines[index + 1];

        let paceMs = root.songPaceMs > 0 ? root.songPaceMs : root.rowTransitionDuration;
        if (line && nextLine) {
            const lineDurationMs = (nextLine.time - line.time) * 1000;
            if (isFinite(lineDurationMs) && lineDurationMs > 0)
                paceMs = root.songPaceMs > 0
                    ? Math.min(lineDurationMs, root.songPaceMs * 1.35)
                    : lineDurationMs;
        }

        return Math.max(
            root.minimumRowTransitionDuration,
            Math.min(root.rowTransitionDuration,
                paceMs * root.rowTransitionPaceFactor / root.playbackRate)
        );
    }

    // Smootherstep. The centre line snaps into focus rather than crossing it
    // linearly, which is what reads as impact during the row change.
    function focusEasing(linearFocus) {
        const t = Math.max(0, Math.min(1, linearFocus));
        return t * t * t * (t * (t * 6 - 15) + 10);
    }

    // The list jumps to the new line at once and each row carries the distance it
    // would have scrolled as an offset of its own. Rows then release that offset
    // one after another (see chainAnimation in the delegate), which is what turns
    // the scroll into a wave with a soft bounce.
    function startRowChain(deltaY) {
        const limit = root.rowHeight * root.halfVisibleLines;
        root.chainDelta = Math.max(-limit, Math.min(limit, deltaY));
        root.chainDirection = deltaY >= 0 ? 1 : -1;
        root.chainDuration = Math.round(Math.max(
            root.chainMinimumDuration,
            Math.min(root.chainMaximumDuration,
                root.transitionDurationForIndex(root.currentIndex) * root.chainDurationFactor)
        ) * Appearance.animMultiplier);
        root.chainStartMs = Date.now();
        root.chainActive = true;
        chainSettleTimer.interval = root.chainDuration
            + root.chainMaximumRank * root.chainStaggerMs * Appearance.animMultiplier + 80;
        chainSettleTimer.restart();
        root.chainStarted();
    }

    function settleRows() {
        chainSettleTimer.stop();
        root.chainActive = false;
        root.chainCancelled();
    }

    function centerCurrentLine(animated) {
        if (root.rowHeight <= 0)
            return;

        if (!root.hasCurrentLine) {
            root.settleRows();
            lyricsList.contentY = lyricsList.originY;
            return;
        }

        const targetY = root.targetContentY(root.currentIndex);
        const deltaY = targetY - lyricsList.contentY;
        lyricsList.contentY = targetY;

        if (!animated || Appearance.animMultiplier <= 0) {
            root.settleRows();
            return;
        }

        if (Math.abs(deltaY) > 0.5)
            root.startRowChain(deltaY);
    }

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        Qt.callLater(function() {
            root.centerCurrentLine(false);
        });
    }

    onCurrentIndexChanged: root.centerCurrentLine(true)
    onRowHeightChanged: {
        root.settleRows();
        Qt.callLater(function() {
            root.centerCurrentLine(false);
        });
    }

    Behavior on focusReveal {
        NumberAnimation {
            duration: root.rowTransitionDuration <= 0 || Appearance.animMultiplier <= 0
                ? 0 : Math.round(Math.max(
                root.minimumRowTransitionDuration,
                Math.min(root.rowTransitionDuration, 400 * Appearance.animMultiplier)
            ))
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
        }
    }

    Connections {
        target: LyricsService

        function onSyncedLinesChanged() {
            root.settleRows();
            Qt.callLater(function() {
                root.centerCurrentLine(false);
            });
        }
    }

    Timer {
        id: chainSettleTimer

        onTriggered: root.chainActive = false
    }

    ListView {
        id: lyricsList

        anchors.fill: parent
        interactive: false
        // Distance blur alone never made the far rows leave; the edges now
        // dissolve so the column reads as depth instead of as a cropped list.
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: lyricsList.width
                height: lyricsList.height
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: root.edgeFadeFraction; color: "black" }
                    GradientStop { position: 1.0 - root.edgeFadeFraction; color: "black" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        currentIndex: -1
        model: LyricsService.syncedLines.length

        header: Item {
            width: lyricsList.width
            height: root.viewportEdgePadding
        }

        footer: Item {
            width: lyricsList.width
            height: root.viewportEdgePadding
        }

        delegate: Item {
            id: lyricRow

            required property int index

            // Verse-change offset: distance this row still has to travel back to rest.
            property real chainOffset: 0
            readonly property real centerYInViewport: y - lyricsList.contentY + height / 2
                + chainOffset
            readonly property real signedDistanceRatio: root.height > 0
                ? Math.max(-1, Math.min(1,
                    (centerYInViewport - root.height / 2) / (root.height / 2)))
                : 0
            readonly property real parallaxTranslation: signedDistanceRatio
                * signedDistanceRatio * signedDistanceRatio * root.parallaxMaximum
            readonly property real distanceInRows: root.rowHeight > 0
                ? Math.abs(centerYInViewport - root.height / 2) / root.rowHeight
                : 0
            readonly property real focusedBlurRadius: root.blurForDistance(distanceInRows)
            readonly property real blurRadius: root.farBlurRadius
                + (focusedBlurRadius - root.farBlurRadius) * root.focusReveal
            readonly property real focusFactor: root.focusEasing(1 - distanceInRows)
                * root.focusReveal
            // Fixed font weight ensures glyph advances never shift, locking word wrap permanently.
            readonly property int weightAxis: root.focusedFontWeight
            readonly property int gradeAxis: Math.round(root.focusedFontGrade * focusFactor / 5) * 5
            readonly property real depthOpacity: Math.max(root.minimumRowOpacity,
                1 - distanceInRows * root.rowOpacityFalloff)
            readonly property var lineData: LyricsService.syncedLines[lyricRow.index] ?? null
            readonly property bool isCurrentLine: lyricRow.index === root.currentIndex
            readonly property bool hasWordTiming: isCurrentLine && root.currentLineHasWords
            readonly property string lineText: lineData ? (lineData.text ?? "") : ""

            width: lyricsList.width
            height: root.rowHeight

            // The row that leads the ripple is the one the list is moving away from;
            // every row after it waits one more stagger step.
            function beginChain() {
                chainAnimation.stop();

                const limit = root.rowHeight * root.halfVisibleLines;
                lyricRow.chainOffset = Math.max(-limit, Math.min(limit,
                    lyricRow.chainOffset + root.chainDelta));

                const lead = root.chainDirection > 0
                    ? root.currentIndex - 1 : root.currentIndex + 1;
                const rank = Math.min(root.chainMaximumRank, Math.max(0,
                    root.chainDirection > 0 ? lyricRow.index - lead : lead - lyricRow.index));
                // A row created mid-ripple joins it where the others already are.
                const elapsed = Date.now() - root.chainStartMs;

                chainAnimation.startDelay = Math.max(0, Math.round(
                    rank * root.chainStaggerMs * Appearance.animMultiplier - elapsed));
                chainAnimation.restart();
            }

            function settle() {
                chainAnimation.stop();
                lyricRow.chainOffset = 0;
            }

            Component.onCompleted: {
                if (root.chainActive)
                    beginChain();
            }
            ListView.onPooled: settle()
            ListView.onReused: {
                if (root.chainActive)
                    beginChain();
                else
                    settle();
            }

            Connections {
                target: root

                function onChainStarted() {
                    lyricRow.beginChain();
                }

                function onChainCancelled() {
                    lyricRow.settle();
                }
            }

            SequentialAnimation {
                id: chainAnimation

                property int startDelay: 0

                PauseAnimation {
                    duration: chainAnimation.startDelay
                }
                NumberAnimation {
                    target: lyricRow
                    property: "chainOffset"
                    to: 0
                    duration: root.chainDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.45, 0.12, 0.45, root.bounceLevel, 1, 1]
                }
            }

            Item {
                id: blurLayer

                anchors.fill: parent
                opacity: lyricRow.depthOpacity
                transform: Translate {
                    y: lyricRow.parallaxTranslation + lyricRow.chainOffset
                }
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: root.blurMaximum
                    blur: Math.min(1, lyricRow.blurRadius / root.blurMaximum)
                }

                StyledText {
                    id: lyricText

                    anchors.fill: parent
                    anchors.leftMargin: root.nearBlurRadius + Appearance.font.pixelSize.normal
                    anchors.rightMargin: root.nearBlurRadius + Appearance.font.pixelSize.normal
                    textFormat: lyricRow.hasWordTiming ? Text.StyledText : Text.PlainText
                    text: lyricRow.hasWordTiming ? root.currentLineHtml : lyricRow.lineText
                    color: ColorUtils.mix(
                        root.focusedTextColor,
                        root.dimTextColor,
                        lyricRow.focusFactor
                    )
                    font.family: Appearance.font.family.main
                    // Layout always uses the focused metrics. A real transform supplies
                    // the visual size transition without relayout or integer pixel steps.
                    font.pixelSize: root.layoutFontSize
                    font.variableAxes: ({
                        "wght": lyricRow.weightAxis,
                        "wdth": 100,
                        "opsz": root.layoutFontSize,
                        // GRAD changes stroke emphasis without changing glyph advances.
                        "GRAD": lyricRow.gradeAxis,
                        "ROND": Config.options.appearance.fonts.roundnessFull ? 100 : 0
                    })
                    scale: 1.0
                    transformOrigin: Item.Center
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: root.maximumLyricLines
                    elide: Text.ElideRight
                }
            }

            TapHandler {
                cursorShape: Qt.PointingHandCursor
                onTapped: LyricsService.changeDurationToIndex(lyricRow.index)
            }
        }
    }
}
