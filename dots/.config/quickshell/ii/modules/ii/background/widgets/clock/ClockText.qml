import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

StyledText {
    Layout.fillWidth: true
    font {
        family: Appearance.font.family.expressive
        pixelSize: 20
        weight: 350
        // Set empty to prevent conflicts, not meaningless
        styleName: ""
        variableAxes: ({})
        // Tabular digits: a narrow "1" would otherwise shrink its line
        features: ({ "tnum": 1 })
    }
    // Distance-field glyphs turn polygonal at display sizes; curves stay smooth
    renderType: Text.CurveRendering
    style: Text.Raised
    styleColor: Appearance.colors.colShadow
    animateChange: Config.options.background.widgets.clock_digital.animateChange
}