import QtQuick
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "LockLook.js" as LockLook

/**
 * The looks as pictures: each preset is the lock wallpaper already wearing it.
 * Pointing at one tries it on the preview (`hoveredPreset`); clicking keeps it.
 * The chosen one wears the selection ring and a filled name pill.
 *
 * Laid out as a grid: given a `fillHeight`, it picks the columns whose cells come
 * closest to the monitor's shape and fills the height; without one, it is a single
 * row of cells at their natural height.
 */
Item {
    id: root

    /// Width over height the pictures try to keep (the monitor's).
    property real aspect: 16 / 9
    /// Height to fill; -1 lays the looks out in one row.
    property real fillHeight: -1

    readonly property int gap: 10
    // Room for the selection ring, which stands outside the picture.
    readonly property int inset: 5
    readonly property int count: LockLook.PRESETS.length
    readonly property real innerWidth: root.width - root.inset * 2
    readonly property real innerHeight: root.fillHeight - root.inset * 2

    function cellWidthFor(cols: int): real {
        return Math.floor((root.innerWidth - root.gap * (cols - 1)) / cols);
    }
    function cellHeightFor(cols: int): real {
        const rows = Math.ceil(root.count / cols);
        return Math.floor((root.innerHeight - root.gap * (rows - 1)) / rows);
    }

    readonly property int columns: {
        if (root.fillHeight <= 0)
            return root.count;
        let best = root.count;
        let bestError = Infinity;
        for (const cols of [1, 2, 3, 6]) {
            const w = root.cellWidthFor(cols);
            const h = root.cellHeightFor(cols);
            if (w <= 0 || h <= 0)
                continue;
            const error = Math.abs(Math.log((w / h) / root.aspect));
            if (error < bestError) {
                bestError = error;
                best = cols;
            }
        }
        return best;
    }
    readonly property real cellWidth: root.cellWidthFor(root.columns)
    readonly property real cellHeight: root.fillHeight > 0
        ? root.cellHeightFor(root.columns)
        : Math.round(Math.max(52, Math.min(84, root.cellWidth * 0.62)))

    /// The preset under the pointer, or null.
    property var hoveredPreset: null
    readonly property var lock: Config.options.lock
    readonly property var names: ({
        "clear": Translation.tr("Clear"),
        "soft": Translation.tr("Soft"),
        "frosted": Translation.tr("Frosted"),
        "muted": Translation.tr("Muted"),
        "tinted": Translation.tr("Tinted"),
        "noir": Translation.tr("Noir")
    })
    /// Name of the saved look when it is a preset, "" when it is custom.
    readonly property string chosenName: {
        for (const preset of LockLook.PRESETS)
            if (LockLook.matches(root.lock, preset))
                return root.names[preset.id];
        return "";
    }

    implicitHeight: root.fillHeight > 0 ? root.fillHeight : root.cellHeight + root.inset * 2

    // Leaving the looks always ends the try-on, whatever a cell last reported.
    HoverHandler {
        onHoveredChanged: if (!hovered) root.hoveredPreset = null
    }

    Grid {
        x: root.inset
        y: root.inset
        columns: root.columns
        spacing: root.gap

        Repeater {
            model: LockLook.PRESETS

            Item {
                id: cell
                required property var modelData
                readonly property bool chosen: LockLook.matches(root.lock, cell.modelData)
                readonly property real ringGap: 2
                readonly property real ringWidth: 2.5

                width: root.cellWidth
                height: root.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -(cell.ringGap + cell.ringWidth)
                    radius: Appearance.rounding.large + cell.ringGap + cell.ringWidth
                    color: "transparent"
                    border.width: cell.ringWidth
                    border.color: Appearance.colors.colPrimary
                    opacity: cell.chosen ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1

                    LockEffectLayer {
                        anchors.fill: parent
                        animated: false
                        screenScale: width / 1920
                        blurRadius: cell.modelData.blur
                        desaturation: cell.modelData.desaturate
                        colorWash: cell.modelData.colorWash
                        vignette: cell.modelData.vignette
                    }

                    RippleButton {
                        id: cellButton
                        anchors.fill: parent
                        buttonRadius: Appearance.rounding.large
                        colBackground: "transparent"
                        colBackgroundHover: Qt.rgba(1, 1, 1, 0.08)
                        colRipple: Qt.rgba(1, 1, 1, 0.2)
                        onHoveredChanged: {
                            if (cellButton.hovered)
                                root.hoveredPreset = cell.modelData;
                            // By id: a JS-array model hands out a fresh copy on every read.
                            else if (root.hoveredPreset && root.hoveredPreset.id === cell.modelData.id)
                                root.hoveredPreset = null;
                        }
                        onClicked: LockLook.apply(root.lock, cell.modelData)
                    }

                    Rectangle {
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            bottom: parent.bottom
                            bottomMargin: 8
                        }
                        width: Math.min(parent.width - 12, nameRow.implicitWidth + 16)
                        height: 24
                        radius: height / 2
                        color: cell.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        Row {
                            id: nameRow
                            anchors.centerIn: parent
                            spacing: 2

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: cell.chosen && root.cellWidth >= 96
                                text: "check"
                                iconSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, root.cellWidth - 26)
                                text: root.names[cell.modelData.id]
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: cell.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
