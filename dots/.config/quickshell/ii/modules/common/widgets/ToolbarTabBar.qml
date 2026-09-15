pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int currentIndex: 0
    required property var tabButtonList
    property bool requestOnly: false
    signal indexSelected(int index)

    function incrementCurrentIndex() {
        root.setCurrentIndex(root.currentIndex + 1);
    }
    function decrementCurrentIndex() {
        root.setCurrentIndex(root.currentIndex - 1);
    }
    function setCurrentIndex(index) {
        if (root.tabButtonList.length === 0)
            return;

        const nextIndex = Math.max(0, Math.min(root.tabButtonList.length - 1, index));
        if (nextIndex === root.currentIndex)
            return;

        if (root.requestOnly)
            root.indexSelected(nextIndex);
        else
            root.currentIndex = nextIndex;
    }

    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
    implicitWidth: contentItem.implicitWidth
    implicitHeight: 40
    property bool showShortcutHints: false
    // See ToolbarTabButton: keeps a three-tab bar inside a narrow panel.
    property bool collapseInactiveLabels: false
    property int _delegateRevision: 0

    property Component delegate: ToolbarTabButton {
        required property int index
        required property var modelData
        current: index == root.currentIndex
        text: modelData.name
        materialSymbol: modelData.icon
        collapseInactiveLabel: root.collapseInactiveLabels
        shortcutIndex: index + 1
        showShortcut: root.showShortcutHints
        onClicked: {
            root.setCurrentIndex(index);
        }
    }

    Row {
        id: contentItem
        z: 1
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            id: tabRepeater
            model: root.tabButtonList
            delegate: root.delegate
            onItemAdded: root._delegateRevision++
            onItemRemoved: root._delegateRevision++
        }
    }

    Rectangle {
        id: activeIndicator
        z: 0
        color: Appearance.colors.colSecondaryContainer
        anchors.verticalCenter: contentItem.verticalCenter
        height: activeIndicator.targetItem?.height ?? root.implicitHeight
        implicitWidth: activeIndicator.targetItem?.implicitWidth ?? 0
        implicitHeight: root.implicitHeight
        readonly property int fullRadius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
        radius: fullRadius
        // Animation
        property Item targetItem: root._delegateRevision >= 0
            ? tabRepeater.itemAt(root.currentIndex)
            : null
        AnimatedTabIndexPair {
            id: leftBound
            idx1Duration: 150
            idx2Duration: 250
            easingType: Easing.OutQuad
            index: activeIndicator.targetItem ? contentItem.x + activeIndicator.targetItem.x : contentItem.x
        }
        AnimatedTabIndexPair {
            id: rightBound
            idx1Duration: 150
            idx2Duration: 250
            easingType: Easing.OutQuad
            index: activeIndicator.targetItem ? contentItem.x + activeIndicator.targetItem.x + activeIndicator.targetItem.width : contentItem.x
        }
        x: Math.min(leftBound.idx1, leftBound.idx2)
        width: Math.max(rightBound.idx1, rightBound.idx2) - x
    }

    MouseArea {
        anchors.fill: parent
        z: 2
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor

        property bool throttleActive: false

        Timer {
            id: coalesceTimer
            interval: 300
            repeat: false
            onTriggered: parent.throttleActive = false
        }

        onWheel: event => {
            event.accepted = true;

            if (!throttleActive) {
                if (event.angleDelta.y < 0) {
                    root.incrementCurrentIndex();
                } else if (event.angleDelta.y > 0) {
                    root.decrementCurrentIndex();
                }
                throttleActive = true;
            }

            coalesceTimer.restart();
        }
    }

}
