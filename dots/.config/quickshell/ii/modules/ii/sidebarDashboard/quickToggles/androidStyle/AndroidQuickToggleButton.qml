import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarDashboard
import "QuickToggleCatalog.js" as QuickToggleCatalog

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

    // Effective sizes for live preview during resize
    // The controller updates the draft during resize; rendering reads that
    // canonical size directly instead of applying a second local geometry.
    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]

    readonly property bool isWide: effectiveSizeW > 1
    readonly property bool isTall: effectiveSizeH > 1
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
        baseDelayRatio: 0.2
        staggerRatio: 0.06
    }

    // Sizing shenanigans - use effective sizes for live resize preview
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

        x: 0
        y: 0
        
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        
        width: root.width
        height: root.height

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

    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
    }
}
