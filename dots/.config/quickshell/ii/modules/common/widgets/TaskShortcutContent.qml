import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Fixed geometry: revealing a shortcut never moves its control or neighbours.
Item {
    id: root
    property string symbol: ""
    property string shortcut: ""
    property bool showHint: false
    property bool circle: false
    property real iconSize: Appearance.font.pixelSize.larger
    property real fill: 0
    property color color: Appearance.colors.colOnSurface
    property color badgeColor: Appearance.colors.colPrimary
    property color badgeTextColor: Appearance.colors.colOnPrimary
    // Text button variant: a label stands in for the icon when there is none.
    property string labelText: ""
    property real labelPixelSize: Appearance.font.pixelSize.larger
    property int labelFontWeight: Font.Normal
    readonly property bool hasBoth: root.symbol.length > 0 && root.labelText.length > 0
    // Label and pair variants reserve the widest of content and hint
    // (OptionChip rule): revealing a shortcut never moves the control.
    implicitWidth: hasBoth ? (root.iconSize + 6 + Math.max(pairLabel.implicitWidth, hintLabel.implicitWidth)) : (symbol.length > 0 ? iconSize : Math.max(iconSize, singleLabel.implicitWidth, hintLabel.implicitWidth))
    implicitHeight: Math.max(root.iconSize, root.labelText.length > 0 ? root.labelPixelSize : 0)
    property real hintProgress: showHint && shortcut.length > 0 ? 1 : 0

    Behavior on hintProgress {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Row {
        id: pairRow
        anchors.centerIn: parent
        visible: root.hasBoth
        spacing: 6
        opacity: 1 - root.hintProgress
        transform: Translate { y: -root.hintProgress * root.iconSize / 3 }

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: root.symbol
            iconSize: root.iconSize
            fill: root.fill
            color: root.color
        }

        StyledText {
            id: pairLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.labelText
            font.pixelSize: root.labelPixelSize
            font.weight: Font.Bold
            color: root.color
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.symbol.length > 0 && !root.hasBoth
        text: root.symbol
        iconSize: root.iconSize
        fill: root.fill
        color: root.color
        opacity: 1 - root.hintProgress
        transform: Translate { y: -root.hintProgress * root.iconSize / 3 }
    }

    StyledText {
        id: singleLabel
        anchors.centerIn: parent
        // Stretched hosts (fillWidth rows) elide instead of overflowing.
        width: Math.min(implicitWidth, parent.width)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        visible: root.symbol.length === 0 && root.labelText.length > 0
        text: root.labelText
        font.pixelSize: root.labelPixelSize
        font.weight: root.labelFontWeight
        color: root.color
        opacity: 1 - root.hintProgress
        transform: Translate { y: -root.hintProgress * root.iconSize / 3 }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.circle ? root.iconSize : parent.width
        height: root.circle ? width : parent.height
        radius: Appearance.rounding.full
        color: root.circle ? root.badgeColor : "transparent"
        opacity: root.hintProgress
        visible: opacity > 0
        transform: Translate { y: (1 - root.hintProgress) * root.iconSize / 3 }

        StyledText {
            id: hintLabel
            anchors.fill: parent
            text: root.shortcut
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: root.circle ? root.badgeTextColor : root.color
        }
    }
}
