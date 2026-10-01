import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import QtQuick

/**
 * The 32 px round icon button of editor rows and forms: the clock's icon button at a
 * smaller size. Icon in `buttonIcon`, an optional tooltip in `tooltip`.
 */
ClockIconButton {
    property string buttonIcon

    symbol: buttonIcon
    size: 32
    iconSize: 20
}
