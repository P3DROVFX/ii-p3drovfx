import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    implicitHeight: layout.implicitHeight + 28
    Layout.fillWidth: true

    readonly property bool isEnabled: TouchGestureService.enabled
    readonly property string status: TouchGestureService.helperStatus
    readonly property var devices: TouchGestureService.devices

    readonly property string statusIcon: {
        if (!isEnabled) return "do_not_disturb_on";
        if (status === "ready") return "check_circle";
        if (status === "no_touchscreen") return "touch_app";
        if (status === "permission_denied") return "security";
        if (status === "stopped") return "pause_circle";
        return "error";
    }

    readonly property color statusColor: {
        if (!isEnabled) return Appearance.colors.colSubtext;
        if (status === "ready") return Appearance.colors.colSuccess ? Appearance.colors.colSuccess : Appearance.m3colors.m3primary;
        if (status === "no_touchscreen") return Appearance.colors.colWarning ? Appearance.colors.colWarning : Appearance.colors.colSubtext;
        if (status === "permission_denied") return Appearance.colors.colWarning ? Appearance.colors.colWarning : Appearance.colors.colSubtext;
        return Appearance.colors.colError ? Appearance.colors.colError : Appearance.colors.colSubtext;
    }

    readonly property string statusTitle: {
        if (!isEnabled) return Translation.tr("Touchscreen gestures are disabled");
        if (status === "ready") {
            if (devices && devices.length === 1) return (devices[0] && devices[0].name) ? devices[0].name : Translation.tr("Touchscreen connected");
            if (devices && devices.length > 1) return Translation.tr("%1 touchscreen devices active").arg(String(devices.length));
            return Translation.tr("Touchscreen ready");
        }
        if (status === "permission_denied") return Translation.tr("Input permission required (add user to 'input' group)");
        if (status === "no_touchscreen") return Translation.tr("No physical or absolute touchscreen detected");
        if (status === "error") return Translation.tr("Helper error: %1").arg(TouchGestureService.helperError ? TouchGestureService.helperError : "unknown");
        return Translation.tr("Helper status: %1").arg(status);
    }

    readonly property string statusSubtitle: {
        if (!isEnabled) return Translation.tr("Enable gestures to start the input helper daemon");
        if (status === "ready") {
            if (devices && devices.length > 0) return Translation.tr("Observing input passively via evdev (no exclusive grab)");
            return Translation.tr("Helper running, waiting for touchscreen events");
        }
        if (status === "permission_denied") return Translation.tr("Run: sudo usermod -aG input $USER (then log out and log back in)");
        if (status === "no_touchscreen") return Translation.tr("Gestures require a direct touchscreen or Sunshine absolute pointer");
        return "";
    }

    RowLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 14

        Rectangle {
            implicitWidth: 42
            implicitHeight: 42
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3
            Layout.alignment: Qt.AlignVCenter

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.larger
                text: root.statusIcon
                color: root.statusColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                text: root.statusTitle
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            StyledText {
                visible: root.statusSubtitle !== ""
                text: root.statusSubtitle
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }
}
