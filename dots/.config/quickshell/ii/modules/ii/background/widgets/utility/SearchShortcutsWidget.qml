pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Search with Shortcuts (2x0.5): the search bar on a card, with a row of
 * four shortcuts under it - the Pixel bar with its suggestion chips. The bar
 * opens the launcher's search and carries one accent key at its end; the
 * shortcuts are a connected button group whose pressed key rounds into a
 * pill. Every key is picked in Settings.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "search_shortcuts"
    designWidth: 492
    designHeight: 124
    cardRadius: Appearance.rounding.verylarge

    readonly property real padding: 10
    readonly property real barHeight: 56
    readonly property real chipHeight: 40
    readonly property string barKey: root.options?.barAction ?? "ai_chat"
    readonly property var shortcuts: [
        root.options?.shortcut1 ?? "clipboard",
        root.options?.shortcut2 ?? "emojis",
        root.options?.shortcut3 ?? "files",
        root.options?.shortcut4 ?? "lens"
    ]

    SearchActions {
        id: actions
    }

    // The bar searches through the widget's own pointer area (cardTapped): a
    // button there would take the press, and the widget could not be moved.
    onCardTapped: at => {
        if (bar.contains(bar.mapFromItem(root.contentItem, at.x, at.y)))
            actions.run("search");
    }

    // ── The bar ──
    Rectangle {
        id: bar
        x: root.padding
        y: root.padding
        width: root.designWidth - root.padding * 2
        height: root.barHeight
        radius: root.pill(height)
        color: barHover.hovered && root.actionsEnabled
            ? ColorUtils.mix(WidgetColorScheme.textColorOnBg, WidgetColorScheme.pillBgColor, root.pressed ? 0.12 : 0.06)
            : WidgetColorScheme.pillBgColor
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        HoverHandler {
            id: barHover
        }

        Item {
            anchors.fill: parent
            MaterialSymbol {
                id: searchGlyph
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "search"
                iconSize: 26
                color: WidgetColorScheme.textColorOnBg
            }

            StyledText {
                anchors.left: searchGlyph.right
                anchors.leftMargin: 12
                anchors.right: barKey.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.options?.hint || Translation.tr("Search apps, files and the web")
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.large
                font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
            }

            WidgetButton {
                id: barKey
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: keyLabel.implicitWidth + 60
                height: root.barHeight - 12
                symbol: actions.details(root.barKey).icon
                symbolSize: 20
                label: actions.details(root.barKey).displayName
                labelSize: Appearance.font.pixelSize.small
                labelAxes: ({ "wght": 650, "wdth": 95, "ROND": 100 })
                colFill: WidgetColorScheme.accentColor
                colContent: WidgetColorScheme.onAccentColor
                restRadius: barKey.hovered ? Appearance.rounding.normal : root.pill(height)
                onClicked: if (root.actionsEnabled) actions.run(root.barKey)

                StyledText {
                    id: keyLabel
                    visible: false
                    text: barKey.label
                    font.pixelSize: barKey.labelSize
                }
            }
        }
    }

    // ── Shortcuts: a connected button group ──
    Row {
        id: chips
        x: root.padding
        y: bar.y + bar.height + 8
        width: root.designWidth - root.padding * 2
        height: root.chipHeight
        spacing: 3

        Repeater {
            model: root.shortcuts

            delegate: WidgetButton {
                id: chip
                required property string modelData
                required property int index
                readonly property bool first: chip.index === 0
                readonly property bool last: chip.index === root.shortcuts.length - 1
                readonly property real outerRadius: root.pill(height)
                property real joinRadius: chip.down || chip.hovered ? chip.outerRadius : Appearance.rounding.verysmall
                Behavior on joinRadius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                width: (chips.width - chips.spacing * (root.shortcuts.length - 1)) / root.shortcuts.length
                height: chips.height
                symbol: actions.details(chip.modelData).icon
                symbolSize: 18
                label: actions.details(chip.modelData).displayName
                labelSize: Appearance.font.pixelSize.smaller
                labelAxes: ({ "wght": 620, "wdth": 92, "ROND": 100 })
                colFill: chip.index % 2 === 0 ? WidgetColorScheme.pillBgColor : ColorUtils.mix(WidgetColorScheme.accentColor, WidgetColorScheme.pillBgColor, 0.14)
                colContent: WidgetColorScheme.textColorOnBg
                topLeftRadius: chip.first ? chip.outerRadius : chip.joinRadius
                bottomLeftRadius: chip.first ? chip.outerRadius : chip.joinRadius
                topRightRadius: chip.last ? chip.outerRadius : chip.joinRadius
                bottomRightRadius: chip.last ? chip.outerRadius : chip.joinRadius
                onClicked: if (root.actionsEnabled) actions.run(chip.modelData)
            }
        }
    }
}
