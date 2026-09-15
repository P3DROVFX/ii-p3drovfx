pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common

Item {
    id: root
    property int count: 18
    property real thickness: 3
    property real gap: 2
    property real extent: 18
    property color color: Appearance.colors.colPrimary
    property bool running: false

    implicitWidth: root.count * root.thickness + (root.count - 1) * root.gap
    implicitHeight: root.extent

    function level(i) {
        const src = CavaService.visualizerPoints;
        const n = src.length;
        if (n === 0)
            return 0;
        const per = n / root.count;
        const a = Math.floor(i * per);
        const b = Math.max(a + 1, Math.floor((i + 1) * per));
        let m = 0;
        for (let k = a; k < b; k++)
            m = Math.max(m, src[k] ?? 0);
        return m;
    }

    Row {
        anchors.centerIn: parent
        height: root.extent
        spacing: root.gap

        Repeater {
            model: root.count
            delegate: Rectangle {
                required property int index
                width: root.thickness
                radius: root.thickness / 2
                color: root.color
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(2, root.level(index) * root.extent)
                Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
        }
    }
}
