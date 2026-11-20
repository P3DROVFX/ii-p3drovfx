pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * One At a Glance page, drawn from an AtAGlanceService page object. The
 * templates follow Smartspacer's: basic, date (title + up to two
 * complications), image, list, headToHead, carousel, button and a
 * complications-only page. Sizes are design units; the widget scales them.
 */
Item {
    id: root

    property var page: null
    property bool interactive: true

    property color colTitle
    property color colSubtitle
    property color colAccent
    property color colButton
    property color colOnButton

    // Design metrics.
    readonly property real titleSize: 23
    readonly property real subtitleSize: 15
    readonly property real smallSize: 12
    readonly property real iconSize: 18
    readonly property real leadingSize: 52
    readonly property real gap: 12
    readonly property real lineGap: 2

    readonly property string template: root.page?.template ?? "basic"
    readonly property var chips: root.page?.complications ?? []
    readonly property bool hasLeading: ["image", "headToHead", "button"].includes(root.template)
        && !(root.template === "image" && String(root.page?.image ?? "") === "")
    readonly property bool hasTrailing: (root.template === "list" && (root.page?.items ?? []).length > 0)
        || (root.template === "carousel" && (root.page?.columns ?? []).length > 0)

    signal buttonActivated(var action)

    implicitHeight: 72

    // The action under a point (this item's coordinates): a complication's own
    // action wins over the page's.
    function actionAt(x, y) {
        const repeaters = [chipRepeater, bigChipRepeater];
        for (const rep of repeaters) {
            for (let i = 0; i < rep.count; i++) {
                const chip = rep.itemAt(i);
                if (!chip || !chip.visible)
                    continue;
                const p = chip.mapFromItem(root, x, y);
                if (p.x >= 0 && p.y >= 0 && p.x <= chip.width && p.y <= chip.height)
                    return { complication: true, action: chip.chipAction };
            }
        }
        return { complication: false, action: root.page?.action ?? null };
    }

    component Chip: Row {
        id: chip
        required property int index
        property var entry: root.chips[index] ?? null
        property real textSize: root.subtitleSize
        property real glyphSize: root.iconSize
        readonly property var chipAction: chip.entry?.action ?? null
        spacing: 6
        visible: chip.entry !== null && (String(chip.entry.text ?? "") !== "" || String(chip.entry.icon ?? "") !== "" || String(chip.entry.iconImage ?? "") !== "")

        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: String(chip.entry?.iconImage ?? "") !== ""
            source: chip.entry?.iconImage ?? ""
            width: chip.glyphSize * 1.2
            height: width
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: String(chip.entry?.iconImage ?? "") === "" && String(chip.entry?.icon ?? "") !== ""
            text: chip.entry?.icon ?? ""
            iconSize: chip.glyphSize
            fill: 1
            color: root.colSubtitle
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.entry?.text ?? ""
            color: root.colSubtitle
            font.pixelSize: chip.textSize
            font.family: Appearance.font.family.main
        }
    }

    // ── Complications-only page ────────────────────────────────────────────────
    Row {
        id: bigChips
        visible: root.template === "complications"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        spacing: 20

        Repeater {
            id: bigChipRepeater
            model: root.template === "complications" ? root.chips.length : 0
            delegate: Chip {
                textSize: root.titleSize
                glyphSize: root.titleSize
            }
        }
    }

    RowLayout {
        visible: root.template !== "complications"
        anchors.fill: parent
        spacing: root.gap

        // ── Leading: image, head-to-head or button ─────────────────────────────
        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.hasLeading
            visible: active
            sourceComponent: root.template === "image" ? imageLeading
                : root.template === "headToHead" ? headToHeadLeading : buttonLeading
        }

        // ── Text ───────────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: root.lineGap

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.page?.title ?? ""
                color: root.colTitle
                font.pixelSize: root.titleSize
                font.family: Appearance.font.family.main
                elide: root.page?.type === "calendar" ? Text.ElideMiddle : Text.ElideRight
                maximumLineCount: 1
            }

            // Subtitle line: icon + subtitle (+ sub-complication), or the date
            // template's complications.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.template === "date" ? root.chips.length > 0
                    : (String(root.page?.subtitle ?? "") !== "" || String(root.page?.icon ?? "") !== "" || String(root.page?.iconImage ?? "") !== "")

                Image {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.template !== "date" && String(root.page?.iconImage ?? "") !== ""
                    source: visible ? root.page.iconImage : ""
                    Layout.preferredWidth: root.iconSize * 1.2
                    Layout.preferredHeight: root.iconSize * 1.2
                    sourceSize: Qt.size(root.iconSize * 2.4, root.iconSize * 2.4)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.template !== "date" && String(root.page?.iconImage ?? "") === "" && String(root.page?.icon ?? "") !== ""
                    text: root.page?.icon ?? ""
                    iconSize: root.iconSize
                    fill: 1
                    color: root.colAccent
                }
                StyledText {
                    Layout.fillWidth: !subComplication.visible
                    Layout.maximumWidth: subComplication.visible ? implicitWidth : -1
                    visible: root.template !== "date" && text !== ""
                    text: root.page?.subtitle ?? ""
                    color: root.colSubtitle
                    font.pixelSize: root.subtitleSize
                    font.family: Appearance.font.family.main
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Sub-complication (a calendar event's location).
                Row {
                    id: subComplication
                    Layout.fillWidth: true
                    visible: root.template !== "date" && (root.page?.subComplication ?? null) !== null
                    spacing: 6
                    clip: true
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "·"
                        color: root.colSubtitle
                        font.pixelSize: root.subtitleSize
                    }
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.page?.subComplication?.icon ?? ""
                        iconSize: root.iconSize
                        fill: 1
                        color: root.colAccent
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, subComplication.width - x)
                        text: root.page?.subComplication?.text ?? ""
                        color: root.colSubtitle
                        font.pixelSize: root.subtitleSize
                        font.family: Appearance.font.family.main
                        elide: Text.ElideRight
                    }
                }

                Row {
                    visible: root.template === "date"
                    spacing: 16
                    Repeater {
                        id: chipRepeater
                        model: root.template === "date" ? root.chips.length : 0
                        delegate: Chip {}
                    }
                }

                Item {
                    Layout.fillWidth: true
                    visible: root.template === "date"
                }
            }
        }

        // ── Trailing: list items or carousel ───────────────────────────────────
        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.hasTrailing
            visible: active
            sourceComponent: root.template === "list" ? listTrailing : carouselTrailing
        }
    }

    Component {
        id: imageLeading
        // ClippingRectangle: a plain Rectangle's clip is square, the art
        // would keep sharp corners under the radius.
        ClippingRectangle {
            width: root.leadingSize
            height: root.leadingSize
            radius: Appearance.rounding.normal
            color: Qt.alpha(root.colTitle, 0.12)
            StyledImage {
                anchors.fill: parent
                source: root.page?.image ?? ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(root.leadingSize * 2, root.leadingSize * 2)
            }
        }
    }

    Component {
        id: headToHeadLeading
        Column {
            spacing: 2
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: root.page?.header ?? ""
                color: root.colSubtitle
                font.pixelSize: root.smallSize
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 120)
                horizontalAlignment: Text.AlignHCenter
            }
            Row {
                spacing: 8
                Repeater {
                    model: [root.page?.home, root.page?.away]
                    delegate: Row {
                        id: team
                        required property var modelData
                        required property int index
                        spacing: 4
                        layoutDirection: team.index === 0 ? Qt.LeftToRight : Qt.RightToLeft
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            source: team.modelData?.logo ?? ""
                            visible: source.toString() !== ""
                            sourceSize: Qt.size(48, 48)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: team.modelData?.score !== "" ? team.modelData?.score ?? "" : (team.modelData?.name ?? "")
                            color: root.colTitle
                            font.pixelSize: root.titleSize - 2
                        }
                    }
                }
            }
        }
    }

    Component {
        id: buttonLeading
        RippleButton {
            implicitHeight: 40
            implicitWidth: buttonRow.implicitWidth + 28
            buttonRadius: height / 2
            colBackground: root.colButton
            colBackgroundHover: Qt.lighter(root.colButton, 1.08)
            colRipple: Qt.alpha(root.colOnButton, 0.24)
            enabled: root.interactive
            onClicked: root.buttonActivated(root.page?.buttonAction ?? null)
            contentItem: Item {
                Row {
                    id: buttonRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.page?.buttonIcon ?? ""
                        iconSize: 20
                        fill: 1
                        color: root.colOnButton
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.page?.buttonText ?? ""
                        color: root.colOnButton
                        font.pixelSize: root.subtitleSize - 1
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    Component {
        id: listTrailing
        Row {
            spacing: 6
            Column {
                spacing: 1
                Repeater {
                    model: (root.page?.items ?? []).slice(0, 3)
                    delegate: StyledText {
                        required property var modelData
                        text: modelData
                        color: root.colSubtitle
                        font.pixelSize: root.smallSize
                        font.family: Appearance.font.family.main
                        width: Math.min(implicitWidth, 150)
                        elide: Text.ElideRight
                    }
                }
            }
            MaterialSymbol {
                text: "list"
                iconSize: 14
                color: root.colSubtitle
            }
        }
    }

    Component {
        id: carouselTrailing
        Row {
            spacing: 10
            Repeater {
                model: root.page?.columns ?? []
                delegate: Column {
                    id: column
                    required property var modelData
                    spacing: 1
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: column.modelData.upper ?? ""
                        color: root.colSubtitle
                        font.pixelSize: root.smallSize - 1
                    }
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 22
                        height: 22
                        source: column.modelData.icon ?? ""
                        sourceSize: Qt.size(44, 44)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: column.modelData.lower ?? ""
                        color: root.colTitle
                        font.pixelSize: root.smallSize
                    }
                }
            }
        }
    }
}
