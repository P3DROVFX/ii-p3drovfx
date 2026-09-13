pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * The right pane while a template is picked in the list: the routine it
 * would create, laid out like the editor but read-only, with one button
 * to add it. Lets the user see what they get before it is in their list.
 */
Item {
    id: root

    required property string templateKey
    readonly property var template: ModeSchema.routineTemplate(root.templateKey)
    readonly property bool isOnce: root.template?.kind === "once"
    readonly property string colorKey: root.template?.color ?? ""
    readonly property var triggers: Array.from(root.template?.triggers ?? [])
    readonly property var actions: Array.from(root.template?.actions ?? [])
    readonly property int copies: Modes.routines.filter(r => r.template === root.templateKey).length

    signal added(string id)
    signal dismissed()

    function add() {
        const id = Modes.addRoutineFromTemplate(root.templateKey);
        if (id.length)
            root.added(id);
    }

    function handleEscape() {
        root.dismissed();
        return true;
    }

    function handleKey(key, modifiers) {
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            root.add();
            return true;
        }
        return false;
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.implicitHeight + 24
        clip: true

        ColumnLayout {
            id: column
            width: flick.width - 8
            x: 4
            y: 8
            spacing: 18

            // -------------------------------------------------- header
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                spacing: 14

                Rectangle {
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: Appearance.rounding.full
                    color: ModeUi.container(root.colorKey)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.template?.icon ?? "bolt"
                        iconSize: 32
                        color: ModeUi.onContainer(root.colorKey)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: root.template?.name ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        text: ModeUi.templateDescription(root.templateKey)
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    RowLayout {
                        Layout.topMargin: 8
                        spacing: 6

                        Rectangle {
                            implicitWidth: kindRow.implicitWidth + 16
                            implicitHeight: 24
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2

                            RowLayout {
                                id: kindRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    text: "auto_awesome"
                                    iconSize: 14
                                    color: Appearance.colors.colOnLayer2
                                }

                                StyledText {
                                    text: Translation.tr("Template")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer2
                                }
                            }
                        }

                        Rectangle {
                            visible: root.copies > 0
                            implicitWidth: copiesRow.implicitWidth + 16
                            implicitHeight: 24
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colSecondaryContainer

                            RowLayout {
                                id: copiesRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    text: "check"
                                    iconSize: 14
                                    color: Appearance.colors.colOnSecondaryContainer
                                }

                                StyledText {
                                    text: root.copies === 1 ? Translation.tr("In your list")
                                        : Translation.tr("In your list ×%1").arg(root.copies)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 4
                    implicitHeight: 48
                    implicitWidth: addRow.implicitWidth + 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: ModeUi.accent(root.colorKey)
                    colBackgroundHover: ColorUtils.mix(colBackground, ModeUi.onAccent(root.colorKey), 0.9)
                    colRipple: ColorUtils.mix(colBackground, ModeUi.onAccent(root.colorKey), 0.8)
                    onClicked: root.add()

                    StyledToolTip {
                        text: root.copies > 0 ? Translation.tr("Add another copy")
                            : Translation.tr("Copy it into your list")
                    }

                    contentItem: RowLayout {
                        id: addRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: "add"
                            iconSize: 22
                            color: ModeUi.onAccent(root.colorKey)
                        }

                        StyledText {
                            text: Translation.tr("Add to my routines")
                            font.weight: Font.DemiBold
                            color: ModeUi.onAccent(root.colorKey)
                        }
                    }
                }
            }

            // -------------------------------------------------- if
            EditorSection {
                title: Translation.tr("If")
                icon: "filter_alt"
                subtitle: {
                    if (root.triggers.length === 0)
                        return Translation.tr("No conditions: runs by hand only");
                    const how = root.isOnce ? Translation.tr("Fires the moment a condition below becomes true")
                        : Translation.tr("Runs for as long as a condition below holds");
                    if (root.triggers.length < 2)
                        return how;
                    return how + " · " + (root.template?.match === "all"
                        ? Translation.tr("all of them") : Translation.tr("any of them"));
                }

                Repeater {
                    model: root.triggers

                    delegate: EditorRow {
                        id: triggerRow
                        required property var modelData

                        icon: ModeUi.triggerTypeIcon(triggerRow.modelData.type)
                        label: ModeUi.triggerTypeLabel(triggerRow.modelData.type)
                        hint: ModeUi.triggerText(triggerRow.modelData)

                        Rectangle {
                            visible: triggerRow.modelData.not === true
                            implicitWidth: invertText.implicitWidth + 14
                            implicitHeight: 22
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colSecondaryContainer

                            StyledText {
                                id: invertText
                                anchors.centerIn: parent
                                text: Translation.tr("Inverted")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------- then
            EditorSection {
                title: Translation.tr("Then")
                icon: "bolt"
                subtitle: {
                    const span = ModeSchema.sequenceSpanSec(root.actions);
                    const base = root.actions.length === 1 ? Translation.tr("1 action")
                        : Translation.tr("%1 actions, in this order").arg(root.actions.length);
                    return span > 0 ? Translation.tr("%1, over %2").arg(base).arg(ModeUi.durationText(span)) : base;
                }

                Repeater {
                    model: root.actions

                    delegate: EditorRow {
                        id: actionRow
                        required property var modelData

                        icon: ModeUi.actionIcon(actionRow.modelData.type)
                        label: ModeUi.actionLabel(actionRow.modelData.type)
                        hint: {
                            const delay = ModeUi.actionDelayText(actionRow.modelData);
                            const value = ModeUi.actionValueText(actionRow.modelData);
                            return delay.length ? `${delay} · ${value}` : value;
                        }
                    }
                }
            }

            // -------------------------------------------------- type
            EditorSection {
                title: Translation.tr("Type")
                icon: "sync_alt"
                subtitle: root.isOnce
                    ? Translation.tr("Acts once when its conditions turn true and leaves things as they are")
                    : Translation.tr("Keeps its actions applied while its conditions hold, then puts them back")

                EditorRow {
                    icon: root.isOnce ? "bolt" : "sync_alt"
                    label: ModeUi.routineKindText(root.template?.kind ?? "while")
                }
            }

            // -------------------------------------------------- options
            EditorSection {
                title: Translation.tr("Options")
                icon: "tune"

                EditorRow {
                    visible: root.isOnce
                    icon: "timer"
                    label: Translation.tr("Cooldown")
                    hint: (root.template?.cooldownSec ?? 0) > 0
                        ? Translation.tr("Will not fire again this soon after the last time")
                        : Translation.tr("Fires on every change")

                    StyledText {
                        text: (root.template?.cooldownSec ?? 0) > 0
                            ? Translation.tr("%1 s").arg(root.template?.cooldownSec ?? 0)
                            : Translation.tr("None")
                        color: Appearance.colors.colOnLayer2
                    }
                }

                EditorRow {
                    visible: !root.isOnce
                    icon: "settings_backup_restore"
                    label: Translation.tr("Put settings back when it ends")

                    StyledText {
                        text: ModeUi.onOff(root.template?.end?.revert ?? true)
                        color: Appearance.colors.colOnLayer2
                    }
                }

                EditorRow {
                    icon: "play_arrow"
                    label: root.isOnce ? Translation.tr("Show a banner when it fires")
                        : Translation.tr("Show a banner when it starts")

                    StyledText {
                        text: ModeUi.onOff(root.template?.notify ?? true)
                        color: Appearance.colors.colOnLayer2
                    }
                }

                EditorRow {
                    visible: !root.isOnce
                    icon: "stop_circle"
                    label: Translation.tr("Show a banner when it ends")

                    StyledText {
                        text: ModeUi.onOff(root.template?.end?.notify ?? root.template?.notify ?? true)
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: Translation.tr(
                    "Adding makes a copy you can rename and edit freely; the template stays here.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
