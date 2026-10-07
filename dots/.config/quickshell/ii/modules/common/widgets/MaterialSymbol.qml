import qs.modules.common
import QtQuick

StyledText {
    id: root
    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0
    // Keep the font on a complete outlined or filled glyph. Fractional FILL
    // values during animation can drop internal paths in Qt's variable-font
    // renderer after a parent scale transform.
    readonly property real truncatedFill: root.fill >= 0.5 ? 1 : 0

    // True while this symbol or any ancestor is scaled or rotated (popup scale
    // multiplier, rotating shapes). The binding reads every ancestor's
    // scale/rotation/parent, so it follows animations and reparenting.
    readonly property bool transformed: {
        for (let p = root; p; p = p.parent) {
            if (Math.abs(p.scale - 1) > 0.001 || p.rotation % 360 !== 0)
                return true;
        }
        return false;
    }

    // NativeRendering gives the crispest glyph at its real size, but rasterizes
    // before transforms: a scale stretches that bitmap into jagged steps.
    // CurveRendering evaluates the outline at the final on-screen size, so it is
    // used only under a transform — untransformed its small-size antialiasing
    // wobbles. QtRendering's distance field drops contours from filled glyphs
    // (`devices`, `settings`), so it is never used here.
    renderType: root.transformed ? Text.CurveRendering : Text.NativeRendering
    antialiasing: true
    smooth: true
    horizontalAlignment: Text.AlignHCenter

    font {
        hintingPreference: Font.PreferNoHinting
        family: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"
        pixelSize: iconSize
        weight: Font.Normal
        variableAxes: ({
                "FILL": parseFloat(root.truncatedFill),
                "wght": 400,
                "opsz": Math.max(20, Math.min(48, iconSize))
            })
    }

    Behavior on fill {
        NumberAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }
}

