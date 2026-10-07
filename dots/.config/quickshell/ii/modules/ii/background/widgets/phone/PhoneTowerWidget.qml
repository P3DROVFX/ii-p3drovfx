pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Phone Tower (1x2). The phone stands at full height on the card with its
 * battery on a burst badge at its foot; under it the name and state, then the
 * three actions as one grouped list - Mirror, Send file, Send clipboard - each
 * row with its own shape. The row being pressed (or the mirror while it runs)
 * rounds into a pill and its neighbours follow.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "phone_tower"
    designWidth: 240
    designHeight: 492

    readonly property real padding: 14
    readonly property real imageHeight: 210
    readonly property real rowHeight: 56
    readonly property real rowGap: 3

    PhoneSource {
        id: phone
        enabled: root.actionsEnabled
    }

    // ── Phone ──
    Image {
        id: phoneImage
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.padding + 6
        width: root.designWidth - 70
        height: root.imageHeight
        source: phone.imageSource
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        opacity: phone.hasDevice ? 1 : 0.45
    }

    Item {
        id: badge
        visible: phone.hasDevice && phone.charge >= 0
        x: root.designWidth / 2 + 36
        y: phoneImage.y + phoneImage.height - 58
        width: 64
        height: 64

        readonly property color fillColor: phone.charge <= 15 && !phone.charging ? WidgetColorScheme.warningColor : WidgetColorScheme.accentColor

        MaterialShape {
            anchors.fill: parent
            shape: phone.charging ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Sunny
            color: badge.fillColor
        }

        Column {
            anchors.centerIn: parent
            spacing: -6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(phone.charge)
                color: WidgetColorScheme.onAccentColor
                font.family: Appearance.font.family.main
                font.pixelSize: 26
                font.variableAxes: ({ "wght": 780, "wdth": 50, "ROND": 100, "opsz": 36 })
                renderType: Text.QtRendering
            }
            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: phone.charging ? "bolt" : "percent"
                iconSize: 13
                fill: 1
                color: WidgetColorScheme.onAccentColor
            }
        }
    }

    // ── Name ──
    Column {
        id: info
        x: root.padding + 4
        anchors.top: phoneImage.bottom
        anchors.topMargin: 14
        width: root.designWidth - x * 2
        spacing: 0

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: phone.name
            elide: Text.ElideRight
            color: phone.hasDevice ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.huge + 2
            font.variableAxes: Appearance.font.variableAxes.titleRounded
        }

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: phone.status
            elide: Text.ElideRight
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // ── Actions, one grouped list ──
    Column {
        id: list
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        width: root.designWidth - root.padding * 2
        spacing: root.rowGap

        // Which row is a pill: the pressed one, else the running mirror.
        property int pillIndex: -1
        readonly property int effectivePill: list.pillIndex >= 0 ? list.pillIndex : (phone.mirrorRunning ? 0 : -1)

        ActionRow {
            index: 0
            symbol: phone.mirrorRunning ? "open_in_new" : "cast"
            shape: MaterialShape.Shape.Cookie9Sided
            label: phone.mirrorRunning ? Translation.tr("Show mirror") : (phone.mirrorLaunching ? Translation.tr("Starting mirror…") : Translation.tr("Mirror screen"))
            active: phone.mirrorRunning
            available: phone.canMirror
            trailing: phone.mirrorRunning ? "close" : ""
            onActivated: phone.mirror()
            onTrailingActivated: phone.stopMirror()
        }

        ActionRow {
            index: 1
            symbol: "upload_file"
            shape: MaterialShape.Shape.Clover4Leaf
            label: Translation.tr("Send file")
            available: phone.hasDevice
            onActivated: phone.sendFile()
        }

        ActionRow {
            index: 2
            symbol: phone.sent === "clipboard" ? "check" : "content_paste_go"
            shape: phone.sent === "clipboard" ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie6Sided
            label: phone.sent === "clipboard" ? Translation.tr("Clipboard sent") : Translation.tr("Send clipboard")
            available: phone.hasDevice
            onActivated: phone.sendClipboard()
        }
    }

    component ActionRow: Rectangle {
        id: row
        property int index: 0
        property string symbol
        property int shape
        property string label
        property bool active: false
        property bool available: true
        property string trailing: ""
        signal activated
        signal trailingActivated

        readonly property bool isPill: list.effectivePill === row.index
        readonly property bool facesPillAbove: list.effectivePill === row.index - 1
        readonly property bool facesPillBelow: list.effectivePill === row.index + 1
        readonly property real outer: Appearance.rounding.large
        readonly property real join: Appearance.rounding.verysmall
        readonly property real full: root.pill(height)
        readonly property color contentColor: row.active ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg

        width: list.width
        height: root.rowHeight
        topLeftRadius: row.isPill ? row.full : (row.index === 0 || row.facesPillAbove ? row.outer : row.join)
        topRightRadius: topLeftRadius
        bottomLeftRadius: row.isPill ? row.full : (row.index === 2 || row.facesPillBelow ? row.outer : row.join)
        bottomRightRadius: bottomLeftRadius
        color: row.active ? WidgetColorScheme.accentColor
            : (rowHover.hovered && row.available ? ColorUtils.mix(WidgetColorScheme.textColorOnBg, WidgetColorScheme.pillBgColor, 0.08) : WidgetColorScheme.pillBgColor)

        Behavior on topLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on topRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on bottomLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on bottomRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialShape {
            id: rowShape
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 38
            shape: row.shape
            color: row.active ? WidgetColorScheme.onAccentColor : WidgetColorScheme.pillFillColor
            opacity: row.available ? 1 : 0.5

            MaterialSymbol {
                anchors.centerIn: parent
                text: row.symbol
                iconSize: 20
                fill: 1
                color: row.active ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnPillFill
            }
        }

        StyledText {
            anchors.left: rowShape.right
            anchors.leftMargin: 12
            anchors.right: trailingKey.visible ? trailingKey.left : parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            elide: Text.ElideRight
            color: row.contentColor
            opacity: row.available ? 1 : 0.5
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": row.active ? 680 : 580, "wdth": 96, "ROND": 100 })
        }

        HoverHandler {
            id: rowHover
            enabled: row.available
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: row.available
            onPressedChanged: list.pillIndex = pressed ? row.index : -1
            onTapped: row.activated()
        }

        WidgetButton {
            id: trailingKey
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            visible: row.trailing !== ""
            symbol: row.trailing
            symbolSize: 18
            colFill: ColorUtils.applyAlpha(row.contentColor, 0.16)
            colContent: row.contentColor
            onClicked: row.trailingActivated()
        }
    }
}
