import qs.modules.common
import QtQuick

Text {
    id: root
    // The value-change slide lives in AnimatedStyledText / AnimatedMaterialSymbol.
    // These stay declared so a plain text still accepts them (and simply does not
    // animate) instead of failing to load.
    property bool animateChange: false
    property real animationDistanceX: 0
    property real animationDistanceY: 6

    // NativeRendering rasterizes glyphs before parent transforms. Popup content
    // uses fractional monitor scaling, so that bitmap becomes jagged when
    // enlarged. QtRendering keeps glyphs transformable at the final scale.
    renderType: Text.QtRendering
    verticalAlignment: Text.AlignVCenter
    property bool shouldUseNumberFont: /^[0-9\s.,]+$/.test(root.text.trim())
    property var defaultFont: shouldUseNumberFont ? Appearance.font.family.numbers : Appearance.font.family.main
    
    font {
        hintingPreference: Font.PreferDefaultHinting
        family: defaultFont + (shouldUseNumberFont ? "," + Appearance.font.family.main : "")
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        variableAxes: shouldUseNumberFont ? ({}) : Appearance.font.variableAxes.main
    }
    color: Appearance?.m3colors.m3onBackground ?? "black"
    linkColor: Appearance?.m3colors.m3primary
}
