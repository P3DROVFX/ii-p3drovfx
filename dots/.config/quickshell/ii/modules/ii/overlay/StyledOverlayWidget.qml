pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas

/*
 * To make an overlay widget:
 * 1. Create a modules/overlay/<yourWidget>/<YourWidget>.qml, using this as the base class and declare your widget content as contentItem
 * 2. Add an entry to OverlayContext.availableWidgets with identifier=<yourWidgetIdentifier>
 * 3. Add an entry in Persistent.states.overlay.<yourWidgetIdentifier> with x, y, width, height, pinned, clickthrough properties set to reasonable defaults
 * 4. Add an entry in OverlayWidgetDelegateChooser with roleValue=<yourWidgetIdentifier> and Declare your widget in there
 * Use existing entries as reference.
 */
AbstractOverlayWidget {
    id: root

    // To be defined by subclasses
    required property Item contentItem
    property bool fancyBorders: true
    property bool showCenterButton: false
    property bool showClickabilityButton: true
    property Component titleIconComponent: null
    property real editorBackgroundOpacity: 1

    // Defaults n stuff
    required property var modelData
    readonly property string identifier: modelData.identifier
    readonly property string materialSymbol: modelData.materialSymbol ?? "widgets"
    property string title: identifier.replace(/([A-Z])/g, " $1").replace(/^./, function(str){ return str.toUpperCase(); })
    property var persistentStateEntry: Persistent.states.overlay[identifier]
    property real radius: Appearance.rounding.windowRounding
    property real minimumWidth: contentItem.implicitWidth
    property real minimumHeight: contentItem.implicitHeight
    property real resizeMargin: 8
    property real padding: 6
    property real contentRadius: radius - padding
    // A widget that draws its own card (the performance HUD) can sit flush
    // against the screen edges: its chrome (margins, title bar) may leave the
    // screen, its content may not.
    property bool flushToEdges: false
    readonly property real edgeInsetLeft: flushToEdges ? root.resizeMargin + contentContainer.x : 0
    readonly property real edgeInsetTop: flushToEdges ? root.resizeMargin + contentContainer.y : 0
    readonly property real edgeInsetRight: flushToEdges ? root.width - root.edgeInsetLeft - contentContainer.width : 0
    readonly property real edgeInsetBottom: flushToEdges ? root.height - root.edgeInsetTop - contentContainer.height : 0
    // Such a widget can be pushed against the top of the screen, which would
    // hide its title bar; the bar then moves under the content instead.
    property bool titleBelow: false
    // Set by a widget that places itself (a snapped HUD), so moving the title
    // bar does not also move the widget.
    property bool externallyPositioned: false
    // Extra buttons at the start of the title bar's button row.
    property Component titleExtraComponent: null
    property bool titleElides: false
    readonly property bool dragging: dragHandler.active
    property bool _compensateTitleFlip: false

    function updateTitlePlacement() {
        if (!root.flushToEdges || root.dragging) {
            if (!root.flushToEdges)
                root.titleBelow = false;
            return;
        }
        // Where the content's top edge is on screen, whichever side the bar is on
        const contentTop = root.y + root.resizeMargin + contentContainer.y;
        const below = contentTop < titleBar.implicitHeight + root.resizeMargin;
        if (below === root.titleBelow)
            return;
        root._compensateTitleFlip = !root.externallyPositioned;
        root.titleBelow = below;
    }
    onYChanged: {
        if (root.flushToEdges && !root.dragging)
            Qt.callLater(root.updateTitlePlacement);
    }

    // Resizing
    function getXResizeDirection(x) {
        return (x < root.resizeMargin) ? -1 : (x > root.width - root.resizeMargin) ? 1 : 0
    }
    function getYResizeDirection(y) {
        return (y < root.resizeMargin) ? -1 : (y > root.height - root.resizeMargin) ? 1 : 0
    }
    hoverEnabled: true
    property bool resizable: true
    property bool resizing: false
    property bool dragLocked: false // Set to true by children (e.g. volume sliders) to prevent drag
    property int resizeXDirection: getXResizeDirection(mouseX)
    property int resizeYDirection: getYResizeDirection(mouseY)
    // Gesture origin, in canvas coordinates so that moving root while resizing doesn't feed back
    property real resizeStartCanvasX: 0
    property real resizeStartCanvasY: 0
    property real resizeStartX: 0
    property real resizeStartY: 0
    property real resizeStartWidth: 0
    property real resizeStartHeight: 0
    property int resizeCursorShape: Qt.ArrowCursor
    draggable: GlobalStates.overlayOpen
    drag.target: undefined
    preventStealing: root.resizing
    animateXPos: !dragHandler.active
    animateYPos: !dragHandler.active
    z: dragHandler.active ? 2 : 1
    cursorShape: {
        if (root.resizing) return root.resizeCursorShape;
        if (dragHandler.active) return Qt.ArrowCursor;
        if (!root.resizable) return Qt.ArrowCursor;
        if (resizeMargin < mouseX && mouseX < width - resizeMargin &&
            resizeMargin < mouseY && mouseY < height - resizeMargin) {
            return Qt.ArrowCursor;
        } else {
            const dragIsLeft = mouseX < width / 2
            const dragIsTop = mouseY < height / 2
            if ((dragIsLeft && dragIsTop) || (!dragIsLeft && !dragIsTop)) {
                return Qt.SizeFDiagCursor
            } else {
                return Qt.SizeBDiagCursor
            }
        }
    }

    // Positioning & sizing
    x: Math.round(persistentStateEntry.x) // Round or it'll be blurry
    y: Math.round(persistentStateEntry.y) // Round or it'll be blurry
    pinned: persistentStateEntry.pinned
    clickthrough: persistentStateEntry.clickthrough
    drag {
        minimumX: -root.edgeInsetLeft
        minimumY: -root.edgeInsetTop
        maximumX: root.parent?.width - root.width + root.edgeInsetRight
        maximumY: root.parent?.height - root.height + root.edgeInsetBottom
    }
    opacity: (GlobalStates.overlayOpen || !clickthrough) ? 1.0 : Config.options.overlay.clickthroughOpacity

    // Guarded states & registration funcs
    property bool open: Persistent.states.overlay.open
    property bool actuallyPinned: pinned && open
    property bool actuallyClickable: !clickthrough && actuallyPinned && open
    onActuallyPinnedChanged: reportPinnedState();
    onActuallyClickableChanged: reportClickableState();
    function reportPinnedState() {
        OverlayContext.pin(identifier, actuallyPinned);
    }
    function reportClickableState() {
        OverlayContext.registerClickableWidget(contentItem, actuallyClickable);
    }

    // Self-registeration with OverlayContext
    Component.onCompleted: {
        reportPinnedState();
        reportClickableState();
        Qt.callLater(root.updateTitlePlacement);
    }

    Connections {
        target: OverlayContext
        function onRequestCenter(identifier) {
            if (identifier === root.identifier) {
                root.center()
            }
        }
    }

    // Hooks
    onPressed: (event) => {
        // We're only interested in handling resize here
        // Early returns
        if (!root.resizable) return;
        if (root.resizeMargin < event.x && event.x < root.width - root.resizeMargin &&
            root.resizeMargin < event.y && event.y < root.height - root.resizeMargin) {
            return;
        }
        // Resizing setup
        root.resizeXDirection = getXResizeDirection(event.x);
        root.resizeYDirection = getYResizeDirection(event.y);
        if (root.resizeYDirection !== 0 && root.resizeXDirection === 0) {
            root.resizeXDirection = event.x < root.width / 2 ? -1 : 1;
        } else if (root.resizeXDirection !== 0 && root.resizeYDirection === 0) {
            root.resizeYDirection = event.y < root.height / 2 ? -1 : 1;
        }
        const origin = root.mapToItem(root.parent, event.x, event.y);
        root.resizeStartCanvasX = origin.x;
        root.resizeStartCanvasY = origin.y;
        root.resizeStartX = root.x;
        root.resizeStartY = root.y;
        root.resizeStartWidth = contentContainer.implicitWidth;
        root.resizeStartHeight = contentContainer.implicitHeight;
        root.resizeCursorShape = root.cursorShape;
        root.resizing = true;
    }
    onPositionChanged: (event) => {
        if (!root.resizing) return;
        const current = root.mapToItem(root.parent, event.x, event.y);
        const newWidth = Math.max(root.resizeStartWidth + (current.x - root.resizeStartCanvasX) * root.resizeXDirection, root.minimumWidth);
        const newHeight = Math.max(root.resizeStartHeight + (current.y - root.resizeStartCanvasY) * root.resizeYDirection, root.minimumHeight);
        contentContainer.implicitWidth = newWidth;
        contentContainer.implicitHeight = newHeight;
        // Dragging a left/top edge keeps the opposite edge pinned
        if (root.resizeXDirection === -1) root.x = root.resizeStartX + root.resizeStartWidth - newWidth;
        if (root.resizeYDirection === -1) root.y = root.resizeStartY + root.resizeStartHeight - newHeight;
    }
    function endResize() {
        if (!root.resizing) return;
        root.resizing = false;
        root.savePosition();
    }
    onReleased: root.endResize()
    onCanceled: root.endResize()

    DragHandler {
        id: dragHandler
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        enabled: root.draggable && !root.resizing && !root.dragLocked
        target: root
        onActiveChanged: { // Handle drag release
            if (!active) {
                root.resizing = false;
                root.savePosition();
                Qt.callLater(root.updateTitlePlacement);
            }
        }
        xAxis.minimum: -root.edgeInsetLeft
        xAxis.maximum: root.parent?.width - root.width + root.edgeInsetRight
        yAxis.minimum: -root.edgeInsetTop
        yAxis.maximum: root.parent?.height - root.height + root.edgeInsetBottom
    }

    function close() {
        Persistent.states.overlay.open = Persistent.states.overlay.open.filter(type => type !== root.identifier);
    }

    function togglePinned() {
        persistentStateEntry.pinned = !persistentStateEntry.pinned;
    }

    function toggleClickthrough() {
        persistentStateEntry.clickthrough = !persistentStateEntry.clickthrough;
    }

    function savePosition(xPos = root.x, yPos = root.y, width = contentContainer.implicitWidth, height = contentContainer.implicitHeight) {
        persistentStateEntry.x = Math.round(xPos);
        persistentStateEntry.y = Math.round(yPos);
        persistentStateEntry.width = Math.round(width);
        persistentStateEntry.height = Math.round(height);
    }

    function center() {
        const targetX = (root.parent.width - contentColumn.width) / 2 - root.resizeMargin
        const targetY = (root.parent.height - contentContainer.height) / 2 - titleBar.implicitHeight + border.border.width - root.resizeMargin
        root.x = targetX
        root.y = targetY
        root.savePosition(targetX, targetY)
    }

    visible: GlobalStates.overlayOpen || actuallyPinned
    implicitWidth: contentColumn.implicitWidth + resizeMargin * 2
    implicitHeight: contentColumn.implicitHeight + resizeMargin * 2

    Rectangle {
        id: border
        anchors {
            fill: parent
            margins: root.resizeMargin
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer1Base, (root.fancyBorders && GlobalStates.overlayOpen) ? 1 - root.editorBackgroundOpacity : 1)
        radius: root.radius
        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, GlobalStates.overlayOpen ? 0 : 1)
        border.width: 1

        layer.enabled: GlobalStates.overlayOpen
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: border.width
                height: border.height
                radius: root.radius
            }
        }

        GridLayout {
            id: contentColumn
            z: root.fancyBorders ? 0 : -1
            anchors.fill: parent
            columns: 1
            rowSpacing: 0
            columnSpacing: 0

            // Title bar
            Rectangle {
                id: titleBar
                opacity: GlobalStates.overlayOpen ? 1 : 0
                Layout.row: root.titleBelow ? 1 : 0
                Layout.fillWidth: true
                implicitWidth: titleBarRow.implicitWidth + root.padding * 2
                implicitHeight: titleBarRow.implicitHeight + root.padding * 2
                color: root.fancyBorders ? "transparent" : Appearance.colors.colLayer1Base
                // border.color: Appearance.colors.colOutlineVariant
                // border.width: 1
                
                RowLayout {
                    id: titleBarRow
                    anchors {
                        fill: parent
                        margins: root.padding
                    }
                    spacing: 2

                    MaterialSymbol {
                        visible: root.titleIconComponent === null
                        text: root.materialSymbol
                        Layout.leftMargin: 6
                        iconSize: 20
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                    }
                    Loader {
                        visible: root.titleIconComponent !== null
                        active: root.titleIconComponent !== null
                        sourceComponent: root.titleIconComponent
                        Layout.leftMargin: 6
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                    }
                    
                    StyledText {
                        Layout.fillWidth: true
                        // A compact widget lets its title elide instead of widening the bar
                        Layout.preferredWidth: root.titleElides ? 0 : -1
                        text: root.title
                        elide: Text.ElideRight
                    }

                    Loader {
                        visible: root.titleExtraComponent !== null
                        active: root.titleExtraComponent !== null
                        sourceComponent: root.titleExtraComponent
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TitlebarButton {
                        visible: root.showCenterButton
                        materialSymbol: "recenter"
                        onClicked: root.center()
                        StyledToolTip {
                            text: "Center"
                        }
                    }

                    TitlebarButton {
                        visible: (root.pinned && root.showClickabilityButton)
                        materialSymbol: "mouse"
                        toggled: !root.clickthrough
                        onClicked: root.toggleClickthrough()
                        StyledToolTip {
                            text: "Clickable when pinned"
                        }
                    }

                    TitlebarButton {
                        materialSymbol: "keep"
                        toggled: root.pinned
                        onClicked: root.togglePinned()
                        StyledToolTip {
                            text: "Pin"
                        }
                    }

                    TitlebarButton {
                        materialSymbol: "close"
                        onClicked: root.close()
                        StyledToolTip {
                            text: "Close"
                        }
                    }
                }
            }

            // Content
            Item {
                id: contentContainer
                Layout.row: root.titleBelow ? 0 : 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: root.fancyBorders ? root.padding : 0
                // Border of a rectangle is drawn inside its bounds, so the side facing the title bar tucks in to keep the gap small
                Layout.topMargin: root.titleBelow ? (root.fancyBorders ? root.padding : 0) : -border.border.width
                Layout.bottomMargin: root.titleBelow ? -border.border.width : (root.fancyBorders ? root.padding : 0)
                // Keep the content still on screen when the title bar changes sides
                property real lastY: 0
                onYChanged: {
                    if (root._compensateTitleFlip) {
                        root._compensateTitleFlip = false;
                        root.y -= y - lastY;
                        root.savePosition();
                    }
                    lastY = y;
                }
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                implicitWidth: Math.max(root.persistentStateEntry.width, root.minimumWidth)
                implicitHeight: Math.max(root.persistentStateEntry.height, root.minimumHeight)
                children: [root.contentItem]
            }
        }
    }


    component TitlebarButton: RippleButton {
        id: titlebarButton
        required property string materialSymbol
        buttonRadius: height / 2
        implicitHeight: contentItem.implicitHeight
        implicitWidth: implicitHeight
        padding: 0

        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        contentItem: Item {
            anchors.centerIn: parent
            implicitWidth: 30
            implicitHeight: 30

            MaterialSymbol {
                id: iconWidget
                anchors.centerIn: parent
                iconSize: 20
                text: titlebarButton.materialSymbol
                fill: titlebarButton.toggled
                color: titlebarButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
            }
        }
    }
}
