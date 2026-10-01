import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Performance")
    // The HUD draws its own semi-transparent card and sizes itself from the
    // toggles, so it neither fades when click-through nor resizes by hand,
    // and it may sit flush against the screen edges.
    opacity: 1
    resizable: false
    flushToEdges: true
    titleElides: true

    readonly property var cfg: Config.options.overlay.perfMonitor

    function savePosition(xPos = root.x, yPos = root.y, width = 0, height = 0) {
        root.persistentStateEntry.x = Math.round(xPos);
        root.persistentStateEntry.y = Math.round(yPos);
        root.persistentStateEntry.width = 0;
        root.persistentStateEntry.height = 0;
    }

    PerfSampler {
        id: hudSampler
        active: root.visible
    }
    // IPC `perfMonitor cycleGpu` reaches the live HUD's sampler through here.
    Component.onCompleted: {
        OverlayContext.perfSampler = hudSampler;
        blurRuleTimer.restart();
    }
    Component.onDestruction: {
        if (OverlayContext.perfSampler === hudSampler)
            OverlayContext.perfSampler = null;
        root.pushBlurRule(false);
    }

    contentItem: PerfMonitorContent {
        id: hudContent
        sampler: hudSampler
    }

    // ------------------------------------------------------------ snapping

    // A corner keeps the HUD there as its size changes; dragging it frees it.
    readonly property string corner: root.cfg.anchor ?? "none"
    readonly property bool snapped: ["topLeft", "topRight", "bottomLeft", "bottomRight"].includes(root.corner)
    readonly property real snapMargin: root.cfg.snapMargin ?? 16
    readonly property real snapX: root.corner.endsWith("Left")
        ? -root.edgeInsetLeft + root.snapMargin
        : (root.parent?.width ?? 0) - root.width + root.edgeInsetRight - root.snapMargin
    readonly property real snapY: root.corner.startsWith("top")
        ? -root.edgeInsetTop + root.snapMargin
        : (root.parent?.height ?? 0) - root.height + root.edgeInsetBottom - root.snapMargin
    externallyPositioned: root.snapped

    function snapTo(corner) {
        Config.options.overlay.perfMonitor.anchor = corner;
    }
    onDraggingChanged: {
        if (root.dragging && root.snapped)
            Config.options.overlay.perfMonitor.anchor = "none";
    }

    Binding {
        target: root
        property: "x"
        value: Math.round(root.snapX)
        when: root.snapped && !root.dragging
        // Letting go must not fall back to the old free position
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "y"
        value: Math.round(root.snapY)
        when: root.snapped && !root.dragging
        restoreMode: Binding.RestoreNone
    }
    // Remember where the corner put it, for when it is freed again
    onSnapXChanged: snapSaveTimer.restart()
    onSnapYChanged: snapSaveTimer.restart()
    Timer {
        id: snapSaveTimer
        interval: 500
        onTriggered: {
            if (root.snapped && !root.dragging)
                root.savePosition(Math.round(root.snapX), Math.round(root.snapY));
        }
    }

    titleExtraComponent: Component {
        RowLayout {
            spacing: 0

            Repeater {
                model: [
                    { "corner": "topLeft", "icon": "north_west", "name": Translation.tr("Top left") },
                    { "corner": "topRight", "icon": "north_east", "name": Translation.tr("Top right") },
                    { "corner": "bottomLeft", "icon": "south_west", "name": Translation.tr("Bottom left") },
                    { "corner": "bottomRight", "icon": "south_east", "name": Translation.tr("Bottom right") }
                ]
                delegate: RippleButton {
                    id: snapButton
                    required property var modelData
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: height / 2
                    toggled: root.corner === snapButton.modelData.corner
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    onClicked: root.snapTo(snapButton.modelData.corner)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: snapButton.modelData.icon
                        iconSize: 18
                        color: snapButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                    }
                    StyledToolTip {
                        text: Translation.tr("Snap to %1").arg(snapButton.modelData.name)
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ blur

    // Hyprland blurs every quickshell surface, and on the overlay layer it
    // skips only pixels at or under `ignore_alpha`. With blur off, the
    // threshold rises just above the HUD's own card while it is on screen,
    // so the card stays clear; it drops back when the HUD goes away.
    readonly property real cardAlpha: {
        const card = Math.max(0, Math.min(1, root.cfg.backgroundOpacity));
        const tile = Math.min(1, card * 0.9);
        return 1 - (1 - card) * (1 - tile);
    }
    readonly property bool clearCard: root.visible && !(root.cfg.blur ?? false)
    onClearCardChanged: blurRuleTimer.restart()
    onCardAlphaChanged: blurRuleTimer.restart()

    function pushBlurRule(clear) {
        const threshold = clear ? Math.min(1, root.cardAlpha + 0.02) : 0.3;
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.layer_rule({ name = 'ii:overlay:perf-hud', match = { namespace = 'quickshell:overlay' }, ignore_alpha = ${threshold.toFixed(3)} })`]);
    }

    Timer {
        id: blurRuleTimer
        interval: 150
        onTriggered: root.pushBlurRule(root.clearCard)
    }
}
