import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One panel family, as something you can look at before committing to it.
 *
 * Deliberately a card rather than the SessionScreen's icon button. Lock and Shutdown are
 * one word each and everybody already knows what they do; "Waffle" is not, and picking the
 * wrong one rebuilds every surface on screen. The card has room to say what it is.
 */
RippleButton {
    id: card

    required property var family
    property bool isCurrent: false
    property int animIndex: 0
    property bool shown: false

    readonly property bool activeState: card.focus || card.hovered || card.isPressed

    /// The one you are running is deliberately bigger, not only differently coloured. Size
    /// is the difference you read before you have looked at anything, which is what "which
    /// one am I in" should be.
    implicitWidth: card.isCurrent ? 300 : 256
    implicitHeight: card.isCurrent ? 344 : 300

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(card)
    }

    buttonRadius: Appearance.rounding.verylarge

    /**
     * Three states that have to be told apart at a glance, so each gets a whole surface
     * step rather than a tint of the last one:
     *
     *   current   colPrimaryContainer — the only card in the accent itself
     *   pointed at a third of the way from the resting surface to that accent
     *   resting   colLayer1
     *
     * Three named tokens were tried for the middle state and all three failed on this
     * theme: colLayer1Hover is colLayer1 mixed 8% towards its foreground, colLayer2 is one
     * surface step, and colSecondaryContainer turns out to be another dark navy here. Each
     * is a correct choice for a list row an inch tall and none of them reads across a
     * 300px card. Mixing towards the accent by a fixed fraction is not a token, but it is
     * the only version that cannot collapse into the resting colour whatever the palette
     * does — and it puts the middle state visibly *between* the other two, which is what it
     * means.
     */
    colBackground: card.isCurrent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: card.isCurrent
        ? Appearance.colors.colPrimaryContainer
        : ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.34)
    colRipple: card.isCurrent
        ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimaryContainer

    // The cascade and the spring are the SessionScreen's, so the two surfaces read as the
    // same gesture of the shell offering a choice.
    property real animScale: card.shown ? 1.0 : 0.8
    property real animOpacity: card.shown ? 1.0 : 0.0

    scale: (card.down ? 0.96 : (card.activeState ? 1.03 : 1.0)) * card.animScale
    opacity: card.animOpacity

    Behavior on animScale {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }
    Behavior on animOpacity {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    Timer {
        id: cascadeTimer
        interval: card.animIndex * 45
        repeat: false
        onTriggered: card.shown = true
    }

    function animateIn() {
        card.shown = false;
        cascadeTimer.restart();
    }
    function animateOut() {
        cascadeTimer.stop();
        card.shown = false;
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered)
                card.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            card.clicked();
            event.accepted = true;
        }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: card.isCurrent ? 108 : 92
            Layout.preferredHeight: card.isCurrent ? 108 : 92
            radius: card.activeState || card.isCurrent ? width / 2 : Appearance.rounding.large
            // Steps with the card, so the plate is a second reading of the same state
            // rather than a constant that makes hover look like nothing happened.
            // On a hovered card the plate has to leave the container colour behind, or the
            // two merge into one flat shape.
            color: card.isCurrent
                ? Appearance.colors.colPrimary
                : (card.activeState ? Appearance.colors.colPrimaryContainer
                                    : Appearance.colors.colLayer2)

            Behavior on radius {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: card.family?.icon ?? "widgets"
                iconSize: card.isCurrent ? 50 : 42
                fill: card.isCurrent ? 1 : 0
                color: card.isCurrent
                    ? Appearance.colors.colOnPrimary
                    : (card.activeState ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colOnLayer2)

                Behavior on iconSize {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr(card.family?.name ?? "")
            font.family: Appearance.font.family.title
            font.pixelSize: card.isCurrent
                ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.large
            color: card.isCurrent
                ? Appearance.colors.colOnPrimaryContainer
                : (card.activeState ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer1)
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr(card.family?.description ?? "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: card.isCurrent
                ? Appearance.colors.colOnPrimaryContainer
                : (card.activeState ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext)
            wrapMode: Text.Wrap
        }

        // Says which one you are already in, so tapping it is understood as a no-op rather
        // than tried and found to do nothing.
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 26
            Layout.preferredWidth: currentRow.implicitWidth + 20
            radius: height / 2
            visible: card.isCurrent
            color: Appearance.colors.colPrimary

            RowLayout {
                id: currentRow
                anchors.centerIn: parent
                spacing: 5

                MaterialSymbol {
                    text: "check"
                    iconSize: 15
                    color: Appearance.colors.colOnPrimary
                }
                StyledText {
                    text: Translation.tr("Current")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: !card.isCurrent
            text: Translation.tr(card.family?.summary ?? "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: card.activeState
                ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1Inactive
        }
    }
}
