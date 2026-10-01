pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * A Medium or Strong reminder taking the screen, Samsung Reminder's full-screen alert:
 * the user's alert background (a colour or a picture), what to remember with its notes
 * and checklist, and Complete / Snooze / Dismiss.
 *
 * Keys: Enter completes, S snoozes, Esc dismisses (the reminder stays open, with a
 * notification left behind). Stands aside while the island owns reminders.
 */
Scope {
    id: root

    readonly property var reminder: RemindersService.ringing
    readonly property var options: Config.options.clockApp.reminders
    readonly property string backgroundImage: root.options?.alertBackgroundImage ?? ""
    readonly property string backgroundColor: root.options?.alertBackgroundColor ?? ""
    readonly property color colAccent: root.reminder ? (RemindersService.category(root.reminder.categoryId)?.color || Appearance.colors.colPrimary)
        : Appearance.colors.colPrimary

    PanelWindow {
        id: popupWindow
        visible: root.reminder !== null && !GlobalStates.islandOwnsReminder
        color: "transparent"
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

        WlrLayershell.namespace: "quickshell:reminderAlert"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // ── Backdrop: the theme, a colour, or a picture ─────────────────
        Rectangle {
            anchors.fill: parent
            color: root.backgroundColor.length > 0
                ? ColorUtils.transparentize(root.backgroundColor, 0.1)
                : ColorUtils.transparentize(Appearance.m3colors.m3background, 0.3)
        }

        Loader {
            anchors.fill: parent
            active: root.backgroundImage.length > 0
            sourceComponent: Item {
                StyledImage {
                    anchors.fill: parent
                    source: "file://" + root.backgroundImage
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: popupWindow.width
                    sourceSize.height: popupWindow.height
                }

                Rectangle {
                    anchors.fill: parent
                    color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.45)
                }
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(460, popupWindow.width - 48)
            height: content.implicitHeight + 56
            radius: Appearance.rounding.verylarge
            color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHigh, 0.08)
            focus: popupWindow.visible
            scale: popupWindow.visible ? 1 : 0.92

            Behavior on scale {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }

            Keys.onPressed: event => {
                const id = root.reminder?.id ?? "";
                if (id.length === 0)
                    return;
                if (event.key === Qt.Key_S) {
                    RemindersService.snooze(id, RemindersService.snoozeMinutes);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    RemindersService.complete(id);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space) {
                    RemindersService.stopRinging(true);
                    event.accepted = true;
                }
            }

            ColumnLayout {
                id: content
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 28
                }
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: RemindersService.ringingLevel === "strong" ? "alarm" : "notifications_active"
                    iconSize: 34
                    padding: 18
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: root.colAccent
                    colSymbol: (0.299 * root.colAccent.r + 0.587 * root.colAccent.g + 0.114 * root.colAccent.b) > 0.6 ? "#1d1b16" : "#ffffff"
                    fill: 1
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.reminder ? RemindersService.whenText(root.reminder, new Date()) : ""
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.reminder ? (root.reminder.title || Translation.tr("Reminder")) : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.title
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: (root.reminder?.notes ?? "").length > 0
                    horizontalAlignment: Text.AlignHCenter
                    text: root.reminder?.notes ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                }

                // The checklist, still tickable here.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: (root.reminder?.checklist ?? []).length > 0
                    spacing: 2

                    Repeater {
                        model: (root.reminder?.checklist ?? []).slice(0, 8)

                        RippleButton {
                            id: checkRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: RemindersService.toggleChecklistItem(root.reminder.id, checkRow.modelData.id)

                            contentItem: RowLayout {
                                spacing: 10

                                MaterialSymbol {
                                    Layout.leftMargin: 8
                                    text: checkRow.modelData.done ? "check_box" : "check_box_outline_blank"
                                    iconSize: 22
                                    fill: checkRow.modelData.done ? 1 : 0
                                    color: root.colAccent
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: checkRow.modelData.text
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.strikeout: checkRow.modelData.done
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                        }
                    }
                }

                Item {
                    implicitHeight: 6
                }

                AlertButton {
                    symbol: "check_circle"
                    label: Translation.tr("Complete")
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    colContent: Appearance.colors.colOnPrimary
                    onClicked: RemindersService.complete(root.reminder.id)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    AlertButton {
                        symbol: "snooze"
                        label: Translation.tr("Snooze %1 min").arg(String(RemindersService.snoozeMinutes))
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        colContent: Appearance.colors.colOnSecondaryContainer
                        onClicked: RemindersService.snooze(root.reminder.id, RemindersService.snoozeMinutes)
                    }

                    AlertButton {
                        symbol: "close"
                        label: Translation.tr("Dismiss")
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        colContent: Appearance.colors.colOnLayer3
                        onClicked: RemindersService.stopRinging(true)
                    }
                }
            }
        }
    }

    component AlertButton: RippleButton {
        id: button
        property string symbol: ""
        property string label: ""
        property color colContent: Appearance.colors.colOnLayer3

        Layout.fillWidth: true
        Layout.preferredHeight: 52
        buttonRadius: 26
        buttonRadiusPressed: Appearance.rounding.small

        contentItem: Item {
            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    text: button.symbol
                    iconSize: 22
                    color: button.colContent
                }

                StyledText {
                    text: button.label
                    font.weight: Font.Bold
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: button.colContent
                }
            }
        }
    }
}
