import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs
import qs.services
import "./widgets"

DockButton {
    id: root

    property var dockContent: null
    property int delegateIndex: -1
    property string actionId: ""
    property int trashCount: 0
    property int symbolSize: Math.round(root.buttonSize * 0.5)
    property string symbolName: ""
    property string toggledSymbolName: ""
    property color activeColor: Appearance.m3colors.m3onPrimary
    property color inactiveColor: Appearance.colors.colOnLayer0
    property bool dragActive: false
    property string dragSymbol: ""
    property int normalShape: MaterialShape.Shape.Pill
    property int activeShape: MaterialShape.Shape.Cookie9Sided
    property bool dragOver: false
    property string fileDropIcon: ""
    property bool fileDropActive: false
    property string customImageSource: ""
    // A glyph-like picture in place of the symbol (the overview button's icon
    // from assets/icons); `-symbolic` files take the glyph's colour.
    property string customIconSource: ""
    // Black-and-white pictures are drawn in the glyph's colour.
    property bool tintCustomIcon: root.customIconSource.indexOf("symbolic") >= 0
    // The plate's shape by name, and whether it stays up when not toggled.
    property string shapeName: ""
    property bool alwaysShowShape: false
    readonly property bool plateShown: root.toggled || root.alwaysShowShape
    // Drawn at the lens's largest scale so magnifying never stretches it.
    readonly property real renderScale: root.dockContent?.magnificationRenderScale ?? 1
    property real symbolFill: root.toggled ? 1.0 : 0.0
    property bool _pressed: false
    readonly property bool isDragging: dragActive || fileDropActive

    readonly property real magScale: root.dockMagnificationScale
    readonly property real slotWidth: root.dockContent?.buttonSlotSize ?? root.buttonSize
    readonly property real slotHeight: root.dockContent
        ? (root.dockContent.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : root.buttonSize

    width: root.slotWidth
    height: root.slotHeight

    transformOrigin: {
        let pos = root.dockContent?.dockPos ?? "bottom";
        if (pos === "top")
            return Item.Top;
        if (pos === "left")
            return Item.Left;
        if (pos === "right")
            return Item.Right;
        return Item.Bottom;
    }

    readonly property string launchAnimation: Config.options?.dock?.launchAnimation ?? "bounce"

    transform: [attention.shift, attention.grow, attention.turn]

    DockAttentionAnimation {
        id: attention
        host: root
        dockPos: root.dockContent?.dockPos ?? "bottom"
    }

    onClicked: attention.playLaunch(root.launchAnimation)

    scale: (_pressed ? 0.88 : 1.0) * magScale
    // Two tiers (see the delegate wrapper's z): no per-frame render stack reorder.
    z: magScale > 1.01 ? 2 : 1

    Loader {
        anchors.fill: parent
        z: 10
        active: true
        sourceComponent: MouseArea {
            id: actionDragOverlay
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            property real pressCoord: 0
            property bool dragActive: false

            onEntered: {
                if (root.dockContent?.suppressHover)
                    return;
                root.dockContent?.onButtonEntered(root);
            }
            onExited: {
                root.dockContent?.onButtonExited(root);
            }

            onPressed: event => {
                if (event.button === Qt.LeftButton) {
                    pressCoord = root.dockContent?.isVertical ? event.y : event.x;
                }
                root._pressed = true;
            }
            onPositionChanged: event => {
                // event.button is NoButton on a move: ask what is held.
                if (!pressed || !(pressedButtons & Qt.LeftButton))
                    return;
                var cur = root.dockContent?.isVertical ? event.y : event.x;
                var dist = Math.abs(cur - pressCoord);
                if (!dragActive && dist > 5 && root.dockContent) {
                    dragActive = true;
                    root._pressed = false;
                    root.dockContent.startItemDrag(root.delegateIndex, actionDragOverlay, event.x, event.y);
                }
                if (dragActive && root.dockContent) {
                    root.dockContent.moveItemDrag(actionDragOverlay, event.x, event.y);
                }
            }
            onReleased: event => {
                root._pressed = false;
                if (dragActive) {
                    dragActive = false;
                    if (root.dockContent)
                        root.dockContent.endItemDrag();
                    return;
                }
                if (event.button === Qt.RightButton) {
                    if (root.actionId === "trash")
                        trashContextMenu.open();
                    else if (root.actionId === "overview" || root.actionId === "pin")
                        actionMenu.open();
                    return;
                }
                root.clicked();
            }
            onCanceled: {
                root._pressed = false;
                if (dragActive) {
                    dragActive = false;
                    if (root.dockContent)
                        root.dockContent.cancelDrag();
                }
            }
        }
    }

    DockTrashContextMenu {
        id: trashContextMenu
        trashCount: root.trashCount
        anchorItem: root
    }

    // Overview and pin: what they do, how the overview button looks, and
    // taking them off the dock (Dock → Content brings them back).
    DockContextMenuBase {
        id: actionMenu
        anchorItem: root
        headerText: root.actionId === "overview" ? Translation.tr("Overview") : Translation.tr("Pin")
        headerSubtitle: root.actionId === "overview" ? Translation.tr("Dock button") : Translation.tr("Drop an app here to pin it")
        headerSymbol: root.symbolName
        menuGroups: actionMenu.menuOpen ? [
            root.actionId === "overview" ? [
                { id: "open", icon: "open_in_full", text: Translation.tr("Open overview") }
            ] : [],
            [
                root.actionId === "overview"
                    ? { id: "settings", icon: "palette", text: Translation.tr("Icon and shape") }
                    : { id: "settings", icon: "settings", text: Translation.tr("Dock settings") },
                { id: "remove", icon: "remove_circle", text: Translation.tr("Remove from dock"), destructive: true }
            ]
        ].filter(group => group.length > 0) : []

        onActionTriggered: id => {
            actionMenu.close();
            switch (id) {
            case "open":
                root.clicked();
                break;
            case "settings":
                if (root.actionId === "overview")
                    GlobalStates.openSettingsPage("dock", "widgets/DockOverviewButtonConfig.qml");
                else
                    GlobalStates.openSettingsPage("dock", "");
                break;
            case "remove":
                if (root.actionId === "overview")
                    Config.options.dock.showOverviewButton = false;
                else
                    Config.options.dock.showPinButton = false;
                break;
            }
        }
    }

    contentItem: Item {
        id: contentContainer
        implicitWidth: root.buttonSize
        implicitHeight: root.buttonSize
        anchors.fill: parent
        clip: false // Allow larger icons to overflow slightly if needed

        Item {
            id: shapeSymbol
            anchors.centerIn: parent
            visible: root.customImageSource === ""
            implicitWidth: root.dragOver ? root.buttonSize * 1.1 : root.buttonSize * 0.9
            implicitHeight: implicitWidth

            MaterialShape {
                id: plateShape
                width: parent.width * root.renderScale
                height: parent.height * root.renderScale
                transformOrigin: Item.Center
                x: (parent.width - width) / 2
                y: (parent.height - height) / 2
                scale: 1 / root.renderScale
                shape: root.shapeName.length > 0 && !root.isDragging
                    ? (plateShape.shapeMap[root.shapeName] ?? root.normalShape)
                    : (root.toggled || root.isDragging) ? root.activeShape : root.normalShape
                rotation: root.dragOver ? 90 : (root.isDragging ? 45 : (root.toggled && root.shapeName.length === 0 ? 90 : 0))
                color: root.isDragging ? Appearance.colors.colSecondaryContainer
                    : root._pressed ? Appearance.colors.colPrimaryActive
                    : root.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                opacity: root.plateShown || root.isDragging ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on rotation {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
            }

            // The custom icon, glyph-sized, sharp under the lens.
            IconImage {
                id: customIcon
                anchors.centerIn: parent
                // Hidden for symbolic ones: the effect below draws them from it.
                visible: root.customIconSource.length > 0 && !root.isDragging && !root.tintCustomIcon
                implicitSize: root.symbolSize
                source: root.customIconSource
                backer.sourceSize: Qt.size(Math.ceil(root.symbolSize * root.renderScale), Math.ceil(root.symbolSize * root.renderScale))
            }
            // Black-and-white pictures: lifted to white and coloured like
            // the glyph. QtQuick.Effects, not Qt5Compat — this
            // button is also drawn in Settings, whose window is destroyed on
            // close (a Qt5Compat effect would keep a reference to it).
            MultiEffect {
                anchors.fill: customIcon
                visible: root.customIconSource.length > 0 && !root.isDragging && root.tintCustomIcon
                source: customIcon
                brightness: 1.0
                colorization: 1.0
                colorizationColor: root.plateShown ? root.activeColor : root.inactiveColor
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.customIconSource.length === 0 || root.isDragging
                // The lens scales this glyph up to magnificationScale. Native
                // glyphs are rasterized once at the base size and stretched,
                // which reads as jagged steps; curves are re-evaluated at
                // whatever size the transform draws them.
                renderType: Text.CurveRendering
                text: root.fileDropActive ? root.fileDropIcon : root.dragActive ? root.dragSymbol : root.symbolName
                fill: root.symbolFill
                iconSize: root.isDragging ? Math.round(root.buttonSize * 0.4) : root.symbolSize
                color: root.isDragging ? Appearance.colors.colOnSecondaryContainer : (root.plateShown ? root.activeColor : root.inactiveColor)

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
            }
        }

        // Custom image (for trash icon, etc.)
        Image {
            visible: root.customImageSource !== ""
            source: root.customImageSource
            anchors.centerIn: parent
            width: root.buttonSize * 1.0 // Standard size
            height: root.buttonSize * 1.0
            fillMode: Image.PreserveAspectFit
            smooth: true
            antialiasing: true
            mipmap: true
        }
    }
}
