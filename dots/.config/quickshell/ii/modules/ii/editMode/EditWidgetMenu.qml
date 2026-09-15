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

    // Whether the widget names a Settings page of its own. Most do; the
    // handful that do not simply have no options row.
    readonly property bool hasConfigPage: String(root.metadata?.configPage ?? "") !== ""

    readonly property real scaleFactor: widget ? widget.committedScaleFactor : 1
    readonly property real scaleStep: EditModeLogic.nearestSizeStep(root.scaleFactor)
    readonly property bool canGrow: root.widget !== null && EditModeLogic.steppedScale(root.scaleFactor, 1) !== null
    readonly property bool canShrink: root.widget !== null && EditModeLogic.steppedScale(root.scaleFactor, -1) !== null
    readonly property int padding: 8

    implicitWidth: 268
    implicitHeight: column.implicitHeight + root.padding * 2
    width: implicitWidth
    height: implicitHeight

    // Whether a side panel is showing, and which side of the card it opens on:
    // the card is placed at a pointer that can be anywhere, so a panel flips
    // rather than running off the screen. The two are exclusive - one card
    // beside the menu at a time, or the second would land on the first.
    property bool lockChooserOpen: false
    property bool configOpen: false
    readonly property real chooserWidth: 274
    readonly property real chooserGap: 8
    readonly property real configWidth: Math.min(440, Math.max(300,
        (root.parent ? root.parent.width : 900) - root.width - root.chooserGap * 4))
    readonly property real configMaxHeight: Math.max(240,
        (root.parent ? root.parent.height : 720) - 32)

    function opensOnLeft(panelWidth) {
        return root.parent !== null
            && (root.x + root.width + root.chooserGap + panelWidth) > root.parent.width;
    }
    readonly property bool chooserOnLeft: root.opensOnLeft(root.chooserWidth)
    readonly property bool configOnLeft: root.opensOnLeft(root.configWidth)

    // Six of the widgets' Settings pages carry a text field, and under
    // layer-shell no item in a surface at keyboardFocus None can hold active
    // focus at all: the caret would never appear and the keys would go
    // wherever the keyboard already was. So the open panel asks the chrome to
    // hold the keyboard the same way the catalogue's search field does - as
    // intent, published upward, never read back off activeFocus.
    readonly property bool wantsKeyboard: root.configOpen && root.instance !== null && root.hasConfigPage

    onInstanceIdChanged: {
        root.lockChooserOpen = false;
        root.configOpen = false;
    }

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
            hostRadius: Appearance.rounding.windowRounding
            hostPadding: root.padding
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
            hostRadius: Appearance.rounding.windowRounding
            hostPadding: root.padding
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

        // Beside the size, the way back to the plain one - a widget resized
        // by the grip has no other route to exactly 100%.
        EditPanelRow {
            hostRadius: Appearance.rounding.windowRounding
            hostPadding: root.padding
            Layout.fillWidth: true
            first: false
            last: false
            visible: root.widget !== null && Math.abs(root.scaleFactor - 1) > 0.001
            symbol: "fit_screen"
            title: Translation.tr("Reset size")
            trailingKind: "none"
            onActivated: {
                if (root.widget && root.widget.commitResizeScale)
                    root.widget.commitResizeScale(1);
            }
        }

        // Everything the widget itself can be told to do. Not a copy of its
        // Settings page - the page itself, loaded beside the menu - so the
        // options here are whatever Settings has, without a second list of
        // them to keep in step.
        EditPanelRow {
            id: configRow
            hostRadius: Appearance.rounding.windowRounding
            hostPadding: root.padding
            Layout.fillWidth: true
            first: false
            last: false
            visible: root.hasConfigPage
            rowEnabled: root.instance !== null
            symbol: "tune"
            title: Translation.tr("Widget options")
            trailingKind: "chevron"
            selected: root.configOpen
            onActivated: {
                root.lockChooserOpen = false;
                root.configOpen = !root.configOpen;
            }
        }

        // One more of this one, a step down and to the right. A widget can
        // be placed more than once, and the catalogue's row gives a fresh
        // copy at a default spot; this gives one that keeps its settings.
        EditPanelRow {
            hostRadius: Appearance.rounding.windowRounding
            hostPadding: root.padding
            Layout.fillWidth: true
            first: false
            last: false
            rowEnabled: root.instance !== null
            symbol: "content_copy"
            title: Translation.tr("Duplicate")
            trailingKind: "none"
            onActivated: {
                const instanceId = root.instanceId;
                const monitor = root.instance ? (root.instance.monitorName ?? "") : "";
                root.dismissRequested();
                Config.duplicateWidgetInstance(instanceId, monitor);
            }
        }

        EditPanelRow {
            hostRadius: Appearance.rounding.windowRounding
            hostPadding: root.padding
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
            onActivated: {
                root.configOpen = false;
                root.lockChooserOpen = !root.lockChooserOpen;
            }
        }

        // On the Lockscreen tab a desktop widget is hidden from the lock, not
        // removed from the desktop; a lock-only one is removed outright.
        EditPanelRow {
            hostRadius: Appearance.rounding.windowRounding
            hostPadding: root.padding
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
                const instanceId = root.instanceId;
                root.dismissRequested();
                if (GlobalStates.editLockPreview && !root.lockOnly)
                    Config.updateWidgetLockBehavior(instanceId, "hide");
                else
                    // THIS copy, not every widget of its kind: the menu is
                    // about the one the pointer opened it on, and a widget can
                    // now be placed more than once.
                    Config.removeWidgetInstance(instanceId);
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
                        hostRadius: Appearance.rounding.windowRounding
                        hostPadding: root.padding
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

    // ── The widget's own settings ────────────────────────────────────────────
    // The same side-panel gesture as the chooser above, carrying the widget's
    // real Settings page instead of a hand-written copy of it.
    Loader {
        id: configLoader
        active: root.configOpen && root.instance !== null && root.hasConfigPage
        // Beside the menu and inside the screen: a page of forms is taller
        // than the menu that opened it, so the card slides up as far as it
        // must rather than hanging off the bottom.
        y: {
            const h = configLoader.item ? configLoader.item.height : 0;
            const parentHeight = root.parent ? root.parent.height : root.height;
            return Math.max(16 - root.y, Math.min(0, parentHeight - 16 - root.y - h));
        }
        x: root.configOnLeft
            ? -root.chooserGap - root.configWidth
            : root.width + root.chooserGap
        z: 5

        sourceComponent: EditWidgetConfigPanel {
            id: configPanel
            widgetId: root.instance ? root.instance.widgetId : ""
            maxWidth: root.configWidth
            maxHeight: root.configMaxHeight
            onDismissRequested: root.configOpen = false

            transformOrigin: root.configOnLeft ? Item.TopRight : Item.TopLeft
            scale: 0.9
            opacity: 0
            Component.onCompleted: {
                configPanel.scale = 1;
                configPanel.opacity = 1;
            }
            Behavior on scale {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(configPanel)
            }
            Behavior on opacity {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(configPanel)
            }
        }
    }
}
