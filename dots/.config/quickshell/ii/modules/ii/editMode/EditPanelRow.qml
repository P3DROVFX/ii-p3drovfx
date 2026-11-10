import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

/**
 * One row of Edit Mode's panel: a filled pill carrying a circled icon, a title,
 * an optional second line, and whatever the row's answer is on the right - a
 * chevron into a sub-page, a check, a plus, a value, a switch, or a stepper.
 *
 * The shape is the shell's grouped-list shape: full rounding on the ends of a
 * run and a tight corner between neighbours, with the pressed row swelling to
 * fully round. `first`/`last` are handed in rather than derived from the
 * sibling order the way RippleButton's `useDynamicRadius` does it, because
 * these rows are usually ListView delegates: the view recycles and reorders
 * its children, so counting siblings answers with whatever the pool happens to
 * hold rather than with the row's place in the model.
 *
 * An EditDragArea rather than a RippleButton because half of these rows are
 * also drag handles - a catalogue row carried onto the desktop or onto the
 * bar - and that needs a press/move/release the button does not expose.
 */
EditDragArea {
    id: root

    property string symbol: ""
    property string iconSource: ""
    property string title: ""
    property string subtitle: ""
    property string valueText: ""
    // "none" | "chevron" | "check" | "add" | "value" | "switch" | "stepper"
    property string trailingKind: "chevron"
    property bool switchChecked: false
    property bool stepUpEnabled: true
    property bool stepDownEnabled: true
    property bool first: true
    property bool last: true
    // The row is the thing that is on: filled in the primary role.
    property bool selected: false
    // A row whose action takes something away.
    property bool destructive: false
    property bool rowEnabled: true
    property real rowPadding: 14
    // A second line that has to be READ rather than glanced at - a choice's
    // description - wraps and grows the row instead of eliding.
    property bool subtitleWrap: false
    // Place in the fill, for the cascade a page arrives with. -1 arrives
    // settled, which is what a row outside a run wants. ListView pages get
    // this from the view's own `populate` transition instead; this is for the
    // Repeater-built pages, which have no equivalent.
    property int staggerIndex: -1
    // The context menus' compact style (ContextMenus.compact): a 34 px row
    // with no pill until hovered, a bare glyph instead of the circle, no
    // second line unless it has to be read, and a natural width so the card
    // can fit its content. Edit Mode's panels never set it.
    property bool dense: false
    // Drawn as hovered without the pointer: the row whose submenu is open
    // beside the menu.
    property bool highlighted: false
    readonly property bool _lit: root.containsMouse || root.activeFocus || root.highlighted

    // A row only takes the keyboard when a host hands it focus (the icon
    // menu's arrow navigation); it then reads as hovered and Enter/Space
    // are the click. Nothing in Edit Mode focuses rows, so there it is inert.
    Keys.onReturnPressed: event => { event.accepted = true; if (root.rowEnabled) root.activated(); }
    Keys.onEnterPressed: event => { event.accepted = true; if (root.rowEnabled) root.activated(); }
    Keys.onSpacePressed: event => { event.accepted = true; if (root.rowEnabled) root.activated(); }
    signal stepUp()
    signal stepDown()

    implicitHeight: root.dense ? Math.max(34, rowLayout.implicitHeight + 8)
        : Math.max(58, rowLayout.implicitHeight + 16)
    implicitWidth: root.dense ? rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin : 0
    enabled: root.rowEnabled
    opacity: (root.rowEnabled ? 1 : 0.45) * revealProxy.opacity
    scale: revealProxy.scale

    // The cascade drives a PROXY rather than the row itself. StaggeredEntrance
    // assigns `opacity` and `scale` on its target, and this row's opacity
    // already carries its disabled state - an assignment would replace that
    // rule rather than join it, so a row that is disabled later would stop
    // dimming. Multiplying the proxy in keeps both.
    Item {
        id: revealProxy
        visible: false
        width: 0
        height: 0

        StaggeredEntrance {
            target: revealProxy
            index: root.staggerIndex
            active: root.staggerIndex >= 0 && !Appearance.reducedMotion
        }
    }

    // A switch that is on fills the row in the primary container family; its
    // icon leaves the circle for a rounded square on primary.
    readonly property bool switchOn: root.trailingKind === "switch" && root.switchChecked && !root.selected
    readonly property real iconBoxSize: root.dense ? 20 : 38
    readonly property real iconBoxActiveRadius: Math.round(root.iconBoxSize * 0.3)

    readonly property color colOn: root.selected
        ? (root.dense ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary)
        : root.switchOn && !root.dense ? Appearance.colors.colOnPrimaryContainer
        : root.destructive ? Appearance.m3colors.m3error : Appearance.colors.colOnSurface

    // The corner of the surface this row sits on, and how far in from it the
    // row starts. The end of a run is drawn CONCENTRIC with that surface -
    // `hostRadius - hostPadding` - rather than at a token of its own, which is
    // the rule the shell's other inset lists follow (EditMenuRow does the same
    // arithmetic). Picking `rounding.large` here instead was visibly wrong on
    // the two menu cards: their corner is `windowRounding` (18 at the default
    // scale) and the rows were rounder than the card holding them.
    //
    // The defaults are the catalogue panel's own numbers, so the pages inside
    // it need say nothing; the menus hand in theirs.
    property real hostRadius: Appearance.rounding.verylarge
    property real hostPadding: 14
    readonly property real rEnd: Math.max(Appearance.rounding.verysmall, root.hostRadius - root.hostPadding)
    // The seam between neighbours, as a fraction of the end rather than a
    // token: at a small end radius a fixed `verysmall` seam is nearly the same
    // corner and the run stops reading as a run.
    readonly property real rSeam: Math.max(Appearance.rounding.unsharpen, Math.round(root.rEnd * 0.34))
    readonly property real rPressed: Math.min(root.height / 2, Appearance.rounding.large * 2)
    // Dense rows are not a run: each one is its own hover highlight,
    // concentric with the card, and a press only tightens it a little.
    readonly property real rDense: root.pressed ? Math.max(Appearance.rounding.verysmall, root.rEnd - 4) : root.rEnd

    Rectangle {
        id: pill
        anchors.fill: parent
        topLeftRadius: root.dense ? root.rDense : root.pressed ? root.rPressed : (root.first ? root.rEnd : root.rSeam)
        topRightRadius: root.dense ? root.rDense : root.pressed ? root.rPressed : (root.first ? root.rEnd : root.rSeam)
        bottomLeftRadius: root.dense ? root.rDense : root.pressed ? root.rPressed : (root.last ? root.rEnd : root.rSeam)
        bottomRightRadius: root.dense ? root.rDense : root.pressed ? root.rPressed : (root.last ? root.rEnd : root.rSeam)
        antialiasing: true

        // A plain row shows hover with `hoverLayer` below, not by stepping to
        // the next surface tone.
        color: root.dense && !root.selected
            ? (root.pressed ? Appearance.colors.colSurfaceContainerHighestActive
                : Qt.alpha(Appearance.colors.colSurfaceContainerHighest, 0))
            : root.dense
            ? (root.pressed ? Appearance.colors.colSecondaryContainerActive
                : root._lit ? Appearance.colors.colSecondaryContainerHover
                : Appearance.colors.colSecondaryContainer)
            : root.selected
            ? (root.pressed ? Appearance.colors.colPrimaryActive
                : root.containsMouse ? Appearance.colors.colPrimaryHover
                : Appearance.colors.colPrimary)
            : root.switchOn
            ? (root.pressed ? Appearance.colors.colPrimaryContainerActive
                : root._lit ? Appearance.colors.colPrimaryContainerHover
                : Appearance.colors.colPrimaryContainer)
            : (root.pressed ? Appearance.colors.colSurfaceContainerHighestActive
                : Appearance.colors.colSurfaceContainerHigh)

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pill)
        }

        // Hover on a plain row: the content colour at 8 % over the fill (M3's
        // state layer). With transparency on, the surface tones are solved as
        // overlays, each against a different base, so on an opaque menu card
        // High and Highest land a few levels apart and a tone-step hover
        // vanished. A layer reads the same over any fill.
        Rectangle {
            id: hoverLayer
            anchors.fill: parent
            topLeftRadius: pill.topLeftRadius
            topRightRadius: pill.topRightRadius
            bottomLeftRadius: pill.bottomLeftRadius
            bottomRightRadius: pill.bottomRightRadius
            antialiasing: true
            // The filled rows (selected; a comfortable switch that is on)
            // keep their own opaque hover tones.
            visible: !root.selected && (root.dense || !root.switchOn)
            color: root.colOn
            opacity: root._lit && !root.pressed ? 0.08 : 0

            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(hoverLayer)
            }
        }
        Behavior on topLeftRadius {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pill)
        }
        Behavior on topRightRadius {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pill)
        }
        Behavior on bottomLeftRadius {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pill)
        }
        Behavior on bottomRightRadius {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(pill)
        }
    }

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.leftMargin: root.dense ? 10 : root.rowPadding
        anchors.rightMargin: root.trailingKind === "stepper" ? (root.dense ? 2 : 6) : root.dense ? 8 : root.rowPadding
        spacing: root.dense ? 10 : 12

        // The circle. It is what makes a run of rows read as a list of things
        // rather than as a stack of labels.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: root.symbol !== "" || root.iconSource !== ""
            implicitWidth: root.iconBoxSize
            implicitHeight: root.iconBoxSize
            radius: root.switchOn ? root.iconBoxActiveRadius : width / 2
            color: root.dense ? "transparent"
                : root.selected
                ? Qt.alpha(Appearance.colors.colOnPrimary, 0.2)
                : root.switchOn
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSurfaceContainerHighest

            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on radius {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }

            MaterialSymbol {
                id: symbolGlyph
                anchors.centerIn: parent
                visible: root.iconSource === ""
                text: root.symbol
                iconSize: root.dense ? 18 : 21
                fill: (root.trailingKind === "switch" && root.switchChecked) ? 1 : 0
                color: root.switchOn ? (root.dense ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary)
                    : root.dense && !root.selected && !root.destructive ? Appearance.colors.colOnSurfaceVariant
                    : root.colOn

                // A glyph that changes under a settled row (a copy turning
                // into a check, pin into unpin) pops back in from small, so
                // the change is seen rather than just swapped.
                onTextChanged: {
                    if (!Appearance.reducedMotion && root.visible)
                        symbolPop.restart();
                }
                SequentialAnimation {
                    id: symbolPop
                    NumberAnimation {
                        target: symbolGlyph; property: "scale"; to: 0.55
                        duration: 70; easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: symbolGlyph; property: "scale"; to: 1
                        duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2
                    }
                }
            }

            IconImage {
                anchors.centerIn: parent
                visible: root.iconSource !== ""
                implicitSize: root.dense ? 18 : 24
                source: root.iconSource
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: root.dense ? Appearance.font.pixelSize.smallie + 1 : Appearance.font.pixelSize.small
                font.weight: root.dense ? Font.Normal : Font.Medium
                color: root.colOn
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle !== "" && (!root.dense || root.subtitleWrap)
                text: root.subtitle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.colOn
                opacity: 0.7
                elide: Text.ElideRight
                wrapMode: root.subtitleWrap ? Text.Wrap : Text.NoWrap
                maximumLineCount: root.subtitleWrap ? 2 : 1
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.valueText !== "" && root.trailingKind !== "stepper"
            text: root.valueText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colOn
            opacity: 0.8
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            visible: root.trailingKind === "chevron" || root.trailingKind === "check"
                || root.trailingKind === "add"
            text: root.trailingKind === "check" ? "check_circle"
                : root.trailingKind === "add" ? "add_circle" : "chevron_right"
            iconSize: root.dense ? 18 : root.trailingKind === "chevron" ? 22 : 20
            fill: root.trailingKind === "check" ? 1 : 0
            color: (root.trailingKind === "check" && !root.selected)
                ? Appearance.colors.colPrimary : root.colOn
            opacity: root.trailingKind === "chevron" ? 0.7 : 1
        }

        StyledSwitch {
            Layout.alignment: Qt.AlignVCenter
            visible: root.trailingKind === "switch"
            checked: root.switchChecked
            sizeScale: root.dense ? 0.6 : (PanelFamily.touchFirst ? 1.0 : 0.75)
            // The row owns the gesture: a 30px target inside a 58px row is a
            // target people miss, and the switch reads as a state either way.
            enabled: false
        }

        // The stepper, for the handful of rows that carry a number.
        Row {
            Layout.alignment: Qt.AlignVCenter
            visible: root.trailingKind === "stepper"
            spacing: 0

            StepButton {
                symbol: "remove"
                enabled: root.stepDownEnabled
                onTriggered: root.stepDown()
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: root.dense ? 34 : 46
                horizontalAlignment: Text.AlignHCenter
                text: root.valueText
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.numbers
                color: root.colOn
            }
            StepButton {
                symbol: "add"
                enabled: root.stepUpEnabled
                onTriggered: root.stepUp()
            }
        }
    }

    component StepButton: Rectangle {
        id: step
        property string symbol: ""
        signal triggered()

        width: root.dense ? 26 : 34
        height: width
        radius: width / 2
        color: stepMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
            : stepMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighest
            : "transparent"

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(step)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: step.symbol
            iconSize: 19
            color: step.enabled ? root.colOn : Appearance.m3colors.m3outline
        }

        MouseArea {
            id: stepMouse
            anchors.fill: parent
            enabled: step.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: step.triggered()
        }
    }
}
