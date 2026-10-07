import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * The base of the utility widgets that live on a card (To-Do, timers,
 * translator, phone, send, session, water): the lock behaviour every widget
 * repeats, the entry's options and size, and the card itself. Children go in
 * `content`, a box of the design size scaled by Widget Size, so they lay out
 * in design units.
 */
AbstractBackgroundWidget {
    id: root

    property real designWidth: 240
    property real designHeight: 240
    property bool showCard: true
    property color cardColor: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
    property real cardRadius: Appearance.rounding.large
    default property alias content: contentBox.data
    readonly property alias contentItem: contentBox

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === root.configEntryName)

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.[root.configEntryName] ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    // Whether a press may do something: the Settings preview shows the widget
    // but never runs its actions (a preview of the session grid that powers off).
    readonly property bool actionsEnabled: !root.isPreview

    // Whichever of the card's two text colours reads better on `fill`: a
    // contrast for fills the scheme has no "on" colour for (the warning).
    function contentOn(fill) {
        const lum = c => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        const a = WidgetColorScheme.textColorOnBg;
        const b = WidgetColorScheme.cardBgColor;
        return Math.abs(lum(a) - lum(fill)) >= Math.abs(lum(b) - lum(fill)) ? a : b;
    }

    // A pill's corner that still respects sharp mode (rounding scale 0).
    function pill(height) {
        return Appearance.rounding.scale === 0 ? 0 : height / 2;
    }

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    Item {
        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: root.contentScale

        StyledRectangularShadow {
            target: card
            visible: root.showCard && (Config.options.background.widgets.enableShadows ?? true)
        }

        Rectangle {
            id: card
            anchors.fill: parent
            visible: root.showCard
            radius: root.cardRadius
            color: root.cardColor

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Item {
            id: contentBox
            anchors.fill: parent
        }

        // A preview looks live but takes no input: nothing under it runs.
        MouseArea {
            anchors.fill: parent
            z: 100
            visible: root.isPreview
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
        }
    }
}
