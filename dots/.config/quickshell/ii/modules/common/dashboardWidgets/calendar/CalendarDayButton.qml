import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.animations
import qs.modules.common.widgets

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    property var taskList
    readonly property int taskMargin: 5
    property bool showPopup: false
    property bool popupPinned: false
    readonly property bool compactCell: button.cellSize < 28
    property int gridRow: -1
    property int gridCol: -1
    property int entranceKey: 0
    property bool entranceAnimationsEnabled: false
    property real _entranceOpacity: 1
    property real _entranceScale: 1
    property real _entranceTranslateX: 0
    property real _entranceTranslateY: 0
    property real _taskDotScale: 1
    property bool _entranceDone: true

    opacity: _entranceDone ? 1 : _entranceOpacity
    scale: _entranceDone ? 1 : _entranceScale
    transform: Translate {
        x: button._entranceDone ? 0 : button._entranceTranslateX
        y: button._entranceDone ? 0 : button._entranceTranslateY
    }

    function finishEntrance() {
        if (entranceController.item)
            entranceController.item.stop();
        _entranceDone = true;
        _entranceOpacity = 1;
        _entranceScale = 1;
        _entranceTranslateX = 0;
        _entranceTranslateY = 0;
        _taskDotScale = 1;
    }

    function resetAndAnimate() {
        if (!entranceAnimationsEnabled || gridRow < 0 || gridCol < 0) {
            finishEntrance();
            return;
        }
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.82;
        _entranceTranslateX = -15;
        _entranceTranslateY = -10;
        _taskDotScale = 0;
        Qt.callLater(function() {
            if (button.entranceAnimationsEnabled && entranceController.item)
                entranceController.item.restart();
        });
    }

    onEntranceKeyChanged: resetAndAnimate()
    onEntranceAnimationsEnabledChanged: entranceAnimationsEnabled ? resetAndAnimate() : finishEntrance()
    Component.onCompleted: finishEntrance()

    Loader {
        id: entranceController
        active: button.entranceAnimationsEnabled
        sourceComponent: Item {
            function restart() { animation.restart(); }
            function stop() { animation.stop(); }
            SequentialAnimation {
                id: animation
                PauseAnimation {
                    duration: Math.round((Math.max(0, button.gridRow) + Math.max(0, button.gridCol))
                        * Appearance.animation.elementMove.duration * 0.07)
                }
                ParallelAnimation {
                    SidebarGroupAnimation { target: button; property: "_entranceOpacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: button; property: "_entranceScale"; from: 0.82; to: 1; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: button; property: "_entranceTranslateX"; from: -15; to: 0; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: button; property: "_entranceTranslateY"; from: -10; to: 0; animationSpec: Appearance.animation.elementMove }
                }
                ScriptAction { script: button._entranceDone = true }
                SidebarGroupAnimation { target: button; property: "_taskDotScale"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
            }
        }
    }

    Layout.fillWidth: false
    Layout.fillHeight: false
    // The grid is the tallest thing in the sidebar's bottom group, so the cell
    // shrinks with the space the calendar is given instead of being clipped.
    property real cellSize: 38
    implicitWidth: cellSize
    implicitHeight: cellSize
    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small
    
    Rectangle {
        id: taskDot
        width: button.compactCell ? 4 : 8
        height: width
        radius: Appearance.rounding.full
        scale: button._taskDotScale
        visible: taskList.length > 0 && isToday !== -1 && !bold
        color: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
        anchors {
            top: button.compactCell ? undefined : parent.top
            left: button.compactCell ? undefined : parent.left
            bottom: button.compactCell ? parent.bottom : undefined
            horizontalCenter: button.compactCell ? parent.horizontalCenter : undefined
            margins: button.compactCell ? 1 : 4
        }
    }

    LazyLoader {
        id: popupLoader
        active: itemScale > 0.9

        property real itemScale: button.showPopup ? 1 : 0.85
        property real itemOpacity: button.showPopup ? 1 : 0
        
        Behavior on itemScale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on itemOpacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        component: CalendarPopup {
            id: popup
            parent: button.QsWindow?.contentItem // i cant believe this works..
            scale: popupLoader.itemScale
            opacity: popupLoader.itemOpacity
            

            x: {
                if (!button.QsWindow) return 0;
                const buttonPos = button.QsWindow.contentItem.mapFromItem(button, 0, 0);
                const centeredX = buttonPos.x + (button.width / 2) - (popup.width / 2);
                return Math.max(0, Math.min(centeredX, parent.width - popup.width));
            }
            
            y: {
                if (!button.QsWindow) return 0;
                const buttonPos = button.QsWindow.contentItem.mapFromItem(button, 0, 0);
                const gap = 4;
                const above = buttonPos.y - popup.height - gap;
                const below = buttonPos.y + button.height + gap;
                const preferred = above >= 0 ? above : below;
                return Math.max(0, Math.min(preferred, parent.height - popup.height));
            }
        }
        
    }
    
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: PanelFamily.touchFirst ? Qt.LeftButton : Qt.NoButton
        onEntered: {
            if (button.taskList.length > 0 && button.isToday !== -1 && !button.bold) {
                button.showPopup = true
            }
        }
        onExited: {
            if (!button.popupPinned)
                button.showPopup = false;
        }
        onClicked: {
            if (button.taskList.length === 0 || button.isToday === -1 || button.bold)
                return;
            button.popupPinned = !button.popupPinned;
            button.showPopup = button.popupPinned;
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                button.popupPinned = false;
                button.showPopup = false;
            }
        }
    }
    
    StyledText {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: button.compactCell ? -2 : 0
        text: day
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: button.compactCell
            ? Appearance.font.pixelSize.smallie
            : Appearance.font.pixelSize.normal
        font.weight: bold ? Font.DemiBold : Font.Normal
        color: (isToday == 1) ? Appearance.m3colors.m3onPrimary : (isToday == 0) ? Appearance.colors.colOnLayer1 : Appearance.colors.colOutlineVariant
    }
}
