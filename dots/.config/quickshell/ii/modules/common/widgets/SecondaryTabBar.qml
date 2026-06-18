import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.models

TabBar {
    id: root
    property real indicatorPadding: 8
    Layout.fillWidth: true

    background: Item {
        WheelHandler {
            onWheel: (event) => {
                if (event.angleDelta.y < 0) root.incrementCurrentIndex();
                else if (event.angleDelta.y > 0) root.decrementCurrentIndex();
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
                
                property real lastIndex: root.currentIndex
                property real jumpDistance: 1
                
                onIndexChanged: {
                    jumpDistance = Math.max(1, Math.abs(index - lastIndex));
                    lastIndex = index;
                }
                
                easingOvershoot: jumpDistance <= 1 ? 1.4 : Math.max(0.4, 1.4 / jumpDistance)
                index: root.currentIndex
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
