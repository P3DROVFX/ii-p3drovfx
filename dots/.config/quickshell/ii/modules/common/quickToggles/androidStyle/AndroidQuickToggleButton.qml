import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles
import qs.modules.common.animations
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import "QuickToggleCatalog.js" as QuickToggleCatalog
import "QuickToggleResize.js" as Resize

Item {
    id: root

    // Info to be passed to by repeaterestou
    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData.type, root.buttonData.sizeW, root.buttonData.sizeH, root.gridColumns)

    // Catalog spans own packing; the visual surface owns continuous morph progress.
    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]
    readonly property real morphWideProgress: Resize.progress(visualButton.width,
        root.baseCellWidth, root.baseCellWidth * 2 + root.cellSpacing)
    readonly property real morphTallProgress: Resize.progress(visualButton.height,
        root.baseCellHeight, root.baseCellHeight * 2 + root.cellSpacing)
    readonly property real resizeDirectionX: editableItem.directionX
    readonly property real resizeDirectionY: editableItem.directionY
    readonly property real threeWayProgress: root.is3Way && (Config.options.sidebar.quickToggles.useThreeWaySliders ?? false)
        ? root.morphWideProgress * (1 - root.morphTallProgress)
            * (1 - Resize.progress(visualButton.width, root.baseCellWidth * 2 + root.cellSpacing,
                root.baseCellWidth * 3 + root.cellSpacing * 2)) : 0
    property string expandedIconShape: "Circle"
    property Component expandedIconComponent: null
    property bool centerExpandedIcon: false
    property color expandedSurfaceColor: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
    property color expandedSymbolColor: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
    property real expandedStatusTransparency: 0.3
    property string expandedTitle: root.name
    property string expandedStatus: root.statusText

    // Every metric inside a tile is proportional to the cell height, so a touch-sized grid
    // grows its icon circles and labels along with it. Damped so a twice-as-tall cell doesn't
    // double the type; at the ii default (56) this is exactly 1.0 and nothing changes there.
    function scaled(value) {
        return QuickToggleMetrics.scaled(root.baseCellHeight, value);
    }

    readonly property bool isSquare: effectiveSizeW === 0
    readonly property bool isWide: effectiveSizeW > 1
    readonly property bool isTall: effectiveSizeH > 1
    readonly property bool isOneByOne: (effectiveSizeW === 1 || effectiveSizeW === 0) && effectiveSizeH === 1
    readonly property bool expandedSize: isWide
    readonly property bool is3Way: (root.buttonData.type === "soundcoreAnc" || root.buttonData.type === "powerProfile" || root.buttonData.type === "keyboardBacklight")
    readonly property bool is3WaySlider: is3Way && effectiveSizeW === 2 && effectiveSizeH === 1 && (Config.options.sidebar.quickToggles.useThreeWaySliders ?? false)

    // Use the rendered widget's hover state while keeping it in this delegate's
    // local scene graph. The stable canvas delegate remains the layout owner.
    property bool hovered: (visualButton.hovered || visualButton.mouseArea.containsMouse)
                           || (root.editMode && editableItem.containsMouse)

    // Signals
    signal openMenu

    // Declared in specific toggles
    property QuickToggleModel toggleModel
    property string name: toggleModel?.name ?? ""
    property string statusText: (toggleModel?.hasStatusText) ? (toggleModel?.statusText || (root.toggled ? Translation.tr("Active") : Translation.tr("Inactive"))) : ""
    property string tooltipText: toggleModel?.tooltipText ?? ""
    property string buttonIcon: toggleModel?.icon ?? "close"
    property bool available: toggleModel?.available ?? true
    property bool toggled: toggleModel?.toggled ?? false
    property var mainAction: toggleModel?.mainAction ?? null
    property bool hasMenu: toggleModel?.hasMenu ?? false
    property var altAction: root.hasMenu ? (() => root.openMenu()) : (toggleModel?.altAction ?? null)

    // Optional custom layout for 2x2 size — set by subclasses to override ios2x2Layout
    property Component wide2x2OverrideComponent: null

    // Optional custom layout for 1x2 (tall) size — set by subclasses to override tallLayout
    property Component tall1x2OverrideComponent: null

    // Optional background icon for wifi signal effect (ghost behind foreground)
    property string backgroundIcon: ""

    // Edit mode state
    property bool editMode: false
    property bool isUnused: false // injected by delegate chooser
    property bool isDragging: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null
    property var gridRef: null

    // Active pages and the drawer use one explicit packed coordinate system.
    // Bind only when geometry is present so fixed sliders can still be owned by
    // their Column positioner.
    readonly property bool hasExplicitGeometry: root.buttonData
        && root.buttonData.layoutX !== undefined
        && root.buttonData.layoutY !== undefined
    Binding on x {
        when: root.hasExplicitGeometry
        value: editableItem.resizing ? editableItem.resizeOriginX : Number(root.buttonData.layoutX)
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding on y {
        when: root.hasExplicitGeometry
        value: editableItem.resizing ? editableItem.resizeOriginY : Number(root.buttonData.layoutY)
        restoreMode: Binding.RestoreBindingOrValue
    }
    z: root.isDragging || editableItem.resizing ? 100 : 0

    Behavior on x {
        enabled: root.hasExplicitGeometry && !root.isDragging && !editableItem.resizing
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on y {
        enabled: root.hasExplicitGeometry && !root.isDragging && !editableItem.resizing
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
    readonly property bool entrancePageActive: root.pageIndex === -1 || !root.panel
        || root.panel.currentPage === root.pageIndex

    DashboardEntranceProgress {
        id: entranceProgress
        animationSpec: Appearance.animation.elementMove
        animationsEnabled: root.entranceAnimationsEnabled
        trigger: root.entranceTrigger
        pageActive: root.entrancePageActive
        delayIndex: Math.min(Math.max(root.buttonIndex, 0), 15)
        baseDelayRatio: 0.2
        staggerRatio: 0.06
    }

    // Sizing shenanigans - use effective sizes for live resize preview
    property real baseWidth: root.isSquare ? root.baseCellHeight : (root.baseCellWidth * root.effectiveSizeW + cellSpacing * (root.effectiveSizeW - 1))
    property real baseHeight: root.baseCellHeight * root.effectiveSizeH + cellSpacing * (root.effectiveSizeH - 1)

    readonly property real allocatedWidth: (root.buttonData && root.buttonData.pixelWidth !== undefined && !root.isSquare)
        ? Number(root.buttonData.pixelWidth)
        : baseWidth

    width: allocatedWidth
    implicitWidth: baseWidth
    implicitHeight: baseHeight
    
    // Ghost block visibility when dragging
    Rectangle {
        anchors.fill: parent
        radius: root.isSquare ? visualButton.buttonRadius : Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainer
        visible: root.isDragging
        opacity: 0.5
    }

    GroupButton {
        id: visualButton

        x: 0
        y: 0
        
        Behavior on width {
            enabled: !editableItem.resizing
            NumberAnimation {
                duration: Appearance.animation.elementResize.duration
                easing.type: Appearance.animation.elementResize.type
                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
            }
        }
        Behavior on height {
            enabled: !editableItem.resizing
            NumberAnimation {
                duration: Appearance.animation.elementResize.duration
                easing.type: Appearance.animation.elementResize.type
                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
            }
        }
        
        width: editableItem.resizing ? editableItem.previewWidth : root.width
        height: editableItem.resizing ? editableItem.previewHeight : root.height

        scale: (root.isDragging ? 1.05 : 1.0) * (0.92 + 0.08 * entranceProgress.progress)
        opacity: {
            if (entranceProgress.progress < 1) return entranceProgress.progress;
            if (root.isUnused) return 0.5;
            if (root.editMode && !root.isDragging) return 0.9;
            if (root.isDragging) return 0.95;
            return 1.0;
        }
        z: root.isDragging ? 99 : 1

        transform: Translate {
            x: (root.isDragging ? root.dragOffsetX : 0)
                + ((root.buttonIndex % 3 === 0) ? -18 : (root.buttonIndex % 3 === 1) ? 0 : 18)
                    * (1 - entranceProgress.progress)
            y: (root.isDragging ? root.dragOffsetY : 0)
                + ((root.buttonIndex % 2 === 0) ? -12 : 12) * (1 - entranceProgress.progress)
        }
        
        Behavior on scale {
            enabled: !root.isDragging && !entranceProgress.running
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
        Behavior on opacity {
            enabled: !entranceProgress.running
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

        enableImplicitWidthAnimation: !root.editMode && visualButton.mouseArea.containsMouse
        enableImplicitHeightAnimation: !root.editMode && visualButton.mouseArea.containsMouse

        enabled: root.available || root.editMode
        padding: root.scaled(6)
        horizontalPadding: padding
        verticalPadding: padding

        readonly property real layer2Mix: Math.max(root.hasMenu ? root.morphWideProgress : 0,
            root.morphTallProgress * (1 - root.morphWideProgress))
        colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, root.threeWayProgress)
        colBackgroundToggled: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colLayer2, 1 - layer2Mix), root.threeWayProgress)
        colBackgroundToggledHover: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colPrimaryHover, Appearance.colors.colLayer2Hover, 1 - layer2Mix), root.threeWayProgress)
        colBackgroundToggledActive: ColorUtils.transparentize(ColorUtils.mix(Appearance.colors.colPrimaryActive, Appearance.colors.colLayer2Active, 1 - layer2Mix), root.threeWayProgress)
        readonly property real fullRadius: Math.min(width, height) / 2
        readonly property real squareMorphProgress: Resize.progress(width, root.baseCellHeight, root.baseCellWidth)
        buttonRadius: Config.options.appearance.sharpMode ? 0 : (
            width < root.baseCellWidth
                ? (root.toggled
                    ? Resize.mix(fullRadius, root.scaled(Appearance.rounding.large), squareMorphProgress)
                    : Resize.mix(root.scaled(Appearance.rounding.large), fullRadius, squareMorphProgress))
                : Math.min(fullRadius,
                    Resize.mix(root.toggled ? root.scaled(Appearance.rounding.large) : fullRadius,
                        root.scaled(Appearance.rounding.large), root.morphTallProgress))
        )
        // GroupButton animates its corner radii for press feedback. During resize
        // the visual geometry already interpolates them; avoid a second chase.
        leftRadius: isPressed ? buttonRadiusPressed : buttonRadius
        rightRadius: isPressed ? buttonRadiusPressed : buttonRadius
        Behavior on leftRadius { enabled: !root.editMode; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton) }
        Behavior on rightRadius { enabled: !root.editMode; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton) }
        buttonRadiusPressed: is3WaySlider ? (height / 2) : (root.isSquare ? (root.toggled ? fullRadius : root.scaled(Appearance.rounding.normal)) : root.scaled(Appearance.rounding.normal))
        property color colText: ColorUtils.transparentize(root.toggled
            ? ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colOnLayer2, 1 - layer2Mix)
            : Appearance.colors.colOnLayer2, enabled ? 0 : 0.7)
        property color colIcon: root.toggled ? Appearance.colors.colOnPrimary
            : ColorUtils.mix(colText, Appearance.colors.colOnLayer3, 1 - root.morphWideProgress)

        toggled: root.toggled
        altAction: root.altAction

        onClicked: {
            if (is3WaySlider) return;
            if ((root.expandedSize || root.isTall) && root.hasMenu)
                root.altAction();
            else
                root.mainAction();
        }

        contentItem: Item {
            anchors.fill: parent
            readonly property Component overrideComponent: root.isTall
                ? (root.isWide ? root.wide2x2OverrideComponent : root.tall1x2OverrideComponent) : null
            readonly property real sliderReveal: root.threeWayProgress

            QuickToggleMorphLayer {
                anchors.fill: parent
                reveal: parent.overrideComponent ? 0 : 1 - parent.sliderReveal
                directionX: root.resizeDirectionX
                directionY: root.resizeDirectionY
                travel: root.scaled(12)
                QuickToggleMorphContent {
                    anchors.fill: parent
                    tile: root
                    button: visualButton
                }
            }
            Loader {
                anchors.fill: parent
                active: !!parent.overrideComponent
                sourceComponent: parent.overrideComponent
            }
            QuickToggleMorphLayer {
                anchors.fill: parent
                reveal: parent.sliderReveal
                entering: true
                directionX: root.resizeDirectionX
                directionY: root.resizeDirectionY
                travel: root.scaled(12)
                Loader {
                    anchors.fill: parent
                    active: parent.reveal > 0
                    sourceComponent: ThreeWaySlider {
                        toggleType: root.buttonData.type
                        toggleModel: root.toggleModel
                        entranceTrigger: root.entranceTrigger
                    }
                }
            }
        }
    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
    }
}
