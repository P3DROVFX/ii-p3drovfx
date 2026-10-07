import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Phone Key (1x1). The mirror is one big shaped key in the middle: a cookie
 * while it waits, a burst while scrcpy starts, a rounded square in the accent
 * while the phone is on screen (a press then brings the window forward, the
 * small key on its shoulder stops it). The phone's name and battery above,
 * send-file and send-clipboard below.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "phone_key"
    designWidth: 240
    designHeight: 240

    readonly property real padding: 16
    readonly property real keySize: 104
    readonly property real smallKeyHeight: 40

    PhoneSource {
        id: phone
        enabled: root.actionsEnabled
    }

    // ── Header ──
    StyledText {
        x: root.padding + 2
        y: root.padding - 2
        width: root.designWidth - root.padding * 2 - battery.width - 8
        text: phone.name
        elide: Text.ElideRight
        color: phone.hasDevice ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.larger
        font.variableAxes: Appearance.font.variableAxes.titleRounded
    }

    StyledText {
        x: root.padding + 2
        y: root.padding + 22
        text: phone.status
        color: WidgetColorScheme.subtextColorOnBg
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    Row {
        id: battery
        visible: phone.hasDevice && phone.charge >= 0
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding
        spacing: 2

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: phone.charging ? "battery_charging_full" : "battery_full"
            iconSize: 16
            fill: 1
            color: phone.charge <= 15 && !phone.charging ? WidgetColorScheme.warningColor : WidgetColorScheme.accentColor
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: phone.charge + "%"
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // ── Mirror key ──
    Item {
        id: key
        anchors.horizontalCenter: parent.horizontalCenter
        y: 62
        width: root.keySize
        height: root.keySize
        scale: keyTap.pressed ? 0.95 : 1

        Behavior on scale {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }

        MaterialShape {
            anchors.fill: parent
            shape: phone.mirrorRunning ? MaterialShape.Shape.Square
                : phone.mirrorLaunching ? MaterialShape.Shape.SoftBurst
                : (keyHover.hovered && phone.canMirror ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided)
            color: phone.mirrorRunning ? WidgetColorScheme.accentColor
                : phone.canMirror ? WidgetColorScheme.pillFillColor : WidgetColorScheme.pillBgColor

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: phone.mirrorRunning ? "open_in_new" : (phone.hasDevice ? "cast" : "phonelink_off")
            iconSize: 40
            fill: 1
            color: phone.mirrorRunning ? WidgetColorScheme.onAccentColor
                : phone.canMirror ? WidgetColorScheme.textColorOnPillFill : WidgetColorScheme.subtextColorOnBg
        }

        HoverHandler {
            id: keyHover
            enabled: phone.canMirror
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: keyTap
            enabled: phone.canMirror
            onTapped: phone.mirror()
        }

        // Stop, on the key's shoulder while the mirror runs.
        WidgetButton {
            x: parent.width - width + 8
            y: -8
            width: 34
            height: 34
            visible: phone.mirrorRunning
            symbol: "close"
            symbolSize: 18
            colFill: WidgetColorScheme.warningColor
            colContent: root.contentOn(WidgetColorScheme.warningColor)
            onClicked: phone.stopMirror()
        }
    }

    // ── Send ──
    Row {
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        spacing: 8

        readonly property real keyWidth: (root.designWidth - root.padding * 2 - spacing) / 2

        WidgetButton {
            width: parent.keyWidth
            height: root.smallKeyHeight
            enabled: phone.hasDevice
            symbol: "upload_file"
            symbolSize: 18
            label: Translation.tr("File")
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: phone.sendFile()
        }

        WidgetButton {
            width: parent.keyWidth
            height: root.smallKeyHeight
            enabled: phone.hasDevice
            readonly property bool justSent: phone.sent === "clipboard"
            symbol: justSent ? "check" : "content_paste_go"
            symbolSize: 18
            label: justSent ? Translation.tr("Sent") : Translation.tr("Clipboard")
            colFill: justSent ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor
            colContent: justSent ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
            restRadius: justSent ? Appearance.rounding.small : root.pill(height)
            onClicked: phone.sendClipboard()
        }
    }
}
