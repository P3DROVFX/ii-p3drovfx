import QtQuick
import qs.modules.common

/**
 * The lock screen live on a row of its own, in the monitor's proportions, and
 * under it the effects beside the looks (stacked on a narrow page). Pointing at a
 * look tries it on the preview.
 */
Item {
    id: root

    readonly property int gap: 12
    readonly property bool wide: root.width >= 620
    readonly property real aspect: preview.aspect
    // The whole row, unless that would make it taller than a screenful; then centred.
    readonly property int previewWidth: Math.round(Math.min(root.width, 580 * root.aspect))
    readonly property int previewHeight: Math.round(root.previewWidth / root.aspect)
    readonly property int paneWidth: root.wide ? Math.round(Math.max(300, Math.min(520, (root.width - root.gap) * 0.55))) : root.width
    readonly property int belowY: root.previewHeight + root.gap

    implicitHeight: root.wide
        ? root.belowY + pane.implicitHeight
        : root.belowY + pane.implicitHeight + root.gap + looks.implicitHeight

    LockPreview {
        id: preview
        x: Math.round((root.width - root.previewWidth) / 2)
        y: 0
        width: root.previewWidth
        height: root.previewHeight
        lookOverride: looks.hoveredPreset
    }

    LockEffectsPane {
        id: pane
        x: 0
        y: root.belowY
        width: root.paneWidth
        height: pane.implicitHeight
        presetName: looks.chosenName
        tryingName: looks.hoveredPreset ? looks.names[looks.hoveredPreset.id] : ""
    }

    // The looks keep a margin for the selection ring; their pictures line up with the pane.
    LockPresetStrip {
        id: looks
        aspect: root.aspect
        x: (root.wide ? root.paneWidth + root.gap : 0) - looks.inset
        y: (root.wide ? root.belowY : root.belowY + pane.implicitHeight + root.gap) - looks.inset
        width: (root.wide ? root.width - root.paneWidth - root.gap : root.width) + looks.inset * 2
        fillHeight: root.wide ? pane.implicitHeight + looks.inset * 2 : -1
    }
}
