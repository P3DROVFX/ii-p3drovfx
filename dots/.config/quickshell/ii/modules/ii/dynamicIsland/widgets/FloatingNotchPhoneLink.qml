pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The phone's camera or microphone streaming into this computer.
 *
 * Contracted, it is only ever on screen for the moment a stream starts (see
 * PhoneLinkSource); the rest of the time it is a glance beside the clock or in a bubble.
 * Expanded is that bubble's card: each stream, with Stop.
 *
 * The services are only read from inside a row that exists because its stream is
 * running, which means the service already does.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    // The island's controller, found the way the other legacy faces find their host.
    // Absent in a bubble's card, which reads the flags directly.
    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.phoneLink : null;
    }
    readonly property string announcedKind: root.source ? root.source.announcedKind : ""

    readonly property var streams: [GlobalStates.phoneCameraRunning ? "camera" : "",
        GlobalStates.phoneMicRunning ? "microphone" : ""].filter(kind => kind !== "")
    readonly property real rowHeight: 40
    /**
     * Each stream's badge, camera first like the bubble's glyphs, so each glyph lands on
     * its own row (see AuxiliaryBubble's heroes).
     */
    readonly property var heroItems: {
        if (!root.isExpanded)
            return [];
        const badges = [];
        for (let i = 0; i < streamRows.count; i++)
            badges.push(streamRows.itemAt(i) ? streamRows.itemAt(i).badge : null);
        return badges;
    }
    readonly property real preferredExpandedHeight: 14 + 28
        + Math.max(1, root.streams.length) * root.rowHeight + 14

    function iconFor(kind) {
        return kind === "camera" ? "videocam" : "mic";
    }

    function labelFor(kind) {
        return kind === "camera" ? Translation.tr("Phone camera") : Translation.tr("Phone microphone");
    }

    function detailFor(kind) {
        return kind === "camera" ? Translation.tr("Streaming as a webcam")
            : Translation.tr("Streaming as an input");
    }

    // ── Contracted: a stream just started ────────────────────────────────────
    RowLayout {
        visible: !root.isExpanded
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 16
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(22, Math.min(30, root.height - 10))
            implicitHeight: implicitWidth
            radius: width / 2
            color: Appearance.colors.colPrimary

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.iconFor(root.announcedKind)
                fill: 1
                iconSize: Math.round(parent.width * 0.58)
                color: Appearance.colors.colOnPrimary
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("%1 · %2").arg(root.labelFor(root.announcedKind))
                .arg(root.detailFor(root.announcedKind))
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Expanded, in the bubble's card: each stream ──────────────────────────
    ColumnLayout {
        visible: root.isExpanded
        anchors.fill: parent
        anchors.margins: 14
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            text: Translation.tr("From your phone")
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }

        Repeater {
            id: streamRows
            model: root.streams

            RowLayout {
                id: row
                required property var modelData
                readonly property string kind: String(row.modelData)
                readonly property Item badge: streamBadge
                readonly property bool micMuted: row.kind === "microphone" && PhoneMicService.muted
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight
                spacing: 10

                Rectangle {
                    id: streamBadge
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 14
                    color: Appearance.colors.colPrimary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: row.micMuted ? "mic_off" : root.iconFor(row.kind)
                        fill: 1
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.labelFor(row.kind)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.micMuted ? Translation.tr("Muted") : root.detailFor(row.kind)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: stopLabel.implicitWidth + 24
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: {
                        if (row.kind === "camera")
                            PhoneCameraService.stopCamera();
                        else
                            PhoneMicService.stopMic();
                    }

                    contentItem: StyledText {
                        id: stopLabel
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Stop")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }
}
