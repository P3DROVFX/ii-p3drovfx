#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 color;
    float radius;
    float smoothing;
    float dockHeight;
    float dockWidth;
    float bumpX;
    float bumpWidth;
    float bumpHeight;
    float sminK;
    float waveX;
    float waveProgress;
    float launcherX;
    float launcherW;
    float launcherH;
    float launcherR;
    float waveAmp;
    float trayX;
    float trayW;
    float trayH;
    float trayR;
    float qsX;
    float qsW;
    float qsH;
    float qsR;
    float mediaX;
    float mediaW;
    float mediaH;
    float mediaR;
    vec4 audio;
    float audioPhase;
    float audioAmp;
    float popupDetach;
    float popupGap;
    float waveHalfW;
    float qsWaveX;
    float qsWave;
    float calX;
    float calW;
    float calH;
    float calR;
    float weatherX;
    float weatherW;
    float weatherH;
    float weatherR;
    float resX;
    float resW;
    float resH;
    float resR;
    float chipX;
    float chipW;
    float chipH;
    float chipR;
    float flipY;
    float hugRadius;
};

float sdSquircle(vec2 p, vec2 b, float r, float n) {
    vec2 q = abs(p) - b + vec2(r);
    float outside = pow(pow(max(q.x, 0.0), n) + pow(max(q.y, 0.0), n), 1.0 / n);
    float inside = min(max(q.x, q.y), 0.0);
    return outside + inside - r;
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

void main() {
    vec2 P = qt_TexCoord0 * size;
    if (flipY > 0.5)
        P.y = size.y - P.y;
    float n = max(smoothing, 2.0);

    float dockTop = size.y - dockHeight;
    vec2 dockCenter = vec2(size.x * 0.5, size.y - dockHeight * 0.5);
    vec2 dockHalf = vec2(dockWidth * 0.5, dockHeight * 0.5);
    float rDock = min(radius, min(dockHalf.x, dockHalf.y));
    float dDock = sdSquircle(P - dockCenter, dockHalf, rDock, n);

    float popupOvl = radius * (1.0 - popupDetach);
    float popupLift = popupGap * popupDetach;

    float d = dDock;
    if (bumpHeight > 0.5) {
        float bumpBottom = dockTop + popupOvl - popupLift;
        float bumpTop = dockTop - bumpHeight - popupLift;
        vec2 bumpCenter = vec2(bumpX, (bumpTop + bumpBottom) * 0.5);
        vec2 bumpHalf = vec2(bumpWidth * 0.5, (bumpBottom - bumpTop) * 0.5);
        float rBump = min(radius, bumpHalf.x);
        float dBump = sdSquircle(P - bumpCenter, bumpHalf, rBump, n);
        d = smin(dDock, dBump, sminK);
    }

    if (launcherH > 0.5) {
        float lBottom = dockTop + popupOvl - popupLift;
        float lTop = dockTop - launcherH - popupLift;
        vec2 lCenter = vec2(launcherX, (lTop + lBottom) * 0.5);
        vec2 lHalf = vec2(launcherW * 0.5, (lBottom - lTop) * 0.5);
        float lR = min(launcherR, lHalf.x);
        float dL = sdSquircle(P - lCenter, lHalf, lR, n);
        d = smin(d, dL, sminK);
    }

    if (trayH > 0.5) {
        float tBottom = dockTop + popupOvl - popupLift;
        float tTop = dockTop - trayH - popupLift;
        vec2 tCenter = vec2(trayX, (tTop + tBottom) * 0.5);
        vec2 tHalf = vec2(trayW * 0.5, (tBottom - tTop) * 0.5);
        float tR = min(trayR, tHalf.x);
        float dT = sdSquircle(P - tCenter, tHalf, tR, n);
        d = smin(d, dT, sminK);
    }

    if (qsH > 0.5) {
        float qBottom = dockTop + popupOvl - popupLift;
        float qTop = dockTop - qsH - popupLift;
        vec2 qCenter = vec2(qsX, (qTop + qBottom) * 0.5);
        vec2 qHalf = vec2(qsW * 0.5, (qBottom - qTop) * 0.5);
        float qR = min(qsR, qHalf.x);
        float dQ = sdSquircle(P - qCenter, qHalf, qR, n);
        if (qsWave > 0.0 && qsWave < 1.0) {
            float dy = abs(P.y - qCenter.y);
            float amp = 10.0 * (1.0 - qsWave);
            float rip = amp * sin(0.06 * dy - 7.0 * qsWave) * exp(-0.010 * dy);
            float edge = clamp(1.0 - abs(P.x - qsWaveX) / 30.0, 0.0, 1.0);
            dQ -= rip * edge;
        }
        d = smin(d, dQ, sminK);
    }

    if (mediaH > 0.5) {
        float mBottom = dockTop + popupOvl - popupLift;
        float mTop = dockTop - mediaH - popupLift;
        vec2 mCenter = vec2(mediaX, (mTop + mBottom) * 0.5);
        vec2 mHalf = vec2(mediaW * 0.5, (mBottom - mTop) * 0.5);
        float mR = min(mediaR, mHalf.x);
        float dM = sdSquircle(P - mCenter, mHalf, mR, n);
        vec2 rel = P - mCenter;
        float theta = atan(rel.y, rel.x);
        float level = audio.x * 0.7 + audio.y * 0.2 + audio.z * 0.07 + audio.w * 0.03;
        float wave = sin(5.0 * theta - audioPhase * 4.0);
        float bump = pow(max(0.0, wave), 5.0);
        float edge = clamp(1.0 - abs(dM) / 28.0, 0.0, 1.0);
        dM -= bump * level * edge * audioAmp;
        d = smin(d, dM, sminK);
    }

    if (calH > 0.5) {
        float cBottom = dockTop + popupOvl - popupLift;
        float cTop = dockTop - calH - popupLift;
        vec2 cCenter = vec2(calX, (cTop + cBottom) * 0.5);
        vec2 cHalf = vec2(calW * 0.5, (cBottom - cTop) * 0.5);
        float cR = min(calR, cHalf.x);
        float dC = sdSquircle(P - cCenter, cHalf, cR, n);
        d = smin(d, dC, sminK);
    }

    if (weatherH > 0.5) {
        float wBottom = dockTop + popupOvl - popupLift;
        float wTop = dockTop - weatherH - popupLift;
        vec2 wCenter = vec2(weatherX, (wTop + wBottom) * 0.5);
        vec2 wHalf = vec2(weatherW * 0.5, (wBottom - wTop) * 0.5);
        float wR = min(weatherR, wHalf.x);
        float dW = sdSquircle(P - wCenter, wHalf, wR, n);
        d = smin(d, dW, sminK);
    }

    if (resH > 0.5) {
        float rBottom = dockTop + popupOvl - popupLift;
        float rTop = dockTop - resH - popupLift;
        vec2 rCenter = vec2(resX, (rTop + rBottom) * 0.5);
        vec2 rHalf = vec2(resW * 0.5, (rBottom - rTop) * 0.5);
        float rRad = min(resR, rHalf.x);
        float dR = sdSquircle(P - rCenter, rHalf, rRad, n);
        d = smin(d, dR, sminK);
    }

    if (chipH > 0.5) {
        float chipBottom = dockTop + popupOvl - popupLift;
        float chipTop = dockTop - chipH - popupLift;
        vec2 chipCenter = vec2(chipX, (chipTop + chipBottom) * 0.5);
        vec2 chipHalf = vec2(chipW * 0.5, (chipBottom - chipTop) * 0.5);
        float chipRad = min(chipR, chipHalf.x);
        float dChip = sdSquircle(P - chipCenter, chipHalf, chipRad, n);
        d = smin(d, dChip, sminK);
    }

    if (hugRadius > 0.5) {
        float hr = hugRadius;
        vec2 lc = vec2(hr, dockTop - hr);
        float lFoot = max(sdSquircle(P - vec2(hr * 0.5, dockTop - hr * 0.5), vec2(hr * 0.5), 0.0, 2.0), -(length(P - lc) - hr));
        vec2 rc = vec2(size.x - hr, dockTop - hr);
        float rFoot = max(sdSquircle(P - vec2(size.x - hr * 0.5, dockTop - hr * 0.5), vec2(hr * 0.5), 0.0, 2.0), -(length(P - rc) - hr));
        d = min(d, min(lFoot, rFoot));
    }

    if (waveProgress > 0.0 && waveProgress < 1.0) {
        float decay = max(0.004, 0.012 - waveAmp * 0.00014);
        float amp = waveAmp * (1.0 - waveProgress);
        float d1 = abs(P.x - (waveX - waveHalfW));
        float d2 = abs(P.x - (waveX + waveHalfW));
        float ripple = amp * 0.5 * (sin(0.05 * d1 - 8.0 * waveProgress) * exp(-decay * d1)
                                  + sin(0.05 * d2 - 8.0 * waveProgress) * exp(-decay * d2));
        float dy = P.y - dockTop;
        float reachUp = 16.0 + waveAmp * 1.8;
        float band = dy < 0.0 ? clamp(1.0 + dy / reachUp, 0.0, 1.0)
                              : clamp(1.0 - dy / 14.0, 0.0, 1.0);
        d -= ripple * band;
    }

    float coverage = clamp(0.5 - d, 0.0, 1.0);
    float a = color.a * coverage * qt_Opacity;
    fragColor = vec4(color.rgb * a, a);
}
