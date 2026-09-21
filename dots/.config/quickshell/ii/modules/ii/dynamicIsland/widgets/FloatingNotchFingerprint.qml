pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * "Touch the sensor": something is waiting on the fingerprint reader.
 *
 * The glyph is still while waiting - the request can last 30 s and nothing here needs a
 * frame per tick to say so - shakes once for a scan that did not count, and turns into a
 * green tick on a match, which is the moment the island exists to show.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.fingerprint : null;
    }
    readonly property string phase: root.source ? root.source.phase : "idle"
    readonly property bool matched: root.phase === "match"
    readonly property bool retrying: root.phase === "retry"

    readonly property color tint: root.matched ? "#34C759"
        : (root.retrying ? Appearance.colors.colError : Appearance.colors.colPrimary)

    onPhaseChanged: {
        if (root.retrying)
            shake.restart();
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 16
        spacing: 10

        Rectangle {
            id: badge
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(26, Math.min(34, root.height - 10))
            implicitHeight: implicitWidth
            radius: width / 2
            color: root.tint

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(badge)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.matched ? "check" : "fingerprint"
                fill: 1
                iconSize: Math.round(parent.width * 0.62)
                color: root.matched ? "#000000" : Appearance.colors.colOnPrimary
            }

            transform: Translate {
                id: shakeOffset
            }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeOffset; property: "x"; to: -5; duration: 50 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 5; duration: 70 }
                NumberAnimation { target: shakeOffset; property: "x"; to: -3; duration: 60 }
                NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 50 }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2

            StyledText {
                Layout.fillWidth: true
                text: root.matched ? Translation.tr("Authenticated")
                    : (root.retrying ? (root.source && root.source.hint !== "" ? root.source.hint
                        : Translation.tr("Not recognised · try again"))
                    : Translation.tr("Touch the fingerprint sensor"))
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.source ? root.source.requester : ""
                elide: Text.ElideMiddle
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
}
