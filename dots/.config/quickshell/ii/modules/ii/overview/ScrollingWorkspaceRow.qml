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
 * One workspace of the scrolling overview: its label chip in the left gutter,
 * and the strip its columns scroll along.
 *
 * The strip keeps the monitor's own viewport as a frame in its middle and lays
 * every window where Hyprland really has it, so columns that are off screen
 * are off the frame here too. The strip pans sideways on its own (Shift+wheel,
 * a horizontal swipe, or the keyboard selection walking off the frame); that
 * pan is a view of the row, never a change to the workspace.
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

    // ── Entrance and exit, played by the overview ──────────────────────────
    /** 0 = gone (faded, a little lower), 1 = in place. */
    property real reveal: 0
    opacity: root.reveal
    transform: Translate {
        y: (1 - root.reveal) * 28
    }

    SequentialAnimation {
        id: revealAnimation
        PauseAnimation {
            id: revealPause
        }
        NumberAnimation {
            id: revealNumber
            target: root
            property: "reveal"
        }
    }

    /**
     * Arrivals decelerate in, later the further the row is from the active
     * one, so the list unfolds from the middle; departures are quick and all
     * at once, so nothing lingers over whatever is taking the screen.
     */
    function playReveal(show, delay) {
        revealAnimation.stop();
        if (root.overview.animationsDisabled) {
            root.reveal = show ? 1 : 0;
            return;
        }
        const motion = show ? Appearance.animation.elementMoveEnter : Appearance.animation.elementMoveExit;
        revealPause.duration = show ? delay : 0;
        revealNumber.from = root.reveal;
        revealNumber.to = show ? 1 : 0;
        revealNumber.duration = show ? motion.duration : Math.round(motion.duration * 0.6);
        revealNumber.easing.type = motion.type;
        revealNumber.easing.bezierCurve = motion.bezierCurve;
        revealAnimation.start();
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
    /** The chip's column on the left; content panned right stops beside it. */
    readonly property real chipInset: 16
    readonly property real leftPadding: root.chipInset + chip.width + 20
    readonly property real rightPadding: 56
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

    // ── Workspace chip ──────────────────────────────────────────────────────
    Rectangle {
        id: chip
        readonly property bool hovered: chipMouse.containsMouse
        anchors.verticalCenter: parent.verticalCenter
        // Hugs the row's leftmost window, and stays on screen when the row runs past the edge.
        x: Math.max(root.chipInset, root.frameRestX + root.pan + root.contentLeft - width - 20)
        z: 2
        width: 60
        height: chipColumn.implicitHeight + 28
        radius: Math.min(Appearance.rounding.large, width / 2)
        color: root.active ? Appearance.colors.colPrimary
            : (root.dropTarget || root.holdsSelection) ? Appearance.colors.colSecondaryContainer
            : chip.hovered ? Appearance.colors.colSurfaceContainerHighestHover
            : Appearance.colors.colSurfaceContainerHigh
        scale: chipMouse.pressed ? 0.95 : 1
        Behavior on color {
            enabled: !root.overview.animationsDisabled
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on scale {
            enabled: !root.overview.animationsDisabled
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        readonly property color contentColor: root.active ? Appearance.colors.colOnPrimary
            : (root.dropTarget || root.holdsSelection) ? Appearance.colors.colOnSecondaryContainer
            : Appearance.colors.colOnSurface

        ColumnLayout {
            id: chipColumn
            anchors.centerIn: parent
            spacing: 2

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: String(root.workspaceId - root.overview.workspaceOffset)
                color: chip.contentColor
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.hugeass + 8
                font.variableAxes: ({ "wght": root.active ? 760 : 600, "wdth": 60, "ROND": 100 })
            }
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                visible: root.empty
                text: "add"
                iconSize: Appearance.font.pixelSize.normal
                color: chip.contentColor
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: !root.empty
                text: String(root.addresses.length)
                color: chip.contentColor
                opacity: 0.8
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.overview.focusWorkspace(root.workspaceId)
        }

        DropArea {
            anchors.fill: parent
            onEntered: root.overview.setDropTarget("workspace", root.workspaceId, "")
            onExited: root.overview.clearDropTarget("workspace", "")
        }

        StyledToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: chip.hovered && !root.overview.dragging
            text: root.empty ? Translation.tr("New workspace")
                : (root.addresses.length === 1 ? Translation.tr("Workspace %1 · 1 window").arg(String(root.workspaceId - root.overview.workspaceOffset))
                    : Translation.tr("Workspace %1 · %2 windows").arg(String(root.workspaceId - root.overview.workspaceOffset)).arg(String(root.addresses.length)))
        }
    }

    // ── Strip ───────────────────────────────────────────────────────────────
    Item {
        id: strip
        width: parent.width
        height: parent.height
        clip: true

        // The strip's ends fade rather than cut, but only when something runs past them.
        layer.enabled: root.overflowing && root.shown
        layer.effect: EdgeFadeMask {
            readonly property real edge: Math.min(0.45, 56 / Math.max(1, strip.width))
            verticalAxis: false
            startClear: 0
            startSolid: edge
            endSolid: 1 - edge
            endClear: 1
        }

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

                Rectangle {
                    anchors.fill: parent
                    radius: root.overview.frameRadius
                    color: Appearance.colors.colLayer1
                    visible: wallpaper.status !== Image.Ready
                }
                Image {
                    id: wallpaper
                    anchors.fill: parent
                    visible: false
                    source: root.overview.wallpaperSource
                    fillMode: Image.PreserveAspectCrop
                    // Fixed, never derived from the frame: any change in it decodes and
                    // rescales the whole wallpaper again, on every row, as it opens.
                    sourceSize: root.overview.wallpaperDecodeSize
                    asynchronous: true
                    cache: true
                    retainWhileLoading: true
                }
                OverviewRoundedMask {
                    anchors.fill: parent
                    source: wallpaper
                    cornerRadius: root.overview.frameRadius
                    visible: wallpaper.status === Image.Ready
                }
                // Other workspaces sit a step back; the active one matches the zoom exactly.
                Rectangle {
                    anchors.fill: parent
                    radius: root.overview.frameRadius
                    color: root.dropTarget || root.selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer0
                    opacity: root.dropTarget ? 0.7 : root.selected ? 0.5 : root.active ? 0 : 0.3
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
                    visible: root.empty
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
                    chipsShown: !carried
                    targetX: rect.x
                    targetY: rect.y
                    targetWidth: rect.width
                    targetHeight: rect.height
                }
            }
        }
    }
}
