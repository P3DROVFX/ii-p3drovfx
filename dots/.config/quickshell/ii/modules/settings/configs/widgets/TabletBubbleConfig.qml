import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * What the floating bubble offers, and how much of the screen it is willing to take.
 *
 * The eight slots are pickers over the shell's own action catalogue — the same one the
 * gesture bindings read — rather than a list of bubble-specific actions. A second catalogue
 * would be a second thing to keep in step with the first, and every action worth putting on
 * the bubble is already an action something else can be bound to.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property int slotCount: 8

    /// Padded to a fixed length, so a slot the user emptied stays a slot rather than
    /// shifting every action after it up by one.
    function actionAt(index) {
        const stored = Config.options?.tablet?.bubble?.actions ?? [];
        return index < stored.length ? String(stored[index]) : "none";
    }

    function setActionAt(index, actionId) {
        if (!Config.ready)
            return;
        const next = [];
        for (let i = 0; i < root.slotCount; i++)
            next.push(i === index ? actionId : root.actionAt(i));
        // Trailing empties are dropped on write: they carry no information, and a stored
        // list of eight "none" entries is a list that looks configured and is not.
        while (next.length > 0 && next[next.length - 1] === "none")
            next.pop();
        Config.options.tablet.bubble.actions = next;
    }

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
                text: Translation.tr("Floating bubble")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Appearance")
            icon: "bubble_chart"

            ConfigSwitch {
                buttonIcon: "bubble_chart"
                text: Translation.tr("Show the floating bubble")
                checked: Config.options.tablet.bubble.enable
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.bubble.enable)
                        Config.options.tablet.bubble.enable = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "fullscreen"
                text: Translation.tr("Stay on top of fullscreen windows")
                checked: Config.options.tablet.bubble.showOverFullscreen
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.bubble.showOverFullscreen)
                        Config.options.tablet.bubble.showOverFullscreen = checked;
                }
                StyledToolTip {
                    text: Translation.tr("The reason the bubble exists: a fullscreen application is exactly when every edge gesture becomes hard to reach. Turn it off and the bubble sits below fullscreen windows instead, which a video player would prefer.")
                }
            }

            ConfigSwitch {
                buttonIcon: "align_horizontal_right"
                text: Translation.tr("Snap to the nearest side")
                checked: Config.options.tablet.bubble.snapToEdge
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.bubble.snapToEdge)
                        Config.options.tablet.bubble.snapToEdge = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Released, the bubble slides to whichever side edge is nearer, keeping the height you dragged it to. Off, it stays exactly where you let go.")
                }
            }

            ConfigSpinBox {
                icon: "radio_button_unchecked"
                text: Translation.tr("Bubble size (px)")
                value: Config.options.tablet.bubble.size
                from: 40
                to: 96
                stepSize: 4
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.bubble.size)
                        Config.options.tablet.bubble.size = value;
                }
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Fade after (s, 0 never fades)")
                value: Config.options.tablet.bubble.idleAfterSeconds
                from: 0
                to: 60
                stepSize: 1
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.bubble.idleAfterSeconds)
                        Config.options.tablet.bubble.idleAfterSeconds = value;
                }
                StyledToolTip {
                    text: Translation.tr("A control that is always on top has to be able to stop competing with what it is on top of. It never disappears — it only dims.")
                }
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Faded opacity (%)")
                visible: Config.options.tablet.bubble.idleAfterSeconds > 0
                value: Config.options.tablet.bubble.idleOpacity
                from: 15
                to: 100
                stepSize: 5
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.bubble.idleOpacity)
                        Config.options.tablet.bubble.idleOpacity = value;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Actions")
            icon: "bolt"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "grid_view"
                text: Translation.tr("The sheet draws two tiles per row, in this order. Set a slot to None to leave it out — the sheet shrinks to fit whatever is left.")
            }

            Repeater {
                model: root.slotCount

                delegate: ConfigRow {
                    id: slotRow
                    required property int index

                    uniform: false
                    Layout.fillWidth: true

                    readonly property string currentId: root.actionAt(slotRow.index)
                    readonly property var currentAction: ShellActionRegistry.actionById(slotRow.currentId)

                    StyledText {
                        Layout.preferredWidth: 80
                        text: Translation.tr("Slot %1").arg(slotRow.index + 1)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    StyledComboBox {
                        id: slotPicker
                        Layout.fillWidth: true

                        // Only what the running family can perform. An action whose surface
                        // this family never loads would draw a tile that does nothing, which
                        // reads as the bubble being broken rather than as a setting being wrong.
                        readonly property var availableActions:
                            TouchGestureActionRegistry.availableActionsForFamily(PanelFamily.current)

                        buttonIcon: slotRow.currentAction?.icon ?? "block"
                        model: slotPicker.availableActions.map(action => Translation.tr(action.name))
                        currentIndex: {
                            for (let i = 0; i < slotPicker.availableActions.length; ++i) {
                                if (slotPicker.availableActions[i].id === slotRow.currentId)
                                    return i;
                            }
                            return 0;
                        }
                        onActivated: index => {
                            const action = slotPicker.availableActions[index];
                            if (action)
                                root.setActionAt(slotRow.index, action.id);
                        }
                    }
                }
            }
        }
    }
}
