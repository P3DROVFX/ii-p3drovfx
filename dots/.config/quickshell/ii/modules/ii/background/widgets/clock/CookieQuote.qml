import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects


Item {
    id: root

    readonly property string quoteText: Config.options.background.widgets.concentric_clock?.quoteText || Config.options.background.widgets.clock_cookie?.quoteText || ""

    implicitWidth: quoteBox.implicitWidth
    implicitHeight: quoteBox.implicitHeight

    DropShadow {
        source: quoteBox 
        anchors.fill: quoteBox
        horizontalOffset: 0
        verticalOffset: 2
        radius: 12
        samples: radius * 2 + 1
        color: Appearance.colors.colShadow
        transparentBorder: true
    }
    
    Rectangle {
        id: quoteBox

        implicitWidth: quoteRow.implicitWidth + 8 * 2
        implicitHeight: quoteRow.implicitHeight + 4 * 2
        radius: Appearance.rounding.small
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.innerShapeColor)

        Row {
            id: quoteRow
            anchors.centerIn: parent
            spacing: 4
            
            MaterialSymbol {
                id: quoteIcon
                anchors.top: parent.top
                iconSize: Appearance.font.pixelSize.huge
                text: "format_quote"
                color: WidgetColorScheme.accentColor
            }
            StyledText {
                id: quoteStyledText
                horizontalAlignment: Text.AlignLeft
                text: root.quoteText
                color: WidgetColorScheme.textColorOnBg
                font {
                    family: Appearance.font.family.reading
                    pixelSize: Appearance.font.pixelSize.large
                    weight: Font.Normal
                }
            }
        }
    }
}
