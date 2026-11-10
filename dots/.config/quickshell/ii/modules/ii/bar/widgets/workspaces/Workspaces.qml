import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property bool vertical: false

    BarWidgetPalette {
        id: widgetPalette
        colorMode: Config.options.bar.workspaces.colorMode
    }

    WorkspaceBarModel {
        id: wsModel
        screen: root.QsWindow.window?.screen ?? null
        trackWindows: root.showIcons
        includeFloating: false
        windowLimit: Config.options.bar.workspaces.maxWindowCount
    }

    readonly property bool scratchpadOpen: wsModel.scratchpadOpen
    property real blur: root.scratchpadOpen ? 1 : 0

    // ── Slots ─────────────────────────────────────────────────────────────
    // A fixed row of slots, paged around the active workspace. Dynamic mode
    // keeps the row and hides the empty slots; with a workspace map it grows
    // the row to the whole of this monitor's range instead of paging.
    readonly property int slotCount: wsModel.useMap && wsModel.dynamic && wsModel.rangeEnd >= 0
        ? wsModel.rangeEnd - wsModel.offset
        : wsModel.shown
    readonly property int firstSlotId: wsModel.pageStart(root.slotCount)
    readonly property int activeSlot: {
        const slot = wsModel.activeId - root.firstSlotId;
        return slot >= 0 && slot < root.slotCount ? slot : -1;
    }

    function idAt(slot) {
        return root.firstSlotId + slot;
    }

    function isOccupied(slot) {
        return wsModel.occupied[root.idAt(slot)] === true;
    }

    function isSlotVisible(slot) {
        return !wsModel.dynamic || slot === root.activeSlot || root.isOccupied(slot);
    }

    // Position of the active slot among the visible ones.
    readonly property int visibleActiveIndex: {
        let count = 0;
        for (let i = 0; i < root.slotCount; i++) {
            if (i === root.activeSlot)
                return count;
            if (root.isSlotVisible(i))
                count++;
        }
        return count;
    }

    function slotItem(slot) {
        void workspaceRepeater.count;
        return workspaceRepeater.itemAt(slot);
    }

    // Length of a slot along the bar; hidden slots take none.
    function slotLength(slot) {
        const item = root.slotItem(slot);
        if (!item || !item.visible)
            return 0;
        return root.vertical ? item.height : item.width;
    }

    // How much the visible slots before `slot` are longer than a bare slot.
    function extraBefore(slot) {
        let extra = 0;
        for (let i = 0; i < slot; i++) {
            const length = root.slotLength(i);
            if (length > 0)
                extra += length - root.iconBoxWrapperSize;
        }
        return extra;
    }

    readonly property var noWindows: []

    // ── Sizing ────────────────────────────────────────────────────────────
    // Every measurement in this widget derives from these two, so scaling them scales the
    // pills, the active indicator and the window dots together. They were drawn for the
    // 40px bar and stayed that size on a taller one, which is what left the workspace row
    // looking like a strip of desktop pills floating in a touch-sized bar.
    readonly property real contentScale: root.vertical
        ? Appearance.sizes.verticalBarContentScale
        : Appearance.sizes.barContentScale

    property int individualIconBoxHeight: Math.round(22 * root.contentScale)
    property int iconBoxWrapperSize: Math.round(26 * root.contentScale)
    property int workspaceDotSize: 4
    property real iconRatio: 0.8
    property bool showIcons: Config.options.bar.workspaces.showAppIcons

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : contentLayout.implicitWidth
    implicitHeight: root.vertical ? contentLayout.implicitHeight : Appearance.sizes.baseBarHeight

    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on blur {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // ── Direction arrow ───────────────────────────────────────────────────
    // The active indicator turns into a triangle aimed the way you just moved,
    // holds for a beat, then settles back into a circle. `ShapeCanvas` morphs
    // between polygons on its own whenever `roundedPolygon` changes, so the
    // whole effect is two assignments to `shapeString` — there is no tween to
    // write here, and writing one would fight the built-in morph.
    readonly property bool directionArrowEnabled: Config.options.bar.workspaces.useDirectionArrowForActiveIndicator
    // Both modes need a square indicator: a triangle (or a cookie) stretched
    // across a multi-workspace pill would be sheared rather than rotated.
    readonly property bool squareActiveIndicator: root.directionArrowEnabled || wsModel.useRandomShape

    // `ShapeCanvas`' own morph runs on the M3 expressive fast-spatial bezier,
    // whose third control point is 1.67 — it overshoots by construction. That
    // is right for a shape *arriving* somewhere, and wrong for a polygon morph:
    // `progress` passes 1 and the interpolation extrapolates past the triangle,
    // so the arrow over-sharpens and settles back. Reads as a flick rather than
    // a turn. The arrow gets a curve with no overshoot instead, and long enough
    // that the triangle is a shape you see rather than a frame you catch.
    readonly property int arrowMorphDuration: Math.round(420 * Appearance.animMultiplier)
    // Time the triangle stands still after the morph finishes. Without it the
    // return starts the instant the arrow is fully formed and the whole gesture
    // reads as a wobble.
    readonly property int arrowRestDuration: Math.round(260 * Appearance.animMultiplier)

    property int previousActiveId: -1
    property bool arrowShown: false
    // Material's Triangle points up, so up is 0 and the rest follow clockwise.
    // On a vertical bar the workspaces run top to bottom, so the same "moved
    // forward" gesture points down instead of right.
    property real arrowRotation: 0

    // Seeded, not left at -1: the first switch after startup should draw an
    // arrow like any other, and `showDirectionArrow` refuses a negative
    // previous id precisely so a cold start does not.
    Component.onCompleted: root.previousActiveId = wsModel.activeId

    Timer {
        id: arrowHoldTimer
        // The morph in, and then the rest. Measured from the switch, so the
        // triangle is fully formed for its whole rest.
        interval: root.arrowMorphDuration + root.arrowRestDuration
        onTriggered: root.arrowShown = false
    }

    function showDirectionArrow(previousId, nextId) {
        if (!root.directionArrowEnabled || previousId < 0 || previousId === nextId)
            return;
        const forward = nextId > previousId;
        if (root.vertical)
            root.arrowRotation = forward ? 180 : 0;
        else
            root.arrowRotation = forward ? 90 : 270;
        root.arrowShown = true;
        arrowHoldTimer.restart();
    }

    Connections {
        target: wsModel

        // The change handler is the only place that still knows both ends of
        // the move: `activeId` is a binding and carries no history of its own.
        function onActiveIdChanged() {
            root.showDirectionArrow(root.previousActiveId, wsModel.activeId);
            root.previousActiveId = wsModel.activeId;
        }
    }

    // ── Content ───────────────────────────────────────────────────────────
    Item {
        id: contentContainer
        anchors.fill: parent
        opacity: root.scratchpadOpen ? 0.65 : 1
        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: root.blur
        }

        // Active workspace indicator
        Loader {
            id: activeIndicator
            z: 2
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter

            readonly property real baseSize: root.iconBoxWrapperSize
            readonly property int windowCount: root.activeSlot < 0
                ? 0
                : (wsModel.windowCounts[wsModel.activeId] ?? 0)

            readonly property real visualInset: {
                if (!root.showIcons)
                    return baseSize * 0.07 - 0.5;
                if (windowCount === 0)
                    return baseSize * 0.07;
                if (windowCount === 1)
                    return baseSize * 0.14;
                return baseSize * 0.1;
            }

            AnimatedTabIndexPair {
                id: idxPair
                index: Math.max(0, root.visibleActiveIndex)
                easingType: Easing.OutBack
                easingOvershoot: 1.7
                idx1Duration: 250
                idx2Duration: 350
            }

            readonly property real pairMin: Math.min(idxPair.idx1, idxPair.idx2)
            readonly property real pairAbs: Math.abs(idxPair.idx1 - idxPair.idx2)

            // How much longer the active slot is than a bare one (its icons).
            readonly property real activeExtra: root.activeSlot < 0
                ? 0
                : Math.max(0, root.slotLength(root.activeSlot) - baseSize)

            readonly property real indicatorPosition: pairMin * baseSize
                + root.extraBefore(root.activeSlot) + visualInset
            readonly property real indicatorLength: (pairAbs + 1) * baseSize + activeExtra - visualInset * 2
            readonly property real squareOffset: (indicatorLength - root.individualIconBoxHeight) / 2
            readonly property real mainPosition: root.squareActiveIndicator
                ? indicatorPosition + squareOffset
                : indicatorPosition
            readonly property real mainLength: root.squareActiveIndicator
                ? root.individualIconBoxHeight
                : indicatorLength

            x: root.vertical ? 0 : mainPosition
            y: root.vertical ? mainPosition : 0
            width: root.vertical ? root.individualIconBoxHeight : mainLength
            height: root.vertical ? mainLength : root.individualIconBoxHeight

            opacity: root.scratchpadOpen || root.activeSlot < 0 ? 0 : 1
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            sourceComponent: Config.options.bar.workspaces.useMaterialShapeForActiveIndicator
                || root.squareActiveIndicator ? materialShapeComponent : rectangleComponent

            Component {
                id: rectangleComponent
                Rectangle {
                    radius: Appearance.rounding.full
                    color: widgetPalette.colBackground
                    opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            Component {
                id: materialShapeComponent
                MaterialShape {
                    anchors.fill: parent
                    transformOrigin: Item.Center
                    shapeString: {
                        // The arrow outranks the random shape: a triangle that only
                        // sometimes points the right way is worse than no arrow.
                        if (root.directionArrowEnabled)
                            return root.arrowShown ? "Triangle" : "Circle";
                        if (wsModel.useRandomShape)
                            return wsModel.randomShape;
                        return Config.options.bar.workspaces.activeIndicatorShape;
                    }
                    color: widgetPalette.colBackground
                    opacity: Config.options.bar.workspaces.activeIndicatorOpacity / 100

                    // Replaces the one ShapeCanvas ships with. Only the arrow wants
                    // a settling curve; the random shape is a shape *landing*, and
                    // the overshoot is what gives that its snap.
                    animation: NumberAnimation {
                        duration: root.directionArrowEnabled
                            ? root.arrowMorphDuration
                            : Math.round(350 * Appearance.animMultiplier)
                        easing.type: root.directionArrowEnabled ? Easing.InOutCubic : Easing.BezierSpline
                        easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1]
                    }

                    rotation: {
                        if (root.directionArrowEnabled)
                            return root.arrowRotation;
                        return wsModel.useRandomShape ? wsModel.randomRotation : 0;
                    }
                    Behavior on rotation {
                        // Off in arrow mode on purpose. The triangle has to be
                        // aimed before it appears; animating the angle would spin
                        // it into place — and `Clockwise` would take the long way
                        // round on a backwards switch, pointing every wrong
                        // direction on the way there.
                        enabled: !root.directionArrowEnabled
                        RotationAnimation {
                            duration: 350
                            direction: RotationAnimation.Clockwise
                            easing.type: Easing.OutBack
                        }
                    }
                }
            }
        }

        Rectangle {
            id: hoverIndicator
            z: 2
            anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter

            readonly property int hoverSlot: interactionMouseArea.hoverSlot
            readonly property Item hoverItem: hoverSlot >= 0 ? root.slotItem(hoverSlot) : null
            readonly property real margin: root.iconBoxWrapperSize * 0.05

            property real indicatorPosition: {
                if (!hoverItem)
                    return 0;
                return (root.vertical ? contentLayout.y + hoverItem.y : contentLayout.x + hoverItem.x) + margin;
            }
            property real indicatorLength: root.slotLength(hoverSlot) - margin * 2

            color: "transparent"
            radius: Appearance.rounding.full
            visible: interactionMouseArea.containsMouse && hoverItem !== null

            x: root.vertical ? 0 : indicatorPosition
            y: root.vertical ? indicatorPosition : 0
            implicitWidth: root.vertical ? root.individualIconBoxHeight : indicatorLength
            implicitHeight: root.vertical ? indicatorLength : root.individualIconBoxHeight

            // Jump to the first slot hovered, then glide between slots. NOTE: still no unhover animation.
            onVisibleChanged: {
                if (!visible)
                    return;
                positionBehavior.enabled = false;
                lengthBehavior.enabled = false;
                Qt.callLater(() => {
                    positionBehavior.enabled = true;
                    lengthBehavior.enabled = true;
                });
            }

            Behavior on indicatorPosition {
                id: positionBehavior
                animation: Appearance.animation.elementMove.numberAnimation.createObject(hoverIndicator)
            }
            Behavior on indicatorLength {
                id: lengthBehavior
                animation: Appearance.animation.elementMove.numberAnimation.createObject(hoverIndicator)
            }

            HoverOverlay {
                hover: interactionMouseArea.containsMouse
            }
        }

        MouseArea {
            id: interactionMouseArea
            z: 4
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            acceptedButtons: Qt.RightButton | Qt.LeftButton | Qt.BackButton

            // The visible slot under the pointer, or the last one past the end.
            readonly property int hoverSlot: {
                const position = root.vertical ? mouseY - contentLayout.y : mouseX - contentLayout.x;
                let last = -1;
                for (let i = 0; i < root.slotCount; i++) {
                    const item = root.slotItem(i);
                    if (!item || !item.visible)
                        continue;
                    last = i;
                    const end = root.vertical ? item.y + item.height : item.x + item.width;
                    if (position < end)
                        return i;
                }
                return last;
            }

            onPressed: event => {
                if (event.button === Qt.RightButton)
                    GlobalStates.toggleOverview();
                else if (event.button === Qt.BackButton)
                    wsModel.toggleScratchpad();
                else if (event.button === Qt.LeftButton && hoverSlot >= 0)
                    wsModel.focus(root.idAt(hoverSlot));
            }

            onWheel: event => {
                event.accepted = true;
                wsModel.scroll(event.angleDelta.y);
            }
        }

        // Occupied workspaces: one pill per run of neighbours, drawn as a mask
        // so touching pills melt into each other.
        StyledRectangle {
            id: occupiedIndicatorsBg
            anchors.fill: occupiedIndicatorsLayout
            contentLayer: StyledRectangle.ContentLayer.Group
            color: ColorUtils.transparentize(widgetPalette.colContainer, 0.4)
            visible: false
        }

        GridLayout {
            id: occupiedIndicatorsLayout
            anchors.centerIn: parent
            columnSpacing: 0
            rowSpacing: 0
            z: 1

            columns: root.vertical ? 1 : 99
            rows: root.vertical ? 99 : 1

            layer.enabled: true
            visible: false

            Repeater {
                model: root.slotCount
                delegate: Item {
                    id: wsBg
                    Layout.alignment: Qt.AlignCenter

                    readonly property int wsId: root.idAt(index)
                    readonly property bool wsVisible: root.isSlotVisible(index)
                    // The active workspace carries its own indicator, so it breaks the run.
                    function occupiedAt(slot) {
                        return slot >= 0 && slot < root.slotCount && root.isOccupied(slot) && slot !== root.activeSlot;
                    }
                    readonly property bool currentOccupied: occupiedAt(index)
                    readonly property bool previousOccupied: occupiedAt(index - 1)
                    readonly property bool nextOccupied: occupiedAt(index + 1)

                    readonly property real itemSize: {
                        const item = root.slotItem(index);
                        if (!item)
                            return root.iconBoxWrapperSize;
                        return root.vertical ? item.height : item.width;
                    }

                    implicitWidth: root.vertical ? root.iconBoxWrapperSize : (wsVisible ? itemSize : 0)
                    implicitHeight: root.vertical ? (wsVisible ? itemSize : 0) : root.iconBoxWrapperSize

                    Pill {
                        // Not scaled: it would stretch multi-window workspaces far too much.
                        readonly property real stretchAmount: 12

                        property real undirectionalWidth: wsBg.currentOccupied ? root.iconBoxWrapperSize : 0
                        property real undirectionalLength: {
                            if (!wsBg.currentOccupied)
                                return 0;
                            return wsBg.itemSize
                                + (wsBg.previousOccupied ? stretchAmount : 0)
                                + (wsBg.nextOccupied ? stretchAmount : 0);
                        }
                        property real undirectionalOffset: {
                            if (!wsBg.currentOccupied)
                                return 0.5 * root.iconBoxWrapperSize;
                            return wsBg.previousOccupied ? -stretchAmount : 0;
                        }

                        anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                        x: root.vertical ? 0 : undirectionalOffset
                        y: root.vertical ? undirectionalOffset : 0
                        implicitWidth: root.vertical ? undirectionalWidth : undirectionalLength
                        implicitHeight: root.vertical ? undirectionalLength : undirectionalWidth

                        Behavior on undirectionalWidth {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        Behavior on undirectionalLength {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        Behavior on undirectionalOffset {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        MultiEffect {
            z: 1
            anchors.centerIn: parent
            implicitWidth: occupiedIndicatorsLayout.implicitWidth
            implicitHeight: occupiedIndicatorsLayout.implicitHeight
            source: occupiedIndicatorsBg
            maskEnabled: true
            maskSource: occupiedIndicatorsLayout
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        GridLayout {
            id: contentLayout
            anchors.centerIn: parent
            columnSpacing: 0
            rowSpacing: 0
            z: 3

            columns: root.vertical ? 1 : 99
            rows: root.vertical ? 99 : 1

            Repeater {
                id: workspaceRepeater
                model: root.slotCount

                delegate: Item {
                    id: background
                    Layout.alignment: Qt.AlignCenter

                    readonly property int wsId: root.idAt(index)
                    readonly property bool isShowingScratchpad: root.scratchpadOpen && index === root.activeSlot

                    visible: root.isSlotVisible(index)
                    implicitWidth: root.vertical
                        ? root.iconBoxWrapperSize
                        : Math.max(layout.implicitWidth + 8, root.iconBoxWrapperSize)
                    implicitHeight: root.vertical
                        ? Math.max(layout.implicitHeight + 8, root.iconBoxWrapperSize)
                        : root.iconBoxWrapperSize

                    Behavior on implicitWidth {
                        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
                    }

                    Item {
                        anchors.fill: parent
                        opacity: background.isShowingScratchpad ? 0 : 1
                        scale: background.isShowingScratchpad ? 0.8 : 1

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on scale {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        WorkspaceBackgroundIndicator {
                            workspaceValue: background.wsId
                            isActive: index === root.activeSlot
                            isOccupied: root.isOccupied(index)
                            // A dot only where no icon sits over it.
                            visible: layout.implicitHeight + 8 < root.iconBoxWrapperSize
                                || Config.options.bar.workspaces.alwaysShowNumbers
                                || wsModel.numbersByInteraction
                        }

                        GridLayout {
                            id: layout
                            anchors.centerIn: parent
                            columnSpacing: 0
                            rowSpacing: 0
                            columns: root.vertical ? 1 : 99
                            rows: root.vertical ? 99 : 1

                            Repeater {
                                model: root.showIcons ? (wsModel.windows[background.wsId] ?? root.noWindows) : root.noWindows
                                delegate: WindowIcon {}
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: scratchpadPositionHelper
            readonly property real indicatorSize: root.individualIconBoxHeight + 2
            readonly property Item activeItem: root.activeSlot >= 0 ? root.slotItem(root.activeSlot) : null

            x: {
                if (!activeItem)
                    return 0;
                if (root.vertical)
                    return contentLayout.x + (contentLayout.width - indicatorSize) / 2;
                return contentLayout.x + activeItem.x + (activeItem.width - indicatorSize) / 2;
            }
            y: {
                if (!activeItem)
                    return 0;
                if (root.vertical)
                    return contentLayout.y + activeItem.y + (activeItem.height - indicatorSize) / 2;
                return contentLayout.y + (contentLayout.height - indicatorSize) / 2;
            }
            width: indicatorSize
            height: indicatorSize
            visible: false
        }
    }

    // Kept outside the blurred content so it stays sharp.
    Item {
        id: scratchpadOverlay
        z: 10

        readonly property bool shown: root.scratchpadOpen && root.activeSlot >= 0

        x: scratchpadPositionHelper.x
        y: scratchpadPositionHelper.y
        width: scratchpadPositionHelper.width
        height: scratchpadPositionHelper.height

        visible: shown
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.7

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialShape {
            anchors.fill: parent
            shapeString: "Flower"
            color: widgetPalette.colAccent
        }

        Rectangle {
            anchors.centerIn: parent
            width: 4
            height: 4
            radius: 2
            color: widgetPalette.colOnAccent

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.scratchpadOpen
                NumberAnimation {
                    to: 0.3
                    duration: 1500
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    to: 1.0
                    duration: 1500
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    component WindowIcon: Item {
        id: iconContainer
        required property var modelData

        readonly property bool enableShapeMask: Config.options.appearance.icons.enableShapeMask
        readonly property real baseIconSize: root.individualIconBoxHeight * root.iconRatio

        Layout.alignment: Qt.AlignHCenter
        width: root.individualIconBoxHeight
        height: root.individualIconBoxHeight

        layer.enabled: enableShapeMask
        layer.effect: OpacityMask {
            maskSource: iconMask
        }

        MaterialShape {
            id: iconMask
            anchors.fill: parent
            shapeString: Config.options.appearance.icons.shapeMask
            visible: false
        }

        IconImage {
            id: mainAppIcon
            anchors {
                left: parent.left
                top: parent.top
                leftMargin: wsModel.numbersByInteraction ? 15 : 2
                topMargin: wsModel.numbersByInteraction ? 15 : 2
            }
            source: iconContainer.modelData.icon
            implicitSize: iconContainer.baseIconSize * (wsModel.numbersByInteraction ? 1 / 1.5 : 1)

            // Force reload when the icon theme regenerates; decode at the stable
            // base size so hover animations don't re-decode every frame. Resolved
            // on this thread: the shared icon loader is not safe to read from Qt's
            // image thread while the theme is changing under it.
            asynchronous: false
            backer.cache: false
            backer.sourceSize: Qt.size(iconContainer.baseIconSize + TaskbarApps.iconThemeRevision,
                iconContainer.baseIconSize + TaskbarApps.iconThemeRevision)

            Behavior on anchors.leftMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on anchors.topMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on implicitSize {
                animation: Appearance.animation.barResize.numberAnimation.createObject(this)
            }

            layer.enabled: iconContainer.enableShapeMask
            layer.effect: OpacityMask {
                maskSource: iconMask
            }
        }

        Loader {
            active: Config.options.bar.workspaces.monochromeIcons
            anchors.fill: mainAppIcon
            sourceComponent: Item {
                Desaturate {
                    id: desaturatedIcon
                    visible: false
                    anchors.fill: parent
                    source: mainAppIcon
                    desaturation: 0.8
                    layer.enabled: iconContainer.enableShapeMask
                    layer.effect: OpacityMask {
                        maskSource: iconMask
                    }
                }
                ColorOverlay {
                    anchors.fill: desaturatedIcon
                    source: desaturatedIcon
                    color: ColorUtils.transparentize(widgetPalette.colBackground, Config.options.appearance.iconTintPercentage)
                }
            }
        }
    }

    component HoverOverlay: Rectangle {
        property bool hover: false

        anchors.fill: parent
        color: widgetPalette.colBackground
        radius: Appearance.rounding.full
        opacity: hover ? 0.1 : 0

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    component WorkspaceBackgroundIndicator: Rectangle {
        property int workspaceValue
        property bool isActive
        property bool isOccupied
        readonly property bool showNumbers: wsModel.showNumbers
        readonly property color indColor: {
            if (isActive)
                return widgetPalette.colOnBackground;
            if (isOccupied)
                return widgetPalette.colOnContainer;
            return ColorUtils.transparentize(widgetPalette.colOnContainer, 0.45);
        }

        anchors.centerIn: parent
        width: root.workspaceDotSize
        height: width
        radius: width / 2
        color: showNumbers ? "transparent" : indColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        StyledText {
            anchors.centerIn: parent
            opacity: parent.showNumbers ? 1 : 0
            text: wsModel.labelFor(parent.workspaceValue)
            font.weight: Font.Black
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: parent.indColor

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveSlow.numberAnimation.createObject(this)
            }
        }
    }
}
