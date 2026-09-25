import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/** − value + stepper. The value label is formatted by `format(value)`. */
RowLayout {
    id: root

    property int value: 0
    property int from: 0
    property int to: 100
    property int stepSize: 1
    property var format: value => String(value)

    signal moved(int value)

    function step(delta: int): void {
        const next = Math.max(root.from, Math.min(root.to, root.value + delta * root.stepSize));
        if (next !== root.value)
            root.moved(next);
    }

    spacing: ClockStyle.gapTiny

    ClockIconButton {
        symbol: "remove"
        size: ClockStyle.iconButton - 4
        enabled: root.value > root.from
        colBackground: ClockStyle.colSurfaceHighest
        onClicked: root.step(-1)
    }

    StyledText {
        Layout.minimumWidth: ClockStyle.iconButton * 1.6
        horizontalAlignment: Text.AlignHCenter
        text: root.format(root.value)
        font.pixelSize: ClockStyle.textNormal
        font.weight: Font.DemiBold
        color: ClockStyle.colOnSurface

        WheelHandler {
            onWheel: event => root.step(event.angleDelta.y > 0 ? 1 : -1)
        }
    }

    ClockIconButton {
        symbol: "add"
        size: ClockStyle.iconButton - 4
        enabled: root.value < root.to
        colBackground: ClockStyle.colSurfaceHighest
        onClicked: root.step(1)
    }
}
