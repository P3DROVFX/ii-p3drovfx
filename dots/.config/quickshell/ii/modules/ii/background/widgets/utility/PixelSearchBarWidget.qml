pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Pixel Search Bar (2x0.5): the Pixel home screen's bar. A tall pill with the
 * logo, the hint and two round keys inside opens the launcher's search; the
 * circle beside it is the bar's third key in the accent colour (AI by
 * default), and it softens into a cookie under the pointer. All three keys
 * are picked in Settings.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "search_pixel"
    designWidth: 492
    designHeight: 76
    showCard: false

    readonly property real gap: 8
    readonly property real keySize: 52
    readonly property string logo: root.options?.logo ?? "google"
    readonly property var keys: [root.options?.action1 ?? "lens", root.options?.action2 ?? "music_rec"]
    readonly property string sideKey: root.options?.action3 ?? "ai_chat"

    SearchActions {
        id: actions
    }

    // The bar searches through the widget's own pointer area (cardTapped): a
    // button there would take the press, and the widget could not be moved.
    onCardTapped: at => {
        if (pill.contains(pill.mapFromItem(root.contentItem, at.x, at.y)))
            actions.run("search");
        else if (side.contains(side.mapFromItem(root.contentItem, at.x, at.y)))
            actions.run(root.sideKey);
    }

    StyledRectangularShadow {
        target: pill
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: pill
        width: root.designWidth - root.designHeight - root.gap
        height: root.designHeight
        radius: root.pill(height)
        color: pillHover.hovered && root.actionsEnabled
            ? ColorUtils.mix(WidgetColorScheme.textColorOnBg, root.cardColor, root.pressed ? 0.12 : 0.06)
            : root.cardColor
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        HoverHandler {
            id: pillHover
        }

        Item {
            anchors.fill: parent
            Item {
                id: logoBox
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                height: 48

                CustomIcon {
                    anchors.centerIn: parent
                    visible: root.logo !== "spark"
                    width: 30
                    height: 30
                    source: root.logo === "distro" ? SystemInfo.distroIcon : "google.svg"
                    colorize: true
                    color: WidgetColorScheme.accentColor
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.logo === "spark"
                    text: "search"
                    iconSize: 30
                    color: WidgetColorScheme.accentColor
                }
            }

            StyledText {
                anchors.left: logoBox.right
                anchors.leftMargin: 6
                anchors.right: keyRow.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.options?.hint || Translation.tr("Search")
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.larger
                font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
            }

            Row {
                id: keyRow
                anchors.right: parent.right
                anchors.rightMargin: (root.designHeight - root.keySize) / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: root.keys

                    delegate: WidgetButton {
                        id: key
                        required property string modelData
                        width: root.keySize
                        height: root.keySize
                        symbol: actions.details(key.modelData).icon
                        symbolSize: 26
                        symbolFilled: false
                        colFill: root.cardColor
                        colContent: WidgetColorScheme.textColorOnBg
                        onClicked: if (root.actionsEnabled) actions.run(key.modelData)

                        StyledToolTip {
                            text: actions.details(key.modelData).displayName
                        }
                    }
                }
            }
        }
    }

    // ── The side key: a circle that turns into a cookie under the pointer ──
    Item {
        id: side
        x: root.designWidth - width
        width: root.designHeight
        height: root.designHeight
        scale: sideHover.hovered && root.pressed ? 0.92 : 1
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledRectangularShadow {
            target: sideShadowShape
            visible: Config.options.background.widgets.enableShadows ?? true
        }
        Rectangle {
            id: sideShadowShape
            anchors.fill: parent
            anchors.margins: 6
            radius: width / 2
            color: "transparent"
        }

        MaterialShape {
            anchors.fill: parent
            shape: sideHover.hovered && root.actionsEnabled ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
            color: WidgetColorScheme.accentColor
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: actions.details(root.sideKey).icon
            iconSize: 30
            fill: 1
            color: WidgetColorScheme.onAccentColor
        }

        HoverHandler {
            id: sideHover
            cursorShape: Qt.PointingHandCursor
        }
        StyledToolTip {
            text: actions.details(root.sideKey).displayName
            extraVisibleCondition: sideHover.hovered
        }
    }
}
