.pragma library

var identityValue = 1.0;
var minimumSaturation = 0.0;
var maximumSaturation = 2.0;
var minimumAdjustment = 0.5;
var maximumAdjustment = 1.5;

function finiteOr(value, fallback) {
    const numeric = Number(value);
    return isFinite(numeric) ? numeric : fallback;
}

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

function defaultProfile() {
    return {
        saturation: identityValue,
        contrast: identityValue,
        red: identityValue,
        green: identityValue,
        blue: identityValue
    };
}

function normalizeProfile(profile) {
    const source = profile || {};
    return {
        saturation: clamp(finiteOr(source.saturation, identityValue), minimumSaturation, maximumSaturation),
        contrast: clamp(finiteOr(source.contrast, identityValue), minimumAdjustment, maximumAdjustment),
        red: clamp(finiteOr(source.red, identityValue), minimumAdjustment, maximumAdjustment),
        green: clamp(finiteOr(source.green, identityValue), minimumAdjustment, maximumAdjustment),
        blue: clamp(finiteOr(source.blue, identityValue), minimumAdjustment, maximumAdjustment)
    };
}

function isIdentity(profile) {
    const normalized = normalizeProfile(profile);
    const epsilon = 0.0001;
    return Math.abs(normalized.saturation - identityValue) < epsilon
        && Math.abs(normalized.contrast - identityValue) < epsilon
        && Math.abs(normalized.red - identityValue) < epsilon
        && Math.abs(normalized.green - identityValue) < epsilon
        && Math.abs(normalized.blue - identityValue) < epsilon;
}

function shaderNumber(value) {
    return Number(value).toFixed(4);
}

function buildShader(entries) {
    const branches = [];
    const seenIds = {};
    const sourceEntries = Array.isArray(entries) ? entries : [];

    for (let i = 0; i < sourceEntries.length; i++) {
        const entry = sourceEntries[i] || {};
        const outputId = Number(entry.id);
        if (!isFinite(outputId) || outputId < 0 || Math.round(outputId) !== outputId || seenIds[outputId])
            continue;

        const profile = normalizeProfile(entry.profile);
        if (isIdentity(profile))
            continue;

        seenIds[outputId] = true;
        const keyword = branches.length === 0 ? "if" : "else if";
        branches.push(`    ${keyword} (wl_output == ${outputId})\n`
            + `        calibrated = applyDisplayCalibration(calibrated, ${shaderNumber(profile.saturation)}, ${shaderNumber(profile.contrast)}, vec3(${shaderNumber(profile.red)}, ${shaderNumber(profile.green)}, ${shaderNumber(profile.blue)}));`);
    }

    const branchSource = branches.length > 0 ? `\n${branches.join("\n")}\n` : "\n";
    return "#version 300 es\n"
        + "precision highp float;\n\n"
        + "in vec2 v_texcoord;\n"
        + "uniform sampler2D tex;\n"
        + "uniform int wl_output;\n"
        + "out vec4 fragColor;\n\n"
        + "vec3 applyDisplayCalibration(vec3 color, float saturation, float contrast, vec3 channelGain) {\n"
        + "    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));\n"
        + "    color = mix(vec3(luma), color, saturation);\n"
        + "    color = (color - vec3(0.5)) * contrast + vec3(0.5);\n"
        + "    return clamp(color * channelGain, vec3(0.0), vec3(1.0));\n"
        + "}\n\n"
        + "void main() {\n"
        + "    vec4 pixColor = texture(tex, v_texcoord);\n"
        + "    vec3 calibrated = pixColor.rgb;"
        + branchSource
        + "    fragColor = vec4(calibrated, pixColor.a);\n"
        + "}\n";
}
