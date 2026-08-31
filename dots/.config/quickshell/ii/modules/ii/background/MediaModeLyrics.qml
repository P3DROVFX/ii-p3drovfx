import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

// Focused five-row lyrics presentation used exclusively by the background Media Mode.
// Blur follows physical distance from the viewport center, keeping retargets coherent.
// Row motion mirrors PixelPlayer: timed FastOutSlowIn scroll plus cubic parallax.
Item {
    id: root

    clip: true

    // Size of a *resting* line. The centred line is this scaled by
    // focusedFontSizeMultiplier, so the gap between the two is the transition.
    property real largeFontSize: Appearance.font.pixelSize.hugeass * 1.5
    property color activeColor: Appearance.colors.colPrimary
    // Upper clamp only: the effective duration is derived per line from the
    // song's own cadence, so fast tracks stop dragging through a fixed 2s scroll.
    property int rowTransitionDuration: 1400
    property int minimumRowTransitionDuration: 320
    // Share of a line's on-screen time the scroll into it is allowed to consume.
    property real rowTransitionPaceFactor: 0.7
    property real nearBlurRadius: 10
    property real farBlurRadius: 32
    property real rowSpacingFactor: 0.78
    property real focusedFontSizeMultiplier: 1.42
    property int maximumLyricLines: 3
    property real baseFontWeight: 500
    property real focusedFontWeight: 820
    property real focusedFontGrade: 100
    property real minimumRowOpacity: 0.24
    property real rowOpacityFalloff: 0.34
    // Top/bottom fade: how much of the viewport each edge dissolves over.
    property real edgeFadeFraction: 0.16
    property int activeRowTransitionDuration: rowTransitionDuration
    property real focusReveal: hasCurrentLine ? 1 : 0
    property real waveProgress: 1
    property int waveTargetIndex: -1
    property int lastWaveIndex: -1
    property int waveAnimationDuration: 700
    property real waveDurationMultiplier: 1.2
    property real waveMagnificationStrength: 0.022
    property real waveBandWidth: 0.065
    property real waveColorStrength: 0.08

    readonly property int halfVisibleLines: 2
    readonly property int visibleLineCount: halfVisibleLines * 2 + 1
    readonly property int currentIndex: LyricsService.currentIndex
    readonly property bool hasCurrentLine: currentIndex >= 0
    readonly property real layoutFontSize: largeFontSize * focusedFontSizeMultiplier
    // A row only decides spacing. Text is laid out inside a taller centred box so
    // that tightening the spacing can never clip a wrapped line.
    readonly property real rowContentHeight: Math.ceil(layoutFontSize * 1.3) * maximumLyricLines
    // Tight spacing, but never tighter than one focused line: a short panel must
    // not stack the rows on top of each other.
    readonly property real rowHeight: Math.max(layoutFontSize * 1.32,
        height / visibleLineCount * rowSpacingFactor)
    readonly property real viewportEdgePadding: Math.max(0, height / 2 - rowHeight / 2)
    readonly property real playbackRate: Math.max(0.25, MprisController.activePlayer?.rate ?? 1)
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
    readonly property real waveLift: Appearance.font.pixelSize.normal * 0.075
    readonly property bool waveRunning: waveAnimation.running
    readonly property int blurMaximum: Math.max(2, Math.ceil(farBlurRadius))
    readonly property color focusedTextColor: ColorUtils.mix(
        Appearance.colors.colOnLayer0,
        activeColor,
        0.82
    )

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

    function effectiveTransitionDuration(baseDuration) {
        if (root.rowTransitionDuration <= 0 || Appearance.animMultiplier <= 0)
            return 0;

        return Math.round(Math.max(
            root.minimumRowTransitionDuration,
            Math.min(root.rowTransitionDuration, baseDuration * Appearance.animMultiplier)
        ));
    }

    function textDirection(text) {
        const firstStrong = String(text ?? "").match(
            /[A-Za-z\u00c0-\u052f\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufefc]/
        );
        if (!firstStrong)
            return 1;
        return /[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufefc]/.test(firstStrong[0])
            ? -1 : 1;
    }

    // Smootherstep. The centre line snaps into focus rather than crossing it
    // linearly, which is what reads as impact during the row change.
    function focusEasing(linearFocus) {
        const t = Math.max(0, Math.min(1, linearFocus));
        return t * t * t * (t * (t * 6 - 15) + 10);
    }

    function cancelMagnificationWave() {
        waveAnimation.stop();
        root.waveProgress = 1;
        root.waveTargetIndex = -1;
    }

    function scheduleMagnificationWave() {
        root.cancelMagnificationWave();

        if (!root.hasCurrentLine) {
            root.lastWaveIndex = -1;
            return;
        }

        const previousIndex = root.lastWaveIndex;
        root.lastWaveIndex = root.currentIndex;
        if (previousIndex < 0)
            return;

        const jumpDistance = Math.abs(root.currentIndex - previousIndex);

        const transitionDuration = root.effectiveTransitionDuration(
            root.activeRowTransitionDuration
        );
        if (!rowMoveAnimation.running
                || jumpDistance > root.halfVisibleLines
                || transitionDuration < 240)
            return;

        root.waveTargetIndex = root.currentIndex;
        root.waveAnimationDuration = Math.round(
            transitionDuration * root.waveDurationMultiplier
        );
        root.waveProgress = 0;
        waveAnimation.restart();
    }

    function centerCurrentLine(animated) {
        rowMoveAnimation.stop();

        if (root.rowHeight <= 0)
            return;

        if (!root.hasCurrentLine) {
            root.activeRowTransitionDuration = root.rowTransitionDuration;
            lyricsList.contentY = lyricsList.originY;
            return;
        }

        const targetY = root.targetContentY(root.currentIndex);

        if (!animated || root.rowTransitionDuration <= 0 || Appearance.animMultiplier <= 0) {
            root.activeRowTransitionDuration = root.rowTransitionDuration;
            lyricsList.contentY = targetY;
            return;
        }

        let deltaY = targetY - lyricsList.contentY;
        let distanceInRows = Math.abs(deltaY) / root.rowHeight;

        if (distanceInRows > root.halfVisibleLines) {
            const direction = deltaY > 0 ? 1 : -1;
            lyricsList.contentY = targetY - direction * root.rowHeight;
            deltaY = targetY - lyricsList.contentY;
            distanceInRows = Math.abs(deltaY) / root.rowHeight;
        }

        if (distanceInRows < 0.001) {
            root.activeRowTransitionDuration = root.rowTransitionDuration;
            lyricsList.contentY = targetY;
            return;
        }

        root.activeRowTransitionDuration = root.transitionDurationForIndex(root.currentIndex);
        rowMoveAnimation.to = targetY;
        rowMoveAnimation.restart();
    }

    Component.onCompleted: {
        LyricsService.initiliazeLyrics();
        Qt.callLater(function() {
            root.centerCurrentLine(false);
        });
    }

    onCurrentIndexChanged: {
        root.centerCurrentLine(true);
        root.scheduleMagnificationWave();
    }
    onRowHeightChanged: {
        root.cancelMagnificationWave();
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
            root.cancelMagnificationWave();
            Qt.callLater(function() {
                root.centerCurrentLine(false);
            });
        }
    }

    NumberAnimation {
        id: rowMoveAnimation

        target: lyricsList
        property: "contentY"
        duration: Appearance.animMultiplier <= 0 ? 0 : Math.round(Math.max(
            root.minimumRowTransitionDuration,
            Math.min(root.rowTransitionDuration,
                root.activeRowTransitionDuration * Appearance.animMultiplier)
        ))
        // Jetpack Compose FastOutSlowInEasing, used by PixelPlayer's lyric scroll.
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
    }

    NumberAnimation {
        id: waveAnimation

        target: root
        property: "waveProgress"
        from: 0
        to: 1
        duration: root.waveAnimationDuration
        easing.type: Easing.InOutSine
        onFinished: root.waveTargetIndex = -1
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

            readonly property real centerYInViewport: y - lyricsList.contentY + height / 2
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
            // Quantised so the variable-axis font object (and the relayout it
            // forces) churns a handful of times per row change, not every frame.
            readonly property int weightAxis: Math.round((root.baseFontWeight
                + (root.focusedFontWeight - root.baseFontWeight) * focusFactor) / 20) * 20
            readonly property int gradeAxis: Math.round(root.focusedFontGrade * focusFactor / 5) * 5
            readonly property real depthOpacity: Math.max(root.minimumRowOpacity,
                1 - distanceInRows * root.rowOpacityFalloff)
            readonly property string lineText: LyricsService.syncedLines[lyricRow.index]
                ? LyricsService.syncedLines[lyricRow.index].text
                : ""
            readonly property bool waveActive: lyricRow.index === root.waveTargetIndex
                && root.waveRunning
            readonly property real waveDirection: root.textDirection(lineText)

            width: lyricsList.width
            height: root.rowHeight

            Item {
                id: blurLayer

                width: parent.width
                height: Math.max(parent.height, root.rowContentHeight)
                anchors.verticalCenter: parent.verticalCenter
                opacity: lyricRow.depthOpacity
                transform: Translate {
                    y: lyricRow.parallaxTranslation
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

                    property real firstVisualLineSpan: 1
                    property real secondVisualLineSpan: 1
                    property real thirdVisualLineSpan: 1
                    // Where the laid-out block sits inside this taller box, in
                    // normalised coordinates, so the wave shader can locate each line.
                    readonly property real textTopNorm: height > 0
                        ? (height - contentHeight) / 2 / height : 0
                    readonly property real lineSpanNorm: (height > 0 && lineCount > 0)
                        ? contentHeight / lineCount / height : 1

                    anchors.fill: parent
                    anchors.leftMargin: root.nearBlurRadius + Appearance.font.pixelSize.normal
                    anchors.rightMargin: root.nearBlurRadius + Appearance.font.pixelSize.normal
                    text: lyricRow.lineText
                    color: ColorUtils.mix(
                        root.focusedTextColor,
                        Appearance.colors.colSubtext,
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
                    scale: (1 + (root.focusedFontSizeMultiplier - 1)
                        * lyricRow.focusFactor) / root.focusedFontSizeMultiplier
                    transformOrigin: Item.Center
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: root.maximumLyricLines
                    elide: Text.ElideRight

                    onTextChanged: {
                        firstVisualLineSpan = 1;
                        secondVisualLineSpan = 1;
                        thirdVisualLineSpan = 1;
                    }
                    onLineLaidOut: line => {
                        const span = Math.max(0.05, Math.min(1,
                            line.implicitWidth / Math.max(1, lyricText.width)));
                        if (line.number === 0)
                            firstVisualLineSpan = span;
                        else if (line.number === 1)
                            secondVisualLineSpan = span;
                        else if (line.number === 2)
                            thirdVisualLineSpan = span;
                    }

                    // The extra texture exists only during the one-shot focus wave. The
                    // outer row layer continues to own the distance-based blur.
                    layer.enabled: lyricRow.waveActive
                    layer.smooth: true
                    layer.effect: ShaderEffect {
                        property real waveProgress: root.waveProgress
                        property real waveStrength: root.waveMagnificationStrength
                        property real waveWidth: root.waveBandWidth
                        property real waveLift: root.waveLift / Math.max(1, lyricText.height)
                        property real lineCountValue: lyricText.lineCount
                        property real firstLineSpan: lyricText.firstVisualLineSpan
                        property real secondLineSpan: lyricText.secondVisualLineSpan
                        property real thirdLineSpan: lyricText.thirdVisualLineSpan
                        property real textTopNorm: lyricText.textTopNorm
                        property real lineSpanNorm: lyricText.lineSpanNorm
                        property real waveDirection: lyricRow.waveDirection
                        property real colorStrength: root.waveColorStrength
                        property color waveColor: root.activeColor

                        fragmentShader: "shaders/lyricsMagnificationWave.frag.qsb"
                    }
                }
            }

            TapHandler {
                cursorShape: Qt.PointingHandCursor
                onTapped: LyricsService.changeDurationToIndex(lyricRow.index)
            }
        }
    }
}
