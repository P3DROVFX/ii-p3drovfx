import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
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

    implicitWidth: 260
    implicitHeight: 300

    buttonRadius: Appearance.rounding.verylarge
    colBackground: card.isCurrent ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

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
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            radius: card.activeState ? width / 2 : Appearance.rounding.large
            color: card.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colLayer2

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
                iconSize: 44
                fill: card.isCurrent ? 1 : 0
                color: card.isCurrent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr(card.family?.name ?? "")
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr(card.family?.description ?? "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
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
            color: Appearance.colors.colOnLayer1Inactive
        }
    }
}
