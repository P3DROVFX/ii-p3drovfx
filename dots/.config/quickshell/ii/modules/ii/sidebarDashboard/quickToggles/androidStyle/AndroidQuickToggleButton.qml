import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    // Info to be passed to by repeaterestou
    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    // Effective sizes for live preview during resize
    readonly property int effectiveSizeW: {
        if (root.editMode && visualButton.editingRight) {
            var delta = root.baseCellWidth > 0 ? Math.round(visualButton.editDragX / root.baseCellWidth) : 0;
            var w = (root.buttonData.sizeW ?? root.buttonData.size ?? 1) + delta;
            return Math.max(1, Math.min(8, w));
        }
        return root.buttonData.sizeW ?? root.buttonData.size ?? 1;
    }
    readonly property int effectiveSizeH: {
        if (root.editMode && visualButton.editingBottom) {
            var delta = root.baseCellHeight > 0 ? Math.round(visualButton.editDragY / root.baseCellHeight) : 0;
            var h = (root.buttonData.sizeH ?? 1) + delta;
            return Math.max(1, Math.min(8, h));
        }
        return root.buttonData.sizeH ?? 1;
    }

    readonly property bool isWide: effectiveSizeW > 1
    readonly property bool isTall: effectiveSizeH > 1
    readonly property bool expandedSize: isWide
    readonly property bool is3Way: (root.buttonData.type === "soundcoreAnc" || root.buttonData.type === "powerProfile" || root.buttonData.type === "keyboardBacklight")
    readonly property bool is3WaySlider: is3Way && effectiveSizeW === 2 && effectiveSizeH === 1 && (Config.options.sidebar.quickToggles.useThreeWaySliders ?? false)

    // visualButton is reparented — use its native hovered (Button.hovered) so the
    // tooltip fires from the actual rendered widget, not the invisible grid placeholder
    property bool hovered: (visualButton.hovered || visualButton.mouseArea.containsMouse)
                           || (root.editMode && editModeInteraction.containsMouse)

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
    property real dragAbsX: 0
    property real dragAbsY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null
    property var gridRef: null

    // Entrance animation (Reorder animation effect - tuned delay & full opacity fade)
    property int entranceTrigger: -1
    property real _entranceOpacity: 0
    property real _entranceScale: 0.92
    property real _entranceOffsetX: ((buttonIndex % 3 === 0) ? -18 : (buttonIndex % 3 === 1) ? 0 : 18)
    property real _entranceOffsetY: ((buttonIndex % 2 === 0) ? -12 : 12)
    property bool _entranceDone: false
    readonly property bool _animationsDisabled: (Config.options?.appearance?.animationMultiplier ?? 1.0) <= 0.25

    onEntranceTriggerChanged: {
        if (_animationsDisabled) {
            _entranceDone = true;
            _entranceOpacity = 1;
            _entranceScale = 1;
            _entranceOffsetX = 0;
            _entranceOffsetY = 0;
            return;
        }
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.92;
        _entranceOffsetX = ((buttonIndex % 3 === 0) ? -18 : (buttonIndex % 3 === 1) ? 0 : 18);
        _entranceOffsetY = ((buttonIndex % 2 === 0) ? -12 : 12);
        Qt.callLater(function() {
            entranceAnim.start();
        });
    }

    Component.onCompleted: {
        if (_animationsDisabled) {
            _entranceDone = true;
            _entranceOpacity = 1;
            _entranceScale = 1;
            _entranceOffsetX = 0;
            _entranceOffsetY = 0;
            return;
        }
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.92;
        _entranceOffsetX = ((buttonIndex % 3 === 0) ? -18 : (buttonIndex % 3 === 1) ? 0 : 18);
        _entranceOffsetY = ((buttonIndex % 2 === 0) ? -12 : 12);
        Qt.callLater(function() {
            entranceAnim.start();
        });
    }

    SequentialAnimation {
        id: entranceAnim
        PauseAnimation { duration: 80 + Math.min(Math.max(root.buttonIndex, 0), 15) * 25 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "_entranceOpacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_entranceScale"; from: 0.92; to: 1.0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            NumberAnimation { target: root; property: "_entranceOffsetX"; from: ((root.buttonIndex % 3 === 0) ? -18 : (root.buttonIndex % 3 === 1) ? 0 : 18); to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            NumberAnimation { target: root; property: "_entranceOffsetY"; from: ((root.buttonIndex % 2 === 0) ? -12 : 12); to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
        PropertyAction { target: root; property: "_entranceDone"; value: true }
    }

    // Cross-page drag: tracks which page the drag is currently hovering over
    property int dragTargetPage: root.pageIndex

    property real pageScale: 1.0

    Connections {
        target: root.panel
        function onDragScrollPageChanged(newPage) {
            // Drag scroll handler
        }
        function onCurrentPageChanged() {
            if (root.panel && root.panel.currentPage === root.pageIndex && root.pageIndex !== -1) {
                pageEntranceAnimation.restart();
            }
        }
    }

    SequentialAnimation {
        id: pageEntranceAnimation
        NumberAnimation {
            target: root
            property: "pageScale"
            from: 0.96
            to: 1.0
            duration: 350
            easing.type: Easing.OutQuint
        }
    }

    // Sizing shenanigans - use effective sizes for live resize preview
    Layout.row: (root.buttonData && root.buttonData.gridRow !== undefined) ? root.buttonData.gridRow : -1
    Layout.column: (root.buttonData && root.buttonData.gridCol !== undefined) ? root.buttonData.gridCol : -1
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
    
    // Ghost block visibility when dragging
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainer
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1
        visible: root.isDragging
        opacity: 0.5
    }

    GroupButton {
        id: visualButton
        
        parent: root.isDragging ? (root.panel ? root.panel : root) : root

        x: root.isDragging ? dragAbsX : 0
        y: root.isDragging ? dragAbsY : 0
        
        Behavior on x {
            enabled: !root.isDragging && !entranceAnim.running
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on y {
            enabled: !root.isDragging && !entranceAnim.running
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

        scale: (root.isDragging ? 1.05 : 1.0) * root.pageScale * (root._entranceDone ? 1.0 : root._entranceScale)
        opacity: {
            if (!root._entranceDone) return root._entranceOpacity;
            if (root.isUnused) return 0.5;
            if (root.editMode && !root.isDragging) return 0.9;
            if (root.isDragging) return 0.95;
            return 1.0;
        }
        z: root.isDragging ? 99 : 1

        transform: Translate {
            x: root._entranceDone ? 0 : root._entranceOffsetX
            y: root._entranceDone ? 0 : root._entranceOffsetY
        }
        
        Behavior on scale {
            enabled: !root.isDragging && !pageEntranceAnimation.running && !entranceAnim.running
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
        Behavior on opacity {
            enabled: !entranceAnim.running
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

        enableImplicitWidthAnimation: !root.editMode && visualButton.mouseArea.containsMouse
        enableImplicitHeightAnimation: !root.editMode && visualButton.mouseArea.containsMouse

        enabled: root.available || root.editMode
        padding: 6
        horizontalPadding: padding
        verticalPadding: padding

        property bool useLayer2Bg: (root.hasMenu && root.expandedSize) || (root.isTall && !root.isWide)
        colBackground: is3WaySlider ? "transparent" : Appearance.colors.colLayer2
        colBackgroundToggled: is3WaySlider ? "transparent" : (useLayer2Bg ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary)
        colBackgroundToggledHover: is3WaySlider ? "transparent" : (useLayer2Bg ? Appearance.colors.colLayer2Hover : Appearance.colors.colPrimaryHover)
        colBackgroundToggledActive: is3WaySlider ? "transparent" : (useLayer2Bg ? Appearance.colors.colLayer2Active : Appearance.colors.colPrimaryActive)
        readonly property int fullRadius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
        buttonRadius: is3WaySlider ? (height / 2) : ((root.toggled || root.isTall) ? Appearance.rounding.large : fullRadius)
        buttonRadiusPressed: is3WaySlider ? (height / 2) : Appearance.rounding.normal
        property color colText: (root.toggled && !useLayer2Bg && enabled) ? Appearance.colors.colOnPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer2, enabled ? 0 : 0.7)
        property color colIcon: root.expandedSize ? ((root.toggled) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3) : colText

        toggled: root.toggled
        altAction: root.altAction

        onClicked: {
            if (is3WaySlider) return;
            if ((root.expandedSize || root.isTall) && root.hasMenu)
                root.altAction();
            else
                root.mainAction();
        }

        contentItem: Loader {
            id: contentItemLoader
            anchors.fill: parent
            sourceComponent: is3WaySlider ? threeWaySliderLayout
                           : (root.isWide && root.isTall && root.wide2x2OverrideComponent) ? root.wide2x2OverrideComponent
                           : (root.isWide && root.isTall) ? ios2x2Layout
                           : (root.isTall && !root.isWide && root.tall1x2OverrideComponent) ? root.tall1x2OverrideComponent
                           : (root.isTall && !root.isWide) ? tallLayout
                           : standardLayout
        }

    Component {
        id: tallLayout
        Item {
            anchors.fill: parent
            anchors.margins: 4

            MouseArea {
                id: tallIconMouseArea
                width: 54
                height: 54
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                hoverEnabled: true
                acceptedButtons: root.altAction ? Qt.LeftButton : Qt.NoButton
                cursorShape: Qt.PointingHandCursor

                onClicked: root.mainAction()

                Rectangle {
                    id: tallIconBg
                    anchors.fill: parent
                    radius: width / 2
                    color: root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(tallIconBg)
                    }

                    Item {
                        width: parent.width
                        height: parent.width // 54x54, matching the top circle of the pill
                        anchors.top: parent.top

                        MaterialSymbol {
                            visible: root.backgroundIcon !== ""
                            anchors.centerIn: parent
                            iconSize: 26
                            opacity: 0.3
                            color: root.toggled ? Appearance.colors.colOnPrimary : visualButton.colIcon
                            text: root.backgroundIcon
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: root.toggled ? 1 : 0
                            iconSize: 26
                            color: root.toggled ? Appearance.colors.colOnPrimary : visualButton.colIcon
                            text: root.buttonIcon
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }

                    // Hover/Press state layer
                    Loader {
                        anchors.fill: parent
                        active: root.altAction
                        sourceComponent: Rectangle {
                            radius: tallIconBg.radius
                            color: ColorUtils.transparentize(visualButton.colIcon, tallIconMouseArea.containsPress ? 0.88 : tallIconMouseArea.containsMouse ? 0.95 : 1)
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            Column {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: 8
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 0

                StyledText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: 600
                    color: visualButton.colText
                    elide: Text.ElideRight
                    text: root.name
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    visible: root.statusText !== ""
                    anchors.left: parent.left
                    anchors.right: parent.right
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: 100
                    color: ColorUtils.transparentize(visualButton.colText, 0.3)
                    elide: Text.ElideRight
                    text: root.statusText
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Component {
        id: ios2x2Layout
        ColumnLayout {
            spacing: 0
            anchors {
                fill: parent
                leftMargin: visualButton.horizontalPadding + 10
                rightMargin: visualButton.horizontalPadding + 10
                topMargin: visualButton.verticalPadding + 4
                bottomMargin: visualButton.verticalPadding + 4
            }

            // Top section: Icon aligned to top-left
            MouseArea {
                id: iosIconMouseArea
                hoverEnabled: true
                acceptedButtons: root.altAction ? Qt.LeftButton : Qt.NoButton
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                cursorShape: Qt.PointingHandCursor

                onClicked: root.mainAction()

                Rectangle {
                    id: iosIconBackground
                    anchors.fill: parent
                    radius: width / 2
                    color: {
                        if (root.toggled) {
                            return root.altAction ? Appearance.colors.colPrimary : Appearance.colors.colPrimary;
                        } else {
                            return Appearance.colors.colLayer3;
                        }
                    }

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        visible: root.backgroundIcon !== ""
                        anchors.centerIn: parent
                        iconSize: 22
                        opacity: 0.3
                        color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                        text: root.backgroundIcon
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: root.toggled ? 1 : 0
                        iconSize: 22
                        color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                        text: root.buttonIcon
                    }

                    // Hover/Press state layer
                    Loader {
                        anchors.fill: parent
                        active: root.altAction
                        sourceComponent: Rectangle {
                            radius: iosIconBackground.radius
                            color: ColorUtils.transparentize(visualButton.colIcon, iosIconMouseArea.containsPress ? 0.88 : iosIconMouseArea.containsMouse ? 0.95 : 1)
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            // Spacer
            Item {
                Layout.fillHeight: true
            }

            // Bottom section: Text aligned to bottom-left
            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignLeft | Qt.AlignBottom
                spacing: 0

                StyledText {
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: 600
                    color: visualButton.colText
                    elide: Text.ElideRight
                    text: root.name
                }

                StyledText {
                    visible: root.statusText !== ""
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    font {
                        pixelSize: Appearance.font.pixelSize.smaller
                        weight: 400
                    }
                    color: ColorUtils.transparentize(visualButton.colText, 0.3)
                    elide: Text.ElideRight
                    text: root.statusText
                }
            }
        }
    }

    Component {
        id: standardLayout
        RowLayout {
            spacing: root.isWide ? 10 : 4
            anchors {
                centerIn: root.isWide ? undefined : parent
                fill: root.isWide ? parent : undefined
                leftMargin: visualButton.horizontalPadding
                rightMargin: visualButton.horizontalPadding
            }

            // Icon
            MouseArea {
                id: iconMouseArea
                hoverEnabled: true
                acceptedButtons: (root.isWide && root.altAction) ? Qt.LeftButton : Qt.NoButton
                Layout.alignment: root.isWide ? Qt.AlignVCenter : Qt.AlignCenter
                Layout.fillHeight: root.isWide
                Layout.topMargin: root.isWide ? visualButton.verticalPadding : 0
                Layout.bottomMargin: root.isWide ? visualButton.verticalPadding : 0
                
                Layout.preferredWidth: (root.isWide && !root.toggled && !root.isTall) ? (root.baseCellHeight - visualButton.verticalPadding * 2) : (root.isWide ? (root.baseCellHeight - visualButton.verticalPadding * 2) : -1)
                Layout.preferredHeight: (!root.isWide && root.isTall) ? (root.baseHeight - visualButton.verticalPadding * 2) : -1

                implicitWidth: root.baseCellHeight - visualButton.verticalPadding * 2
                implicitHeight: root.baseCellHeight - visualButton.verticalPadding * 2
                cursorShape: Qt.PointingHandCursor

                onClicked: root.mainAction()

                Rectangle {
                    id: iconBackground
                    anchors.fill: parent
                    radius: {
                        if (root.isTall && !root.isWide) return Appearance.rounding.full;
                        if (root.isWide && !root.isTall && !root.toggled) return visualButton.radius - visualButton.verticalPadding;
                        return visualButton.radius - visualButton.verticalPadding;
                    }
                    color: {
                        const baseColor = root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3;
                        const transparentizeAmount = (root.altAction && root.isWide) ? 0 : (root.toggled ? 0 : 1);
                        if (!root.toggled && root.isWide) return "transparent"; // fix the inactive circle background
                        return ColorUtils.transparentize(baseColor, transparentizeAmount);
                    }

                    Behavior on radius {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        visible: root.backgroundIcon !== ""
                        anchors.centerIn: parent
                        iconSize: root.isWide ? 22 : 24
                        opacity: 0.3
                        color: visualButton.colIcon
                        text: root.backgroundIcon
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: root.toggled ? 1 : 0
                        iconSize: root.isWide ? 22 : 24
                        color: visualButton.colIcon
                        text: root.buttonIcon
                    }

                    // State layer
                    Loader {
                        anchors.fill: parent
                        active: (root.isWide && root.altAction)
                        sourceComponent: Rectangle {
                            radius: iconBackground.radius
                            color: ColorUtils.transparentize(visualButton.colIcon, iconMouseArea.containsPress ? 0.88 : iconMouseArea.containsMouse ? 0.95 : 1)
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            // Text column for expanded size
            Loader {
                Layout.alignment: root.isTall ? Qt.AlignTop : Qt.AlignVCenter
                Layout.topMargin: root.isTall ? visualButton.verticalPadding * 1.5 : 0
                Layout.leftMargin: 0 // Keep consistent spacing across toggles
                Layout.fillWidth: true
                visible: root.isWide
                active: visible
                sourceComponent: Column {
                    spacing: -2

                    StyledText {
                        anchors {
                            left: parent.left
                            right: parent.right
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: 600
                        color: visualButton.colText
                        elide: Text.ElideRight
                        text: root.name
                    }

                    StyledText {
                        visible: root.statusText !== ""
                        anchors {
                            left: parent.left
                            right: parent.right
                        }
                        font {
                            pixelSize: Appearance.font.pixelSize.smaller
                            weight: 100
                        }
                        color: visualButton.colText
                        elide: Text.ElideRight
                        text: root.statusText
                    }
                }
            }
        }
    }

    Component {
        id: threeWaySliderLayout
        ThreeWaySlider {
            anchors.fill: parent
            toggleType: root.buttonData.type
            toggleModel: root.toggleModel
            entranceTrigger: root.entranceTrigger
        }
    }

        // Expose drag state to edit border
        property real editDragX: 0
        property real editDragY: 0
        property bool editingRight: false
        property bool editingBottom: false

        MouseArea { // Blocking MouseArea for edit interactions
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
            property string dragTargetType: ""

            function findTargetTypeAt(gridX, gridY) {
                var layout = root.gridRef ? root.gridRef : (root.parent ? root.parent : null);
                if (!layout) return null;
                var bestType = null;
                var minDistance = Infinity;

                for (var i = 0; i < layout.children.length; i++) {
                    var sibling = layout.children[i];
                    if (!sibling || !sibling.visible) continue;
                    
                    var bData = sibling.modelData || sibling.buttonData;
                    if (!bData || !bData.type) continue;
                    if (bData.type === root.buttonData.type) continue;

                    var sX = sibling.x;
                    var sY = sibling.y;
                    var sW = sibling.width;
                    var sH = sibling.height;

                    if (gridX >= sX && gridX <= sX + sW && gridY >= sY && gridY <= sY + sH) {
                        return bData.type;
                    }

                    var sCenterX = sX + sW / 2;
                    var sCenterY = sY + sH / 2;
                    var dist = Math.hypot(gridX - sCenterX, gridY - sCenterY);
                    if (dist < minDistance) {
                        minDistance = dist;
                        bestType = bData.type;
                    }
                }
                return bestType;
            }

            onPressed: event => {
                dragTargetType = (root.buttonData && root.buttonData.type) ? root.buttonData.type : "";
                var panelItem = root.panel ? root.panel : root;
                var absPos = panelItem.mapFromItem(editModeInteraction, event.x, event.y);
                pressAbsX = absPos.x;
                pressAbsY = absPos.y;
                var originPos = panelItem.mapFromItem(root, 0, 0);
                initialVisualX = originPos.x;
                initialVisualY = originPos.y;
                root.dragAbsX = initialVisualX;
                root.dragAbsY = initialVisualY;
                root.isDragging = false;
                root.dragTargetPage = root.pageIndex;
            }
            
            onPositionChanged: event => {
                if (pressed) {
                    var myType = dragTargetType || (root.buttonData ? root.buttonData.type : "");
                    var panelItem = root.panel ? root.panel : root;
                    var absPos = panelItem.mapFromItem(editModeInteraction, event.x, event.y);
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
                        
                        // Cross-page drag: ask panel to scroll if near horizontal edges
                        if (root.panel && root.panel.handleDragScrollRequest) {
                            var panelPos = (panelItem === root.panel) ? { x: centerX, y: centerY } : root.panel.mapFromItem(panelItem, centerX, centerY);
                            root.panel.handleDragScrollRequest(panelPos.x, root);
                        }

                        // Live visual reorder preview
                        if (!root.isUnused && (root.dragTargetPage === root.pageIndex || root.dragTargetPage === -1)) {
                            var gridPos = root.gridRef ? root.gridRef.mapFromItem(panelItem, centerX, centerY) : { x: centerX, y: centerY };
                            var targetType = (root.panel && root.panel.findTargetToggleAtGridPos)
                                             ? root.panel.findTargetToggleAtGridPos(gridPos.x, gridPos.y, root.pageIndex, myType)
                                             : findTargetTypeAt(gridPos.x, gridPos.y);
                            if (root.panel && root.panel.setDragPreview) {
                                root.panel.setDragPreview(myType, targetType || myType, root.pageIndex);
                            }
                        }
                    }
                }
            }

            onReleased: event => {
                var myType = dragTargetType || (root.buttonData ? root.buttonData.type : "");
                if (root.isDragging) {
                    var targetPage = (root.panel && root.panel.currentPage !== undefined)
                                     ? root.panel.currentPage : root.pageIndex;
                    if (root.panel && targetPage !== root.pageIndex) {
                        if (root.panel.cancelDrag)
                            root.panel.cancelDrag();
                        root.panel.moveToggleToPage(
                            myType,
                            root.pageIndex,
                            targetPage
                        );
                    } else if (root.panel && !root.isUnused) {
                        if (root.panel.commitDrag) {
                            root.panel.commitDrag(myType, root.pageIndex);
                        }
                    }
                    if (root.panel && root.panel.cancelDragScroll)
                        root.panel.cancelDragScroll();
                    root.isDragging = false;
                } else {
                    if (root.panel && root.panel.cancelDrag)
                        root.panel.cancelDrag();
                    if (!visualButton.editingRight && !visualButton.editingBottom) {
                        if (root.panel && root.panel.toggleToggle) {
                            root.panel.toggleToggle(myType, root.pageIndex);
                        }
                    }
                }
            }

            onCanceled: {
                if (root.panel && root.panel.cancelDrag)
                    root.panel.cancelDrag();
                if (root.panel && root.panel.cancelDragScroll)
                    root.panel.cancelDragScroll();
                root.isDragging = false;
            }
        }

        Rectangle {
            id: editBorder
            anchors.fill: parent
            visible: root.editMode && !root.isDragging
            color: "transparent"
            border.width: 2
            radius: visualButton.radius
            
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
                acceptedButtons: Qt.NoButton // don't swallow clicks — let them reach editModeInteraction
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
                        if (newSizeW !== (root.buttonData.sizeW ?? root.buttonData.size ?? 1)) {
                            if (root.panel && root.panel.setToggleSize) {
                                root.panel.setToggleSize(root.buttonData.type, root.pageIndex, newSizeW, root.buttonData.sizeH ?? 1);
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: bottomDragHandle
                height: 8
                width: 24
                radius: 4
                color: Appearance.colors.colPrimary
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -height / 2
                visible: !root.isUnused

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    cursorShape: Qt.SizeVerCursor
                    preventStealing: true
                    property real pressAbsY: 0
                    onPressed: event => {
                        var absPos = visualButton.mapFromItem(bottomDragHandle, event.x, event.y);
                        pressAbsY = absPos.y;
                        visualButton.editingBottom = true;
                    }
                    onPositionChanged: event => {
                        var absPos = visualButton.mapFromItem(bottomDragHandle, event.x, event.y);
                        var dy = absPos.y - pressAbsY;
                        var currentH = root.buttonData.sizeH ?? 1;
                        visualButton.editDragY = Math.max(-root.baseCellHeight * (currentH - 1), Math.min(dy, root.baseCellHeight * (8 - currentH)));
                    }
                    onReleased: event => {
                        visualButton.editingBottom = false;
                        var currentH = root.buttonData.sizeH ?? 1;
                        var deltaRows = root.baseCellHeight > 0 ? Math.round(visualButton.editDragY / root.baseCellHeight) : 0;
                        var newSizeH = currentH + deltaRows;
                        if (isNaN(newSizeH)) newSizeH = currentH;
                        newSizeH = Math.max(1, Math.min(8, newSizeH));
                        
                        visualButton.editDragY = 0;
                        if (newSizeH !== (root.buttonData.sizeH ?? 1)) {
                            if (root.panel && root.panel.setToggleSize) {
                                root.panel.setToggleSize(root.buttonData.type, root.pageIndex, root.buttonData.sizeW ?? root.buttonData.size ?? 1, newSizeH);
                            }
                        }
                    }
                }
            }
        }
    }

    // addBadge is reparented to the same parent as visualButton so it renders above it
    Rectangle {
        id: addBadge
        parent: root.pageIndex === -1 ? root : (root.parent ? root.parent.parent : root)
        width: 20
        height: 20
        radius: 10
        color: Appearance.m3colors.m3success
        // Position aligned to top-right corner of visualButton
        x: visualButton.x + visualButton.width - width + 6
        y: visualButton.y - height + 6
        visible: root.isUnused
        z: visualButton.z + 10
        
        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 14
            color: Appearance.m3colors.m3onSuccess
        }
    }

    StyledToolTip {
        parent: root
        extraVisibleCondition: root.tooltipText !== "" && (root.hovered || (root.editMode && editModeInteraction.containsMouse))
        text: root.tooltipText
    }
}
