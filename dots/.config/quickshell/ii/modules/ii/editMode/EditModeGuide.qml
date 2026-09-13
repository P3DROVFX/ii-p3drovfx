pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.editMode

/**
 * A short tour of Edit Mode's toolbar, for someone who has never seen it.
 *
 * The mode is discoverable enough once you know what the eight controls do,
 * and opaque before that — which is exactly the state the Welcome drops a
 * first-time user into. So the guide is not a manual: it is one card at a
 * time, parked under the control it is talking about, with a pointer at it.
 *
 * It lives inside the chrome rather than in the Welcome's own surface for one
 * reason: the toolbar is here. A callout drawn anywhere else would be guessing
 * at coordinates that this file already has, and layer surfaces have no
 * dependable order among themselves.
 */
Item {
    id: root

    /** The items the steps point at, in the chrome's own coordinates. */
    required property Item tabsTarget
    required property Item sectionsTarget
    required property Item historyTarget
    required property Item doneTarget
    /** The catalogue panel, which only exists once someone opens it. */
    required property Item drawerTarget

    property int step: 0
    property bool dismissed: false

    /**
     * The bar step has nothing here to point at — the bar is on another layer
     * surface — and pointing at the strip it occupies only works when the bar
     * is along the top, which is also the only side where "up" finds it.
     *
     * So the card parks under the toolbar, which always exists and is always
     * near the top, and the pointer is shown only when it would be telling the
     * truth. Everywhere else the bar is the one thing on screen shaped like a
     * bar, and the card can simply say so.
     */
    readonly property bool barIsAtTop: EditModeInsets.barSide === "top"
    readonly property point belowToolbar: {
        const bar = GlobalStates.editToolbarRect;
        return Qt.point(root.width / 2, bar.height > 0 ? bar.y + bar.height : Appearance.rounding.verylarge * 2);
    }

    readonly property var steps: [{
        "target": root.tabsTarget,
        "title": Translation.tr("What you're editing"),
        "body": Translation.tr("Your desktop, or the lock screen. Each keeps its own widgets.")
    }, {
        // Points at the panel once it is open, and at the chips that open it
        // until then — the same step either way, because they are the same
        // control seen from two sides.
        "target": root.drawerTarget.width > 1 ? root.drawerTarget : root.sectionsTarget,
        "title": Translation.tr("Widgets, Bar, Dock, Style"),
        "body": Translation.tr("These open the panel on the right. It holds everything you can add, and the settings of whichever surface you picked.")
    }, {
        "point": root.belowToolbar,
        "pointer": root.barIsAtTop,
        "title": Translation.tr("Your bar, right now"),
        "body": Translation.tr("Click and drag a widget along the bar to reorder it. Drop it on the panel to take it off.")
    }, {
        "target": root.historyTarget,
        "title": Translation.tr("Nothing here is permanent"),
        "body": Translation.tr("Undo and redo cover everything you change in the mode, and Ctrl+Z works too.")
    }, {
        "target": root.doneTarget,
        "title": Translation.tr("When you're happy"),
        "body": Translation.tr("Done leaves the mode. During setup it also takes you to the next step of the guide.")
    }]

    readonly property var currentStep: root.steps[Math.min(root.step, root.steps.length - 1)]
    readonly property bool onLastStep: root.step >= root.steps.length - 1

    /** Published for the surface's input mask. */
    readonly property alias cardItem: card

    // The mode's entrance has to finish before a card lands on the toolbar it
    // is pointing at, and the whole thing goes away with the mode.
    readonly property bool shown: GlobalStates.editGuideActive
        && GlobalStates.editMode
        && GlobalStates.editProgress > 0.99
        && !root.dismissed

    function advance(): void {
        if (root.onLastStep) {
            root.dismissed = true;
            return;
        }
        root.step += 1;
    }

    // Re-armed for the next session rather than on the way in: a guide that
    // reset itself while its own card was fading out would flash step one.
    Connections {
        target: GlobalStates

        function onEditGuideActiveChanged() {
            if (!GlobalStates.editGuideActive) {
                root.step = 0;
                root.dismissed = false;
            }
        }
    }

    anchors.fill: parent
    visible: opacity > 0.01
    opacity: root.shown ? 1 : 0

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    /**
     * Where the pointer meets the toolbar. `mapToItem` is a function call, not
     * a binding, so the toolbar's own geometry is named in the expression to
     * make it one: the toolbar slides on entry and re-centres whenever the
     * drawer moves the desktop.
     */
    /** Whether this step's card carries the little triangle at all. */
    readonly property bool pointerShown: root.currentStep?.pointer ?? true

    readonly property point anchorPoint: {
        if (!root.shown)
            return Qt.point(0, 0);
        const fixed = root.currentStep?.point ?? null;
        if (fixed)
            return fixed;
        const target = root.currentStep?.target ?? null;
        if (!target || !target.parent)
            return Qt.point(root.width / 2, 0);
        // Named so the binding re-runs with them.
        void target.x;
        void target.width;
        void GlobalStates.editProgress;
        void GlobalStates.editDrawerProgress;
        const mapped = target.mapToItem(root, target.width / 2, target.height);
        return Qt.point(mapped.x, mapped.y);
    }

    Item {
        id: card

        readonly property real gap: Appearance.rounding.small
        readonly property real preferredWidth: Appearance.rounding.verylarge * 11

        // Zero-sized when the guide is not up, the way the closed drawer is:
        // the surface's input mask is built from this item, and a hidden card
        // with a size would keep eating clicks meant for the desktop.
        readonly property real bodyPadding: Appearance.rounding.normal
        // The body's own padding counts twice: `cardBody` is inset from the
        // top AND the bottom, and leaving the second one out pushed the row of
        // buttons through the bottom of the card.
        readonly property real bodyHeight: cardBody.implicitHeight + card.bodyPadding * 2

        width: root.shown ? Math.min(root.width - Appearance.rounding.large * 2, card.preferredWidth) : 0
        height: root.shown ? card.bodyHeight + pointer.reach : 0
        // Clamped so a step near either end of the toolbar keeps the card on
        // screen; the pointer stays on the control regardless.
        x: Math.max(Appearance.rounding.large,
            Math.min(root.width - width - Appearance.rounding.large,
                root.anchorPoint.x - width / 2))
        // Clamped so a step anchored near the bottom edge — a bar down there,
        // a toolbar pushed low — keeps the whole card on screen.
        y: Math.max(Appearance.rounding.large,
            Math.min(root.height - card.height - Appearance.rounding.large,
                root.anchorPoint.y + card.gap))

        Behavior on x {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
        }
        Behavior on y {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
        }

        // The pointer, kept over the control even when the card is clamped.
        // A rotated square straddling the card's top edge: half of it shows as
        // a triangle, the other half is hidden behind the body, and it needs no
        // repaint when the palette changes.
        Rectangle {
            id: pointer

            readonly property real reach: Appearance.rounding.verysmall

            visible: root.pointerShown
            width: pointer.reach * 1.6
            height: width
            rotation: 45
            radius: Appearance.rounding.unsharpen
            color: Appearance.colors.colPrimaryContainer
            x: Math.max(Appearance.rounding.normal,
                Math.min(card.width - Appearance.rounding.normal,
                    root.anchorPoint.x - card.x)) - width / 2
            y: pointer.reach - height / 2

            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(pointer)
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: pointer.reach
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: card.bodyHeight
            radius: Appearance.rounding.large
            color: Appearance.colors.colPrimaryContainer

            ColumnLayout {
                id: cardBody

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: card.bodyPadding
                spacing: Appearance.rounding.verysmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.rounding.small

                    StyledText {
                        Layout.fillWidth: true
                        text: root.currentStep?.title ?? ""
                        color: Appearance.colors.colOnPrimaryContainer
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        text: Translation.tr("%1 of %2")
                            .arg(String(root.step + 1))
                            .arg(String(root.steps.length))
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.7
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.currentStep?.body ?? ""
                    color: Appearance.colors.colOnPrimaryContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.rounding.verysmall
                    spacing: Appearance.rounding.small

                    RippleButton {
                        implicitHeight: Appearance.rounding.verylarge
                        implicitWidth: skipLabel.implicitWidth + Appearance.rounding.large
                        buttonRadius: Appearance.rounding.full
                        colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1)
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        Accessible.name: skipLabel.text
                        onClicked: root.dismissed = true

                        contentItem: StyledText {
                            id: skipLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Skip the tour")
                            color: Appearance.colors.colOnPrimaryContainer
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                        }
                    }

                    Item { Layout.fillWidth: true }

                    RippleButtonWithIcon {
                        implicitHeight: Appearance.rounding.verylarge
                        centerContent: true
                        iconOnRight: !root.onLastStep
                        materialIcon: root.onLastStep ? "check" : "arrow_forward"
                        mainText: root.onLastStep ? Translation.tr("Got it") : Translation.tr("Next")
                        textPixelSize: Appearance.font.pixelSize.small
                        iconPixelSize: Appearance.font.pixelSize.normal
                        buttonRadius: Appearance.rounding.full
                        colText: Appearance.colors.colOnPrimary
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colBackgroundActive: Appearance.colors.colPrimaryActive
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.advance()
                    }
                }
            }
        }
    }
}
