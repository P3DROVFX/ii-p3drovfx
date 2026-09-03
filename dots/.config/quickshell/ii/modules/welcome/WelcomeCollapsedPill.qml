pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The Welcome, stepped aside.
 *
 * The bar step runs a real Edit Mode, and a 1080×780 window parked in the
 * middle of the screen covers the desktop it is teaching. So the window hides
 * and this takes its place: a pill beside Edit Mode's toolbar, holding the one
 * control it still needs — the way back.
 *
 * It is a layer surface rather than a smaller window because a Wayland client
 * cannot place its own toplevel. `GlobalStates.editToolbarRect` is published
 * by the chrome for exactly this: the pill parks against the toolbar's right
 * edge and rides along when the drawer re-centres it.
 */
PanelWindow {
    id: root

    readonly property rect toolbar: GlobalStates.editToolbarRect
    /** Whether the toolbar's published rect describes this screen. */
    readonly property bool besideToolbar: root.toolbar.width > 0
        && (GlobalStates.editModeMonitor === "" || GlobalStates.editModeMonitor === (root.screen?.name ?? ""))
    readonly property real gap: Appearance.rounding.small

    // Never gated on the screen: a collapsed Welcome with nowhere to click is
    // a Welcome the user cannot get back, so the pill shows wherever it is and
    // only its placement depends on knowing where the toolbar went.
    visible: GlobalStates.welcomeCollapsed
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:welcomeCollapsed"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.top: true
    anchors.left: true
    // Beside the toolbar, at its own height. Falls back to the top-left corner
    // before the chrome has published anything.
    margins.left: root.besideToolbar
        ? root.toolbar.x + root.toolbar.width + root.gap
        : Appearance.rounding.large
    margins.top: root.besideToolbar ? root.toolbar.y : Appearance.rounding.large

    implicitWidth: pill.implicitWidth
    implicitHeight: Math.max(pill.implicitHeight, root.besideToolbar ? root.toolbar.height : 0)

    mask: Region {
        item: pill
    }

    RippleButton {
        id: pill

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: pillContent.implicitWidth + Appearance.rounding.large * 2
        // The toolbar's own published height, so the two read as one row
        // rather than as a pill floating next to a bar.
        implicitHeight: root.besideToolbar ? root.toolbar.height : Appearance.sizes.toolbarHeight
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colBackgroundActive: Appearance.colors.colPrimaryActive
        colRipple: Appearance.colors.colPrimaryActive
        Accessible.name: Translation.tr("Continue the setup guide")
        onClicked: GlobalStates.welcomeCollapsed = false

        // Arrives from where the window was — down and to the left of here — so
        // the hand-off reads as one movement rather than as a window vanishing
        // and a pill appearing.
        //
        // Keyed on a property set after construction rather than on `visible`:
        // the loader builds this window only once the collapse has finished,
        // so `visible` is already true on the first frame and a Behavior
        // watching it would never see a change to animate.
        property bool entered: false
        Component.onCompleted: Qt.callLater(() => pill.entered = true)

        scale: pill.entered ? 1 : 0.82
        opacity: pill.entered ? 1 : 0
        transform: Translate {
            x: pill.entered ? 0 : -Appearance.rounding.verylarge
            y: pill.entered ? 0 : Appearance.rounding.large

            Behavior on x {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(pill)
            }
            Behavior on y {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(pill)
            }
        }

        Behavior on scale {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(pill)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(pill)
        }

        // A Control lays its own contentItem out across the padded rect, so a
        // RowLayout put there directly is stretched and packs its children
        // against the left edge. The wrapper takes that geometry and the row
        // centres inside it.
        contentItem: Item {
            RowLayout {
                id: pillContent

                anchors.centerIn: parent
                spacing: Appearance.rounding.small

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Continue")
                    color: Appearance.colors.colOnPrimary
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                }

                // An outline circle rather than a filled one: the pill itself is
                // already the filled surface, and a second fill inside it reads as
                // a button on a button.
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Appearance.font.pixelSize.hugeass + Appearance.rounding.verysmall
                    implicitHeight: Appearance.font.pixelSize.hugeass + Appearance.rounding.verysmall

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: Math.max(1, Math.round(Appearance.font.pixelSize.smallest / 5))
                        border.color: Appearance.colors.colOnPrimary
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_outward"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }
}
