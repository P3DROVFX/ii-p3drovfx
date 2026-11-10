import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A small status pill: "Playing now", "In use", "Default", a count. Tinted with the
 * colour of whatever it sits on (`colContent`) unless a fill is given, so one pill works
 * on a primary-container hero and on an idle card alike.
 */
Rectangle {
    id: root

    property string symbol: ""
    property string label: ""
    /// A filled dot before the label, for a state that is live ("Playing now").
    property bool dot: false
    property color colContent: EasyEffectsStyle.colOnSurface
    property color colFill: EasyEffectsStyle.tint(root.colContent, EasyEffectsStyle.tintPill)
    property real pillHeight: EasyEffectsStyle.pillHeight
    property real labelSize: EasyEffectsStyle.textSmall
    property bool filledSymbol: true
    /// A pill naming something long (a device) stops growing here and elides its label.
    property real maxWidth: Infinity
    /// A count shouldn't be narrower than it is tall.
    property real minWidth: 0

    readonly property real padding: EasyEffectsStyle.gapLarge * 2 - (root.symbol.length > 0 ? EasyEffectsStyle.gapSmall / 2 : 0)

    implicitWidth: Math.max(root.minWidth, Math.min(root.maxWidth, pillRow.implicitWidth + root.padding))
    implicitHeight: root.pillHeight
    radius: EasyEffectsStyle.pill(root.pillHeight)
    color: root.colFill

    RowLayout {
        id: pillRow
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.width - root.padding)
        spacing: EasyEffectsStyle.gapSmall - 2

        Rectangle {
            visible: root.dot
            implicitWidth: EasyEffectsStyle.gapSmall
            implicitHeight: EasyEffectsStyle.gapSmall
            radius: width / 2
            color: root.colContent
        }

        MaterialSymbol {
            visible: root.symbol.length > 0
            text: root.symbol
            iconSize: EasyEffectsStyle.iconSmall
            fill: root.filledSymbol ? 1 : 0
            color: root.colContent
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.label
            elide: Text.ElideRight
            font.pixelSize: root.labelSize
            font.weight: Font.DemiBold
            color: root.colContent
        }
    }
}
