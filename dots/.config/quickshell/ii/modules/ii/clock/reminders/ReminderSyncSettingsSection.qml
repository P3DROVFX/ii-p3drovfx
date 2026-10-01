pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Microsoft To Do sync: the way Samsung Reminder reaches other devices. The phone turns
 * on Reminder → Settings → "Sync with Microsoft To Do"; this signs the desktop into the
 * same Microsoft account (the Outlook sign-in, with To Do access added) and keeps both
 * in step.
 */
ClockSettingsSection {
    id: root

    readonly property var options: Config.options.clockApp.reminders.todoSync
    property string clientIdDraft: OutlookService.clientId

    title: Translation.tr("Microsoft To Do sync")
    symbol: "cloud_sync"

    ClockSettingsRow {
        first: true
        last: !root.options.enable
        symbol: "sync"
        title: Translation.tr("Sync with Microsoft To Do")
        description: Translation.tr("On your phone, turn on Reminder → Settings → Sync with Microsoft To Do with the same account")

        StyledSwitch {
            checked: root.options.enable
            checkable: false
            onClicked: root.options.enable = !root.options.enable
        }
    }

    ClockSettingsRow {
        visible: root.options.enable
        symbol: OutlookService.authenticated && OutlookService.tasksConsented ? "verified_user" : "account_circle"
        title: OutlookService.authenticated
            ? (OutlookService.activeAccountEmail || Translation.tr("Signed in"))
            : Translation.tr("Not signed in")
        description: !OutlookService.authenticated
            ? Translation.tr("Sign in with the Microsoft account your phone syncs to")
            : OutlookService.tasksConsented
                ? (RemindersSync.lastError.length > 0 ? RemindersSync.lastError : RemindersSync.statusText)
                : Translation.tr("Sign in again once to let Reminders use To Do")

        ClockButton {
            visible: !OutlookService.deviceFlowActive
            variant: OutlookService.authenticated && OutlookService.tasksConsented ? "tonal" : "filled"
            symbol: OutlookService.authenticated && OutlookService.tasksConsented ? "sync" : "login"
            label: !OutlookService.authenticated ? Translation.tr("Sign in")
                : !OutlookService.tasksConsented ? Translation.tr("Grant access")
                : Translation.tr("Sync now")
            enabled: !RemindersSync.syncing && !OutlookService.authenticating && root.clientIdDraft.trim().length > 0
            onClicked: {
                if (OutlookService.authenticated && OutlookService.tasksConsented)
                    RemindersSync.syncNow();
                else
                    OutlookService.beginAuthorization(root.clientIdDraft);
            }
        }
    }

    // The device-code step: open the page, type the code.
    ClockSettingsRow {
        visible: root.options.enable && OutlookService.deviceFlowActive
        symbol: "pin"
        title: OutlookService.userCode
        description: Translation.tr("Open %1 and enter this code").arg(OutlookService.verificationUri)

        RowLayout {
            spacing: 4

            ClockIconButton {
                symbol: "content_copy"
                tooltip: Translation.tr("Copy code")
                onClicked: Quickshell.clipboardText = OutlookService.userCode
            }

            ClockButton {
                variant: "filled"
                symbol: "open_in_new"
                label: Translation.tr("Open")
                onClicked: Qt.openUrlExternally(OutlookService.verificationUri)
            }

            ClockIconButton {
                symbol: "close"
                tooltip: Translation.tr("Cancel")
                onClicked: OutlookService.cancelDeviceFlow()
            }
        }
    }

    // Without an app id there is nothing to sign in with; the Outlook calendar shares it.
    ClockSettingsRow {
        visible: root.options.enable && !OutlookService.authenticated && !OutlookService.deviceFlowActive
        symbol: "key"
        title: Translation.tr("Microsoft application (client) ID")
        description: Translation.tr("Shared with the Outlook calendar. Register an app in Microsoft Entra admin center, enable public client flows, and paste its client ID.")

        Rectangle {
            implicitWidth: 240
            implicitHeight: 40
            radius: ClockStyle.radiusSmall
            color: ClockStyle.colField

            StyledTextInput {
                id: clientField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                text: root.clientIdDraft
                color: ClockStyle.colOnSurface
                onTextEdited: root.clientIdDraft = clientField.text

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: clientField.text.length === 0
                    text: "00000000-0000-…"
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }
        }
    }

    ClockSettingsRow {
        visible: root.options.enable
        last: true
        symbol: "schedule"
        title: Translation.tr("Sync every")
        description: OutlookService.lastError.length > 0 && !OutlookService.authenticated ? OutlookService.lastError
            : Translation.tr("And a few seconds after every change")

        ClockStepper {
            value: root.options.intervalMinutes ?? 15
            from: 5
            to: 120
            stepSize: 5
            format: value => Translation.tr("%1 min").arg(String(value))
            onMoved: value => root.options.intervalMinutes = value
        }
    }
}
