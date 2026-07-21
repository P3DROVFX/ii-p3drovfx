import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * One Dynamic Island notch entry: enable switch + contracted-height spinbox.
 * Emits edit signals instead of writing Config directly, since each notch
 * stores its state under differently-named keys — the caller binds
 * `notchEnabled`/`contractedHeight` and persists in the signal handlers.
 */
ColumnLayout {
    id: root

    property string text: ""
    property string buttonIcon: "circle"
    property string tooltip: ""
    property string heightLabel: ""
    // Not every notch is height-tunable (the OSD one isn't)
    property bool hasHeight: true
    // Island master switch — the whole card hides when the island is off
    property bool masterEnabled: true
    property bool notchEnabled: true
    property int contractedHeight: 32
    property int heightFrom: 24
    property int heightTo: 60

    signal notchToggled(bool enabled)
    signal contractedHeightEdited(int value)

    visible: masterEnabled
    spacing: 0

    ConfigSwitch {
        buttonIcon: root.buttonIcon
        text: root.text
        checked: root.notchEnabled
        onCheckedChanged: root.notchToggled(checked)

        StyledToolTip {
            text: root.tooltip
            extraVisibleCondition: root.tooltip !== ""
        }

    }

    ConfigSpinBox {
        icon: "height"
        text: root.heightLabel
        visible: root.hasHeight && root.notchEnabled
        value: root.contractedHeight
        from: root.heightFrom
        to: root.heightTo
        stepSize: 1
        onValueChanged: root.contractedHeightEdited(value)
    }

}
