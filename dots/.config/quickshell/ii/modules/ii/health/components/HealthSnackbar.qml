pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The app's one snackbar: a secondary-container pill at the bottom of the page, for
 * what finished out of sight — an action whose row has already gone, an assistant
 * answer that arrived for a closed sheet. One at a time; a new one replaces the old.
 * It follows the theme rather than Material's inverse surface, which is light on a
 * dark shell.
 *
 * show(text, actionLabel, onAction): the action is a text button in the primary
 * colour, and keeps the snackbar up a little longer.
 */
Item {
    id: root

    property string text: ""
    property string actionLabel: ""
    property var onAction: null
    property bool error: false
    property bool open: false

    function show(text, actionLabel, onAction, error): void {
        root.text = String(text ?? "");
        root.actionLabel = String(actionLabel ?? "");
        root.onAction = onAction ?? null;
        root.error = error === true;
        root.open = root.text.length > 0;
        hideTimer.interval = root.actionLabel.length > 0 ? 6000 : 4000;
        hideTimer.restart();
    }

    function hide(): void {
        root.open = false;
    }

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight
    visible: pill.opacity > 0

    Timer {
        id: hideTimer
        onTriggered: {
            // Not while the pointer rests on it: it is being read, or about to be clicked.
            if (pillHover.hovered)
                hideTimer.restart();
            else
                root.hide();
        }
    }

    Rectangle {
        id: pill
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        implicitWidth: Math.min(row.implicitWidth + ClockStyle.gapLarge * 2, root.width > 0 ? root.width : 560)
        implicitHeight: Math.max(48, row.implicitHeight + ClockStyle.gap * 2)
        width: implicitWidth
        radius: ClockStyle.radiusSmall
        // Not Material's inverse surface: light on a dark shell, it glared.
        color: ClockStyle.colSecondaryContainer
        opacity: root.open ? 1 : 0

        transform: Translate {
            y: root.open ? 0 : 12
            Behavior on y {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }
        }
        Behavior on opacity {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }

        HoverHandler {
            id: pillHover
        }

        RowLayout {
            id: row
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: ClockStyle.gapLarge
                rightMargin: ClockStyle.gap
            }
            spacing: ClockStyle.gap

            MaterialSymbol {
                visible: root.error
                text: "error"
                iconSize: ClockStyle.iconSmall
                fill: 1
                color: ClockStyle.colError
            }

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 460
                text: root.text
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall + 1
                color: ClockStyle.colOnSecondaryContainer
            }

            RippleButton {
                visible: root.actionLabel.length > 0
                implicitHeight: 36
                implicitWidth: actionText.implicitWidth + ClockStyle.gapLarge * 2
                buttonRadius: ClockStyle.pill(36)
                colBackground: "transparent"
                colBackgroundHover: ClockStyle.colSecondaryContainerHover
                colRipple: ClockStyle.colSecondaryContainerActive
                onClicked: {
                    const action = root.onAction;
                    root.hide();
                    if (typeof action === "function")
                        action();
                }

                contentItem: StyledText {
                    id: actionText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.actionLabel
                    font.pixelSize: ClockStyle.textSmall + 1
                    font.weight: Font.Bold
                    color: ClockStyle.colPrimary
                }
            }
        }
    }
}
