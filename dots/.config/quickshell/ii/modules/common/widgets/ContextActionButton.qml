pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common

// One row of a context card using the shell's grouped smart-radius system:
// `useDynamicRadius` + GroupPosition give concentric rounding at the ends of
// a run, a tight seam between neighbours and a pressed/hovered row that
// swells to fully round. Hover colors and geometry mirror EditPanelRow, so
// menu rows cannot drift from the editMode panel's lists.
RippleButton {
    id: root
    property string textLabel: ""
    property string symbol: ""
    // 1 draws the glyph in its filled variant — the toggle rows' "on" state
    // (pin to dock), where the text alone would bury it.
    property real symbolFill: 0
    property url iconSource: ""
    property bool destructive: false
    property bool submenu: false
    // True when a non-button element (e.g. the details plate) follows this row
    // in the same visual run: the bottom then keeps the neighbour seam even
    // though GroupPosition counts this as the run's last button.
    property bool runContinues: false
    readonly property color foreground: root.destructive ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurface

    // The host card's corner and how far the row sits inside it (ItemContextDialog:
    // 1px border + 6px scroll margin). The end of a run is drawn CONCENTRIC with
    // that surface — `hostRadius - hostInset` — the rule the shell's other inset
    // lists follow (EditPanelRow/EditMenuRow). RippleButton's stock end is the
    // standalone `large` token, which on an 18px context card reads rounder than
    // the card holding it.
    property real hostRadius: Appearance.rounding.windowRounding
    property real hostInset: 7
    readonly property real rEnd: Math.max(Appearance.rounding.verysmall, root.hostRadius - root.hostInset)
    // Seam as a fraction of the end, not a fixed token: at a small end radius a
    // constant corner is nearly the same round and the run stops reading as a run.
    readonly property real rSeam: Math.max(Appearance.rounding.unsharpen, Math.round(root.rEnd * 0.34))
    topLeftRadius: (root.isPressed || root.prevIsPressed) ? root.rFull : (root.isFirst ? root.rEnd : root.rSeam)
    topRightRadius: (root.isPressed || root.prevIsPressed) ? root.rFull : (root.isFirst ? root.rEnd : root.rSeam)
    bottomLeftRadius: (root.isPressed || root.nextIsPressed) ? root.rFull : (root.isLast && !root.runContinues ? root.rEnd : root.rSeam)
    bottomRightRadius: (root.isPressed || root.nextIsPressed) ? root.rFull : (root.isLast && !root.runContinues ? root.rEnd : root.rSeam)

    // The Basic style pads a Button's content (6 vertical, 8 horizontal), which
    // stacked on top of the row's own margins made the circle's left inset twice
    // its vertical one. The row owns all its spacing from here.
    padding: 0
    // The circle mirrors its vertical inset exactly, whatever the row height is.
    readonly property real circleInset: (root.height - 38) / 2

    Layout.fillWidth: true
    implicitHeight: 52
    activeFocusOnTab: true
    pointingHandCursor: true
    useDynamicRadius: true
    colBackground: Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
    colBackgroundActive: Appearance.colors.colSurfaceContainerHighestActive
    colRipple: Appearance.colors.colLayer1Active
    borderWidth: activeFocus ? 1 : 0
    borderColor: Appearance.m3colors.m3primary
    Keys.onReturnPressed: root.clicked()

    contentItem: RowLayout {
        spacing: 12
        Rectangle {
            Layout.leftMargin: root.circleInset
            implicitWidth: 38
            implicitHeight: 38
            radius: width / 2
            color: root.hovered ? Qt.rgba(Appearance.colors.colOnLayer2.r, Appearance.colors.colOnLayer2.g, Appearance.colors.colOnLayer2.b, 0.18)
                : Qt.rgba(Appearance.colors.colOnLayer2.r, Appearance.colors.colOnLayer2.g, Appearance.colors.colOnLayer2.b, 0.10)
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.iconSource.toString().length === 0
                text: root.symbol
                iconSize: 22
                fill: root.symbolFill
                color: root.foreground
                opacity: root.enabled ? (root.hovered ? 1 : 0.85) : 0.4
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
            Image {
                anchors.centerIn: parent
                width: 26
                height: 26
                sourceSize: Qt.size(26, 26)
                source: root.iconSource
                visible: source.toString().length > 0
                fillMode: Image.PreserveAspectFit
                opacity: root.enabled ? (root.hovered ? 1 : 0.85) : 0.4
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.textLabel
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: root.foreground
            elide: Text.ElideRight
            opacity: root.enabled ? (root.hovered ? 1 : 0.9) : 0.4
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }
        MaterialSymbol {
            Layout.rightMargin: 12
            visible: root.submenu
            text: "chevron_right"
            iconSize: 22
            color: root.foreground
            opacity: root.hovered ? 1 : 0.7
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }
    }
}
