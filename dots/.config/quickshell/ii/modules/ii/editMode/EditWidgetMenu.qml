import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/**
 * The per-widget menu of Edit Mode: what it is, whether it is pinned, how big
 * it is, what the lock screen does with it, and the way to take it off.
 *
 * Every row carries its own filled body and its own circled icon rather than
 * being a line of text with a hover tint - the same shape the catalogue's rows
 * and the shell's other menus use, so a menu about a widget reads as the same
 * kind of object as the panel that placed it.
 *
 * The lock behaviour is FOUR states, and a row that cycled through them said
 * only where it currently was: you had to click three times to find out what
 * the choices were, and there was no way to reach one of them at all (a
 * lock-only widget could not be brought back to the desktop). It opens a
 * chooser beside the card instead - the same side-panel gesture the shell's
 * appearance menu uses - so the four are named, described and one click away.
 *
 * It acts on the widget item the canvas resolves from the instance id, so
 * every write goes down the widget's own persisted paths (both scale paths,
 * the per-monitor fork, the history pair) and nothing here duplicates them.
 * The card is inert once the widget is gone: rows disable rather than the menu
 * vanishing under the pointer.
 */
Item {
    id: root

    property var canvas: null
    property string instanceId: ""
    signal dismissRequested()

    readonly property var widget: (canvas && canvas.widgetById) ? canvas.widgetById(instanceId) : null
    readonly property var instance: widget ? widget.widgetInstance : null
    readonly property var metadata: instance ? WidgetsRegistry.getWidgetMetadata(instance.widgetId) : null
    readonly property bool pinned: widget ? widget.pinned : false
    readonly property string lockBehavior: widget ? (widget.lockBehavior || "hide") : "hide"
    readonly property bool lockOnly: root.lockBehavior === "lockOnly"

    readonly property var lockChoices: [
        {
            "value": "hide",
            "symbol": "visibility_off",
            "title": Translation.tr("Hidden"),
            "description": Translation.tr("Not drawn while the screen is locked")
        },
        {
            "value": "keep",
            "symbol": "visibility",
            "title": Translation.tr("Shown in place"),
            "description": Translation.tr("Stays exactly where it is on the desktop")
        },
        {
            "value": "center",
            "symbol": "center_focus_strong",
            "title": Translation.tr("Centred"),
            "description": Translation.tr("Moves to the middle, stacked with the others")
        },
        {
            "value": "lockOnly",
            "symbol": "lock",
            "title": Translation.tr("Lock screen only"),
            "description": Translation.tr("Leaves the desktop entirely")
        }
    ]
    readonly property var currentLockChoice: root.lockChoices.find(choice => choice.value === root.lockBehavior)
        ?? root.lockChoices[0]

    readonly property real scaleFactor: widget ? widget.committedScaleFactor : 1
    readonly property real scaleStep: EditModeLogic.nearestSizeStep(root.scaleFactor)
    readonly property bool canGrow: root.widget !== null && EditModeLogic.steppedScale(root.scaleFactor, 1) !== null
    readonly property bool canShrink: root.widget !== null && EditModeLogic.steppedScale(root.scaleFactor, -1) !== null
    readonly property int padding: 8

    implicitWidth: 268
    implicitHeight: column.implicitHeight + root.padding * 2
    width: implicitWidth
    height: implicitHeight

    // Whether the lock chooser is showing, and which side of the card it opens
    // on: the card is placed at a pointer that can be anywhere, so the chooser
    // flips rather than running off the screen.
    property bool lockChooserOpen: false
    readonly property real chooserWidth: 274
    readonly property real chooserGap: 8
    readonly property bool chooserOnLeft: root.parent !== null
        && (root.x + root.width + root.chooserGap + root.chooserWidth) > root.parent.width

    onInstanceIdChanged: root.lockChooserOpen = false

    function stepSize(direction) {
        if (!root.widget || !root.widget.commitResizeScale)
            return;
        const next = EditModeLogic.steppedScale(root.scaleFactor, direction);
        if (next === null)
            return;
        root.widget.commitResizeScale(next);
    }

    StyledRectangularShadow {
        target: card
    }

    // A click on the card's own padding is a click ON the menu, never a
    // click away from it: swallowed here, under the rows.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 3

        // The title. No body of its own - it names the card rather than
        // offering anything - so it is the one thing here that is not a pill.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 2
            Layout.bottomMargin: 4
            spacing: 8

            MaterialSymbol {
                text: root.metadata ? (root.metadata.icon || "widgets") : "widgets"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: root.metadata ? root.metadata.name : Translation.tr("Widget")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: true
            last: false
            rowEnabled: root.instance !== null
            symbol: root.pinned ? "keep_off" : "keep"
            title: root.pinned ? Translation.tr("Unpin position") : Translation.tr("Pin position")
            trailingKind: "switch"
            switchChecked: root.pinned
            onActivated: Config.updateWidgetPinned(root.instanceId, !root.pinned)
        }

        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: root.widget !== null
            symbol: "aspect_ratio"
            title: Translation.tr("Size")
            trailingKind: "stepper"
            valueText: Math.round(root.scaleStep * 100) + "%"
            stepDownEnabled: root.canShrink
            stepUpEnabled: root.canGrow
            onStepDown: root.stepSize(-1)
            onStepUp: root.stepSize(1)
        }

        EditPanelRow {
            id: lockRow
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: root.instance !== null
            symbol: root.currentLockChoice.symbol
            title: Translation.tr("On lock screen")
            subtitle: root.currentLockChoice.title
            trailingKind: "chevron"
            selected: root.lockChooserOpen
            onActivated: root.lockChooserOpen = !root.lockChooserOpen
        }

        // On the Lockscreen tab a desktop widget is hidden from the lock, not
        // removed from the desktop; a lock-only one is removed outright.
        EditPanelRow {
            Layout.fillWidth: true
            first: false
            last: true
            destructive: true
            rowEnabled: root.instance !== null
                && !(GlobalStates.editLockPreview && root.lockBehavior === "hide")
            symbol: "delete"
            title: GlobalStates.editLockPreview && !root.lockOnly
                ? Translation.tr("Hide on lock screen") : Translation.tr("Remove from desktop")
            trailingKind: "none"
            onActivated: {
                const widgetId = root.instance.widgetId;
                root.dismissRequested();
                if (GlobalStates.editLockPreview && !root.lockOnly)
                    Config.updateWidgetLockBehavior(root.instanceId, "hide");
                else
                    Config.removeWidgetFromDesktop(widgetId);
            }
        }
    }

    // ── The lock-behaviour chooser ───────────────────────────────────────────
    // A card of its own beside the menu rather than a submenu inside it: the
    // four states each need a sentence to be choosable, and four sentences do
    // not fit a row that is already carrying its own answer.
    Loader {
        id: chooserLoader
        active: root.lockChooserOpen && root.instance !== null
        // Top-aligned with the row it belongs to, so the eye goes straight
        // from the chevron to the list.
        y: Math.min(lockRow.y, root.height - (chooserLoader.item ? chooserLoader.item.height : 0))
        x: root.chooserOnLeft
            ? -root.chooserGap - root.chooserWidth
            : root.width + root.chooserGap
        z: 5

        sourceComponent: Item {
            id: chooser
            implicitWidth: root.chooserWidth
            implicitHeight: chooserColumn.implicitHeight + root.padding * 2
            width: implicitWidth
            height: implicitHeight

            transformOrigin: root.chooserOnLeft ? Item.TopRight : Item.TopLeft
            scale: 0.9
            opacity: 0
            Component.onCompleted: {
                chooser.scale = 1;
                chooser.opacity = 1;
            }
            Behavior on scale {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(chooser)
            }
            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(chooser)
            }

            StyledRectangularShadow {
                target: chooserCard
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Rectangle {
                id: chooserCard
                anchors.fill: parent
                radius: Appearance.rounding.windowRounding
                color: Appearance.m3colors.m3surfaceContainer
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
            }

            ColumnLayout {
                id: chooserColumn
                anchors.fill: parent
                anchors.margins: root.padding
                spacing: 3

                Repeater {
                    model: root.lockChoices

                    delegate: EditPanelRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        first: index === 0
                        last: index === root.lockChoices.length - 1
                        symbol: modelData.symbol
                        title: modelData.title
                        subtitle: modelData.description
                        subtitleWrap: true
                        selected: modelData.value === root.lockBehavior
                        trailingKind: selected ? "check" : "none"
                        onActivated: {
                            root.lockChooserOpen = false;
                            Config.updateWidgetLockBehavior(root.instanceId, modelData.value);
                        }
                    }
                }
            }
        }
    }
}
