pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Row of icon-only M3-shaped action buttons at the top of the Phone tab.
 *
 * Each button is a single `RippleButton` with `buttonRadius: Appearance.rounding.full`
 * (circular pill shape on `colPrimaryContainer`). The icon is a plain
 * `MaterialSymbol` placed directly inside `contentItem` — no `MaterialShape`
 * wrapping, no double shape. The ripple itself is the M3 surface.
 *
 * Feedback after click: a brief opacity flash + `fill: 1` toggle so the user
 * sees the action was sent. A toast is dispatched via `phoneActionFeedback`
 * signal on the service, surfaced inside the Phone page.
 */
Item {
    id: root
    implicitHeight: actionsRow.implicitHeight + 16
    height: implicitHeight

    readonly property string _devId: KdeConnectService.activeDeviceId || ""
    readonly property var _plugins: KdeConnectService.activeDevice
        ? (KdeConnectService.activeDevice.supportedPlugins || [])
        : []

    function _has(plugin) {
        if (!KdeConnectService.activeReachable) return false
        return _plugins.indexOf(plugin) >= 0
    }

    function _feedback(message, ok) {
        KdeConnectService.dispatchActionFeedback(message, ok)
    }

    Row {
        id: actionsRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Find My Phone
        ActionIconButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "phone_in_talk"
            toolTipText: Translation.tr("Ring phone")
            enabled: root._has("kdeconnect_findmyphone")
            onClicked: {
                KdeConnectService.findMyPhone(root._devId)
                root._feedback(Translation.tr("Ringing phone…"), true)
            }
        }

        // Ping
        ActionIconButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "notifications_active"
            toolTipText: Translation.tr("Send a ping")
            enabled: root._has("kdeconnect_ping")
            onClicked: {
                KdeConnectService.sendPing(root._devId,
                    Translation.tr("Ping from ii"))
                root._feedback(Translation.tr("Ping sent"), true)
            }
        }

        // Send clipboard
        ActionIconButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "content_paste"
            toolTipText: Translation.tr("Send clipboard to phone")
            enabled: root._has("kdeconnect_clipboard")
            onClicked: {
                if (Quickshell.clipboardText.length > 0) {
                    KdeConnectService.sendClipboard(root._devId)
                    root._feedback(Translation.tr("Clipboard shared"), true)
                } else {
                    root._feedback(Translation.tr("Clipboard is empty"), false)
                }
            }
        }

        // Send file
        ActionIconButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "file_upload"
            toolTipText: Translation.tr("Send file…")
            enabled: root._has("kdeconnect_share")
            onClicked: {
                KdeConnectService.sendFile(root._devId)
                root._feedback(Translation.tr("Pick a file to send…"), true)
            }
        }

        // Send current clipboard as URL/text
        ActionIconButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "link"
            toolTipText: Translation.tr("Share desktop clipboard as link/text")
            enabled: root._has("kdeconnect_share") && Quickshell.clipboardText.length > 0
            onClicked: {
                const clip = String(Quickshell.clipboardText).trim()
                if (!clip) {
                    root._feedback(Translation.tr("Clipboard is empty"), false)
                    return
                }
                const looksUrl = /^https?:\/\//i.test(clip)
                    || /^[\w.-]+\.\w{2,}/.test(clip)
                if (looksUrl) {
                    KdeConnectService.shareUrl(root._devId, clip)
                    root._feedback(Translation.tr("Link shared"), true)
                } else {
                    KdeConnectService.shareText(root._devId, clip)
                    root._feedback(Translation.tr("Text shared"), true)
                }
            }
        }

        // Browse files (SFTP)
        ActionIconButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: "folder_shared"
            toolTipText: Translation.tr("Browse phone files (SFTP)")
            enabled: root._has("kdeconnect_sftp")
            onClicked: {
                KdeConnectService.browseFiles(root._devId)
                root._feedback(Translation.tr("Mounting SFTP storage…"), true)
            }
        }
    }

    // ─── Reusable circular icon-only button ──────────────────────────
    component ActionIconButton: RippleButton {
        id: btn
        property string iconName: ""
        property string toolTipText: ""
        property bool feedbackFlash: false

        implicitWidth: 44
        implicitHeight: 44
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colPrimaryContainer
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        colRipple: Appearance.colors.colPrimaryContainerActive

        opacity: enabled ? 1.0 : 0.4

        // Springy "press" pop on hover/press for a more connected feel.
        scale: down ? 0.92 : (hovered ? 1.09 : 1.0)
        Behavior on scale {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutBack
                easing.overshoot: 1.7
            }
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: btn.iconName
            iconSize: 22
            color: Appearance.colors.colOnPrimaryContainer
            // Animate the icon fill (0 -> 1) — Material Symbols supports this
            // natively without needing a `Behavior on text` swap that would
            // leak intermediate non-existent glyph strings during animation.
            fill: btn.feedbackFlash ? 1.0 : 0.0
            animateChange: true

            Behavior on fill {
                NumberAnimation {
                    duration: 300
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        // Press feedback: brief icon "fill" flash, then return
        onPressed: {
            btn.feedbackFlash = true
            flashResetTimer.restart()
        }
        Timer {
            id: flashResetTimer
            interval: 800
            repeat: false
            onTriggered: btn.feedbackFlash = false
        }

        StyledToolTip {
            text: btn.toolTipText
        }
    }
}
