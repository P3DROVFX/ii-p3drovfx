import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * Whether (and how often) a widget is on the desktop, under its section title.
 */
StyledText {
    property string widgetId

    readonly property int count: Config.countWidgetInstances(widgetId)

    Layout.fillWidth: true
    text: count === 0 ? Translation.tr("Not on the desktop. Add it from Desktop Widgets; these options apply once it is there.")
        : count === 1 ? Translation.tr("On the desktop.") : Translation.tr("On the desktop %1 times.").arg(count)
    color: Appearance.colors.colOnSurfaceVariant
    font.pixelSize: Appearance.font.pixelSize.small
    wrapMode: Text.Wrap
}
