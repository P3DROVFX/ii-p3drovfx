import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * The Widget Size slider every desktop widget page has (50-200 %).
 */
ConfigSlider {
    property var options

    buttonIcon: "aspect_ratio"
    text: Translation.tr("Widget Size")
    value: options?.widgetSize ?? 100
    from: 50
    to: 200
    stepSize: 10
    onValueChanged: if (options) options.widgetSize = value
}
