pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import "../../../dock/utilities/UnitConverter.js" as Units

/*
 * Converter (2x1): the dock Converter's units on the desktop. A connected
 * button group picks the category (the chosen one widens to name itself);
 * below, the value you type on the left and the result on the right, a swap
 * key sitting in a notch between them. Each side's unit chip turns its pane
 * into the list of units; a click on the result copies it. Category, pair and
 * value are remembered per widget.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "converter_2x1"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 14
    readonly property real barHeight: 40
    readonly property real paneGap: 12
    readonly property real swapSize: 48
    readonly property real notchSize: 64

    readonly property string categoryId: String(Units.category(root.options?.category ?? "length").id)
    readonly property var category: Units.category(root.categoryId)
    readonly property string fromId: {
        const id = String(root.options?.from ?? "");
        return Units.unit(root.categoryId, id) ? id : String(Units.defaultPair(root.categoryId).from);
    }
    readonly property string toId: {
        const id = String(root.options?.to ?? "");
        return Units.unit(root.categoryId, id) ? id : String(Units.defaultPair(root.categoryId).to);
    }
    readonly property real input: isFinite(Number(root.options?.value)) ? Number(root.options.value) : 1
    readonly property real output: Units.convert(root.input, root.categoryId, root.fromId, root.toId)

    // Which pane shows its unit list instead of its value: "", "from" or "to".
    property string picking: ""
    property bool copied: false

    function setCategory(id) {
        if (!root.actionsEnabled || id === root.categoryId)
            return;
        const pair = Units.defaultPair(id);
        root.picking = "";
        root.options.category = id;
        root.options.from = pair.from;
        root.options.to = pair.to;
    }
    function pickUnit(side, id) {
        if (!root.actionsEnabled)
            return;
        if (side === "from")
            root.options.from = id;
        else
            root.options.to = id;
        root.picking = "";
    }
    function swap() {
        if (!root.actionsEnabled)
            return;
        const value = root.output;
        const from = root.fromId;
        root.options.from = root.toId;
        root.options.to = from;
        if (isFinite(value))
            root.options.value = Number(Units.format(value)) || value;
        root.picking = "";
    }
    function copyResult() {
        if (!root.actionsEnabled || !isFinite(root.output))
            return;
        Quickshell.clipboardText = Units.format(root.output);
        root.copied = true;
        copiedTimer.restart();
    }

    Timer {
        id: copiedTimer
        interval: 1600
        onTriggered: root.copied = false
    }

    // ── Category: a connected button group ──
    Row {
        id: bar
        x: root.padding
        y: root.padding
        width: root.designWidth - root.padding * 2
        height: root.barHeight
        spacing: 3

        readonly property real unitWidth: (bar.width - bar.spacing * (Units.categories.length - 1)) / (Units.categories.length + 2)

        Repeater {
            model: Units.categories

            delegate: WidgetButton {
                id: segment
                required property var modelData
                required property int index
                readonly property bool chosen: root.categoryId === segment.modelData.id
                readonly property bool first: segment.index === 0
                readonly property bool last: segment.index === Units.categories.length - 1
                readonly property real outerRadius: root.pill(height)
                property real joinRadius: segment.chosen || segment.down ? segment.outerRadius : Appearance.rounding.verysmall
                Behavior on joinRadius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                width: bar.unitWidth * (segment.chosen ? 3 : 1)
                height: bar.height
                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                symbol: segment.modelData.symbol
                symbolSize: 18
                symbolFilled: segment.chosen
                label: segment.chosen ? Translation.tr(segment.modelData.title) : ""
                labelSize: Appearance.font.pixelSize.smaller
                labelAxes: ({ "wght": 650, "wdth": 90, "ROND": 100 })
                colFill: segment.chosen ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor
                colContent: segment.chosen ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
                topLeftRadius: segment.first ? segment.outerRadius : segment.joinRadius
                bottomLeftRadius: segment.first ? segment.outerRadius : segment.joinRadius
                topRightRadius: segment.last ? segment.outerRadius : segment.joinRadius
                bottomRightRadius: segment.last ? segment.outerRadius : segment.joinRadius
                onClicked: root.setCategory(segment.modelData.id)

                StyledToolTip {
                    text: Translation.tr(segment.modelData.title)
                    extraVisibleCondition: !segment.chosen && segment.hovered
                }
            }
        }
    }

    // ── One side: unit chip on top, the value (or the unit list) below ──
    component Pane: Rectangle {
        id: pane

        property string side: "from"
        property string unitId: ""
        property color colContent: WidgetColorScheme.textColorOnBg
        property color colChip: WidgetColorScheme.cardBgColor
        property color colChipContent: WidgetColorScheme.textColorOnBg
        readonly property bool picking: root.picking === pane.side
        // The value goes in the pane's own children, anchored to this box,
        // which keeps clear of the swap notch on the inner side.
        readonly property alias valueArea: valueBox

        y: bar.y + bar.height + 10
        width: (root.designWidth - root.padding * 2 - root.paneGap) / 2
        height: root.designHeight - pane.y - root.padding
        radius: Appearance.rounding.large

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        WidgetButton {
            id: unitChip
            x: 12
            y: 12
            width: Math.max(72, chipMeasure.implicitWidth + 50)
            height: 34
            symbol: pane.picking ? "close" : "unfold_more"
            symbolSize: 16
            label: Units.unit(root.categoryId, pane.unitId)?.label ?? ""
            labelSize: Appearance.font.pixelSize.small
            labelAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
            colFill: pane.colChip
            colContent: pane.colChipContent
            restRadius: pane.picking ? Appearance.rounding.small : root.pill(height)
            onClicked: root.picking = pane.picking ? "" : pane.side

            StyledText {
                id: chipMeasure
                visible: false
                text: unitChip.label
                font.pixelSize: unitChip.labelSize
            }
        }

        Item {
            id: valueBox
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.top: unitChip.bottom
            anchors.margins: 14
            anchors.topMargin: 6
            anchors.leftMargin: pane.side === "to" ? root.notchSize / 2 + 8 : 14
            anchors.rightMargin: pane.side === "from" ? root.notchSize / 2 + 8 : 14
            opacity: pane.picking ? 0 : 1
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Flow {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: unitChip.bottom
            anchors.margins: 12
            anchors.topMargin: 10
            spacing: 5
            opacity: pane.picking ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Repeater {
                model: root.category.units

                delegate: WidgetButton {
                    id: unitOption
                    required property var modelData
                    readonly property bool chosen: pane.unitId === unitOption.modelData.id
                    width: optionMeasure.implicitWidth + 22
                    height: 30
                    label: unitOption.modelData.label
                    labelSize: Appearance.font.pixelSize.smaller
                    labelAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                    colFill: unitOption.chosen ? pane.colContent : pane.colChip
                    colContent: unitOption.chosen ? pane.color : pane.colChipContent
                    restRadius: unitOption.chosen ? Appearance.rounding.small : root.pill(height)
                    onClicked: root.pickUnit(pane.side, unitOption.modelData.id)

                    StyledText {
                        id: optionMeasure
                        visible: false
                        text: unitOption.label
                        font.pixelSize: unitOption.labelSize
                    }
                }
            }
        }
    }

    // ── From: typed ──
    Pane {
        id: fromPane
        x: root.padding
        side: "from"
        unitId: root.fromId
        color: entry.holding ? ColorUtils.mix(WidgetColorScheme.accentColor, WidgetColorScheme.pillBgColor, 0.18) : WidgetColorScheme.pillBgColor

        TextInput {
            id: field
            anchors.left: fromPane.valueArea.left
            anchors.right: fromPane.valueArea.right
            anchors.bottom: fromPane.valueArea.bottom
            anchors.bottomMargin: -6
            opacity: fromPane.valueArea.opacity
            visible: fromPane.valueArea.visible
            readonly property real fitSize: Math.max(24, Math.min(64, width / (Math.max(3, field.text.length) * 0.55)))
            text: Units.format(root.input)
            color: WidgetColorScheme.textColorOnBg
            selectionColor: WidgetColorScheme.accentColor
            selectedTextColor: WidgetColorScheme.onAccentColor
            font.family: Appearance.font.family.main
            font.pixelSize: field.fitSize
            font.variableAxes: ({ "wght": 500, "wdth": 75, "ROND": 100 })
            clip: true
            selectByMouse: entry.holding
            readOnly: !entry.holding
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            onTextEdited: {
                const value = Units.parse(field.text);
                if (isFinite(value) && root.actionsEnabled)
                    root.options.value = value;
            }
            onEditingFinished: entry.end()
            Keys.onEscapePressed: entry.end()
            onActiveFocusChanged: {
                if (field.activeFocus) {
                    // Typing writes the value back; a live binding would
                    // reformat "1." to "1" under the cursor.
                    field.text = Units.format(root.input);
                    field.selectAll();
                } else
                    field.text = Qt.binding(() => Units.format(root.input));
            }
        }

        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 21
            visible: !fromPane.picking
            text: entry.holding ? Translation.tr("Type a value") : Translation.tr("Click to type")
            color: WidgetColorScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
        }

        // Arms the keyboard on the first click; then clicks go to the text.
        MouseArea {
            anchors.fill: fromPane.valueArea
            enabled: root.actionsEnabled && !entry.holding && !fromPane.picking
            cursorShape: Qt.IBeamCursor
            onClicked: entry.begin()
        }
    }

    WidgetTextEntry {
        id: entry
        field: field
    }

    // ── To: the result ──
    Pane {
        id: toPane
        x: root.designWidth - root.padding - width
        side: "to"
        unitId: root.toId
        color: WidgetColorScheme.accentColor
        colContent: WidgetColorScheme.onAccentColor
        colChip: ColorUtils.mix(WidgetColorScheme.onAccentColor, WidgetColorScheme.accentColor, 0.16)
        colChipContent: WidgetColorScheme.onAccentColor

        StyledText {
            anchors.left: toPane.valueArea.left
            anchors.right: toPane.valueArea.right
            anchors.bottom: toPane.valueArea.bottom
            anchors.bottomMargin: -6
            opacity: toPane.valueArea.opacity
            visible: toPane.valueArea.visible
            height: 70
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignBottom
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 20
            text: Units.format(root.output)
            color: WidgetColorScheme.onAccentColor
            font.family: Appearance.font.family.main
            font.pixelSize: 64
            font.variableAxes: ({ "wght": 750, "wdth": 75, "ROND": 100 })
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 20
            visible: !toPane.picking
            spacing: 4
            opacity: resultArea.containsMouse || root.copied ? 1 : 0.7

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: root.copied ? "check" : "content_copy"
                iconSize: 14
                color: WidgetColorScheme.onAccentColor
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.copied ? Translation.tr("Copied") : Translation.tr("Copy")
                color: WidgetColorScheme.onAccentColor
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
            }
        }

        MouseArea {
            id: resultArea
            anchors.fill: toPane.valueArea
            enabled: root.actionsEnabled && !toPane.picking
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.copyResult()
        }
    }

    // ── Swap, in a notch cut between the panes ──
    Rectangle {
        id: notch
        x: (root.designWidth - root.notchSize) / 2
        y: fromPane.y + (fromPane.height - root.notchSize) / 2
        width: root.notchSize
        height: root.notchSize
        radius: width / 2
        color: root.cardColor
        visible: root.picking === ""

        HoverHandler {
            id: swapHover
            enabled: root.actionsEnabled
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: root.actionsEnabled
            onTapped: root.swap()
        }

        MaterialShape {
            anchors.centerIn: parent
            width: root.swapSize
            height: root.swapSize
            shape: swapHover.hovered ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
            color: WidgetColorScheme.pillFillColor
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: "swap_horiz"
            iconSize: 24
            fill: 1
            color: WidgetColorScheme.textColorOnPillFill
        }
    }
}
