pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.overview
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell

/**
 * One workspace of the scrolling overview, drawn the way the scrolloverview
 * plugin draws it: no card, just the workspace's windows over the real
 * wallpaper, each where Hyprland really has it (scaled) - so columns that are
 * off screen sit beside the visible ones, unclipped, the tape end to end.
 *
 * The row pans sideways on its own (Shift+wheel, a horizontal swipe, or the
 * keyboard selection walking off the screen); that pan is a view of the row,
 * never a change to the workspace.
 */
Item {
    id: root

    required property var overview
    required property int workspaceId
    required property var addresses
    /** Position in the list of rows; animated so rows slide when one appears or goes. */
    required property int slot
    property bool shown: true

    readonly property bool active: root.overview.activeWorkspaceId === root.workspaceId
    readonly property bool carriedByBackground: root.active && root.overview.backgroundCarriesActiveRow
    readonly property bool empty: root.addresses.length === 0
    readonly property bool dropTarget: root.overview.dragging && root.overview.dropType === "workspace"
        && root.overview.dropWorkspace === root.workspaceId
    /** The row itself is picked (an empty workspace), or one of its windows is. */
    readonly property bool selected: root.overview.selectedAddress === "" && root.overview.selectedWorkspace === root.workspaceId
    readonly property bool holdsSelection: root.overview.selectedWorkspace === root.workspaceId

    readonly property real frameWidth: root.overview.frameWidth
    readonly property real frameHeight: root.overview.frameHeight

    height: root.frameHeight

    // ── Entrance and exit ───────────────────────────────────────────────
    /** 0 = gone (faded, a little lower), 1 = in place; bound by the overview to its zoom. */
    property real reveal: 1
    opacity: root.reveal
    transform: Translate {
        y: (1 - root.reveal) * 28
    }

    readonly property rect frameRect: Qt.rect(root.x + root.frameRestX + root.pan, root.y, root.frameWidth, root.frameHeight)
    onFrameRectChanged: {
        if (root.active)
            root.overview.publishTarget(root.frameRect);
    }
    onActiveChanged: {
        if (root.active)
            root.overview.publishTarget(root.frameRect);
    }
    Component.onCompleted: {
        if (root.active)
            root.overview.publishTarget(root.frameRect);
    }

    /** Every tile has a frame to show, so the real windows can be hidden under them. */
    function tilesReady() {
        for (let i = 0; i < tileRepeater.count; i++) {
            const tile = tileRepeater.itemAt(i);
            if (tile && !tile.ready)
                return false;
        }
        return true;
    }

    // ── Horizontal pan ──────────────────────────────────────────────────────
    readonly property real stripWidth: strip.width
    readonly property real frameRestX: (root.stripWidth - root.frameWidth) / 2
    /** How far the windows reach past the frame on either side, scaled. */
    readonly property real contentLeft: {
        let left = 0;
        for (let i = 0; i < root.addresses.length; i++)
            left = Math.min(left, root.overview.tileRect(root.addresses[i]).x);
        return left;
    }
    readonly property real contentRight: {
        let right = root.frameWidth;
        for (let i = 0; i < root.addresses.length; i++) {
            const r = root.overview.tileRect(root.addresses[i]);
            right = Math.max(right, r.x + r.width);
        }
        return right;
    }
    /** How close panned content may come to the screen's edges. */
    readonly property real leftPadding: 48
    readonly property real rightPadding: 48
    readonly property real panMax: Math.max(0, -(root.frameRestX + root.contentLeft) + root.leftPadding)
    readonly property real panMin: Math.min(0, root.stripWidth - root.rightPadding - (root.frameRestX + root.contentRight))
    readonly property bool overflowing: root.panMax > 0.5 || root.panMin < -0.5

    property real pan: 0
    property bool panImmediate: false
    onPanMaxChanged: root.pan = root.clampPan(root.pan)
    onPanMinChanged: root.pan = root.clampPan(root.pan)

    Behavior on pan {
        enabled: !root.panImmediate && !root.overview.animationsDisabled
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    function clampPan(value) {
        return Math.max(root.panMin, Math.min(root.panMax, value));
    }

    function panBy(delta, immediate) {
        root.panImmediate = immediate;
        root.pan = root.clampPan(root.pan + delta);
        root.panImmediate = false;
    }

    /** Brings a tile (frame coordinates) fully inside the strip. */
    function reveal(rect) {
        const left = root.frameRestX + root.pan + rect.x;
        const right = left + rect.width;
        if (left < root.leftPadding)
            root.pan = root.clampPan(root.pan + (root.leftPadding - left));
        else if (right > root.stripWidth - root.rightPadding)
            root.pan = root.clampPan(root.pan - (right - (root.stripWidth - root.rightPadding)));
    }

    // ── Strip ───────────────────────────────────────────────────────────────
    Item {
        id: strip
        width: parent.width
        height: parent.height
        // Not clipped: like the plugin, the tape runs past the card to the screen's edges.

        DropArea {
            anchors.fill: parent
            onEntered: root.overview.setDropTarget("workspace", root.workspaceId, "")
            onExited: root.overview.clearDropTarget("workspace", "")
        }

        Item {
            id: canvas
            x: root.frameRestX + root.pan
            width: root.frameWidth
            height: root.frameHeight

            // The monitor: its wallpaper, exactly where the background's zoom lands.
            // No layer: the rounded mask samples the wallpaper's own texture, so a
            // row costs no offscreen buffer of its own.
            Item {
                id: frame
                anchors.fill: parent
                // While the zoom carries this row, the plane is its wallpaper. No fade:
                // the two are identical and hand over in one frame.
                visible: !root.carriedByBackground

                // No card: as in the scrolloverview plugin, the windows float over the
                // real wallpaper, which never moves. Only an empty workspace gets a
                // faint outline, so there is something to drop a window on.
                Rectangle {
                    anchors.fill: parent
                    radius: root.overview.frameRadius
                    // The plugin shows nothing there; only while a window is being dragged.
                    visible: root.empty && root.overview.dragging
                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
                    border.width: 1
                    border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.75)
                }
                // Every card shows its wallpaper as is, as in the plugin; only a drop
                // target or a keyboard-picked empty workspace is tinted.
                Rectangle {
                    anchors.fill: parent
                    radius: root.overview.frameRadius
                    color: Appearance.colors.colSecondaryContainer
                    opacity: root.dropTarget ? 0.7 : root.selected ? 0.5 : 0
                    Behavior on opacity {
                        enabled: !root.overview.animationsDisabled
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.empty
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.overview.focusWorkspace(root.workspaceId)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.empty && root.overview.dragging
                    spacing: 8

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        shape: MaterialShape.Shape.Cookie9Sided
                        text: root.dropTarget ? "move_down" : "add"
                        iconSize: Appearance.font.pixelSize.hugeass
                        padding: 12
                        color: root.dropTarget ? Appearance.colors.colSecondary : Appearance.colors.colSecondaryContainer
                        colSymbol: root.dropTarget ? Appearance.colors.colOnSecondary : Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.dropTarget ? Translation.tr("Move here") : Translation.tr("New workspace")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                    }
                }
            }

            Repeater {
                id: tileRepeater
                model: ScriptModel {
                    values: root.addresses
                }
                delegate: ScrollingWindowTile {
                    required property string modelData
                    readonly property rect rect: root.overview.tileRect(modelData)
                    overview: root.overview
                    address: modelData
                    workspaceId: root.workspaceId
                    shown: root.shown
                    // Only what the zoom's captures show waits for them: the monitor's own
                    // area. Columns scrolled off it are not captured, so they arrive and
                    // leave with the row instead of popping in when the zoom lands.
                    readonly property bool insideMonitor: rect.x < root.frameWidth && rect.x + rect.width > 0
                        && rect.y < root.frameHeight && rect.y + rect.height > 0
                    carried: root.carriedByBackground && insideMonitor
                    // The app chip only on the window being pointed at or picked.
                    chipsShown: !carried && root.overview.selectedAddress === modelData
                    targetX: rect.x
                    targetY: rect.y
                    targetWidth: rect.width
                    targetHeight: rect.height
                }
            }
        }
    }
}
