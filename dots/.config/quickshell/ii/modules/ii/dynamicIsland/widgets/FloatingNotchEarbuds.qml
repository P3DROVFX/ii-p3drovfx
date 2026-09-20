import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The earbuds activity when it takes the island's centre instead of sitting on the
 * resting face's end — which is what happens with the auxiliary bubble on, since
 * side glances and bubbles are mutually exclusive. Same glance, pill-sized: the
 * device's own picture when Settings has one, the headphones glyph otherwise.
 */
RowLayout {
    id: root
    anchors.fill: parent
    anchors.leftMargin: 14
    anchors.rightMargin: 14
    spacing: 2

    // The group is centred, the way the other announcement faces are.
    Item {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
    }

    Image {
        id: deviceImage
        Layout.alignment: Qt.AlignVCenter
        source: EarbudsControlService.glanceDevice
            ? BluetoothDeviceImages.sourceFor(EarbudsControlService.glanceDevice) : ""
        sourceSize: Qt.size(18, 18)
        Layout.preferredWidth: 18
        Layout.preferredHeight: 18
        visible: status === Image.Ready
    }

    MaterialSymbol {
        Layout.alignment: Qt.AlignVCenter
        text: "headphones"
        iconSize: 18
        color: Appearance.colors.colOnSurface
        visible: deviceImage.status !== Image.Ready
    }

    StyledText {
        Layout.alignment: Qt.AlignVCenter
        text: Math.max(0, EarbudsControlService.glancePercent) + "%"
        font.pixelSize: Appearance.font.pixelSize.small
        font.bold: true
        color: Appearance.colors.colOnSurface
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
    }
}
