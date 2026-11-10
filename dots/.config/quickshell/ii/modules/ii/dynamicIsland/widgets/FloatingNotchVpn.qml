pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** "Tailscale connected · exit node" / "VPN disconnected", for a moment. */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.vpn : null;
    }
    readonly property var event: root.source ? root.source.payload : null
    readonly property bool connected: !!root.event && root.event.connected === true

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 16
        spacing: 10

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.connected ? "vpn_lock" : "vpn_key_off"
            fill: 1
            iconSize: 20
            color: root.connected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: {
                if (!root.event)
                    return "";
                const state = root.connected ? Translation.tr("%1 connected").arg(root.event.provider)
                    : Translation.tr("%1 disconnected").arg(root.event.provider);
                return root.connected && root.event.detail ? state + " · " + root.event.detail : state;
            }
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }
}
