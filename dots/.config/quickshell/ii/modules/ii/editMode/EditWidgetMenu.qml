import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/**
 * The per-widget menu of Edit Mode: name, Pin, Size stepper, Remove. It acts on
 * the widget item the canvas resolves from the instance id, so every write goes
 * down the widget's own persisted paths (both scale paths, the per-monitor fork,
 * the history pair) and nothing here duplicates them. The card is inert once
 * the widget is gone: rows disable rather than the menu vanishing under the
 * pointer.
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
    readonly property bool lockOnly: lockBehavior === "lockOnly"
    // hide -> keep -> center -> hide; a lock-only instance has no desktop
    // to hide on, so it only alternates keep <-> center.
    function nextLockBehavior() {
        if (root.lockOnly)
            return "lockOnly";
        return root.lockBehavior === "hide" ? "keep" : root.lockBehavior === "keep" ? "center" : "hide";
    }
    readonly property string lockLabel: root.lockOnly ? Translation.tr("Lock screen only")
        : root.lockBehavior === "keep" ? Translation.tr("On lock screen: shown")
        : root.lockBehavior === "center" ? Translation.tr("On lock screen: centered")
        : Translation.tr("On lock screen: hidden")
    readonly property real scaleFactor: widget ? widget.committedScaleFactor : 1
    readonly property real scaleStep: EditModeLogic.nearestSizeStep(scaleFactor)
    readonly property bool canGrow: widget !== null && EditModeLogic.steppedScale(scaleFactor, 1) !== null
    readonly property bool canShrink: widget !== null && EditModeLogic.steppedScale(scaleFactor, -1) !== null
    readonly property int padding: 6

    implicitWidth: 236
    implicitHeight: column.implicitHeight + padding * 2
    width: implicitWidth
    height: implicitHeight

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
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
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

        EditMenuRow {
            cardPadding: root.padding
            symbol: root.pinned ? "keep_off" : "keep"
            label: root.pinned ? Translation.tr("Unpin position") : Translation.tr("Pin position")
            enabled: root.instance !== null
            onClicked: {
                Config.updateWidgetPinned(root.instanceId, !root.pinned);
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 4
            spacing: 4

            MaterialSymbol {
                text: "aspect_ratio"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3onSurface
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Size")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurface
            }
            StepButton {
                symbol: "remove"
                enabled: root.canShrink
                onClicked: root.stepSize(-1)
            }
            StyledText {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignHCenter
                text: Math.round(root.scaleStep * 100) + "%"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurface
            }
            StepButton {
                symbol: "add"
                enabled: root.canGrow
                onClicked: root.stepSize(1)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            height: 1
            color: Appearance.colors.colOutlineVariant
        }

        EditMenuRow {
            cardPadding: root.padding
            symbol: root.lockBehavior === "hide" ? "lock_open" : root.lockBehavior === "center" ? "center_focus_strong" : "lock"
            label: root.lockLabel
            enabled: root.instance !== null && !root.lockOnly
            onClicked: Config.updateWidgetLockBehavior(root.instanceId, root.nextLockBehavior())
        }

        // On the Lockscreen tab a desktop widget is hidden from the lock, not
        // removed from the desktop; a lock-only one is removed outright.
        EditMenuRow {
            cardPadding: root.padding
            symbol: "delete"
            label: GlobalStates.editLockPreview && !root.lockOnly
                ? Translation.tr("Hide on lock screen") : Translation.tr("Remove from desktop")
            enabled: root.instance !== null && !(GlobalStates.editLockPreview && root.lockBehavior === "hide")
            colText: Appearance.m3colors.m3error
            onClicked: {
                const widgetId = root.instance.widgetId;
                root.dismissRequested();
                if (GlobalStates.editLockPreview && !root.lockOnly)
                    Config.updateWidgetLockBehavior(root.instanceId, "hide");
                else
                    Config.removeWidgetFromDesktop(widgetId);
            }
        }
    }

    component StepButton: RippleButton {
        id: step
        property string symbol: ""

        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: step.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: step.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
        }
    }
}
