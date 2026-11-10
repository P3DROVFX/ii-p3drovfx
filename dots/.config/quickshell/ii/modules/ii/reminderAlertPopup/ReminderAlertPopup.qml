pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
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

    // One accent family for the card: the reminder's category colour when it has one,
    // the theme's primary otherwise. A category colour is the user's pick, not a theme
    // role, so its on-colour and states are derived from it.
    readonly property string categoryColor: root.reminder
        ? (RemindersService.category(root.reminder.categoryId)?.color ?? "") : ""
    readonly property bool hasCategoryColor: root.categoryColor.length > 0
    readonly property color colAccent: root.hasCategoryColor ? root.categoryColor : ClockStyle.colPrimary
    readonly property color colOnAccent: root.hasCategoryColor
        ? ColorUtils.categoryOnColor(root.colAccent) : ClockStyle.colOnPrimary
    readonly property color colAccentHover: root.hasCategoryColor
        ? ColorUtils.mix(root.colAccent, root.colOnAccent, 0.88) : ClockStyle.colPrimaryHover
    readonly property color colAccentActive: root.hasCategoryColor
        ? ColorUtils.mix(root.colAccent, root.colOnAccent, 0.76) : ClockStyle.colPrimaryActive

    // The one number: when it is due, in expressive digits; the day goes above it.
    readonly property var due: root.reminder ? RemindersService.dueAt(root.reminder) : null
    readonly property bool hasTime: root.due !== null && (root.reminder?.schedule?.time ?? "").length > 0
    readonly property string timeText: root.hasTime
        ? Qt.locale().toString(root.due, Config.options?.time?.format ?? "hh:mm") : ""
    readonly property string dayText: {
        if (!root.reminder)
            return "";
        if (!root.hasTime)
            return RemindersService.whenText(root.reminder, new Date());
        // The same wording as everywhere else ("Today", "Fri, 9 Oct"), without the time.
        const schedule = Object.assign({}, root.reminder.schedule, { time: "" });
        const dayOnly = Object.assign({}, root.reminder, { schedule: schedule });
        return RemindersService.whenText(dayOnly, new Date());
    }

    PanelWindow {
        id: popupWindow
        visible: root.reminder !== null && !GlobalStates.islandOwnsReminder
        color: "transparent"
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
            ?? Quickshell.screens[0] ?? null

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

            ShellRegionTarget {
                target: card
                label: Translation.tr("Reminder")
                namespace: "quickshell:reminderAlert"
            }
            anchors.centerIn: parent
            width: Math.min(460, popupWindow.width - ClockStyle.gapHuge * 2)
            height: content.implicitHeight + ClockStyle.gapHuge * 2
            radius: ClockStyle.radiusCard
            color: ColorUtils.transparentize(ClockStyle.colSurfaceHigh, 0.08)
            focus: popupWindow.visible

            // One-shot entrance (fade + 24 px rise): the window is built only while a
            // reminder rings, so this runs once per alert and never while hidden.
            property bool entered: false
            Component.onCompleted: card.entered = true
            opacity: card.entered && popupWindow.visible ? 1 : 0
            transform: Translate {
                y: card.entered && popupWindow.visible ? 0 : 24

                Behavior on y {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionEnter.numberAnimation.createObject(this)
                }
            }

            Behavior on opacity {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
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
                    margins: ClockStyle.gapHuge
                }
                spacing: ClockStyle.gap

                // The level as a shape: a burst rings (Strong), a cookie chimes (Medium);
                // a change of level morphs one into the other.
                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: RemindersService.ringingLevel === "strong" ? "alarm" : "notifications_active"
                    iconSize: 34
                    padding: 18
                    shape: RemindersService.ringingLevel === "strong" ? MaterialShape.Shape.SoftBurst
                        : MaterialShape.Shape.Cookie9Sided
                    color: root.colAccent
                    colSymbol: root.colOnAccent
                    fill: 1
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    horizontalAlignment: Text.AlignHCenter
                    text: root.dayText
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: -ClockStyle.gapSmall
                    Layout.bottomMargin: -ClockStyle.gapSmall
                    visible: root.hasTime
                    horizontalAlignment: Text.AlignHCenter
                    text: root.timeText
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.features: ({ "tnum": 1 })
                    font.pixelSize: Math.round(Math.min(card.width * 0.17, 76))
                    color: ClockStyle.colOnSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.reminder ? (root.reminder.title || Translation.tr("Reminder")) : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textTitle
                    color: ClockStyle.colOnSurface
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
                            buttonRadius: ClockStyle.radiusSmall
                            // Tinted with the card's content colour (guide §2.3).
                            colBackground: "transparent"
                            colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.08)
                            colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.16)
                            onClicked: RemindersService.toggleChecklistItem(root.reminder.id,
                                checkRow.modelData.id)

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
                                    color: ClockStyle.colOnSurface
                                }
                            }
                        }
                    }
                }

                Item {
                    implicitHeight: ClockStyle.gapTiny
                }

                // Complete is the card's own accent, so it matches the badge and the ticks.
                AlertButton {
                    symbol: "check_circle"
                    label: Translation.tr("Complete")
                    colBackground: root.colAccent
                    colBackgroundHover: root.colAccentHover
                    colRipple: root.colAccentActive
                    colContent: root.colOnAccent
                    onClicked: RemindersService.complete(root.reminder.id)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    AlertButton {
                        symbol: "snooze"
                        label: Translation.tr("Snooze %1 min").arg(String(RemindersService.snoozeMinutes))
                        colBackground: ClockStyle.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        colContent: ClockStyle.colOnSecondaryContainer
                        onClicked: RemindersService.snooze(root.reminder.id, RemindersService.snoozeMinutes)
                    }

                    // One step up the ladder from the card (colLayer3 is the card's own
                    // surface, so the button vanished into it).
                    AlertButton {
                        symbol: "close"
                        label: Translation.tr("Dismiss")
                        colBackground: ClockStyle.colSurfaceHighest
                        colBackgroundHover: ClockStyle.colSurfaceHover
                        colRipple: ClockStyle.colSurfaceActive
                        colContent: ClockStyle.colOnSurface
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
        property color colContent: ClockStyle.colOnSurface

        Layout.fillWidth: true
        Layout.preferredHeight: 52
        buttonRadius: ClockStyle.pill(52)
        buttonRadiusPressed: ClockStyle.radiusSmall

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
