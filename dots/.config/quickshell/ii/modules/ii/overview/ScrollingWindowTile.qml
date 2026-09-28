pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.overview
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

/**
 * One window of the scrolling overview: its live picture, and the app chip in
 * its bottom-left corner.
 *
 * Geometry is handed in by the row, already scaled; the tile only animates
 * towards it. Every decision about what the tile means (focused, selected,
 * dragged, a drop target) lives on the overview root, so moving the pointer
 * or the keyboard never has to agree with a copy kept here.
 */
Item {
    id: root

    required property var overview
    required property string address
    required property int workspaceId
    required property real targetX
    required property real targetY
    required property real targetWidth
    required property real targetHeight
    /** Whether the row this tile sits on is on screen; hidden rows stop capturing. */
    property bool shown: true
    /** The background's zoom is drawing this window right now (see the row). */
    property bool carried: false
    /** The chip waits for the background's captures to land before it arrives. */
    property bool chipsShown: true
    // Hidden, not faded, while carried: the capture underneath is the same picture.
    visible: !root.carried

    readonly property var windowData: HyprlandData.windowByAddress[root.address] ?? null
    readonly property var toplevel: {
        const values = ToplevelManager.toplevels.values;
        for (let i = 0; i < values.length; i++) {
            if (`0x${values[i].HyprlandToplevel?.address}` === root.address)
                return values[i];
        }
        return null;
    }
    readonly property bool floating: root.windowData?.floating ?? false
    readonly property bool focused: root.overview.focusedAddress === root.address
    readonly property bool selected: root.overview.selectedAddress === root.address
    readonly property bool dragSource: root.overview.dragging && root.overview.dragAddress === root.address
    readonly property bool dropTarget: root.overview.dragging && root.overview.dropType === "window"
        && root.overview.dropAddress === root.address && !root.dragSource
    /** Everything but the focused window sits back, until it is pointed at. */
    readonly property bool dimmed: !root.focused && !root.selected && !root.dropTarget
    readonly property bool compact: root.width < 96 || root.height < 56
    // The real window's rounding at the overview's scale: the background's
    // window captures land on this tile with exactly these corners.
    readonly property real cornerRadius: Math.min(Math.max(6, Appearance.rounding.windowRounding * root.overview.layoutScale), root.width / 4, root.height / 4)

    readonly property string appClass: root.windowData?.class ?? ""
    readonly property string appName: {
        const entry = root.appClass.length > 0 ? DesktopEntries.heuristicLookup(root.appClass) : null;
        return entry?.name || root.appClass || Translation.tr("Window");
    }
    readonly property string windowTitle: root.windowData?.title ?? ""
    readonly property string iconSource: {
        const _ = TaskbarApps.iconThemeRevision;
        return Quickshell.iconPath(AppSearch.guessIcon(root.appClass), "image-missing");
    }

    signal pressedAt(real x, real y)

    x: root.targetX
    y: root.targetY
    width: Math.max(1, root.targetWidth)
    height: Math.max(1, root.targetHeight)
    z: root.floating ? 2 : 1
    opacity: root.dragSource ? 0.35 : 1

    // No motion on the first frame: the tile would fly in from the origin.
    property bool settled: false
    Component.onCompleted: {
        Qt.callLater(() => root.settled = true);
        root.requestRecapture();
    }
    /**
     * A frozen preview is taken again whenever the tile comes back into view,
     * and never while it is hidden: the overview stays built between opens,
     * and every Hyprland refresh hands each tile a new windowData.
     */
    function requestRecapture() {
        if (root.shown && root.visible && root.overview.capturesSettled)
            recapture.restart();
    }
    Connections {
        target: root.overview
        function onCapturesSettledChanged() {
            root.requestRecapture();
        }
    }
    onShownChanged: root.requestRecapture()
    onVisibleChanged: {
        if (root.visible)
            root.requestRecapture();
        else
            recapture.stop();
    }
    onToplevelChanged: root.requestRecapture()
    onWindowDataChanged: {
        if (root.settled && !preview.live)
            root.requestRecapture();
    }
    readonly property bool animate: root.settled && !root.overview.animationsDisabled

    Behavior on x {
        enabled: root.animate
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on y {
        enabled: root.animate
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on width {
        enabled: root.animate
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on height {
        enabled: root.animate
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on opacity {
        enabled: root.animate
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    StyledRectangularShadow {
        target: surface
        radius: root.cornerRadius
        blur: root.selected ? 28 : 16
        opacity: root.selected ? 0.45 : 0.28
        offset: Qt.vector2d(0, root.selected ? 6 : 3)
    }

    Item {
        id: surface
        anchors.fill: parent
        scale: tileMouse.pressed && !root.overview.dragging ? 0.97 : 1
        Behavior on scale {
            enabled: root.animate
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        layer.enabled: true
        layer.smooth: true
        layer.effect: OverviewRoundedMask {
            cornerRadius: root.cornerRadius
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer2
        }

        // Shown until the first frame arrives, and for good with previews off.
        IconImage {
            anchors.centerIn: parent
            implicitSize: Math.round(Math.min(root.width, root.height) * 0.32)
            source: root.iconSource
            visible: !preview.hasContent
        }

        ScreencopyView {
            id: preview
            anchors.fill: parent
            captureSource: (root.toplevel && Config.options.overview.showWindowPreviews) ? root.toplevel : null
            live: root.shown && root.visible && GlobalStates.overviewOpen && root.overview.capturesSettled
                && Config.options.background.windowZoomLiveCapture
            onLiveChanged: {
                if (!live)
                    root.requestRecapture();
            }
        }

        Timer {
            id: recapture
            interval: 60
            onTriggered: {
                if (root.shown && root.visible && root.overview.capturesSettled && preview.captureSource && (!preview.live || !preview.hasContent))
                    preview.captureFrame();
            }
        }

        // Sits the unfocused windows back without letting the wallpaper through.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            opacity: root.dimmed ? 0.38 : 0
            Behavior on opacity {
                enabled: root.animate
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        // Where a dragged window would land: the two trade places.
        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.25)
            opacity: root.dropTarget ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                enabled: root.animate
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            MaterialShapeWrappedMaterialSymbol {
                anchors.centerIn: parent
                shape: MaterialShape.Shape.Cookie7Sided
                text: "swap_horiz"
                iconSize: Math.round(Math.min(Appearance.font.pixelSize.hugeass * 1.4, root.height * 0.22))
                padding: 12
                color: Appearance.colors.colSecondary
                colSymbol: Appearance.colors.colOnSecondary
            }
        }
    }

    // App chip, bottom-left: the focused window's is the primary one.
    Rectangle {
        id: chip
        readonly property real maxWidth: Math.max(0, root.width - 2 * chip.inset)
        readonly property real inset: root.compact ? 4 : 8
        readonly property bool expanded: root.selected && !root.compact && root.windowTitle.length > 0
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: chip.inset
        }
        visible: root.width > 36 && root.height > 28 && opacity > 0
        opacity: root.chipsShown ? 1 : 0
        Behavior on opacity {
            enabled: root.animate
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        height: root.compact ? 24 : 30
        width: Math.min(chip.maxWidth, chipRow.implicitWidth + (root.compact ? 8 : 20))
        radius: height / 2
        color: root.focused ? Appearance.colors.colPrimary
            : root.selected ? Appearance.colors.colSecondaryContainer
            : Appearance.colors.colSurfaceContainerHigh
        clip: true
        Behavior on width {
            enabled: root.animate
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        Behavior on color {
            enabled: root.animate
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            id: chipRow
            anchors {
                left: parent.left
                leftMargin: root.compact ? 4 : 7
                verticalCenter: parent.verticalCenter
            }
            spacing: 6

            IconImage {
                implicitSize: root.compact ? 16 : 18
                source: root.iconSource
            }
            StyledText {
                visible: !root.compact
                Layout.maximumWidth: Math.max(0, chip.maxWidth - 20 - 18 - 6)
                text: chip.expanded ? root.windowTitle : root.appName
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.focused ? Appearance.colors.colOnPrimary
                    : root.selected ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurface
            }
        }
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: root.overview.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        property point pressPoint
        property bool moved: false

        onEntered: root.overview.pointAt(root.address, root.workspaceId)
        onExited: root.overview.pointAway(root.address)
        onPressed: mouse => {
            tileMouse.pressPoint = Qt.point(mouse.x, mouse.y);
            tileMouse.moved = false;
        }
        onPositionChanged: mouse => {
            if (!tileMouse.pressed || !(tileMouse.pressedButtons & Qt.LeftButton))
                return;
            if (!tileMouse.moved) {
                const dx = mouse.x - tileMouse.pressPoint.x;
                const dy = mouse.y - tileMouse.pressPoint.y;
                if (dx * dx + dy * dy < 64)
                    return;
                tileMouse.moved = true;
                root.overview.beginDrag(root, tileMouse.pressPoint);
            }
            root.overview.moveDrag(tileMouse.mapToItem(root.overview, mouse.x, mouse.y));
        }
        onReleased: mouse => {
            if (tileMouse.moved) {
                root.overview.endDrag();
                return;
            }
        }
        onCanceled: {
            if (tileMouse.moved)
                root.overview.cancelDrag();
        }
        onClicked: mouse => {
            if (tileMouse.moved)
                return;
            if (mouse.button === Qt.MiddleButton)
                root.overview.closeWindow(root.address);
            else
                root.overview.focusWindow(root.address);
        }
    }

    DropArea {
        anchors.fill: parent
        enabled: !root.dragSource
        onEntered: root.overview.setDropTarget("window", root.workspaceId, root.address)
        onExited: root.overview.clearDropTarget("window", root.address)
    }

    StyledToolTip {
        extraVisibleCondition: false
        alternativeVisibleCondition: tileMouse.containsMouse && !root.overview.dragging && root.compact
        text: root.windowTitle
    }
}
