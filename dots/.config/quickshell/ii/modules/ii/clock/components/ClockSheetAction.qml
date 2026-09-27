import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The footer buttons of a side sheet, as the timetable rail draws them: `primary` is the
 * filled pill that commits, otherwise a dashed outline that backs out. `danger` turns a
 * primary into the error pair.
 */
RippleButton {
    id: root

    property string label: ""
    property string symbol: ""
    property bool primary: false
    property bool danger: false

    readonly property color colContent: root.primary
        ? (root.danger ? ClockStyle.colOnError : ClockStyle.colOnPrimary)
        : (root.danger ? ClockStyle.colError : ClockStyle.colPrimary)

    Layout.fillWidth: true
    implicitHeight: root.primary ? 48 : 46
    buttonRadius: Appearance.rounding.full
    colBackground: root.primary ? (root.danger ? ClockStyle.colError : ClockStyle.colPrimary) : "transparent"
    colBackgroundHover: root.primary
        ? (root.danger ? Appearance.colors.colErrorHover : ClockStyle.colPrimaryHover)
        : ColorUtils.applyAlpha(root.danger ? ClockStyle.colError : ClockStyle.colPrimary, 0.12)
    colBackgroundActive: root.primary ? ClockStyle.colPrimaryActive
        : ColorUtils.applyAlpha(root.danger ? ClockStyle.colError : ClockStyle.colPrimary, 0.2)
    opacity: root.enabled ? 1 : 0.45

    Behavior on opacity {
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    DashedBorder {
        anchors.fill: parent
        visible: !root.primary
        color: ColorUtils.applyAlpha(root.danger ? ClockStyle.colError : ClockStyle.colPrimary, 0.7)
        borderWidth: 1
        dashLength: 5
        gapLength: 4
        radius: Appearance.rounding.full
    }

    contentItem: Item {
        implicitWidth: actionRow.implicitWidth
        implicitHeight: actionRow.implicitHeight

        RowLayout {
            id: actionRow
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: Appearance.font.pixelSize.larger
                color: root.colContent
            }

            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: root.primary ? Font.Bold : Font.DemiBold
                color: root.colContent
            }
        }
    }
}
