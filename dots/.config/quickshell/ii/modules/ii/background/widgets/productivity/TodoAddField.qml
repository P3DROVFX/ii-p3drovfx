import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * "Add a task": a pill that becomes a text field on click. The desktop takes
 * the keyboard while it is being typed in (WidgetTextEntry); Enter adds the
 * task and keeps the field open for the next, Escape lets it go. The shape
 * beside it morphs from a clover to a sunny burst while it has the keys.
 */
Rectangle {
    id: root

    required property var source
    property bool interactive: true
    readonly property bool typing: entry.holding

    implicitHeight: 44
    radius: Appearance.rounding.scale === 0 ? 0 : height / 2
    color: root.typing ? ColorUtils.mix(WidgetColorScheme.accentColor, WidgetColorScheme.pillBgColor, 0.14)
        : (hover.hovered && root.interactive ? ColorUtils.mix(WidgetColorScheme.textColorOnBg, WidgetColorScheme.pillBgColor, 0.08) : WidgetColorScheme.pillBgColor)

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: hover
        enabled: root.interactive
        cursorShape: Qt.IBeamCursor
    }

    // Over the field until it has the keys: a press there must arm the
    // keyboard first; once typing, presses go to the field for the cursor.
    MouseArea {
        anchors.fill: parent
        z: 2
        enabled: root.interactive && !root.typing
        cursorShape: Qt.IBeamCursor
        onClicked: entry.begin()
    }

    MaterialShape {
        id: badge
        anchors.left: parent.left
        anchors.leftMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: root.height - 14
        shape: root.typing ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Clover4Leaf
        color: root.typing ? WidgetColorScheme.accentColor : WidgetColorScheme.pillFillColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: Math.round(parent.height * 0.62)
            color: root.typing ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnPillFill
        }
    }

    TextInput {
        id: field
        anchors.left: badge.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        enabled: root.interactive
        clip: true
        color: WidgetColorScheme.textColorOnBg
        selectionColor: WidgetColorScheme.accentColor
        selectedTextColor: WidgetColorScheme.onAccentColor
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.normal
        font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
        cursorVisible: root.typing

        Keys.onReturnPressed: {
            root.source.add(field.text);
            field.text = "";
        }
        Keys.onEnterPressed: {
            root.source.add(field.text);
            field.text = "";
        }
        Keys.onEscapePressed: {
            field.text = "";
            entry.end();
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: field.text.length === 0
            text: root.typing ? Translation.tr("Type, then Enter") : Translation.tr("Add a task")
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
        }
    }

    WidgetTextEntry {
        id: entry
        field: field
    }
}
