pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A phone live notification opened up from its glance: the app's icon, what it says
 * now, the line under it and its progress when it has one. A click opens the app on
 * the phone (scrcpy + adb, as for any phone notification). See PhoneLiveSource.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.phoneLive : null;
    }
    readonly property var live: root.source ? root.source.current : null
    readonly property string headline: root.live ? (root.live.critical || root.live.text || root.live.title) : ""
    readonly property string caption: {
        if (!root.live)
            return "";
        const parts = [root.live.appName];
        if (root.live.title && root.live.title !== root.headline)
            parts.push(root.live.title);
        return parts.join(" · ");
    }
    readonly property string detail: root.live ? ((root.live.lines ?? [])[0] ?? root.live.sub ?? "") : ""

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.live)
                KdeConnectService.openNotificationIntent(root.live.publicId);
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 18
        spacing: 12

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 12
            color: Appearance.colors.colLayer2
            clip: true

            Image {
                anchors.fill: parent
                source: root.live?.iconPath ? "file://" + root.live.iconPath : ""
                sourceSize: Qt.size(80, 80)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.live?.iconPath
                text: "smartphone"
                iconSize: 22
                color: Appearance.colors.colOnLayer2
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.caption
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: root.headline
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.detail
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer0
            }

            StyledProgressBar {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.preferredHeight: 3
                valueBarHeight: 3
                visible: (root.live?.progress ?? -1) >= 0
                value: Math.max(0, root.live?.progress ?? 0)
            }
        }
    }
}
