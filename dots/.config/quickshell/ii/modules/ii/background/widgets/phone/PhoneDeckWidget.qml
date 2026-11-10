pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Phone Deck (2x1). The phone itself on a slab at the left - its drawing or
 * the photo set for it - and on the right its name, its state, the battery as
 * ten cells, and one connected button group: Mirror (wide, in the accent once
 * it runs), File, Clipboard. The pressed segment rounds into a pill.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "phone_deck"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 14
    readonly property real slabWidth: 150
    readonly property real groupHeight: 56
    readonly property real groupGap: 3

    PhoneSource {
        id: phone
        enabled: root.actionsEnabled
    }

    // ── Phone ──
    Rectangle {
        id: slab
        x: root.padding
        y: root.padding
        width: root.slabWidth
        height: root.designHeight - root.padding * 2
        radius: Appearance.rounding.normal
        color: phone.mirrorRunning ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Image {
            anchors.centerIn: parent
            width: parent.width - 28
            height: parent.height - 28
            source: phone.imageSource
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            opacity: phone.hasDevice ? 1 : 0.45
            scale: phone.mirrorRunning ? 0.92 : 1

            Behavior on scale {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
    }

    // ── Name, state, battery ──
    Column {
        id: info
        anchors.left: slab.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding + 4
        spacing: 2

        StyledText {
            width: parent.width
            text: phone.name
            elide: Text.ElideRight
            color: phone.hasDevice ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 34
            font.variableAxes: ({ "wght": 700, "wdth": 80, "ROND": 100, "opsz": 36 })
        }

        StyledText {
            width: parent.width
            text: phone.status
            elide: Text.ElideRight
            color: phone.mirrorRunning ? WidgetColorScheme.accentColor : WidgetColorScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": 520, "wdth": 100, "ROND": 100, "slnt": phone.mirrorRunning ? -10 : 0 })
        }
    }

    Row {
        id: cells
        visible: phone.hasDevice && phone.charge >= 0
        anchors.left: info.left
        anchors.bottom: group.top
        anchors.bottomMargin: 18
        spacing: 3

        readonly property int lit: Math.round(phone.charge / 10)
        readonly property color litColor: phone.charge <= 15 && !phone.charging ? WidgetColorScheme.warningColor : WidgetColorScheme.accentColor

        Repeater {
            model: 10

            delegate: Rectangle {
                required property int index
                width: 12
                height: 18
                radius: 3
                color: index < cells.lit ? cells.litColor : WidgetColorScheme.pillBgColor

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        Item { width: 6; height: 1 }

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: phone.charging
            text: "bolt"
            iconSize: 18
            fill: 1
            color: cells.litColor
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: phone.charge + "%"
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    // ── Connected button group ──
    Item {
        id: group
        anchors.left: info.left
        anchors.right: info.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        height: root.groupHeight

        readonly property real sideWidth: 64
        readonly property real mirrorWidth: width - sideWidth * 2 - root.groupGap * 2

        GroupKey {
            id: mirrorKey
            x: 0
            width: group.mirrorWidth
            first: true
            enabled: phone.canMirror
            symbol: phone.mirrorRunning ? "open_in_new" : "cast"
            label: phone.mirrorRunning ? Translation.tr("Focus") : (phone.mirrorLaunching ? Translation.tr("Starting") : Translation.tr("Mirror"))
            colFill: phone.mirrorRunning ? WidgetColorScheme.accentColor : WidgetColorScheme.pillFillColor
            colContent: phone.mirrorRunning ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnPillFill
            onClicked: phone.mirror()
        }

        GroupKey {
            x: group.mirrorWidth + root.groupGap
            width: group.sideWidth
            enabled: phone.hasDevice
            symbol: "upload_file"
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: phone.sendFile()
        }

        GroupKey {
            x: group.mirrorWidth + group.sideWidth + root.groupGap * 2
            width: group.sideWidth
            last: true
            enabled: phone.hasDevice
            symbol: phone.sent === "clipboard" ? "check" : "content_paste_go"
            colFill: phone.sent === "clipboard" ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor
            colContent: phone.sent === "clipboard" ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
            onClicked: phone.sendClipboard()
        }
    }

    // One segment of the group: outer corners pill, the joins small, all pill
    // while pressed.
    component GroupKey: WidgetButton {
        id: groupKey
        property bool first: false
        property bool last: false
        readonly property real outerRadius: root.pill(height)
        property real joinRadius: groupKey.down ? groupKey.outerRadius : Appearance.rounding.verysmall
        Behavior on joinRadius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        height: root.groupHeight
        symbolSize: 22
        topLeftRadius: groupKey.first ? groupKey.outerRadius : groupKey.joinRadius
        bottomLeftRadius: groupKey.first ? groupKey.outerRadius : groupKey.joinRadius
        topRightRadius: groupKey.last ? groupKey.outerRadius : groupKey.joinRadius
        bottomRightRadius: groupKey.last ? groupKey.outerRadius : groupKey.joinRadius
    }
}
