import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/** Labelled button in the three Material emphasis levels: "filled", "tonal", "text". */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property string variant: "tonal"
    property bool danger: false
    property bool iconOnly: false
    property string tooltip: root.iconOnly ? root.label : ""

    readonly property color colContainer: root.variant === "filled"
        ? (root.danger ? ClockStyle.colError : ClockStyle.colPrimary)
        : root.variant === "tonal"
            ? (root.danger ? ClockStyle.colErrorContainer : ClockStyle.colSecondaryContainer)
            : "transparent"
    readonly property color colContent: root.variant === "filled"
        ? (root.danger ? ClockStyle.colOnError : ClockStyle.colOnPrimary)
        : root.variant === "tonal"
            ? (root.danger ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSecondaryContainer)
            : (root.danger ? ClockStyle.colError : ClockStyle.colPrimary)

    implicitHeight: ClockStyle.buttonHeight
    implicitWidth: root.iconOnly ? ClockStyle.buttonHeight : buttonRow.implicitWidth + ClockStyle.gapHuge * 2
    buttonRadius: ClockStyle.pill(ClockStyle.buttonHeight)
    buttonRadiusPressed: ClockStyle.radiusSmall
    colBackground: root.colContainer
    colBackgroundHover: root.variant === "filled"
        ? (root.danger ? ClockStyle.colError : ClockStyle.colPrimaryHover)
        : root.variant === "tonal"
            ? (root.danger ? ClockStyle.colErrorContainerHover : ClockStyle.colSecondaryContainerHover)
            : ClockStyle.colSurfaceHover
    colRipple: root.variant === "filled" ? ClockStyle.colPrimaryActive
        : root.variant === "tonal" ? ClockStyle.colSecondaryContainerActive : ClockStyle.colSurfaceActive

    contentItem: Item {
        RowLayout {
            id: buttonRow
            anchors.centerIn: parent
            spacing: ClockStyle.gapSmall

            MaterialSymbol {
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: ClockStyle.iconSmall + 2
                color: root.colContent
            }

            StyledText {
                visible: !root.iconOnly
                text: root.label
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
                color: root.colContent
            }
        }
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0
    }
}
