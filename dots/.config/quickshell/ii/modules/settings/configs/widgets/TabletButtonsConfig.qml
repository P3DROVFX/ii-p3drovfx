pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Settings -> Touch & Gestures -> Tablet buttons.
 *
 * One picker per OpenTabletDriver express key and pen button. Every change goes into
 * `interactions.tabletButtons`; TabletButtons rewrites the driver's bindings and the
 * Hyprland binds from it.
 */
Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property var opts: Config.options?.interactions?.tabletButtons ?? null
    readonly property real gap: Appearance.sizes.elevationMargin

    readonly property int auxSlots: TabletButtons.auxCount > 0 ? TabletButtons.auxCount : 4
    readonly property int penSlots: TabletButtons.penCount > 0 ? TabletButtons.penCount : 2

    Component.onCompleted: TabletButtons.refresh()

    /// Open/close, undo, spotlight and board on the first four express keys.
    function applyLiveDrawPreset(): void {
        const preset = ["liveDraw", "liveDrawUndo", "liveDrawSpotlight", "liveDrawBoard"];
        for (let slot = 0; slot < Math.min(preset.length, root.auxSlots); slot++)
            TabletButtons.setAction("aux", slot, preset[slot]);
        if (Config.ready && root.opts && !root.opts.enable)
            root.opts.enable = true;
    }

    component SlotRow: RowLayout {
        id: slotRow
        required property string kind
        required property int slot
        readonly property string actionId: TabletButtons.actionFor(slotRow.kind, slotRow.slot)
        readonly property var actions: TabletButtons.actionsForKind(slotRow.kind)
        readonly property var driver: (TabletButtons.tablet?.[slotRow.kind] ?? [])[slotRow.slot] ?? null
        readonly property bool justPressed: TabletButtons.lastPressKind === slotRow.kind
            && TabletButtons.lastPressSlot === slotRow.slot

        Layout.fillWidth: true
        spacing: root.gap

        Rectangle {
            id: badge
            implicitWidth: 36
            implicitHeight: 36
            radius: Appearance.rounding.full
            color: slotRow.justPressed ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(badge)
            }

            StyledText {
                anchors.centerIn: parent
                text: String(slotRow.slot + 1)
                font.pixelSize: Appearance.font.pixelSize.normal
                color: slotRow.justPressed ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: slotRow.kind === "pen" ? Translation.tr("Pen button %1").arg(slotRow.slot + 1)
                    : Translation.tr("Express key %1").arg(slotRow.slot + 1)
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: !slotRow.driver ? Translation.tr("Not reported by the driver")
                    : slotRow.driver.shell ? Translation.tr("Sends %1 to the shell").arg(slotRow.driver.key)
                    : slotRow.driver.current.length > 0 ? Translation.tr("Driver: %1").arg(slotRow.driver.current)
                    : Translation.tr("Driver: nothing")
            }
        }

        StyledComboBox {
            Layout.preferredWidth: 300
            buttonIcon: TabletButtons.actionInfo(slotRow.actionId).icon
            model: slotRow.actions.map(item => Translation.tr(item.name))
            currentIndex: Math.max(0, slotRow.actions.findIndex(item => item.id === slotRow.actionId))
            onActivated: index => TabletButtons.setAction(slotRow.kind, slotRow.slot, slotRow.actions[index].id)
        }
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: root.gap

            RippleButton {
                implicitWidth: root.gap * 4
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
                text: Translation.tr("Tablet Buttons")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "stylus_note"
            title: Translation.tr("Graphics tablet")
            tooltip: Translation.tr("OpenTabletDriver express keys and pen buttons running shell actions. The shell writes the driver's bindings and the Hyprland binds; the driver's own binding comes back when a button is set to Driver default.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap

                ConfigSwitch {
                    buttonIcon: "stylus"
                    text: Translation.tr("Use tablet buttons for shell actions")
                    checked: TabletButtons.enabled
                    onCheckedChanged: {
                        if (Config.ready && root.opts && checked !== root.opts.enable)
                            root.opts.enable = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Off puts every button back to the binding it had in OpenTabletDriver.")
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: !TabletButtons.status ? Translation.tr("Looking for OpenTabletDriver…")
                        : (TabletButtons.tablet ? Translation.tr("Tablet: %1").arg(TabletButtons.tablet.name)
                            : Translation.tr("No tablet profile in OpenTabletDriver yet"))
                          + " · " + (TabletButtons.otdRunning ? Translation.tr("driver running")
                            : Translation.tr("driver not running — changes apply when it starts"))
                          + (TabletButtons.lastPressSlot >= 0 ? " · " + Translation.tr("last press: %1 %2")
                              .arg(TabletButtons.lastPressKind).arg(TabletButtons.lastPressSlot + 1) : "")
                }

                WarningBox {
                    Layout.fillWidth: true
                    visible: TabletButtons.status !== null && (!TabletButtons.otdInstalled || !TabletButtons.status.hasSettings)
                    materialIcon: "warning"
                    text: !TabletButtons.otdInstalled ? Translation.tr("OpenTabletDriver is not installed.")
                        : Translation.tr("OpenTabletDriver has no settings file yet. Open it once with the tablet plugged in.")
                }

                WarningBox {
                    Layout.fillWidth: true
                    visible: TabletButtons.applyError.length > 0
                    materialIcon: "error"
                    text: Translation.tr("Could not update OpenTabletDriver: %1").arg(TabletButtons.applyError)
                }

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Saving from OpenTabletDriver's own window writes its old bindings back. Press Apply again afterwards.")
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: root.gap

                    RippleButtonWithIcon {
                        materialIcon: "draw"
                        mainText: Translation.tr("Live draw preset")
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.applyLiveDrawPreset()
                        StyledToolTip {
                            text: Translation.tr("Express keys 1–4: open/close live draw, undo, spotlight, board")
                        }
                    }
                    RippleButtonWithIcon {
                        materialIcon: "sync"
                        mainText: TabletButtons.applying ? Translation.tr("Applying…") : Translation.tr("Apply again")
                        buttonRadius: Appearance.rounding.full
                        enabled: !TabletButtons.applying
                        onClicked: {
                            TabletButtons.applyToDriver(true);
                            TabletButtons.bindKeys();
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "keyboard_keys"
            title: Translation.tr("Express keys")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap

                Repeater {
                    model: root.auxSlots
                    delegate: SlotRow {
                        required property int index
                        kind: "aux"
                        slot: index
                    }
                }
            }
        }

        ContentSection {
            icon: "stylus"
            title: Translation.tr("Pen buttons")
            tooltip: Translation.tr("A pen button handed to the shell no longer right-clicks or middle-clicks in apps.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap

                Repeater {
                    model: root.penSlots
                    delegate: SlotRow {
                        required property int index
                        kind: "pen"
                        slot: index
                    }
                }
            }
        }

        ContentSection {
            icon: "swap_vert"
            title: Translation.tr("Scrolling")
            tooltip: Translation.tr("Scroll up/down/left/right scroll a fixed step per press and keep going while the button is held. Scroll by dragging (pen buttons only) freezes the pointer while the button is held and turns the pen's movement into scrolling.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.gap

                ConfigSpinBox {
                    icon: "format_line_spacing"
                    text: Translation.tr("Notches per press")
                    value: root.opts?.scrollStep ?? 1
                    from: 1
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        if (Config.ready && root.opts && value !== root.opts.scrollStep)
                            root.opts.scrollStep = value;
                    }
                }

                ConfigSlider {
                    Layout.fillWidth: true
                    buttonIcon: "speed"
                    text: Translation.tr("Drag scroll speed (%)")
                    usePercentTooltip: true
                    from: 25
                    to: 400
                    stepSize: 5
                    value: Math.round((root.opts?.dragSpeed ?? 1) * 100)
                    onValueChanged: {
                        if (Config.ready && root.opts && Math.abs(value / 100 - root.opts.dragSpeed) > 0.001)
                            root.opts.dragSpeed = value / 100;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "swap_vert"
                    text: Translation.tr("Invert drag direction")
                    checked: root.opts?.invertDrag ?? false
                    onCheckedChanged: {
                        if (Config.ready && root.opts && checked !== root.opts.invertDrag)
                            root.opts.invertDrag = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Off: the page follows the pen, like dragging it with a finger.")
                    }
                }

                WarningBox {
                    Layout.fillWidth: true
                    visible: TabletButtons.scrollError.length > 0
                    materialIcon: "error"
                    text: Translation.tr("The scroll helper failed: %1").arg(TabletButtons.scrollError)
                }
            }
        }
    }
}
