import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles
import qs.modules.common.animations
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import "QuickToggleCatalog.js" as QuickToggleCatalog

Item {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight

    // Mirrors AndroidQuickToggleButton: chrome scales with the cell height so touch-sized
    // grids get proportionally larger icons. Identity at the ii default cell height.
    function scaled(value) {
        return QuickToggleMetrics.scaled(root.baseCellHeight, value);
    }
    required property real cellSpacing
    required property int cellSize

    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData.type, root.buttonData.sizeW, root.buttonData.sizeH, root.gridColumns)

    property bool editMode: false
    property bool isUnused: false
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
        value: Number(root.buttonData.layoutX)
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding on y {
        when: root.hasExplicitGeometry
        value: Number(root.buttonData.layoutY)
        restoreMode: Binding.RestoreBindingOrValue
    }
    z: root.isDragging ? 100 : 0

    Behavior on x {
        enabled: root.hasExplicitGeometry && !root.isDragging
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on y {
        enabled: root.hasExplicitGeometry && !root.isDragging
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
        baseDelayRatio: 0.35
        staggerRatio: 0.1
    }

    property real currentSliderValue: root.sliderValue * entranceProgress.progress
    property int _activeValueAnimDuration: 0

    property string tooltipText: ""

    property string materialSymbol: ""
    property string secondaryMaterialSymbol: ""
    property real sliderValue: 0
    signal moved(real value)
    
    // For specific toggles to handle right-click actions if they want
    signal openMenu

    // Effective sizes for live preview during resize
    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]
    readonly property bool isVertical: root.effectiveSizeH >= 3

    property bool hovered: hoverHandler.hovered || (root.editMode && editableItem.containsMouse)

    HoverHandler {
        id: hoverHandler
    }

    property real baseWidth: root.baseCellWidth * root.effectiveSizeW + cellSpacing * (root.effectiveSizeW - 1)
    property real baseHeight: root.baseCellHeight * root.effectiveSizeH + cellSpacing * (root.effectiveSizeH - 1)

    // Compact vertical footprint: the track keeps StyledSlider's M preset at the
    // reference cell height, so a full cell read as ~13px of dead margin per side.
    // The widget hugs the track instead, and the packer reserves this height for
    // slider-only rows (QuickToggleLayout.rowPixelHeights) instead of a full cell.
    readonly property real compactHeight: QuickToggleMetrics.sliderWidgetHeight(root.baseCellHeight)

    readonly property real effectiveTrackThickness: {
        var baseTrack = QuickToggleMetrics.sliderTrack(root.baseCellHeight);
        if (!(baseTrack > 0))
            baseTrack = 30; // StyledSlider.Configuration.M
        if (root.effectiveSizeH > 1) {
            var maxTrack = Math.max(baseTrack, root.baseHeight - root.horizontalMargin * 2);
            return Math.round((baseTrack + maxTrack) / 2);
        }
        return baseTrack;
    }

    // Track corners follow the user's rounding preference (windowRounding is
    // derived from appearance.roundingValue) but at a reduced fraction — the full
    // token saturates a ~30px track into a blob. Half the track thickness is the
    // geometric pill limit, and sharp mode zeroes the override the same way the
    // StyledSlider default would.
    readonly property real trackCornerRadius: Config.options.appearance.sharpMode
        ? 0
        : (root.effectiveSizeH > 1
            ? Appearance.rounding.large
            : Math.min(effectiveTrackThickness / 2, Appearance.rounding.windowRounding * 0.3))

    readonly property real horizontalMargin: root.isVertical ? 0 : QuickToggleMetrics.sliderHorizontalMargin(root.baseCellHeight)

    implicitWidth: baseWidth
    implicitHeight: (root.isVertical || root.effectiveSizeH > 1) ? baseHeight : Math.min(baseHeight, compactHeight)
    
    Rectangle {
        anchors {
            fill: parent
            leftMargin: root.horizontalMargin
            rightMargin: root.horizontalMargin
        }
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainer
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1
        visible: root.isDragging
        opacity: 0.5
    }

    Item {
        id: visualButton

        x: root.horizontalMargin
        y: 0
        
        Behavior on x {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        
        width: Math.max(1, root.width - root.horizontalMargin * 2)
        height: root.height

        scale: (root.isDragging ? 1.05 : 1.0) * (0.85 + 0.15 * entranceProgress.progress)
        opacity: {
            if (entranceProgress.progress < 1) return entranceProgress.progress;
            if (root.isUnused) return 0.5;
            if (root.editMode && !root.isDragging) return 0.9;
            if (root.isDragging) return 0.95;
            return 1.0;
        }
        z: root.isDragging ? 99 : 1
        
        transform: Translate {
            x: root.isDragging ? root.dragOffsetX : 0
            y: (root.isDragging ? root.dragOffsetY : 0) + 20 * (1 - entranceProgress.progress)
        }
        
        Behavior on scale {
            enabled: !entranceProgress.running
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
        Behavior on opacity {
            enabled: !entranceProgress.running
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

        Loader {
            id: sliderLoader
            anchors.fill: parent
            sourceComponent: root.isVertical ? verticalSliderComponent : horizontalSliderComponent
        }

        Component {
            id: horizontalSliderComponent

            StyledSlider {
                id: quickSliderHorizontal
                anchors.fill: parent
                // Touch-sized cells get a track proportional to the cell; at the reference
                // cell height sliderTrack() returns -1 and the fixed M preset stands.
                readonly property real trackThickness: root.effectiveTrackThickness
                configuration: trackThickness > 0 ? trackThickness : StyledSlider.Configuration.M
                trackRadius: root.trackCornerRadius
                unsharpenRadius: root.effectiveSizeH > 1 ? Appearance.rounding.unsharpen : root.trackCornerRadius
                stopIndicatorValues: []
                dividerValues: root.secondaryMaterialSymbol.length > 0 ? [secondaryIcon.iconLocation] : []
                valueAnimationDuration: root._activeValueAnimDuration
                value: root.currentSliderValue
                onMoved: {
                    root._activeValueAnimDuration = 0;
                    root.moved(value);
                }
                
                // To prevent flickable dragging when using slider
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.openMenu()
                }

                MaterialSymbol {
                    id: horizIcon
                    property bool nearFull: quickSliderHorizontal.value >= 0.82
                    visible: root.materialSymbol.length > 0
                    anchors {
                        verticalCenter: parent.verticalCenter
                        right: nearFull ? quickSliderHorizontal.handle.right : parent.right
                        rightMargin: root.effectiveSizeH > 1 ? (nearFull ? 14 : 12) : (nearFull ? 10 : 4)
                    }
                    iconSize: root.scaled(root.effectiveSizeH > 1 ? 22 : 20)
                    text: root.materialSymbol

                    color: {
                        if (quickSliderHorizontal.value > 1.0) {
                            return Appearance.m3colors.m3onErrorContainer;
                        }
                        return nearFull ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer;
                    }

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on anchors.rightMargin {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                MaterialSymbol {
                    id: secondaryIcon
                    visible: root.secondaryMaterialSymbol.length > 0
                    property real iconLocation: 0.3
                    property bool nearIcon: iconLocation - quickSliderHorizontal.value <= 0.1 && iconLocation - quickSliderHorizontal.value > (quickSliderHorizontal.handleWidth + 8 - 14) / quickSliderHorizontal.effectiveDraggingWidth
                    anchors {
                        verticalCenter: parent.verticalCenter
                        right: nearIcon ? quickSliderHorizontal.handle.right : parent.right
                        rightMargin: nearIcon ? 14 : (1 - iconLocation) * quickSliderHorizontal.effectiveDraggingWidth + quickSliderHorizontal.rightPadding + 8
                    }
                    iconSize: root.scaled(root.effectiveSizeH > 1 ? 22 : 20)
                    color: quickSliderHorizontal.value >= iconLocation - 0.1 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    text: root.secondaryMaterialSymbol

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }

        Component {
            id: verticalSliderComponent

            StyledVerticalSlider {
                id: quickSliderVertical
                anchors.fill: parent
                configuration: 48
                trackRadius: root.trackCornerRadius
                unsharpenRadius: root.effectiveSizeH > 1 ? Appearance.rounding.unsharpen : root.trackCornerRadius
                showValueLabel: false
                stopIndicatorValues: []
                valueAnimationDuration: root._activeValueAnimDuration
                value: root.currentSliderValue
                onMoved: {
                    root._activeValueAnimDuration = 0;
                    root.moved(value);
                }

                // To prevent flickable dragging when using slider
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.openMenu()
                }

                MaterialSymbol {
                    id: vertIcon
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom
                        bottomMargin: root.scaled(12)
                    }
                    iconSize: root.scaled(20)
                    text: root.materialSymbol

                    color: {
                        if (quickSliderVertical.value > 1.0) {
                            return Appearance.m3colors.m3onErrorContainer;
                        }
                        return quickSliderVertical.value > 0.12 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer;
                    }

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
        anchors {
            fill: parent
            leftMargin: root.horizontalMargin
            rightMargin: root.horizontalMargin
        }
    }
}
