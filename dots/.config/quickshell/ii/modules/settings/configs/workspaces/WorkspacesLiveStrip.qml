import QtQuick
import qs.modules.common

/** A `WorkspacesStrip` fed by a `WorkspacesPreviewState`, with a style or colour of its own when asked. */
WorkspacesStrip {
    id: root

    required property WorkspacesPreviewState preview
    property string styleOverride: ""
    property string colorOverride: ""
    property int slotOverride: -1

    styleId: root.styleOverride !== "" ? root.styleOverride : root.preview.styleId
    colorMode: root.colorOverride !== "" ? root.colorOverride : root.preview.colorMode
    count: root.preview.count
    numberMap: root.preview.numberMap
    showNumbers: root.preview.showNumbers
    showIcons: root.preview.showIcons
    tintIcons: root.preview.tintIcons
    tintAmount: root.preview.tintAmount
    maskIcons: root.preview.maskIcons
    maskShape: root.preview.maskShape
    indicatorMode: root.preview.indicatorMode
    indicatorShape: root.preview.indicatorShape
    dynamic: root.preview.dynamic
    maxWindows: root.preview.maxWindows
    activeSlot: root.slotOverride >= 0 ? root.slotOverride : root.preview.activeSlot
    dockIndicator: root.preview.dockIndicator
    dockDots: root.preview.dockDots
    dockIcons: root.preview.dockIcons
    onSlotClicked: index => root.preview.jumpTo(index)
}
