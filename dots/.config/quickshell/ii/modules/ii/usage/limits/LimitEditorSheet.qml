pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Creating or editing a limit, in the side sheet. Works on a draft: nothing reaches the
 * config until Save. The budget is the sheet's big number — a tall tile of condensed
 * digits with − and + on it, quick chips below — and the apps come from the picker.
 */
ClockSheet {
    id: root

    property var source: null
    property string startKind: "app"
    property var startKeys: []

    readonly property bool editing: root.source !== null && root.source !== undefined
    readonly property string editingId: root.editing ? root.source.id : ""

    property string draftKind: "app"
    property var draftKeys: []
    property int draftMinutes: 60
    property var draftDays: [true, true, true, true, true, true, true]
    property bool draftStrict: false
    property bool ready: false

    readonly property bool canSave: root.draftKind === "total" || root.draftKeys.length > 0
    readonly property var presets: [
        { label: Translation.tr("Every day"), days: [true, true, true, true, true, true, true] },
        { label: Translation.tr("Weekdays"), days: [false, true, true, true, true, true, false] },
        { label: Translation.tr("Weekends"), days: [true, false, false, false, false, false, true] }
    ]
    readonly property var quickMinutes: [15, 30, 45, 60, 90, 120, 180, 240]
    readonly property real usedToday: ScreenTimeLimits.usedFor({ kind: root.draftKind, keys: root.draftKeys })

    function load(): void {
        if (root.editing) {
            root.draftKind = root.source.kind === "total" ? "total" : "app";
            root.draftKeys = Array.from(root.source.keys ?? []);
            root.draftMinutes = root.source.minutes ?? 60;
            root.draftDays = Array.from(root.source.days ?? [true, true, true, true, true, true, true]);
            root.draftStrict = root.source.strict === true;
            nameField.text = root.source.name ?? "";
        } else {
            root.draftKind = root.startKind === "total" ? "total" : "app";
            root.draftKeys = Array.from(root.startKeys ?? []);
            root.draftMinutes = root.draftKind === "total" ? 240 : 60;
        }
    }

    function toggleKey(key: string): void {
        const next = Array.from(root.draftKeys);
        const index = next.indexOf(key);
        if (index >= 0)
            next.splice(index, 1);
        else
            next.push(key);
        root.draftKeys = next;
    }

    function stepMinutes(delta: int): void {
        const step = root.draftMinutes < 60 || (root.draftMinutes === 60 && delta < 0) ? 5 : 15;
        root.draftMinutes = Math.max(5, Math.min(24 * 60, root.draftMinutes + delta * step));
    }

    function toggleDay(day: int): void {
        const next = Array.from(root.draftDays);
        next[day] = !next[day];
        root.draftDays = next;
    }

    function save(): void {
        if (!root.canSave)
            return;
        const limit = {
            kind: root.draftKind,
            name: nameField.text.trim(),
            keys: root.draftKind === "total" ? [] : root.draftKeys,
            minutes: root.draftMinutes,
            days: root.draftDays,
            strict: root.draftStrict && ScreenTimeLimits.hasPin,
            enabled: true
        };
        if (root.editing)
            limit.id = root.source.id;
        ScreenTimeLimits.saveLimit(limit);
        root.close();
    }

    title: root.editing ? Translation.tr("Edit limit") : Translation.tr("New limit")
    subtitle: root.usedToday > 0 ? Translation.tr("%1 used today").arg(ScreenTimeLimits.formatSeconds(root.usedToday)) : ""

    Component.onCompleted: {
        root.load();
        Qt.callLater(() => root.ready = true);
    }

    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.save();
            event.accepted = true;
        }
    }

    headerActions: [
        ClockIconButton {
            visible: root.editing
            symbol: "delete"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            colIcon: ClockStyle.colError
            tooltip: Translation.tr("Delete")
            onClicked: {
                ScreenTimeLimits.removeLimit(root.source.id);
                root.close();
            }
        }
    ]

    // ── What it limits ──────────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        spacing: 6

        ClockFormChip {
            label: Translation.tr("Apps")
            symbol: "apps"
            selected: root.draftKind === "app"
            onTriggered: root.draftKind = "app"
        }
        ClockFormChip {
            label: Translation.tr("All screen time")
            symbol: "devices"
            selected: root.draftKind === "total"
            onTriggered: root.draftKind = "total"
        }
    }

    // ── Budget ──────────────────────────────────────────────────────────
    Rectangle {
        id: budgetTile
        Layout.fillWidth: true
        implicitHeight: 132
        radius: Appearance.rounding.small
        color: tileHover.hovered ? ClockStyle.colPrimaryContainer : ClockStyle.colField

        readonly property color colContent: tileHover.hovered ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        HoverHandler {
            id: tileHover
        }

        WheelHandler {
            onWheel: event => root.stepMinutes(event.angleDelta.y > 0 ? 1 : -1)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                MaterialSymbol {
                    text: "hourglass_top"
                    iconSize: Appearance.font.pixelSize.smallie
                    color: tileHover.hovered ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Daily limit")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: tileHover.hovered ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Math.floor(root.draftMinutes / 60) + ":" + String(root.draftMinutes % 60).padStart(2, "0")
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: 68
                    color: budgetTile.colContent
                    animateChange: root.ready && !ClockStyle.reducedMotion
                }

                ClockIconButton {
                    symbol: "remove"
                    size: 44
                    enabled: root.draftMinutes > 5
                    // Tinted with the tile's content colour so they follow its hover fill.
                    colBackground: ColorUtils.applyAlpha(budgetTile.colContent, 0.08)
                    colBackgroundHover: ColorUtils.applyAlpha(budgetTile.colContent, 0.16)
                    colBackgroundActive: ColorUtils.applyAlpha(budgetTile.colContent, 0.24)
                    colRipple: colBackgroundActive
                    colIcon: budgetTile.colContent
                    tooltip: Translation.tr("Less")
                    onClicked: root.stepMinutes(-1)
                }

                ClockIconButton {
                    symbol: "add"
                    size: 44
                    enabled: root.draftMinutes < 24 * 60
                    colBackground: ColorUtils.applyAlpha(budgetTile.colContent, 0.08)
                    colBackgroundHover: ColorUtils.applyAlpha(budgetTile.colContent, 0.16)
                    colBackgroundActive: ColorUtils.applyAlpha(budgetTile.colContent, 0.24)
                    colRipple: colBackgroundActive
                    colIcon: budgetTile.colContent
                    tooltip: Translation.tr("More")
                    onClicked: root.stepMinutes(1)
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.quickMinutes

            ClockFormChip {
                required property int modelData
                label: modelData < 60 ? Translation.tr("%1 min").arg(String(modelData))
                    : modelData % 60 === 0 ? Translation.tr("%1 h").arg(String(modelData / 60))
                    : Translation.tr("%1 h %2").arg(String(Math.floor(modelData / 60))).arg(String(modelData % 60))
                selected: root.draftMinutes === modelData
                onTriggered: root.draftMinutes = modelData
            }
        }
    }

    // ── Days ────────────────────────────────────────────────────────────
    StyledText {
        Layout.topMargin: 2
        text: Translation.tr("Applies on")
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.presets

            ClockFormChip {
                required property var modelData
                label: modelData.label
                selected: String(root.draftDays) === String(modelData.days)
                onTriggered: root.draftDays = Array.from(modelData.days)
            }
        }
    }

    ClockDayChips {
        Layout.fillWidth: true
        chipSize: 38
        days: root.draftDays
        onToggled: day => root.toggleDay(day)
    }

    // ── Apps ────────────────────────────────────────────────────────────
    LimitsAppPicker {
        visible: root.draftKind === "app"
        Layout.fillWidth: true
        Layout.topMargin: 4
        selected: root.draftKeys
        onToggled: key => root.toggleKey(key)
    }

    StyledText {
        visible: root.draftKind === "total"
        Layout.fillWidth: true
        text: Translation.tr("Counts every focused minute except always-allowed apps. When it runs out, any app you open is covered.")
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colSubtext
    }

    ClockFormField {
        id: nameField
        Layout.topMargin: 4
        symbol: "label"
        caption: Translation.tr("Name")
        placeholder: root.draftKind === "total" ? Translation.tr("Screen time") : ScreenTimeLimits.ruleName({ kind: "app", keys: root.draftKeys })
        onAccepted: root.save()
    }

    ClockFormToggle {
        symbol: "lock"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        label: Translation.tr("Ask for the PIN")
        description: ScreenTimeLimits.hasPin ? Translation.tr("More time needs the PIN") : Translation.tr("Set a PIN in limit settings first")
        checked: root.draftStrict && ScreenTimeLimits.hasPin
        enabled: ScreenTimeLimits.hasPin
        opacity: enabled ? 1 : 0.55
        onToggled: checked => root.draftStrict = checked
    }

    actions: [
        ClockSheetAction {
            Layout.fillWidth: true
            label: Translation.tr("Cancel")
            onClicked: root.close()
        },
        ClockSheetAction {
            Layout.fillWidth: true
            primary: true
            enabled: root.canSave
            symbol: "check"
            label: root.draftKind === "app" && root.draftKeys.length === 0 ? Translation.tr("Pick an app") : Translation.tr("Save")
            onClicked: root.save()
        }
    ]
}
