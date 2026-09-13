import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int currentIndex: 0
    property bool expanded: false
    property bool _isInitialized: false
    property real spacing: 0
    Component.onCompleted: _isInitialized = true

    default property alias tabData: tabBarColumn.data  

    implicitHeight: tabBarColumn.implicitHeight
    implicitWidth: tabBarColumn.implicitWidth
    Layout.topMargin: 25

    Rectangle {
        id: tabBarHighlight
        visible: root.currentIndex >= 0
        property real itemHeight: tabBarColumn.children[0]?.baseSize ?? 56
        property real baseHighlightHeight: tabBarColumn.children[0]?.baseHighlightHeight ?? 56
        anchors {
            top: tabBarColumn.top
            left: tabBarColumn.left
            topMargin: root.itemTopOffset(root.currentIndex)
        }
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        implicitHeight: root.expanded ? itemHeight : baseHighlightHeight
        implicitWidth: {
            let child = root.currentIndex >= 0 ? tabBarColumn.children[root.currentIndex] : null;
            if (child && child.visualWidth !== undefined) {
                return child.visualWidth;
            }
            return root.expanded ? 130 : 56;
        }

        Behavior on implicitWidth {
            enabled: root._isInitialized

            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        Behavior on anchors.topMargin {
            enabled: root._isInitialized

            NumberAnimation {
                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
    }

    ColumnLayout {
        id: tabBarColumn
        anchors.fill: parent
        spacing: root.spacing
    }

    function itemTopOffset(index) {
        if (index < 0) return 0;

        let offset = 0;
        const childCount = Math.min(index, tabBarColumn.children.length);
        for (let i = 0; i < childCount; i++) {
            const child = tabBarColumn.children[i];
            offset += Number(child.Layout.topMargin) || 0;
            offset += child.implicitHeight;
            offset += Number(child.Layout.bottomMargin) || 0;
            offset += root.spacing;
        }

        if (index < tabBarColumn.children.length) {
            offset += Number(tabBarColumn.children[index].Layout.topMargin) || 0;
        }

        return offset + (root.expanded ? 0 : ((tabBarHighlight.itemHeight - tabBarHighlight.baseHighlightHeight) / 2));
    }
}
