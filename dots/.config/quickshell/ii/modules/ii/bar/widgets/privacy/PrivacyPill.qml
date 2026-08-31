pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.privacy
import qs.services

/**
 * Privacy indicator, built like the one in Android 16.
 *
 * When an access starts the pill grows out of nothing, shows what is being
 * used, then shrinks back to a small static dot that stays for as long as the
 * access lasts. There is deliberately no hover state: this thing reports on
 * the system, and a shape that reacts to the pointer reads as a control.
 */
MouseArea {
    id: root

    property bool vertical: false
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    readonly property var kinds: Privacy.activeKinds
    readonly property string kindSignature: root.kinds.join(",")
    readonly property bool shown: Privacy.enabled && Privacy.active

    readonly property bool collapseToDot: Config.options.bar.privacyPill.collapseToDot ?? true
    readonly property int expandDuration: Math.max(800, Config.options.bar.privacyPill.expandDuration ?? 4000)

    // Expanded, the pill is a bar widget like any other and matches their short
    // axis. Collapsed it is a status light, and stays small on purpose.
    readonly property real thickness: root.vertical
        ? Math.max(18, Appearance.sizes.verticalBarWidth - 8)
        : Math.max(18, Appearance.sizes.baseBarHeight - 8)
    readonly property real dotSize: 10

    // Enough long axis to read as a capsule even with a single icon in it.
    readonly property real expandedLength: root.vertical
        ? Math.max(root.thickness * 1.25, iconGrid.implicitHeight + 20)
        : Math.max(root.thickness * 1.25, iconGrid.implicitWidth + 20)

    property bool expanded: false

    // One number drives every dimension, and it is the only thing animated.
    //
    // Size used to come from two Behaviors — one on the pill, one on the bar
    // slot — running different durations and curves, and the expressive curve
    // overshoots by design. The pill therefore shot past its final size while
    // the slot was still catching up, which is the jump-then-settle: two moves
    // where there should be one. Interpolating a single 0→1 progress keeps the
    // slot and the shape on the same frame, always.
    property real progress: root.expanded ? 1.0 : 0.0

    Behavior on progress {
        NumberAnimation {
            duration: Math.round(420 * Appearance.animMultiplier)
            easing.type: Easing.OutQuint
        }
    }

    readonly property real pillLength: root.dotSize + (root.expandedLength - root.dotSize) * root.progress
    readonly property real pillThickness: root.dotSize + (root.thickness - root.dotSize) * root.progress

    onKindSignatureChanged: {
        if (root.kindSignature.length === 0) {
            collapseTimer.stop();
            root.expanded = false;
            return;
        }
        // Any change in *what* is being accessed re-announces itself.
        root.expanded = true;
        collapseTimer.restart();
    }

    Timer {
        id: collapseTimer
        interval: root.expandDuration
        repeat: false
        onTriggered: {
            if (root.collapseToDot)
                root.expanded = false;
        }
    }

    visible: root.shown
    // Derived from the same interpolation the pill uses, with no Behavior of
    // their own: the bar slot is exactly the pill plus its margin, on every
    // frame of the animation.
    implicitWidth: !root.shown ? 0 : (root.vertical ? Appearance.sizes.verticalBarWidth : root.pillLength + 8)
    implicitHeight: !root.shown ? 0 : (root.vertical ? root.pillLength + 8 : Appearance.sizes.baseBarHeight)

    Rectangle {
        id: pill

        anchors.centerIn: parent
        radius: Appearance.rounding.full
        color: Appearance.colors.colTertiary
        clip: true

        width: root.vertical ? root.pillThickness : root.pillLength
        height: root.vertical ? root.pillLength : root.pillThickness

        GridLayout {
            id: iconGrid

            anchors.centerIn: parent
            columns: root.vertical ? 1 : 99
            rowSpacing: 3
            columnSpacing: 4

            Repeater {
                model: root.kinds

                delegate: MaterialSymbol {
                    id: kindIcon

                    required property var modelData

                    text: Privacy.iconFor(String(kindIcon.modelData))
                    iconSize: 18
                    fill: 1
                    color: Appearance.colors.colOnTertiary

                    opacity: root.expanded ? 1.0 : 0.0
                    scale: root.expanded ? 1.0 : 0.4

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.expanded ? 200 : 110
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: root.expanded ? 380 : 140
                            easing.type: root.expanded ? Easing.OutBack : Easing.InCubic
                        }
                    }
                }
            }
        }
    }

    PrivacyPopup {
        hoverTarget: root
    }
}
