pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.services
import "../functions/KeyboardMap.js" as KeyboardMap

// Shared KLE renderer for the typing preview and the editable cheatsheet.
Item {
    id: root
    property var keys: []
    property var entries: []
    property real unitWidth: 1
    property real unitHeight: 1
    property real unit: 40
    property real keySpacing: 5
    property real labelSize: Appearance.font.pixelSize.normal
    property bool interactive: false
    property bool showSymbols: false
    property int selectedKey: -1
    property string nextChar: ""
    property string pressedChar: ""
    // Optional presentation metadata; only the typing tutor supplies it.
    property var keyHints: []
    property bool hintTooltips: false
    property bool preserveInputFocus: false
    property Item hoveredKeyButton: null
    signal keyClicked(int keyIndex)

    implicitWidth: root.unitWidth * root.unit
    implicitHeight: root.unitHeight * root.unit

    // One tooltip for the whole keyboard, instead of one popup tree per cap.
    StyledToolTip {
        parent: root.hoveredKeyButton ?? root
        extraVisibleCondition: (root.interactive || root.hintTooltips) && root.visible && root.hoveredKeyButton !== null
        text: root.hoveredKeyButton?.keyDescription ?? ""
    }

    Repeater {
        model: root.keys
        delegate: Item {
            id: cap
            required property int index
            required property var modelData
            readonly property var entry: root.entries[index] ?? ({})
            readonly property var hint: root.keyHints[index] ?? ({})
            readonly property bool chosen: root.interactive && root.selectedKey === index
            readonly property bool pressed: root.pressedChar.length > 0 && String(entry.char || "").toLowerCase() === root.pressedChar.toLowerCase()
            readonly property bool next: root.nextChar.length > 0 && String(entry.char || "").toLowerCase() === root.nextChar.toLowerCase()
            readonly property string superGlyph: root.showSymbols && !entry.icon && (entry.label === "Super" || entry.label === "R\nSuper")
                ? String(Config.options.cheatsheet.superKey || "") : ""
            readonly property string symbol: !root.showSymbols || superGlyph || entry.icon === "none" ? "" : (entry.icon || KeyboardMap.automaticIcon(entry.label))
            readonly property color foreground: chosen || pressed ? Appearance.colors.colOnPrimary
                : hint.ink ?? (next ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface)
            x: modelData.x * root.unit
            y: modelData.y * root.unit
            width: Math.max(1, modelData.w * root.unit - root.keySpacing)
            height: Math.max(1, modelData.h * root.unit - root.keySpacing)
            opacity: entry.inherited && !chosen && !hint.fill ? 0.55 : 1
            Accessible.role: Accessible.StaticText
            Accessible.name: (entry.label || "") + (hint.name ? ": " + hint.name : "")
            transform: Rotation {
                angle: cap.modelData.r
                origin.x: (cap.modelData.rx - cap.modelData.x) * root.unit
                origin.y: (cap.modelData.ry - cap.modelData.y) * root.unit
            }

            KeyboardKey {
                anchors.fill: parent
                key: cap.symbol || cap.superGlyph ? "" : (cap.entry.label || (root.interactive ? "—" : ""))
                fitText: true
                horizontalPadding: 3
                verticalPadding: cap.hint.fill ? 5 : 2
                borderWidth: 0
                extraBottomBorderWidth: 0
                borderColor: "transparent"
                borderRadius: Appearance.rounding.verysmall
                pixelSize: root.labelSize
                textColor: cap.foreground
                keyColor: cap.chosen || cap.pressed ? Appearance.colors.colPrimary
                    : cap.hint.fill ?? (cap.next ? Appearance.colors.colPrimaryContainer
                    : ColorUtils.transparentize(Appearance.colors.colOnSurface, root.interactive ? 0.90 : 0.88))
                Behavior on keyColor {
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                }
            }
            // A filled locator preserves the finger color while marking the
            // next cap. It remains legible with a monochrome theme as well.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                width: parent.width * 0.38
                height: 3
                radius: Appearance.rounding.full
                color: cap.foreground
                visible: Boolean(cap.hint.fill) && cap.next
            }
            Loader {
                anchors.fill: parent
                active: cap.symbol.length > 0 || cap.superGlyph.length > 0
                sourceComponent: cap.superGlyph ? superLabel : materialLabel
                Component {
                    id: materialLabel
                    MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        text: cap.symbol
                        iconSize: Math.min(root.labelSize * 1.35, cap.height * 0.55)
                        color: cap.foreground
                    }
                }
                Component {
                    id: superLabel
                    StyledText {
                        padding: 4
                        text: cap.superGlyph
                        font.family: Appearance.font.family.iconNerd
                        font.pixelSize: root.labelSize * 1.35
                        fontSizeMode: Text.Fit
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: cap.foreground
                    }
                }
            }
            RippleButton {
                id: keyButton
                anchors.fill: parent
                visible: root.interactive || root.hintTooltips
                focusPolicy: root.preserveInputFocus ? Qt.NoFocus : Qt.StrongFocus
                readonly property string keyDescription: (cap.entry.label || Translation.tr("Unassigned key"))
                    + (cap.hint.name ? " · " + cap.hint.name : (cap.entry.description ? ": " + cap.entry.description : ""))
                onHoveredChanged: {
                    if (hovered) root.hoveredKeyButton = keyButton;
                    else if (root.hoveredKeyButton === keyButton) root.hoveredKeyButton = null;
                }
                Component.onDestruction: {
                    if (root && root.hoveredKeyButton === keyButton) root.hoveredKeyButton = null;
                }
                scale: 1
                buttonRadius: Appearance.rounding.verysmall
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                Accessible.name: (cap.entry.label || Translation.tr("Unassigned key")) + (cap.entry.description ? ": " + cap.entry.description : "")
                onClicked: if (root.interactive) root.keyClicked(cap.index)
            }
        }
    }
}
