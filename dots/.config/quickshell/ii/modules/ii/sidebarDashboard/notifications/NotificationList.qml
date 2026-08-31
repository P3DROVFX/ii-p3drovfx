import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarDashboard
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../SidebarSpaceArbitration.js" as SpaceArbitration

Item {
    id: root

    property int entranceTrigger: -1
    property bool collapsed: false
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
    property real _entranceScale: 1
    property bool _entranceDone: true
    readonly property real listStatusSpacing: 5
    property real _measuredNotificationHeight: 0
    readonly property real representativeNotificationHeight: _measuredNotificationHeight > 0
        ? _measuredNotificationHeight
        : statusRow.implicitHeight * 2.5
    readonly property real collapsedHeight: statusRow.implicitHeight
    // Compare the group's total height with one and a half representative
    // cards. Adding the permanent status row here would count that space twice
    // and activate compact mode while a useful notification area still fits.
    readonly property real minimumExpandedHeight: SpaceArbitration.minimumUsefulNotificationHeight(
        representativeNotificationHeight,
        1.5
    )

    function scheduleRepresentativeHeightMeasurement() {
        representativeHeightTimer.restart();
    }

    function updateRepresentativeNotificationHeight() {
        let totalHeight = 0;
        let sampleCount = 0;
        const maximumSamples = Math.min(3, listview.count);

        for (let i = 0; i < maximumSamples; i++) {
            const item = listview.itemAtIndex(i);
            if (!item || item.expanded || item.implicitHeight <= 0)
                continue;
            totalHeight += item.implicitHeight;
            sampleCount++;
        }

        if (sampleCount > 0)
            _measuredNotificationHeight = totalHeight / sampleCount;
    }

    function finishEntrance() {
        if (entranceController.item)
            entranceController.item.stop();
        _entranceDone = true;
        _entranceScale = 1;
        statusRow.finishEntrance();
    }

    function startEntrance() {
        if (!entranceAnimationsEnabled || entranceTrigger < 0) {
            finishEntrance();
            return;
        }
        _entranceDone = false;
        _entranceScale = 0.94;
        statusRow.resetEntrance();
        Qt.callLater(function() {
            if (root.entranceAnimationsEnabled && entranceController.item)
                entranceController.item.restart();
        });
    }

    onEntranceTriggerChanged: startEntrance()
    onEntranceAnimationsEnabledChanged: entranceAnimationsEnabled ? startEntrance() : finishEntrance()
    Component.onCompleted: entranceTrigger >= 0 ? startEntrance() : finishEntrance()

    scale: _entranceDone ? 1 : _entranceScale

    Loader {
        id: entranceController
        active: root.entranceAnimationsEnabled
        sourceComponent: Item {
            function restart() { animation.restart(); }
            function stop() { animation.stop(); }

            SequentialAnimation {
                id: animation
                PauseAnimation { duration: Math.round(Appearance.animation.elementMove.duration * 0.25) }
                ParallelAnimation {
                    SidebarGroupAnimation { target: root; property: "_entranceScale"; from: 0.94; to: 1; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: statusRow; property: "_entranceOpacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: statusRow; property: "_leftTranslateX"; from: -40; to: 0; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: statusRow; property: "_rightTranslateX"; from: 40; to: 0; animationSpec: Appearance.animation.elementMove }
                }
                ScriptAction {
                    script: {
                        root._entranceDone = true;
                        statusRow._entranceDone = true;
                    }
                }
            }
        }
    }

    Timer {
        id: representativeHeightTimer
        interval: 0
        repeat: false
        onTriggered: root.updateRepresentativeNotificationHeight()
    }

    Item {
        id: expandedContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusRow.top
        anchors.bottomMargin: root.listStatusSpacing
        opacity: root.collapsed ? 0 : 1
        visible: opacity > 0
        enabled: !root.collapsed

        Behavior on opacity {
            SidebarGroupAnimation {
                animationSpec: Appearance.animation.elementMove
            }
        }

        NotificationListView { // Scrollable window
            id: listview
            anchors.fill: parent

            clip: true

            popup: false
            entranceTrigger: root.entranceTrigger
            entranceAnimationsEnabled: root.entranceAnimationsEnabled
            onCountChanged: root.scheduleRepresentativeHeightMeasurement()
            onContentHeightChanged: root.scheduleRepresentativeHeightMeasurement()
        }

        // Placeholder when list is empty
        PagePlaceholder {
            anchors.fill: parent
            shown: Notifications.list.length === 0
            icon: "notifications_active"
            description: Translation.tr("Nothing")
            shape: MaterialShape.Shape.Ghostish
            descriptionHorizontalAlignment: Text.AlignHCenter
        }
    }

    ButtonGroup {
        id: statusRow
        clip: true
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        property real _leftTranslateX: 0
        property real _rightTranslateX: 0
        property real _entranceOpacity: 1
        property bool _entranceDone: true

        function resetEntrance() {
            _entranceDone = false;
            _entranceOpacity = 0;
            _leftTranslateX = -40;
            _rightTranslateX = 40;
        }

        function finishEntrance() {
            _entranceDone = true;
            _entranceOpacity = 1;
            _leftTranslateX = 0;
            _rightTranslateX = 0;
        }

        GroupButtonWithIcon {
            id: snoozeButton
            Layout.fillWidth: false
            buttonIcon: "notifications_paused"
            toggled: Notifications.silent
            onClicked: () => {
                Notifications.silent = !Notifications.silent;
            }
            opacity: statusRow._entranceDone ? 1 : statusRow._entranceOpacity
            transform: Translate { x: statusRow._entranceDone ? 0 : statusRow._leftTranslateX }
        }
        GroupButtonWithIcon {
            id: countButton
            enabled: false
            Layout.fillWidth: true
            buttonText: Translation.tr("%1 notifications").arg(String(Notifications.list.length))
            opacity: statusRow._entranceDone ? 1 : statusRow._entranceOpacity
        }
        GroupButtonWithIcon {
            id: deleteAllButton
            Layout.fillWidth: false
            buttonIcon: "delete_sweep"
            onClicked: () => {
                Notifications.discardAllNotifications()
            }
            opacity: statusRow._entranceDone ? 1 : statusRow._entranceOpacity
            transform: Translate { x: statusRow._entranceDone ? 0 : statusRow._rightTranslateX }
        }
    }
}
