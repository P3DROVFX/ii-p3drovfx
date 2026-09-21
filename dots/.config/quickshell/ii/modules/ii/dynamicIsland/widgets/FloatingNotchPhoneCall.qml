pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A call on the paired phone, in the island's centre.
 *
 * Ringing: who is calling, with Decline, Silence and Answer - the phone's own layout,
 * red on the left and green on the right. A missed call is one line. A call in progress
 * lives beside the clock instead (see NotchRestingFace), so it is only drawn here if
 * the island is showing it in the centre for some other reason.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.phoneCall : null;
    }
    readonly property string phase: root.source ? root.source.phase : PhoneCallService.callState
    readonly property bool ringing: root.phase === "ringing"
    /** Without ADB the buttons cannot reach the phone; say so instead of pretending. */
    readonly property bool canAct: PhoneCallService.adbLive || PhoneCallService._simulated

    readonly property color acceptColor: "#34C759"
    readonly property color declineColor: "#FF453A"

    // ── Ringing and in progress ──────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12
        visible: root.phase !== "missed"

        // The caller's photo, else their initial on the accept colour.
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.min(48, root.height - 20)
            implicitHeight: implicitWidth

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Appearance.colors.colLayer2
                visible: avatar.status !== Image.Ready

                StyledText {
                    anchors.centerIn: parent
                    text: PhoneCallService.displayName.charAt(0).toUpperCase()
                    font.pixelSize: Math.round(parent.width * 0.42)
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer2
                }
            }

            StyledImage {
                id: avatar
                anchors.fill: parent
                source: PhoneCallService.avatarPath !== "" ? "file://" + PhoneCallService.avatarPath : ""
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectCrop
                visible: false
            }

            Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: avatar.status === Image.Ready
            }

            MultiEffect {
                anchors.fill: parent
                source: avatar
                visible: avatar.status === Image.Ready
                maskEnabled: true
                maskSource: avatarMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: PhoneCallService.displayName
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                text: !root.ringing ? Translation.tr("On a call")
                    : (root.canAct ? Translation.tr("Incoming call")
                        : Translation.tr("Incoming call · answer on the phone"))
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        CallButton {
            visible: root.canAct
            iconName: "call_end"
            fillColor: root.declineColor
            onTriggered: PhoneCallService.decline()
        }

        CallButton {
            visible: root.ringing && root.canAct
            iconName: "notifications_off"
            fillColor: Appearance.colors.colLayer2
            glyphColor: Appearance.colors.colOnLayer2
            onTriggered: PhoneCallService.silence()
        }

        CallButton {
            visible: root.ringing && root.canAct
            iconName: "call"
            fillColor: root.acceptColor
            onTriggered: PhoneCallService.answer()
        }
    }

    // ── Missed ───────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 16
        spacing: 10
        visible: root.phase === "missed"

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "phone_missed"
            iconSize: 20
            color: root.declineColor
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("Missed call · %1").arg(root.source ? root.source.missedName : "")
            elide: Text.ElideRight
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    component CallButton: RippleButton {
        id: button
        required property string iconName
        required property color fillColor
        property color glyphColor: "#FFFFFF"
        signal triggered()

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 40
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        colBackground: button.fillColor
        colBackgroundHover: Qt.lighter(button.fillColor, 1.12)
        colRipple: Qt.darker(button.fillColor, 1.15)
        onClicked: button.triggered()

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: button.iconName
            fill: 1
            iconSize: 20
            color: button.glyphColor
        }
    }
}
