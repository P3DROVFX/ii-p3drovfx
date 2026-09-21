pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../core/PhoneMirror.js" as PhoneMirror

/**
 * The phone mirrored into a scrcpy window: the full screen, or one app.
 *
 * Contracted, it is only ever on screen for the moment a session opens (see
 * PhoneMirrorSource); the rest of the time it is a glance beside the clock or in a
 * bubble. Expanded is that bubble's card: each window, with Show and Stop.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    // The island's controller, found the way the other legacy faces find their host.
    // Absent in a bubble's card, which reads the window list directly.
    readonly property var source: {
        let node = root.parent;
        while (node && !node.hasOwnProperty("controller"))
            node = node.parent;
        return node && node.controller ? node.controller.sources.phoneMirror : null;
    }
    readonly property var announced: root.source ? root.source.announced : null

    readonly property var sessions: root.source ? root.source.sessions
        : PhoneMirror.sessionsFrom(HyprlandData.windowList)
    readonly property real rowHeight: 40
    readonly property real preferredExpandedHeight: 14 + 28
        + Math.max(1, root.sessions.length) * root.rowHeight + 14

    function labelFor(session) {
        if (!session)
            return "";
        return session.kind === "mirror" ? Translation.tr("Phone screen") : PhoneMirror.appLabel(session.package);
    }

    function detailFor(session) {
        if (!session)
            return "";
        return Translation.tr("Mirrored on workspace %1").arg(session.workspace);
    }

    /** Raises the window, switching to its workspace. */
    function show(session) {
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${session.address}" })`);
    }

    /**
     * Through the session manager when this shell started the session, so it is not
     * mistaken for a drop and reopened; closing the window otherwise (a session left
     * over from before a reload, which the manager no longer owns).
     */
    function stop(session) {
        const owned = (PhoneScrcpyService.sessions ?? []).some(live =>
            live.id === (session.kind === "mirror" ? "mirror" : "app:" + session.package));
        if (!owned)
            Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${session.address}" })`);
        else if (session.kind === "mirror")
            PhoneScrcpyService.stopMirror();
        else
            PhoneScrcpyService.stopApp(session.package);
    }

    // ── Contracted: a session just opened ────────────────────────────────────
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
                text: "mobile_screen_share"
                fill: 1
                iconSize: Math.round(parent.width * 0.58)
                color: Appearance.colors.colOnPrimary
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("%1 · %2").arg(root.labelFor(root.announced)).arg(root.detailFor(root.announced))
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Expanded, in the bubble's card: each window ──────────────────────────
    ColumnLayout {
        visible: root.isExpanded
        anchors.fill: parent
        anchors.margins: 14
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            text: Translation.tr("Phone mirror")
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }

        Repeater {
            model: root.sessions

            RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 14
                    color: Appearance.colors.colPrimary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: row.modelData.kind === "mirror" ? "mobile_screen_share" : "apps"
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
                        text: root.labelFor(row.modelData)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.detailFor(row.modelData)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                CardButton {
                    label: Translation.tr("Show")
                    onClicked: root.show(row.modelData)
                }

                CardButton {
                    label: Translation.tr("Stop")
                    onClicked: root.stop(row.modelData)
                }
            }
        }
    }

    component CardButton: RippleButton {
        id: button
        property string label: ""
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: buttonLabel.implicitWidth + 24
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        contentItem: StyledText {
            id: buttonLabel
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: button.label
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer2
        }
    }
}
