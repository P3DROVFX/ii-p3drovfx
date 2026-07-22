import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    property var taskList
    readonly property int taskMargin: 5
    property bool showPopup: false

    property int gridRow: -1
    property int gridCol: -1
    property int entranceKey: 0

    property real _entranceOpacity: 0
    property real _entranceScale: 0.82
    property real _entranceTranslateX: -15
    property real _entranceTranslateY: -10
    property bool _entranceDone: false

    opacity: _entranceDone ? 1.0 : _entranceOpacity
    scale: _entranceDone ? 1.0 : _entranceScale
    transform: Translate {
        x: button._entranceDone ? 0 : button._entranceTranslateX
        y: button._entranceDone ? 0 : button._entranceTranslateY
    }

    function resetAndAnimate() {
        if (gridRow < 0 || gridCol < 0) {
            _entranceDone = true;
            return;
        }
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.82;
        _entranceTranslateX = -15;
        _entranceTranslateY = -10;
        Qt.callLater(function() {
            entranceAnim.start();
        });
    }

    onEntranceKeyChanged: resetAndAnimate()
    Component.onCompleted: resetAndAnimate()

    SequentialAnimation {
        id: entranceAnim
        PauseAnimation { duration: (button.gridRow + button.gridCol) * 28 }
        ParallelAnimation {
            NumberAnimation { target: button; property: "_entranceOpacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: button; property: "_entranceScale"; from: 0.82; to: 1.0; duration: 280; easing.type: Easing.OutBack }
            NumberAnimation { target: button; property: "_entranceTranslateX"; from: -15; to: 0; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: button; property: "_entranceTranslateY"; from: -10; to: 0; duration: 260; easing.type: Easing.OutCubic }
        }
        PropertyAction { target: button; property: "_entranceDone"; value: true }
    }
    
    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38
    implicitHeight: 38
    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small
    
    Rectangle {
        id: taskDot
        width: 8
        height: 8
        radius: Appearance.rounding.full
        scale: 0
        color: (taskList.length > 0 && isToday !== -1 && !bold) ? 
               toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary : "transparent"
        anchors {
            top: parent.top
            left: parent.left
            margins: 4
        }
    }

    Connections {
        target: button
        function on_EntranceDoneChanged() {
            if (button._entranceDone && taskList.length > 0 && isToday !== -1 && !bold) {
                taskDotPop.start();
            }
        }
    }

    SequentialAnimation {
        id: taskDotPop
        NumberAnimation { target: taskDot; property: "scale"; from: 0; to: 1.15; duration: 250; easing.type: Easing.OutBack }
        NumberAnimation { target: taskDot; property: "scale"; from: 1.15; to: 1.0; duration: 150; easing.type: Easing.OutBack }
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
                return buttonPos.y - popup.height - 4; 
            }
        }
        
    }
    
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: {
            if (button.taskList.length > 0 && button.isToday !== -1 && !button.bold) {
                button.showPopup = true
            }
        }
        onExited: button.showPopup = false
    }
    
    StyledText {
        anchors.centerIn: parent
        text: day
        horizontalAlignment: Text.AlignHCenter
        font.weight: bold ? Font.DemiBold : Font.Normal
        color: (isToday == 1) ? Appearance.m3colors.m3onPrimary : (isToday == 0) ? Appearance.colors.colOnLayer1 : Appearance.colors.colOutlineVariant
    }
}
