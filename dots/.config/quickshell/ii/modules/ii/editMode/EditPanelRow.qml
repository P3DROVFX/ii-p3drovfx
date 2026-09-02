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
 * A MouseArea rather than a RippleButton because half of these rows are also
 * drag handles - a catalogue row carried onto the desktop or onto the bar -
 * and that needs `preventStealing` against the list's own flick plus a
 * press/move/release the button does not expose. `activated()` is the click,
 * emitted only for a release that was NOT a drag.
 */
MouseArea {
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
    // A drag on this row carries something; the list it sits in must let go of
    // the gesture the moment it wins.
    property bool draggable: false
    property Flickable dragOwner: null

    signal activated()
    signal dragBegan()
    signal dragMovedTo(real sceneX, real sceneY)
    signal dragFinished(real sceneX, real sceneY)
    signal dragCancelled()
    signal stepUp()
    signal stepDown()

    implicitHeight: Math.max(58, rowLayout.implicitHeight + 16)
    hoverEnabled: true
    enabled: root.rowEnabled
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    // Only a row that CARRIES something holds the gesture against its list.
    // A static row must let the flick through, or a settings page cannot be
    // scrolled by dragging over the rows that fill it.
    preventStealing: root.draggable
    opacity: root.rowEnabled ? 1 : 0.45

    readonly property color colOn: root.selected
        ? Appearance.colors.colOnPrimary
        : root.destructive ? Appearance.m3colors.m3error : Appearance.colors.colOnSurface

    // ── The gesture ──────────────────────────────────────────────────────────
    property real _pressX: 0
    property real _pressY: 0
    property bool dragActive: false

    function _scene(mouse) {
        return root.mapToItem(null, mouse.x, mouse.y);
    }

    onPressed: mouse => {
        root._pressX = mouse.x;
        root._pressY = mouse.y;
        root.dragActive = false;
    }
    onPositionChanged: mouse => {
        if (!root.pressed || !root.draggable)
            return;
        if (!root.dragActive
                && Math.abs(mouse.x - root._pressX) < 5
                && Math.abs(mouse.y - root._pressY) < 5)
            return;
        if (!root.dragActive) {
            root.dragActive = true;
            if (root.dragOwner)
                root.dragOwner.interactive = false;
            root.dragBegan();
        }
        const p = root._scene(mouse);
        root.dragMovedTo(p.x, p.y);
    }
    onReleased: mouse => {
        const wasDrag = root.dragActive;
        root.dragActive = false;
        if (root.dragOwner)
            root.dragOwner.interactive = true;
        if (!wasDrag) {
            root.activated();
            return;
        }
        const p = root._scene(mouse);
        root.dragFinished(p.x, p.y);
    }
    onCanceled: {
        if (!root.dragActive)
            return;
        root.dragActive = false;
        if (root.dragOwner)
            root.dragOwner.interactive = true;
        root.dragCancelled();
    }

    readonly property real rEnd: Appearance.rounding.large
    readonly property real rSeam: Appearance.rounding.verysmall
    readonly property real rPressed: Math.min(root.height / 2, Appearance.rounding.large * 2)

    Rectangle {
        id: pill
        anchors.fill: parent
        topLeftRadius: root.pressed ? root.rPressed : (root.first ? root.rEnd : root.rSeam)
        topRightRadius: root.pressed ? root.rPressed : (root.first ? root.rEnd : root.rSeam)
        bottomLeftRadius: root.pressed ? root.rPressed : (root.last ? root.rEnd : root.rSeam)
        bottomRightRadius: root.pressed ? root.rPressed : (root.last ? root.rEnd : root.rSeam)
        antialiasing: true

        color: root.selected
            ? (root.pressed ? Appearance.colors.colPrimaryActive
                : root.containsMouse ? Appearance.colors.colPrimaryHover
                : Appearance.colors.colPrimary)
            : (root.pressed ? Appearance.colors.colSurfaceContainerHighestActive
                : root.containsMouse ? Appearance.colors.colSurfaceContainerHighest
                : Appearance.colors.colSurfaceContainerHigh)

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pill)
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
        anchors.leftMargin: root.rowPadding
        anchors.rightMargin: root.trailingKind === "stepper" ? 6 : root.rowPadding
        spacing: 12

        // The circle. It is what makes a run of rows read as a list of things
        // rather than as a stack of labels.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: root.symbol !== "" || root.iconSource !== ""
            implicitWidth: 38
            implicitHeight: 38
            radius: width / 2
            color: root.selected
                ? Qt.alpha(Appearance.colors.colOnPrimary, 0.2)
                : root.trailingKind === "switch" && root.switchChecked
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colSurfaceContainerHighest

            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.iconSource === ""
                text: root.symbol
                iconSize: 21
                fill: (root.trailingKind === "switch" && root.switchChecked) ? 1 : 0
                color: (root.trailingKind === "switch" && root.switchChecked && !root.selected)
                    ? Appearance.colors.colOnPrimaryContainer : root.colOn
            }

            IconImage {
                anchors.centerIn: parent
                visible: root.iconSource !== ""
                implicitSize: 24
                source: root.iconSource
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.colOn
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle !== ""
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
            iconSize: root.trailingKind === "chevron" ? 22 : 20
            fill: root.trailingKind === "check" ? 1 : 0
            color: (root.trailingKind === "check" && !root.selected)
                ? Appearance.colors.colPrimary : root.colOn
            opacity: root.trailingKind === "chevron" ? 0.7 : 1
        }

        StyledSwitch {
            Layout.alignment: Qt.AlignVCenter
            visible: root.trailingKind === "switch"
            checked: root.switchChecked
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
                width: 46
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

        width: 34
        height: 34
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
