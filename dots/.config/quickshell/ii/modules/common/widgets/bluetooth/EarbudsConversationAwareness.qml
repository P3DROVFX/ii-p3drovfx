pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

RowLayout {
    id: root

    property bool compact: false
    property bool enabled: false
    property bool available: true
    property string title: Translation.tr("Conversation Awareness")
    property string description: Translation.tr("Automatically lowers volume and enables ambient sound when speaking")

    signal toggled(bool enabled)

    Layout.fillWidth: true
    spacing: root.compact ? 8 : 12
    visible: root.available

    MaterialSymbol {
        text: "record_voice_over"
        iconSize: root.compact ? 18 : 22
        color: root.enabled ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: root.compact ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colOnSurface
            elide: Text.ElideRight
        }

        StyledText {
            visible: !root.compact && root.description.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.description
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    StyledSwitch {
        checked: root.enabled
        Layout.alignment: Qt.AlignVCenter
        onToggled: {
            root.toggled(checked);
        }
    }
}
