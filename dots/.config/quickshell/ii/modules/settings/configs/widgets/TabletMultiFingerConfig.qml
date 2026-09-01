import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Whole-hand swipes on the touchscreen.
 *
 * A tablet has no touchpad, so the compositor's three-finger bindings are unreachable
 * there — and the two it ships with, scratchpad in and scratchpad out, are a desktop
 * window-management idea a tablet has no use for. These put the same fingers on the things
 * a phone puts them on.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var opts: Config.options?.interactions?.touchGestures?.multiFinger ?? null

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin

            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Multi-finger swipes")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "swipe"
            title: Translation.tr("Multi-finger swipes")

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "touch_app"
                text: Translation.tr("These are touchscreen gestures, recognised by the shell. The compositor's own touchpad gestures are separate and keep their own bindings.")
            }

            ConfigSwitch {
                buttonIcon: "swipe"
                text: Translation.tr("Enable multi-finger swipes")
                checked: Config.options.interactions.touchGestures.multiFinger.enable
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.interactions.touchGestures.multiFinger.enable)
                        Config.options.interactions.touchGestures.multiFinger.enable = checked;
                }
            }

            ConfigSpinBox {
                icon: "back_hand"
                text: Translation.tr("Fingers")
                value: Config.options.interactions.touchGestures.multiFinger.fingers
                from: 2
                to: 5
                stepSize: 1
                onValueChanged: {
                    if (Config.ready && value !== Config.options.interactions.touchGestures.multiFinger.fingers)
                        Config.options.interactions.touchGestures.multiFinger.fingers = value;
                }
                StyledToolTip {
                    text: Translation.tr("Exactly this many. A further finger landing mid-swipe is a different gesture, not more of this one.")
                }
            }

            ConfigSpinBox {
                icon: "straighten"
                text: Translation.tr("Commit distance (px)")
                value: Config.options.interactions.touchGestures.multiFinger.distance
                from: 30
                to: 400
                stepSize: 10
                onValueChanged: {
                    if (Config.ready && value !== Config.options.interactions.touchGestures.multiFinger.distance)
                        Config.options.interactions.touchGestures.multiFinger.distance = value;
                }
                StyledToolTip {
                    text: Translation.tr("How far the hand travels before the swipe fires. It fires once per hand-down, so a longer swipe never repeats the action.")
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.width >= 680 ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10

                TouchGestureBindingCard {
                    title: Translation.tr("Swipe left")
                    description: Translation.tr("The hand moves left across the screen")
                    directionIcon: "arrow_back"
                    actionId: Config.options.interactions.touchGestures.multiFinger.swipeLeft
                    onActionSelected: newAction => {
                        if (Config.ready)
                            Config.options.interactions.touchGestures.multiFinger.swipeLeft = newAction;
                    }
                }

                TouchGestureBindingCard {
                    title: Translation.tr("Swipe right")
                    description: Translation.tr("The hand moves right across the screen")
                    directionIcon: "arrow_forward"
                    actionId: Config.options.interactions.touchGestures.multiFinger.swipeRight
                    onActionSelected: newAction => {
                        if (Config.ready)
                            Config.options.interactions.touchGestures.multiFinger.swipeRight = newAction;
                    }
                }

                TouchGestureBindingCard {
                    title: Translation.tr("Swipe up")
                    description: Translation.tr("The hand moves towards the top of the screen")
                    directionIcon: "arrow_upward"
                    actionId: Config.options.interactions.touchGestures.multiFinger.swipeUp
                    onActionSelected: newAction => {
                        if (Config.ready)
                            Config.options.interactions.touchGestures.multiFinger.swipeUp = newAction;
                    }
                }

                TouchGestureBindingCard {
                    title: Translation.tr("Swipe down")
                    description: Translation.tr("The hand moves towards the bottom of the screen")
                    directionIcon: "arrow_downward"
                    actionId: Config.options.interactions.touchGestures.multiFinger.swipeDown
                    onActionSelected: newAction => {
                        if (Config.ready)
                            Config.options.interactions.touchGestures.multiFinger.swipeDown = newAction;
                    }
                }
            }
        }
    }
}
