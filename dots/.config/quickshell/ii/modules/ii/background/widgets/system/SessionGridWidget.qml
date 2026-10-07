pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Session (1x1): lock, power off, restart and log out as a 2x2 grid. Nothing
 * runs on the first press: the tile arms - it fills (accent for lock, warning
 * for the rest), its shape bursts, it asks to be pressed again and a bar
 * drains along its foot. A second press within that time runs it; otherwise
 * it settles back. Lock uses the shell's own lock screen.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "session_grid"
    designWidth: 240
    designHeight: 240

    readonly property real padding: 12
    readonly property real gap: 8
    readonly property int confirmWindow: 3000
    readonly property real tileSize: (root.designWidth - root.padding * 2 - root.gap) / 2

    property string armed: ""

    readonly property var actions: [
        { id: "lock", label: Translation.tr("Lock"), symbol: "lock", shape: MaterialShape.Shape.Cookie4Sided, destructive: false },
        { id: "poweroff", label: Translation.tr("Power off"), symbol: "power_settings_new", shape: MaterialShape.Shape.Cookie9Sided, destructive: true },
        { id: "reboot", label: Translation.tr("Restart"), symbol: "restart_alt", shape: MaterialShape.Shape.Clover4Leaf, destructive: true },
        { id: "logout", label: Translation.tr("Log out"), symbol: "logout", shape: MaterialShape.Shape.Cookie6Sided, destructive: true }
    ]

    function press(id) {
        if (!root.actionsEnabled)
            return;
        if (root.armed !== id) {
            root.armed = id;
            disarmTimer.restart();
            return;
        }
        root.armed = "";
        disarmTimer.stop();
        switch (id) {
        case "lock":
            GlobalStates.screenLocked = true;
            break;
        case "poweroff":
            Session.poweroff();
            break;
        case "reboot":
            Session.reboot();
            break;
        case "logout":
            Session.logout();
            break;
        }
    }

    Timer {
        id: disarmTimer
        interval: root.confirmWindow
        onTriggered: root.armed = ""
    }

    // A lock or a hidden desktop drops a half-made choice.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            root.armed = "";
        }
    }

    Grid {
        x: root.padding
        y: root.padding
        columns: 2
        spacing: root.gap

        Repeater {
            model: root.actions

            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index
                readonly property bool isArmed: root.armed === tile.modelData.id
                readonly property bool dimmed: root.armed !== "" && !tile.isArmed
                readonly property color armedColor: tile.modelData.destructive ? WidgetColorScheme.warningColor : WidgetColorScheme.accentColor
                readonly property color armedContent: tile.modelData.destructive ? root.contentOn(WidgetColorScheme.warningColor) : WidgetColorScheme.onAccentColor
                readonly property color contentColor: tile.isArmed ? tile.armedContent : WidgetColorScheme.textColorOnBg
                // The corners facing the grid's centre stay small: four tiles, one shape.
                readonly property real outer: Appearance.rounding.large
                readonly property real inner: Appearance.rounding.verysmall

                width: root.tileSize
                height: root.tileSize
                topLeftRadius: tile.isArmed || tile.index === 0 ? tile.outer : tile.inner
                topRightRadius: tile.isArmed || tile.index === 1 ? tile.outer : tile.inner
                bottomLeftRadius: tile.isArmed || tile.index === 2 ? tile.outer : tile.inner
                bottomRightRadius: tile.isArmed || tile.index === 3 ? tile.outer : tile.inner
                color: tile.isArmed ? tile.armedColor
                    : (tileHover.hovered && root.actionsEnabled ? ColorUtils.mix(WidgetColorScheme.textColorOnBg, WidgetColorScheme.pillBgColor, 0.08) : WidgetColorScheme.pillBgColor)
                opacity: tile.dimmed ? 0.55 : 1
                scale: tileTap.pressed ? 0.95 : 1

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
                Behavior on topLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on topRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on bottomLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on bottomRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

                MaterialShape {
                    id: badge
                    x: 12
                    y: 12
                    implicitSize: 44
                    shape: tile.isArmed ? MaterialShape.Shape.SoftBurst
                        : (tileHover.hovered && root.actionsEnabled ? MaterialShape.Shape.Cookie12Sided : tile.modelData.shape)
                    color: tile.isArmed ? tile.armedContent : WidgetColorScheme.pillFillColor

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: tile.modelData.symbol
                        iconSize: 22
                        fill: 1
                        color: tile.isArmed ? tile.armedColor : WidgetColorScheme.textColorOnPillFill
                    }
                }

                Column {
                    x: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: parent.width - 24
                    spacing: 0

                    StyledText {
                        width: parent.width
                        visible: tile.isArmed
                        text: Translation.tr("Again?")
                        elide: Text.ElideRight
                        color: tile.contentColor
                        opacity: 0.8
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                    }
                    StyledText {
                        width: parent.width
                        text: tile.modelData.label
                        elide: Text.ElideRight
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 11
                        color: tile.contentColor
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.variableAxes: ({ "wght": tile.isArmed ? 760 : 600, "wdth": tile.isArmed ? 88 : 100, "ROND": 100 })
                    }
                }

                // The confirmation window, draining.
                Rectangle {
                    id: drain
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    x: 14
                    height: 3
                    radius: 1.5
                    visible: tile.isArmed
                    color: tile.armedContent
                    opacity: 0.7
                    width: 0
                }

                NumberAnimation {
                    target: drain
                    property: "width"
                    from: tile.width - 28
                    to: 0
                    duration: root.confirmWindow
                    running: tile.isArmed
                }

                HoverHandler {
                    id: tileHover
                    enabled: root.actionsEnabled
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    id: tileTap
                    enabled: root.actionsEnabled
                    onTapped: root.press(tile.modelData.id)
                }
            }
        }
    }
}
