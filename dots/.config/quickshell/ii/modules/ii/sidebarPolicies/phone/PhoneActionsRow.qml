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

    property int entranceTrigger: -1
    onEntranceTriggerChanged: {
        if (entranceTrigger >= 0) {
            btn1.opacity = 0; btn1Transform.y = 15; btn1.scale = 0.8
            btn2.opacity = 0; btn2Transform.y = 15; btn2.scale = 0.8
            btn3.opacity = 0; btn3Transform.y = 15; btn3.scale = 0.8
            btn4.opacity = 0; btn4Transform.y = 15; btn4.scale = 0.8
            btn5.opacity = 0; btn5Transform.y = 15; btn5.scale = 0.8
            btn6.opacity = 0; btn6Transform.y = 15; btn6.scale = 0.8

            Qt.callLater(function() {
                actionsEntranceAnim.stop()
                actionsEntranceAnim.start()
            })
        }
    }

    ParallelAnimation {
        id: actionsEntranceAnim

        SequentialAnimation {
            PauseAnimation { duration: 60 }
            ParallelAnimation {
                NumberAnimation { target: btn1; property: "opacity"; to: (btn1.enabled ? 1.0 : 0.4); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: btn1Transform; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                NumberAnimation { target: btn1; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            ParallelAnimation {
                NumberAnimation { target: btn2; property: "opacity"; to: (btn2.enabled ? 1.0 : 0.4); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: btn2Transform; property: "y"; to: 0; duration: 400; easing.type: Easing.OutExpo }
                NumberAnimation { target: btn2; property: "scale"; to: 1.0; duration: 400; easing.type: Easing.OutExpo }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            ParallelAnimation {
                NumberAnimation { target: btn3; property: "opacity"; to: (btn3.enabled ? 1.0 : 0.4); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: btn3Transform; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                NumberAnimation { target: btn3; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            ParallelAnimation {
                NumberAnimation { target: btn4; property: "opacity"; to: (btn4.enabled ? 1.0 : 0.4); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: btn4Transform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                NumberAnimation { target: btn4; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutCubic }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            ParallelAnimation {
                NumberAnimation { target: btn5; property: "opacity"; to: (btn5.enabled ? 1.0 : 0.4); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: btn5Transform; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                NumberAnimation { target: btn5; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 210 }
            ParallelAnimation {
                NumberAnimation { target: btn6; property: "opacity"; to: (btn6.enabled ? 1.0 : 0.4); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: btn6Transform; property: "y"; to: 0; duration: 400; easing.type: Easing.OutExpo }
                NumberAnimation { target: btn6; property: "scale"; to: 1.0; duration: 400; easing.type: Easing.OutExpo }
            }
        }
    }

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
            id: btn1
            anchors.verticalCenter: parent.verticalCenter
            iconName: "phone_in_talk"
            toolTipText: Translation.tr("Ring phone")
            enabled: root._has("kdeconnect_findmyphone")
            transform: Translate { id: btn1Transform; y: 0 }
            onClicked: {
                KdeConnectService.findMyPhone(root._devId)
                root._feedback(Translation.tr("Ringing phone…"), true)
            }
        }

        // Ping
        ActionIconButton {
            id: btn2
            anchors.verticalCenter: parent.verticalCenter
            iconName: "notifications_active"
            toolTipText: Translation.tr("Send a ping")
            enabled: root._has("kdeconnect_ping")
            transform: Translate { id: btn2Transform; y: 0 }
            onClicked: {
                KdeConnectService.sendPing(root._devId,
                    Translation.tr("Ping from ii"))
                root._feedback(Translation.tr("Ping sent"), true)
            }
        }

        // Send clipboard
        ActionIconButton {
            id: btn3
            anchors.verticalCenter: parent.verticalCenter
            iconName: "content_paste"
            toolTipText: Translation.tr("Send clipboard to phone")
            enabled: root._has("kdeconnect_clipboard")
            transform: Translate { id: btn3Transform; y: 0 }
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
            id: btn4
            anchors.verticalCenter: parent.verticalCenter
            iconName: "file_upload"
            toolTipText: Translation.tr("Send file…")
            enabled: root._has("kdeconnect_share")
            transform: Translate { id: btn4Transform; y: 0 }
            onClicked: {
                KdeConnectService.sendFile(root._devId)
                root._feedback(Translation.tr("Pick a file to send…"), true)
            }
        }

        // Send current clipboard as URL/text
        ActionIconButton {
            id: btn5
            anchors.verticalCenter: parent.verticalCenter
            iconName: "link"
            toolTipText: Translation.tr("Share desktop clipboard as link/text")
            enabled: root._has("kdeconnect_share") && Quickshell.clipboardText.length > 0
            transform: Translate { id: btn5Transform; y: 0 }
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
            id: btn6
            anchors.verticalCenter: parent.verticalCenter
            iconName: "folder_shared"
            toolTipText: Translation.tr("Browse phone files (SFTP)")
            enabled: root._has("kdeconnect_sftp")
            transform: Translate { id: btn6Transform; y: 0 }
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

        opacity: 0
        scale: 0.8

        // Springy "press" pop on hover/press for a more connected feel.
        Behavior on scale {
            enabled: !actionsEntranceAnim.running
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
