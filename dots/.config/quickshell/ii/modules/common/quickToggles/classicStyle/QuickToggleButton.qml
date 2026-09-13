import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

GroupButton {
    id: button
    property string buttonIcon
    // False hides the toggle when its service is missing, but edit mode still
    // shows it so a toggle can be removed on a machine that lacks it.
    property bool available: true
    // False greys the toggle out without hiding it.
    property bool interactive: true
    property bool editMode: false
    property bool isUnused: false
    // Set by the panel for the toggles that are currently shown; the drag
    // itself is handed to the parent grid, which owns the ordering.
    property string toggleType: ""
    property bool draggable: false
    signal editClicked

    baseWidth: 40
    baseHeight: 40
    clickedWidth: baseWidth + 20
    toggled: false
    visible: available || editMode
    enabled: interactive || editMode
    opacity: (editMode && (!available || !interactive)) ? 0.5 : 1

    readonly property bool sharpMode: Config.options.appearance.sharpMode
    buttonRadius: (altAction && toggled) ? Appearance?.rounding.normal : sharpMode ? 0 : Math.min(baseHeight, baseWidth) / 2
    buttonRadiusPressed: Appearance?.rounding?.small

    property bool isDragging: false
    property real pressPointerX: 0
    property real pressPointerY: 0
    property real pressOriginX: 0
    property real pressOriginY: 0
    property real dragDeltaX: 0
    property real dragDeltaY: 0
    // Bound to x/y so the dragged toggle keeps sitting under the pointer while
    // the grid animates every other toggle into its new slot.
    readonly property real dragOffsetX: button.isDragging ? (button.pressOriginX + button.dragDeltaX - button.x) : 0
    readonly property real dragOffsetY: button.isDragging ? (button.pressOriginY + button.dragDeltaY - button.y) : 0

    z: button.isDragging ? 100 : 0
    transform: Translate {
        x: button.dragOffsetX
        y: button.dragOffsetY
    }

    // The parent grid answers the drag protocol; anything else just ignores it.
    function dragHost() {
        const host = button.parent;
        return (host && host.beginToggleDrag !== undefined) ? host : null;
    }

    function beginDrag() {
        const host = button.dragHost();
        if (!host || !host.beginToggleDrag(button.toggleType))
            return false;
        button.isDragging = true;
        return true;
    }

    function updateDrag() {
        const host = button.dragHost();
        if (!host)
            return;
        host.updateToggleDrag(button.toggleType,
            button.pressOriginX + button.dragDeltaX + button.width / 2,
            button.pressOriginY + button.dragDeltaY + button.height / 2);
    }

    function endDrag(commit) {
        if (!button.isDragging)
            return;
        button.isDragging = false;
        button.dragDeltaX = 0;
        button.dragDeltaY = 0;
        const host = button.dragHost();
        if (!host)
            return;
        if (commit)
            host.endToggleDrag();
        else
            host.cancelToggleDrag();
    }

    Component.onDestruction: button.endDrag(false)

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        iconSize: 22
        fill: toggled ? 1 : 0
        color: toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: buttonIcon

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    // Edit affordances. The mouse area sits above the button's own one, so in
    // edit mode a click adds or removes the toggle instead of firing it.
    Item {
        id: editOverlay
        anchors.fill: parent
        visible: button.editMode
        z: 5

        MouseArea {
            id: editInteraction
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: button.isDragging ? Qt.ClosedHandCursor : (button.draggable ? Qt.OpenHandCursor : Qt.PointingHandCursor)
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            onPressed: event => {
                if (event.button !== Qt.LeftButton || !button.draggable) return;
                const pointer = editInteraction.mapToItem(button.parent, event.x, event.y);
                button.pressPointerX = pointer.x;
                button.pressPointerY = pointer.y;
                button.pressOriginX = button.x;
                button.pressOriginY = button.y;
                button.dragDeltaX = 0;
                button.dragDeltaY = 0;
            }

            onPositionChanged: event => {
                if (!editInteraction.pressed || !button.draggable) return;
                const pointer = editInteraction.mapToItem(button.parent, event.x, event.y);
                const deltaX = pointer.x - button.pressPointerX;
                const deltaY = pointer.y - button.pressPointerY;
                if (!button.isDragging) {
                    if (Math.abs(deltaX) < 4 && Math.abs(deltaY) < 4) return;
                    if (!button.beginDrag()) return;
                }
                button.dragDeltaX = deltaX;
                button.dragDeltaY = deltaY;
                button.updateDrag();
            }

            onReleased: event => {
                if (event.button !== Qt.LeftButton) return;
                if (button.isDragging) {
                    button.endDrag(true);
                    return;
                }
                button.editClicked();
            }

            onCanceled: button.endDrag(false)
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: button.buttonRadius
            border.width: 2
            border.color: button.isUnused
                ? (editInteraction.containsMouse ? Appearance.colors.colPrimary : "transparent")
                : (editInteraction.containsMouse ? Appearance.colors.colPrimary
                    : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7))

            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Rectangle {
            id: editBadge
            width: 18
            height: 18
            radius: Appearance.rounding.full
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: -4
            anchors.rightMargin: -4
            visible: !button.isDragging
            color: button.isUnused ? Appearance.m3colors.m3success : Appearance.m3colors.m3error

            MaterialSymbol {
                anchors.centerIn: parent
                text: button.isUnused ? "add" : "remove"
                iconSize: Appearance.font.pixelSize.small
                color: button.isUnused ? Appearance.m3colors.m3onSuccess : Appearance.m3colors.m3onError
            }
        }
    }
}
