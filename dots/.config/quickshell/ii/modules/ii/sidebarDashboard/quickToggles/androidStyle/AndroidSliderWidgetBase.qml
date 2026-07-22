import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    property bool editMode: false
    property bool isUnused: false
    property bool isDragging: false
    property real dragAbsX: 0
    property real dragAbsY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null
    property var gridRef: null

    // Entrance animation
    property int entranceTrigger: -1
    property real _entranceOpacity: 0
    property real _entranceScale: 0.85
    property real _entranceTranslateY: 20
    property bool _entranceDone: false

    property real currentSliderValue: 0

    readonly property bool _animationsDisabled: (Config.options?.appearance?.animationMultiplier ?? 1.0) <= 0.25

    function resetAndAnimateSlider() {
        if (_animationsDisabled) {
            quickSlider.valueAnimationDuration = 0;
            currentSliderValue = root.sliderValue;
            return;
        }
        // Step 1: Instant reset to 0 without animation
        quickSlider.valueAnimationDuration = 0;
        currentSliderValue = 0;
        
        // Step 2: Set animation duration and assign final target value after entrance delay
        sliderDelayTimer.restart();
    }

    Timer {
        id: sliderDelayTimer
        interval: 180 + Math.min(Math.max(root.buttonIndex, 0), 15) * 40
        repeat: false
        onTriggered: {
            quickSlider.valueAnimationDuration = _animationsDisabled ? 0 : 650;
            currentSliderValue = root.sliderValue;
        }
    }

    onEntranceTriggerChanged: {
        if (_animationsDisabled) {
            _entranceDone = true;
            _entranceOpacity = 1;
            _entranceScale = 1;
            _entranceTranslateY = 0;
            resetAndAnimateSlider();
            return;
        }
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.85;
        _entranceTranslateY = 20;
        resetAndAnimateSlider();
        Qt.callLater(function() {
            entranceAnim.start();
        });
    }

    Component.onCompleted: {
        if (_animationsDisabled) {
            _entranceDone = true;
            _entranceOpacity = 1;
            _entranceScale = 1;
            _entranceTranslateY = 0;
            resetAndAnimateSlider();
            return;
        }
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.85;
        _entranceTranslateY = 20;
        resetAndAnimateSlider();
        Qt.callLater(function() {
            entranceAnim.start();
        });
    }

    SequentialAnimation {
        id: entranceAnim
        PauseAnimation { duration: 150 + Math.min(Math.max(root.buttonIndex, 0), 15) * 55 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "_entranceOpacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_entranceScale"; from: 0.85; to: 1.0; duration: 350; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "_entranceTranslateY"; from: 20; to: 0; duration: 320; easing.type: Easing.OutCubic }
        }
        PropertyAction { target: root; property: "_entranceDone"; value: true }
    }

    property string tooltipText: ""

    property string materialSymbol: ""
    property string secondaryMaterialSymbol: ""
    property real sliderValue: 0
    signal moved(real value)
    
    // For specific toggles to handle right-click actions if they want
    signal openMenu

    // Effective sizes for live preview during resize
    readonly property int effectiveSizeW: {
        if (root.editMode && visualButton.editingRight) {
            var delta = root.baseCellWidth > 0 ? Math.round(visualButton.editDragX / root.baseCellWidth) : 0;
            var w = (root.buttonData.sizeW ?? root.buttonData.size ?? 4) + delta;
            return Math.max(1, Math.min(8, w));
        }
        return root.buttonData.sizeW ?? root.buttonData.size ?? 4;
    }
    readonly property int effectiveSizeH: {
        if (root.editMode && visualButton.editingBottom) {
            var delta = root.baseCellHeight > 0 ? Math.round(visualButton.editDragY / root.baseCellHeight) : 0;
            var h = (root.buttonData.sizeH ?? 1) + delta;
            return Math.max(1, Math.min(8, h));
        }
        return root.buttonData.sizeH ?? 1;
    }

    property bool hovered: hoverHandler.hovered || (root.editMode && editModeInteraction.containsMouse)

    HoverHandler {
        id: hoverHandler
    }

    Layout.columnSpan: root.effectiveSizeW
    Layout.rowSpan: root.effectiveSizeH
    Layout.preferredWidth: root.implicitWidth
    Layout.preferredHeight: root.implicitHeight
    Layout.fillWidth: false
    Layout.fillHeight: false


    property real baseWidth: root.baseCellWidth * root.effectiveSizeW + cellSpacing * (root.effectiveSizeW - 1)
    property real baseHeight: root.baseCellHeight * root.effectiveSizeH + cellSpacing * (root.effectiveSizeH - 1)

    implicitWidth: baseWidth
    implicitHeight: baseHeight
    
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainer
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1
        visible: root.isDragging
        opacity: 0.5
    }

    Item {
        id: visualButton
        
        parent: root.pageIndex === -1 ? root : (root.parent ? root.parent.parent : root)
        
        x: root.isDragging ? dragAbsX : (root.pageIndex === -1 ? 0 : (root.parent ? root.parent.x + root.x : root.x))
        y: root.isDragging ? dragAbsY : (root.pageIndex === -1 ? 0 : (root.parent ? root.parent.y + root.y : root.y))
        
        Behavior on x {
            enabled: !root.isDragging
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on y {
            enabled: !root.isDragging
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        
        width: root.width
        height: root.height

        scale: (root.isDragging ? 1.05 : 1.0) * (root._entranceDone ? 1.0 : root._entranceScale)
        opacity: {
            if (!root._entranceDone) return root._entranceOpacity;
            if (root.isUnused) return 0.5;
            if (root.editMode && !root.isDragging) return 0.9;
            if (root.isDragging) return 0.95;
            return 1.0;
        }
        z: root.isDragging ? 99 : 1
        
        transform: Translate {
            y: root._entranceDone ? 0 : root._entranceTranslateY
        }
        
        Behavior on scale {
            enabled: !entranceAnim.running
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
        Behavior on opacity {
            enabled: !entranceAnim.running
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

            StyledSlider {
                id: quickSlider
                anchors.fill: parent
                configuration: StyledSlider.Configuration.M
                stopIndicatorValues: []
                dividerValues: root.secondaryMaterialSymbol.length > 0 ? [secondaryIcon.iconLocation] : []
                value: root.currentSliderValue
                onMoved: root.moved(value)
                
                // To prevent flickable dragging when using slider
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.openMenu()
                }

            MaterialShapeWrappedMaterialSymbol {
                id: icon
                property bool nearFull: quickSlider.value >= 0.82
                anchors {
                    verticalCenter: quickSlider.verticalCenter
                    right: nearFull ? quickSlider.handle.right : quickSlider.right
                    rightMargin: nearFull ? 10 : 4
                }
                iconSize: 16
                padding: 4
                shape: MaterialShape.Shape.Cookie7Sided
                text: root.materialSymbol

                rotation: quickSlider.value * 360

                Behavior on rotation {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                }

                color: {
                    if (quickSlider.value > 1.0) {
                        return Appearance.colors.colErrorContainer;
                    }
                    return nearFull ? "transparent" : Appearance.colors.colSecondaryContainer;
                }

                colSymbol: {
                    if (quickSlider.value > 1.0) {
                        return Appearance.m3colors.m3onErrorContainer;
                    }
                    return nearFull ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer;
                }

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on colSymbol {
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
                property bool nearIcon: iconLocation - quickSlider.value <= 0.1 && iconLocation - quickSlider.value > (quickSlider.handleWidth + 8 - 14) / quickSlider.effectiveDraggingWidth
                anchors {
                    verticalCenter: quickSlider.verticalCenter
                    right: nearIcon ? quickSlider.handle.right : quickSlider.right
                    rightMargin: nearIcon ? 14 : (1 - iconLocation) * quickSlider.effectiveDraggingWidth + quickSlider.rightPadding + 8
                }
                iconSize: 20
                color: quickSlider.value >= iconLocation - 0.1 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                text: root.secondaryMaterialSymbol

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        // --- Edit Mode Logic ---
        property real editDragX: 0
        property real editDragY: 0
        property bool editingRight: false
        property bool editingBottom: false

        MouseArea {
            id: editModeInteraction
            visible: root.editMode
            anchors.fill: parent
            cursorShape: root.isDragging ? Qt.ClosedHandCursor : (root.isUnused ? Qt.PointingHandCursor : Qt.OpenHandCursor)
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            
            property real pressAbsX: 0
            property real pressAbsY: 0
            property real initialVisualX: 0
            property real initialVisualY: 0

            function mutatePages(mutatorFn) {
                if (root.panel && root.panel.mutatePages) {
                    root.panel.mutatePages(mutatorFn);
                } else {
                    var cloned = JSON.parse(JSON.stringify(Config.options.sidebar.quickToggles.android.pages));
                    mutatorFn(cloned);
                    Config.options.sidebar.quickToggles.android.pages = cloned;
                }
            }

            function toggleEnabled() {
                const buttonType = root.buttonData.type;
                const pi = root.pageIndex;

                mutatePages(function(pages) {
                    if (pi < 0 || pi >= pages.length) return;
                    var page = pages[pi];
                    var existingIdx = -1;
                    for (var i = 0; i < page.length; i++) {
                        if (page[i].type === buttonType) { existingIdx = i; break; }
                    }
                    if (existingIdx === -1) {
                        page.push({ type: buttonType, sizeW: 4, sizeH: 1, size: 4 });
                    } else {
                        page.splice(existingIdx, 1);
                    }
                });
            }

            function setSize(newW, newH) {
                const buttonType = root.buttonData.type;
                const pi = root.pageIndex;
                mutatePages(function(pages) {
                    if (pi < 0 || pi >= pages.length) return;
                    var page = pages[pi];
                    for (var i = 0; i < page.length; i++) {
                        if (page[i].type === buttonType) {
                            page[i].sizeW = newW;
                            page[i].sizeH = newH;
                            page[i].size = newW;
                            return;
                        }
                    }
                });
            }
            
            function resolveLayoutConflicts() {
                if (root.panel && root.panel.resolveLayoutConflicts) {
                    root.panel.resolveLayoutConflicts(root.pageIndex, root.gridColumns);
                }
            }
            
            function checkForSwap(gridX, gridY) {
                if (!root.parent) return;
                var layout = root.parent;
                for (var i = 0; i < layout.children.length; i++) {
                    var sibling = layout.children[i];
                    if (sibling === root || !sibling.visible) continue;
                    
                    if (gridX >= sibling.x && gridX < sibling.x + sibling.width &&
                        gridY >= sibling.y && gridY < sibling.y + sibling.height) {
                        
                        if (sibling.buttonData && sibling.buttonData.type) {
                            var targetType = sibling.buttonData.type;
                            var myType = root.buttonData.type;
                            
                            mutatePages(function(pages) {
                                var page = pages[root.pageIndex];
                                if (!page) return;
                                
                                var myIdx = -1;
                                var targetIdx = -1;
                                for (var j = 0; j < page.length; j++) {
                                    if (page[j].type === myType) myIdx = j;
                                    if (page[j].type === targetType) targetIdx = j;
                                }
                                
                                if (myIdx !== -1 && targetIdx !== -1 && myIdx !== targetIdx) {
                                    var temp = page[myIdx];
                                    page[myIdx] = page[targetIdx];
                                    page[targetIdx] = temp;
                                }
                            });
                            break;
                        }
                    }
                }
            }

            onPressed: event => {
                var absPos = visualButton.parent.mapFromItem(editModeInteraction, event.x, event.y);
                pressAbsX = absPos.x;
                pressAbsY = absPos.y;
                initialVisualX = visualButton.x;
                initialVisualY = visualButton.y;
                root.isDragging = false;
            }
            
            onPositionChanged: event => {
                if (pressed) {
                    var absPos = visualButton.parent.mapFromItem(editModeInteraction, event.x, event.y);
                    var dx = absPos.x - pressAbsX;
                    var dy = absPos.y - pressAbsY;
                    
                    if (!root.isDragging && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
                        root.isDragging = true;
                    }
                    
                    if (root.isDragging) {
                        root.dragAbsX = initialVisualX + dx;
                        root.dragAbsY = initialVisualY + dy;
                        
                        var centerX = root.dragAbsX + visualButton.width / 2;
                        var centerY = root.dragAbsY + visualButton.height / 2;
                        
                        var gridPos = root.parent.mapFromItem(visualButton.parent, centerX, centerY);
                        checkForSwap(gridPos.x, gridPos.y);
                    }
                }
            }

            onReleased: event => {
                if (root.isDragging) {
                    root.isDragging = false;
                } else {
                    if (!visualButton.editingRight && !visualButton.editingBottom)
                        toggleEnabled();
                }
            }
        }

        Rectangle {
            id: editBorder
            anchors.fill: parent
            visible: root.editMode && !root.isDragging
            color: "transparent"
            border.width: 2
            radius: Appearance.rounding.large
            
            border.color: {
                if (root.isUnused) {
                    return root.hovered ? Appearance.colors.colPrimary : "transparent";
                } else {
                    return root.hovered ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7);
                }
            }
            
            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(editBorder)
            }
            
            MouseArea {
                id: editBorderMouseArea
                anchors.fill: parent
                visible: root.isUnused
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            Rectangle {
                id: rightDragHandle
                width: 8
                height: 24
                radius: 4
                color: Appearance.colors.colPrimary
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: -width / 2
                visible: !root.isUnused

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    cursorShape: Qt.SizeHorCursor
                    preventStealing: true
                    property real pressAbsX: 0
                    onPressed: event => {
                        var absPos = visualButton.mapFromItem(rightDragHandle, event.x, event.y);
                        pressAbsX = absPos.x;
                        visualButton.editingRight = true;
                    }
                    onPositionChanged: event => {
                        var absPos = visualButton.mapFromItem(rightDragHandle, event.x, event.y);
                        var dx = absPos.x - pressAbsX;
                        var currentW = root.buttonData.sizeW ?? 4;
                        visualButton.editDragX = Math.max(-root.baseCellWidth * (currentW - 1), Math.min(dx, root.baseCellWidth * (8 - currentW)));
                    }
                    onReleased: event => {
                        visualButton.editingRight = false;
                        var currentW = root.buttonData.sizeW ?? 4;
                        var deltaColumns = root.baseCellWidth > 0 ? Math.round(visualButton.editDragX / root.baseCellWidth) : 0;
                        var newSizeW = currentW + deltaColumns;
                        if (isNaN(newSizeW)) newSizeW = currentW;
                        newSizeW = Math.max(1, Math.min(8, newSizeW)); 
                        
                        visualButton.editDragX = 0;
                        if (newSizeW !== currentW) {
                            var currentH = root.buttonData.sizeH ?? 1;
                            editModeInteraction.setSize(newSizeW, currentH);
                            editModeInteraction.resolveLayoutConflicts();
                        }
                    }
                }
            }
            
            // Sliders typically only support height 1, so no bottomDragHandle for now
        }
    }

    Rectangle {
        id: addBadge
        width: 20
        height: 20
        radius: 10
        color: Appearance.m3colors.m3success
        anchors.top: parent.top
        anchors.topMargin: -6
        anchors.right: parent.right
        anchors.rightMargin: -6
        visible: root.isUnused
        z: 10
        
        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 14
            color: Appearance.m3colors.m3onSuccess
        }
    }

    StyledToolTip {
        parent: root
        extraVisibleCondition: root.tooltipText !== "" && root.hovered
        text: root.tooltipText
    }
}
