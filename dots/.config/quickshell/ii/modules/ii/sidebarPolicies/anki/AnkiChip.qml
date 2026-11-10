import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A tonal pill action (icon + label) on the neutral secondary container; `primary`
 * lifts it to the primary pair for the one action a row is about.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property bool primary: false
    property bool busy: false

    readonly property color colContent: root.primary ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer

    implicitHeight: 40
    implicitWidth: chipRow.implicitWidth + 32
    buttonRadius: Appearance.rounding.full
    buttonRadiusPressed: Appearance.rounding.small
    colBackground: root.primary ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
    colBackgroundHover: root.primary ? ClockStyle.colPrimaryHover : ClockStyle.colSecondaryContainerHover
    colBackgroundActive: root.primary ? ClockStyle.colPrimaryActive : ClockStyle.colSecondaryContainerActive
    colRipple: root.primary ? ClockStyle.colPrimaryActive : ClockStyle.colSecondaryContainerActive
    opacity: root.enabled ? 1 : 0.45

    contentItem: Item {
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                visible: root.symbol.length > 0 && !root.busy
                text: root.symbol
                iconSize: 18
                color: root.colContent
            }
            MaterialLoadingIndicator {
                visible: root.busy
                loading: root.busy
                implicitSize: 22
                shapeColor: root.colContent
            }
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.colContent
            }
        }
    }
}
