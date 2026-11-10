import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * How much a notification says on the lock, as three icons on a feature tile:
 * everything, a hidden body, or just the count. Tinted with the tile's content
 * colour; the chosen one fills with primary.
 */
Row {
    id: root

    property string currentValue: "redacted"
    property color colContent: Appearance.colors.colOnLayer1

    signal selected(string value)

    spacing: 4

    Repeater {
        model: [
            { value: "full", symbol: "visibility", tip: Translation.tr("Full content") },
            { value: "redacted", symbol: "visibility_off", tip: Translation.tr("Hide content") },
            { value: "countOnly", symbol: "numbers", tip: Translation.tr("Count only") }
        ]

        RippleButton {
            id: option
            required property var modelData
            readonly property bool chosen: root.currentValue === option.modelData.value

            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: option.chosen ? Appearance.rounding.normal : height / 2
            enabled: root.enabled
            opacity: root.enabled ? 1 : 0.4
            colBackground: option.chosen ? Appearance.colors.colPrimary : ColorUtils.applyAlpha(root.colContent, 0.1)
            colBackgroundHover: option.chosen ? Appearance.colors.colPrimaryHover : ColorUtils.applyAlpha(root.colContent, 0.18)
            colRipple: option.chosen ? Appearance.colors.colPrimaryActive : ColorUtils.applyAlpha(root.colContent, 0.26)
            onClicked: root.selected(option.modelData.value)

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: option.modelData.symbol
                fill: option.chosen ? 1 : 0
                iconSize: Appearance.font.pixelSize.larger
                color: option.chosen ? Appearance.colors.colOnPrimary : root.colContent
            }

            StyledToolTip {
                text: option.modelData.tip
            }
        }
    }
}
