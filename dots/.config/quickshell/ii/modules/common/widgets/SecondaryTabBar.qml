import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.models

TabBar {
    id: root
    property real indicatorPadding: 8
    // Controlled consumers persist navigation requests, never Qt's insertion/removal indexes.
    property bool requestOnly: false
    // The controlled index is read-only from Qt's point of view: only the owner
    // changes it. Uncontrolled bars continue to follow the native currentIndex.
    property int selectedIndex: root.currentIndex
    signal indexSelected(int index)

    function selectIndex(index) {
        if (root.count === 0)
            return;
        const nextIndex = Math.max(0, Math.min(root.count - 1, index));
        if (root.requestOnly)
            root.indexSelected(nextIndex);
        else
            root.setCurrentIndex(nextIndex);
    }

    Keys.onPressed: event => {
        if (!root.requestOnly)
            return;
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            const direction = event.key === Qt.Key_Right ? 1 : -1;
            root.selectIndex(root.selectedIndex + (root.mirrored ? -direction : direction));
            event.accepted = true;
        }
    }
    Layout.fillWidth: true

    background: Item {
        WheelHandler {
            onWheel: (event) => {
                if (root.requestOnly) {
                    if (event.angleDelta.y < 0) root.selectIndex(root.selectedIndex + 1);
                    else if (event.angleDelta.y > 0) root.selectIndex(root.selectedIndex - 1);
                } else {
                    if (event.angleDelta.y < 0) root.incrementCurrentIndex();
                    else if (event.angleDelta.y > 0) root.decrementCurrentIndex();
                }
            }
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        }

        Rectangle {
            id: activeIndicator
            z: 9999
            anchors.bottom: parent.bottom
            topLeftRadius: height
            topRightRadius: height
            bottomLeftRadius: 0
            bottomRightRadius: 0
            color: Appearance.colors.colPrimary
            // Animation
            property real baseWidth: root.width / root.count
            AnimatedTabIndexPair {
                id: idxPair
                idx1Duration: 150
                idx2Duration: 300
                easingType: Easing.OutBack
                
                property real lastIndex: root.selectedIndex
                property real jumpDistance: 1
                
                onIndexChanged: {
                    jumpDistance = Math.max(1, Math.abs(index - lastIndex));
                    lastIndex = index;
                }
                
                easingOvershoot: jumpDistance <= 1 ? 1.4 : Math.max(0.4, 1.4 / jumpDistance)
                index: root.selectedIndex
            }
            height: 3
            x: Math.min(idxPair.idx1, idxPair.idx2) * baseWidth + root.indicatorPadding
            width: ((Math.max(idxPair.idx1, idxPair.idx2) + 1) * baseWidth - root.indicatorPadding) - x
        }

        Rectangle { // Tabbar bottom border
            id: tabBarBottomBorder
            z: 9998
            anchors.bottom: parent.bottom
            height: 1
            anchors {
                left: parent.left
                right: parent.right
            }
            color: Appearance.colors.colOutlineVariant
        }
    }
}
