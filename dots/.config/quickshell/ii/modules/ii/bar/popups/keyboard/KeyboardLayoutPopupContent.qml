pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The layout in use as a hero — its code in tall condensed digits, its name, and quietly its
 * variant and letter family (QWERTY, AZERTY…) — over a deck of tiles to switch to another one,
 * each with its own shape that morphs on hover and becomes a burst
 * holding the check in use. The hero is the first child, so the popup surface opens on it alone.
 */
ColumnLayout {
    id: content

    property bool opened: false
    property real popupOpenProgress: 0

    readonly property int count: HyprlandXkb.layoutCodes.length
    readonly property int activeIndex: {
        if (HyprlandXkb.activeLayoutIndex >= 0 && HyprlandXkb.activeLayoutIndex < count)
            return HyprlandXkb.activeLayoutIndex;
        const code = HyprlandXkb.currentLayoutCode;
        return code ? HyprlandXkb.layoutCodes.findIndex(c => code.startsWith(c)) : -1;
    }
    readonly property string activeCode: activeIndex >= 0 ? HyprlandXkb.layoutCodes[activeIndex] : HyprlandXkb.currentLayoutCode
    readonly property string activeVariant: activeIndex >= 0 ? (HyprlandXkb.layoutVariants[activeIndex] ?? "") : ""
    readonly property string activeSignature: content.signature(activeCode, activeVariant)

    readonly property var axesCode: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var tileShapes: [MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Clover4Leaf,
        MaterialShape.Shape.Cookie6Sided, MaterialShape.Shape.Sunny, MaterialShape.Shape.Flower, MaterialShape.Shape.Cookie7Sided]

    // A Layout computes its own implicitWidth, so the width is carried by the hero.
    readonly property int panelWidth: 420
    spacing: 14

    Component.onCompleted: HyprlandXkb.requestLayoutDescriptions()
    onCountChanged: HyprlandXkb.requestLayoutDescriptions()

    // The letter row that names a layout family. Only families known for sure: an unknown
    // layout shows nothing rather than a QWERTY it may not have.
    function signature(code, variant) {
        const c = String(code || "").toLowerCase();
        const v = String(variant || "").toLowerCase();
        if (v.includes("dvorak")) return "',.PYF";
        if (v.includes("colemak")) return "QWFPGJ";
        if (v.includes("workman")) return "QDRWBJ";
        if (v.includes("bepo")) return "BÉPOÈ^";
        if (["fr", "be"].includes(c)) return "AZERTY";
        if (["de", "at", "ch", "cz", "hu", "sk", "si", "hr", "ba"].includes(c)) return "QWERTZ";
        if (["ru", "ua", "by"].includes(c)) return "ЙЦУКЕН";
        if (["us", "gb", "br", "pt", "es", "latam", "it", "nl", "se", "no", "dk", "fi", "is", "ee",
             "lv", "lt", "pl", "ro", "tr", "ie", "ca", "jp", "kr", "ph", "id", "my", "za", "au"].includes(c))
            return "QWERTY";
        return "";
    }

    function layoutName(index) {
        if (index === content.activeIndex && HyprlandXkb.currentLayoutName.length > 0)
            return HyprlandXkb.currentLayoutName;
        return HyprlandXkb.descriptionFor(index) || String(HyprlandXkb.layoutCodes[index] ?? "").toUpperCase();
    }

    function deviceName(name) {
        if (!name)
            return "";
        if (name.includes("at-translated-set-2") || name.includes("i8042"))
            return Translation.tr("Built-in keyboard");
        return name.split("-").filter(Boolean)
            .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
    }

    // ── Entrance: one scalar, every piece reads its slice ───────────────
    readonly property bool startAnim: content.opened && content.popupOpenProgress > 0.6
    // Reset only once the surface has fully collapsed, so pieces shrink with it.
    readonly property bool collapsed: content.popupOpenProgress === 0.0
    property real reveal: 0
    onStartAnimChanged: {
        if (!startAnim)
            return;
        revealAnim.stop();
        content.reveal = 0;
        revealAnim.start();
    }
    onCollapsedChanged: {
        if (collapsed) {
            revealAnim.stop();
            content.reveal = 0;
        }
    }
    NumberAnimation {
        id: revealAnim
        target: content
        property: "reveal"
        from: 0
        to: 1
        duration: Appearance.reducedMotion ? 0 : 620
    }
    function slice(slot) {
        const lead = 0.08, span = 0.45, step = 0.06;
        const t = Math.max(0, Math.min(1, (content.reveal - lead * (slot > 0 ? 1 : 0) - step * slot) / span));
        return t * t * (3 - 2 * t);
    }

    // ── Hero: the layout in use ─────────────────────────────────────────
    Rectangle {
        id: hero

        Layout.fillWidth: true
        Layout.preferredWidth: content.panelWidth
        implicitHeight: heroRow.implicitHeight + 40
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colPrimaryContainer
        opacity: content.slice(0)
        transform: Translate {
            y: (1 - content.slice(0)) * 8
        }

        RowLayout {
            id: heroRow

            anchors {
                fill: parent
                margins: 20
                leftMargin: 22
            }
            spacing: 18

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 170
                text: content.activeCode.toUpperCase() || "—"
                font.family: Appearance.font.family.main
                font.variableAxes: content.axesCode
                font.pixelSize: text.length > 3 ? 54 : 76
                color: Appearance.colors.colOnPrimaryContainer
                elide: Text.ElideRight
                animateChange: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                StyledText {
                    text: Translation.tr("Typing in")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.72
                }
                StyledText {
                    Layout.fillWidth: true
                    text: content.activeIndex >= 0 ? content.layoutName(content.activeIndex) : HyprlandXkb.currentLayoutName
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnPrimaryContainer
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                // Variant and letter family, quietly: a detail, not the subject.
                RowLayout {
                    Layout.topMargin: 3
                    visible: content.activeVariant.length > 0 || content.activeSignature.length > 0
                    spacing: 10

                    Rectangle {
                        visible: content.activeVariant.length > 0
                        implicitWidth: variantText.implicitWidth + 18
                        implicitHeight: variantText.implicitHeight + 6
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary

                        StyledText {
                            id: variantText
                            anchors.centerIn: parent
                            text: content.activeVariant
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                    StyledText {
                        visible: content.activeSignature.length > 0
                        text: content.activeSignature
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2.5
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.6
                        animateChange: true
                    }
                }
            }
        }
    }

    // ── Deck: every configured layout as a tile ─────────────────────────
    StyledText {
        visible: content.count > 1
        Layout.leftMargin: 8
        Layout.topMargin: 4
        text: Translation.tr("Switch layout")
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
        color: Appearance.colors.colOnSurfaceVariant
        opacity: content.slice(1)
    }

    GridLayout {
        visible: content.count > 1
        Layout.fillWidth: true
        // Four would leave one tile alone on a row; two by two reads better.
        columns: content.count === 4 ? 2 : Math.max(1, Math.min(content.count, 3))
        columnSpacing: 10
        rowSpacing: 10
        uniformCellWidths: true

        Repeater {
            model: HyprlandXkb.layoutCodes

            delegate: RippleButton {
                id: tile

                required property string modelData
                required property int index
                readonly property bool active: tile.index === content.activeIndex
                readonly property real entry: content.slice(1.5 + tile.index)
                readonly property color colContent: tile.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                // 0 idle, 1 in use; hover sits between. Drives the code's weight and width.
                property real emphasis: tile.active ? 1 : (tile.hovered ? 0.55 : 0)
                Behavior on emphasis {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Layout.fillWidth: true
                implicitHeight: 112
                toggled: tile.active
                // Shape is state: firm corners idle, softer under the hand, a pill in use.
                buttonRadius: tile.active ? Math.min(height / 2, Appearance.rounding.verylarge)
                    : (tile.hovered ? Appearance.rounding.large : Appearance.rounding.normal)

                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Active
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                colBackgroundToggledActive: Appearance.colors.colPrimaryActive

                opacityBehaviorEnabled: content.reveal >= 1
                opacity: tile.entry
                transform: Translate {
                    y: (1 - tile.entry) * 10
                }

                onClicked: {
                    if (!tile.active)
                        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(tile.index)]);
                }

                StyledToolTip {
                    text: tileName.text
                    visible: tile.hovered && tileName.truncated
                }

                contentItem: Item {
                    StyledText {
                        anchors {
                            left: parent.left
                            top: parent.top
                            leftMargin: 18
                            topMargin: 12
                        }
                        text: tile.modelData.toUpperCase()
                        font.family: Appearance.font.family.main
                        font.variableAxes: ({
                            "wght": Math.round(500 + 280 * tile.emphasis),
                            "wdth": Math.round(28 + 22 * tile.emphasis),
                            "ROND": 100
                        })
                        font.pixelSize: 40
                        color: tile.colContent
                    }

                    // Each layout carries its own shape; hovering morphs it, and the layout
                    // in use takes a burst holding the check.
                    MaterialShape {
                        id: badge
                        anchors {
                            right: parent.right
                            top: parent.top
                            rightMargin: 14
                            topMargin: 14
                        }
                        implicitSize: 46
                        shape: tile.active ? MaterialShape.Shape.SoftBurst
                            : tile.hovered ? MaterialShape.Shape.Cookie12Sided
                            : content.tileShapes[tile.index % content.tileShapes.length]
                        color: tile.active ? Appearance.colors.colOnPrimary : Appearance.colors.colSecondary
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: String(tile.index + 1)
                            font.family: Appearance.font.family.main
                            font.variableAxes: content.axesCode
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondary
                            opacity: tile.active ? 0 : 1
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                            opacity: tile.active ? 1 : 0
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }

                    StyledText {
                        id: tileName
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            leftMargin: 18
                            rightMargin: 16
                            bottomMargin: 15
                        }
                        text: HyprlandXkb.descriptionFor(tile.index) || content.layoutName(tile.index)
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.DemiBold
                        color: tile.colContent
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Footer: which keyboard Hyprland is reading ──────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 2
        visible: HyprlandXkb.mainKeyboardName.length > 0
        spacing: 6
        opacity: content.slice(3 + Math.min(content.count, 3))

        MaterialSymbol {
            text: "keyboard"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            text: content.deviceName(HyprlandXkb.mainKeyboardName)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
        StyledText {
            visible: content.count === 1
            text: Translation.tr("Only layout configured")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
