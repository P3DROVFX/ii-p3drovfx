.pragma library

// The bitrate a screen recording gets is derived rather than asked for: Mbps
// means nothing without knowing how many pixels it has to pay for. These
// figures are mirrored in scripts/videos/record.sh, which is what actually runs
// wf-recorder; scripts/tests/test_screen_recording_contract.py fails if the two
// ever drift apart.
var QUALITY_BPP_LOW = 0.05;
var QUALITY_BPP_BALANCED = 0.09;
var QUALITY_BPP_HIGH = 0.15;
var BITRATE_FLOOR_MBPS = 1.5;
var BITRATE_CEILING_MBPS = 80;

// Target boxes a recording is fitted into, aspect ratio preserved. "native"
// is absent on purpose: it means "whatever the screen already is".
var RESOLUTION_BOXES = {
    "2160p": [3840, 2160],
    "1440p": [2560, 1440],
    "1080p": [1920, 1080],
    "720p": [1280, 720],
    "480p": [854, 480]
};

function bitsPerPixel(quality) {
    if (quality === "low") return QUALITY_BPP_LOW;
    if (quality === "high") return QUALITY_BPP_HIGH;
    return QUALITY_BPP_BALANCED;
}

/** The size actually encoded: fitted inside the preset's box, never scaled up. */
function outputSize(sourceWidth, sourceHeight, resolution) {
    var box = RESOLUTION_BOXES[resolution];
    if (!box || (sourceWidth <= box[0] && sourceHeight <= box[1]))
        return [sourceWidth, sourceHeight];

    var ratio = Math.min(box[0] / sourceWidth, box[1] / sourceHeight);
    return [
        Math.max(2, Math.floor(sourceWidth * ratio / 2) * 2),
        Math.max(2, Math.floor(sourceHeight * ratio / 2) * 2)
    ];
}

/** Mbps for a given output size, rounded the way the recorder rounds it. */
function estimateMbps(width, height, framerate, quality) {
    var mbps = width * height * framerate * bitsPerPixel(quality) / 1000000;
    mbps = Math.min(BITRATE_CEILING_MBPS, Math.max(BITRATE_FLOOR_MBPS, mbps));
    return Math.round(mbps * 10) / 10;
}
