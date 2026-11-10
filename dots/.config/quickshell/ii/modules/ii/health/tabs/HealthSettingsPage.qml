pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.health.components

/**
 * Every System Health option: alerts, what to watch, the noise model, thresholds, the
 * assistant, and the helper with its one privileged extra — read access to system crash
 * dumps. Writes go straight to Config; the helper restarts with the new values.
 *
 * The last section is the start guard (scripts/quickshell-guard), which works when the
 * shell itself does not: its switches are read from config.json at the next start, and
 * its pacman hook is installed through pkexec like the crash-dump grant.
 */
Rectangle {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width

    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property real contentWidth: Math.min(root.layoutWidth - root.padding * 2, root.wide ? 1240 : ClockStyle.sheetMaxWidth * 1.3)
    readonly property var h: Config.options.health

    property bool confirmGrant: false
    property bool confirmReset: false

    color: ClockStyle.colBackground

    component Toggle: StyledSwitch {
        property var target
        property string key
        checked: Boolean(target?.[key])
        checkable: false
        onClicked: target[key] = !target[key]
    }

    component Stepper: ClockStepper {
        property var target
        property string key
        value: Number(target?.[key] ?? 0)
        onMoved: v => target[key] = v
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 3
        clip: true

        GridLayout {
            id: column
            x: (flick.width - width) / 2
            y: ClockStyle.gapSmall
            width: root.contentWidth
            columns: root.wide ? 2 : 1
            columnSpacing: ClockStyle.gapHuge
            rowSpacing: ClockStyle.gapHuge
            uniformCellWidths: true

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Alerts")
                symbol: "notifications"

                ClockSettingsRow {
                    first: true
                    symbol: "smart_display"
                    title: Translation.tr("Island alert for new problems")
                    description: Translation.tr("A strip with the fix as its button, for a service that failed or a program that crashed")
                    Toggle { target: root.h.alerts; key: "island" }
                }
                ClockSettingsRow {
                    symbol: "notifications"
                    title: Translation.tr("Notification when the island is off")
                    Toggle { target: root.h.alerts; key: "notifyFallback" }
                }
                ClockSettingsRow {
                    symbol: "fullscreen"
                    title: Translation.tr("Hold alerts in fullscreen and Do Not Disturb")
                    description: Translation.tr("They arrive as one summary when you leave")
                    Toggle { target: root.h.alerts; key: "holdInFullscreen" }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "speed"
                    title: Translation.tr("At most, every 10 minutes")
                    description: Translation.tr("More fold into one summary")
                    Stepper { target: root.h.alerts; key: "maxPer10Min"; from: 1; to: 10 }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("What to watch")
                symbol: "visibility"

                Repeater {
                    model: [
                        { key: "units", symbol: "settings_alert", title: Translation.tr("System services") },
                        { key: "userUnits", symbol: "person", title: Translation.tr("Your services") },
                        { key: "appLaunches", symbol: "rocket_launch", title: Translation.tr("App launches that fail") },
                        { key: "crashes", symbol: "heart_broken", title: Translation.tr("Crashes") },
                        { key: "journal", symbol: "receipt_long", title: Translation.tr("New journal errors") },
                        { key: "drives", symbol: "storage", title: Translation.tr("Drive health (SMART)") },
                        { key: "filesystems", symbol: "hard_drive", title: Translation.tr("Free space") },
                        { key: "firmware", symbol: "memory", title: Translation.tr("Firmware and platform security") },
                        { key: "packages", symbol: "package_2", title: Translation.tr("Update chores") },
                        { key: "pressure", symbol: "speed", title: Translation.tr("Memory and disk pressure") },
                        { key: "thermals", symbol: "device_thermostat", title: Translation.tr("Throttling") },
                        { key: "timesync", symbol: "schedule", title: Translation.tr("Clock synchronisation") },
                        { key: "rebuild", symbol: "construction", title: Translation.tr("Packages that need a rebuild") },
                        { key: "shell", symbol: "deployed_code", title: Translation.tr("The shell's helpers and memory") },
                        { key: "boot", symbol: "timer", title: Translation.tr("Boot time") },
                        { key: "hardware", symbol: "developer_board", title: Translation.tr("Battery, GPU, memory and other hardware") },
                        { key: "shellLog", symbol: "bug_report", title: Translation.tr("QML errors in the shell's log"),
                          description: Translation.tr("Keeps a log reader of about 50 MB running") }
                    ]

                    ClockSettingsRow {
                        required property var modelData
                        required property int index
                        first: index === 0
                        last: index === 16
                        symbol: modelData.symbol
                        title: modelData.title
                        description: modelData.description ?? ""
                        Toggle { target: root.h.sources; key: modelData.key }
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Noise")
                symbol: "volume_off"

                ClockSettingsRow {
                    first: true
                    symbol: "event_repeat"
                    title: Translation.tr("Known after this many boots")
                    description: Translation.tr("An error group seen this often never alerts")
                    Stepper { target: root.h.noise; key: "knownAfterBoots"; from: 1; to: root.h.noise.ofLastBoots }
                }
                ClockSettingsRow {
                    symbol: "history"
                    title: Translation.tr("Out of the last boots")
                    Stepper { target: root.h.noise; key: "ofLastBoots"; from: 2; to: 20 }
                }
                ClockSettingsRow {
                    symbol: "hourglass_empty"
                    title: Translation.tr("New again after a quiet spell of")
                    Stepper { target: root.h.noise; key: "quietDaysForNew"; from: 1; to: 90; format: v => Translation.tr("%1 d").arg(v) }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "restart_alt"
                    title: Translation.tr("Forget mutes and known groups")
                    description: root.confirmReset ? Translation.tr("Press again: every mute and dismissal goes, and the baseline is rebuilt") : Translation.tr("Rebuilds the baseline from the boots the journal still has")
                    ClockButton {
                        label: root.confirmReset ? Translation.tr("Forget") : Translation.tr("Reset")
                        danger: root.confirmReset
                        onClicked: {
                            if (!root.confirmReset) {
                                root.confirmReset = true;
                                return;
                            }
                            root.confirmReset = false;
                            HealthService.resetNoise();
                        }
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Thresholds")
                symbol: "tune"

                ClockSettingsRow {
                    first: true
                    symbol: "hard_drive"
                    title: Translation.tr("Warn when a disk is this full")
                    Stepper { target: root.h.thresholds; key: "diskWarnPercent"; from: 50; to: root.h.thresholds.diskCritPercent - 1; format: v => `${v} %` }
                }
                ClockSettingsRow {
                    symbol: "error"
                    title: Translation.tr("Critical when a disk is this full")
                    Stepper { target: root.h.thresholds; key: "diskCritPercent"; from: root.h.thresholds.diskWarnPercent + 1; to: 99; format: v => `${v} %` }
                }
                ClockSettingsRow {
                    symbol: "memory"
                    title: Translation.tr("Memory stall to warn at")
                    description: Translation.tr("Share of the last minute spent waiting for memory")
                    Stepper { target: root.h.thresholds; key: "psiMemPercent"; from: 1; to: 80; format: v => `${v} %` }
                }
                ClockSettingsRow {
                    symbol: "autorenew"
                    title: Translation.tr("A restart loop is this many restarts")
                    description: Translation.tr("Within 10 minutes")
                    Stepper { target: root.h.thresholds; key: "restartLoop"; from: 2; to: 50 }
                }
                ClockSettingsRow {
                    symbol: "battery_horiz_050"
                    title: Translation.tr("Battery health to warn below")
                    description: Translation.tr("Full charge against its design; 20 points lower is critical")
                    Stepper { target: root.h.thresholds; key: "batteryWearPercent"; from: 40; to: 95; stepSize: 5; format: v => `${v} %` }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "memory_alt"
                    title: Translation.tr("The shell's memory to warn at")
                    description: Translation.tr("Or 600 MB more than in its first hour")
                    Stepper { target: root.h.thresholds; key: "shellMemoryMb"; from: 400; to: 8000; stepSize: 100; format: v => Translation.tr("%1 MB").arg(v) }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Assistant")
                symbol: "auto_awesome"

                ClockSettingsRow {
                    first: true
                    symbol: "auto_awesome"
                    title: Translation.tr("Explain with the assistant")
                    description: SearchPanelRegistry.aiPolicyEnabled
                        ? Translation.tr("Shows the ✦ button. Nothing is sent until you press it.")
                        : Translation.tr("AI is off for the whole shell, so the button stays hidden.")
                    Toggle { target: root.h.assistant; key: "enable" }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "visibility_off"
                    title: Translation.tr("Redact before sending")
                    description: Translation.tr("User and host names, the home path, IP and MAC addresses. Crash dumps are never sent.")
                    Toggle { target: root.h.assistant; key: "redact" }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("Helper and access")
                symbol: "build"

                ClockSettingsRow {
                    first: true
                    symbol: "deployed_code"
                    title: "health_watch"
                    description: HealthService.helperBuild.building ? (HealthService.helperBuild.progressText || Translation.tr("Building…"))
                        : HealthService.helperBuild.buildResult === "failed" ? Translation.tr("The build failed: %1").arg(HealthService.helperBuild.failureSummary?.(HealthService.helperBuild.buildOutput.split("\n")) ?? "")
                        : !HealthService.binaryPresent ? Translation.tr("Not built yet")
                        : HealthService.helperBuild.outdated ? Translation.tr("Built from older sources; rebuild to get the fixes")
                        : HealthService.running ? Translation.tr("Running") : Translation.tr("Stopped")
                    ClockButton {
                        visible: HealthService.helperBuild.cargoAvailable && (HealthService.helperBuild.outdated || !HealthService.binaryPresent || HealthService.helperBuild.buildResult === "failed")
                        enabled: !HealthService.helperBuild.building
                        label: HealthService.binaryPresent ? Translation.tr("Rebuild") : Translation.tr("Build")
                        symbol: "build"
                        onClicked: HealthService.helperBuild.build()
                    }
                }
                ClockSettingsRow {
                    symbol: "receipt_long"
                    title: Translation.tr("Journal access")
                    description: HealthService.journalAccess === "full" ? Translation.tr("The whole system's journal is readable")
                        : HealthService.journalAccess === "user" ? Translation.tr("Only your own. Join the systemd-journal group for the rest.")
                        : Translation.tr("Unknown until the helper runs")
                }
                ClockSettingsRow {
                    symbol: "lock_open"
                    title: Translation.tr("Read system crash dumps")
                    description: HealthService.accessBusy ? Translation.tr("Waiting for the password…")
                        : HealthService.accessError === "cancelled" ? Translation.tr("The password prompt was dismissed; nothing changed.")
                        : HealthService.accessError.length > 0 ? Translation.tr("It did not work: %1").arg(HealthService.accessError)
                        : HealthService.dumpAccess === "granted" ? Translation.tr("Granted to your account. Dumps never leave this computer.")
                        : Translation.tr("Only root can read them. The journal's stack trace still shows on the Crashes page.")
                    ClockButton {
                        visible: !root.confirmGrant
                        enabled: !HealthService.accessBusy
                        label: HealthService.dumpAccess === "granted" ? Translation.tr("Revoke") : Translation.tr("Allow")
                        danger: HealthService.dumpAccess === "granted"
                        onClicked: {
                            if (HealthService.dumpAccess === "granted")
                                HealthService.setDumpAccess(false);
                            else
                                root.confirmGrant = true;
                        }
                    }
                }
                // Said in words before the password prompt, as promised.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.confirmGrant
                    implicitHeight: grantColumn.implicitHeight + ClockStyle.gapLarge * 2
                    color: ClockStyle.colTertiaryContainer
                    radius: ClockStyle.radiusSmall / 2

                    ColumnLayout {
                        id: grantColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: ClockStyle.cardPadding
                        }
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Let your account read crash dumps of system programs. A dump is a copy of a program's memory and can contain passwords or keys. They never leave this computer, and the assistant never sees them.")
                            wrapMode: Text.Wrap
                            font.pixelSize: ClockStyle.textSmall + 1
                            color: ClockStyle.colOnTertiaryContainer
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: ClockStyle.gapSmall
                            ClockButton {
                                label: Translation.tr("Cancel")
                                variant: "text"
                                onClicked: root.confirmGrant = false
                            }
                            ClockButton {
                                label: Translation.tr("Allow, ask for my password")
                                variant: "filled"
                                symbol: "lock_open"
                                onClicked: {
                                    root.confirmGrant = false;
                                    HealthService.setDumpAccess(true);
                                }
                            }
                        }
                    }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "history"
                    title: Translation.tr("Keep daily summaries for")
                    Stepper { target: root.h; key: "historyDays"; from: 7; to: 365; format: v => Translation.tr("%1 d").arg(v) }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                title: Translation.tr("When the shell cannot start")
                symbol: "restart_alt"

                ClockSettingsRow {
                    first: true
                    symbol: "shield"
                    title: Translation.tr("Watch the shell's start")
                    description: Translation.tr("Hyprland's own notifications say why when the shell cannot start or crashes, and a crash restarts it. From the next start.")
                    Toggle { target: root.h.guard; key: "enable" }
                }
                ClockSettingsRow {
                    symbol: "terminal"
                    title: Translation.tr("Open a terminal to rebuild")
                    description: Translation.tr("When a Qt update is why, the rebuild opens on its own and asks before it runs anything.")
                    Toggle {
                        target: root.h.guard
                        key: "openTerminal"
                        enabled: root.h.guard.enable
                    }
                }
                ClockSettingsRow {
                    symbol: root.qtCompat === "ok" || root.qtCompat === "" ? "check_circle" : "warning"
                    title: Translation.tr("Quickshell and Qt")
                    description: root.qtCompat === "" ? Translation.tr("Checking…")
                        : root.qtCompat === "ok" ? Translation.tr("Quickshell matches the installed Qt.")
                        : root.qtCompat
                    ClockButton {
                        visible: root.qtCompat !== "" && root.qtCompat !== "ok"
                        label: Translation.tr("Rebuild")
                        symbol: "build"
                        variant: "filled"
                        onClicked: root.openRebuild()
                    }
                }
                ClockSettingsRow {
                    last: true
                    visible: HealthService.qtHookStatus !== "" && HealthService.qtHookStatus !== "unsupported"
                    symbol: "package_2"
                    title: Translation.tr("Warn during updates")
                    description: HealthService.qtHookBusy ? Translation.tr("Waiting for the password…")
                        : HealthService.qtHookError === "cancelled" ? Translation.tr("The password prompt was dismissed; nothing changed.")
                        : HealthService.qtHookError.length > 0 ? Translation.tr("It did not work: %1").arg(HealthService.qtHookError)
                        : HealthService.qtHookStatus === "installed" ? Translation.tr("A pacman hook checks Quickshell after every Qt update and says so in the update and on screen.")
                        : HealthService.qtHookStatus === "outdated" ? Translation.tr("The pacman hook is from an older version of ii.")
                        : Translation.tr("Recommended. A pacman hook would say so during the update itself, while the shell still runs.")
                    ClockButton {
                        enabled: !HealthService.qtHookBusy
                        label: HealthService.qtHookStatus === "installed" ? Translation.tr("Remove")
                            : HealthService.qtHookStatus === "outdated" ? Translation.tr("Update") : Translation.tr("Install")
                        variant: HealthService.qtHookStatus === "installed" ? "tonal" : "filled"
                        danger: HealthService.qtHookStatus === "installed"
                        onClicked: HealthService.setQtHook(HealthService.qtHookStatus !== "installed")
                    }
                }
            }
        }
    }

    // ── The start guard (scripts/quickshell-guard) ──────────────────────
    readonly property string guardDir: `${Directories.scriptPath}/quickshell-guard`
    /// "" while unknown, "ok", or what Quickshell said about the mismatch.
    property string qtCompat: ""

    // The pacman hook's state is HealthService's: the Overview offers it too.
    Component.onCompleted: {
        compatCheck.running = true;
        HealthService.checkQtHook();
    }

    function openRebuild(): void {
        const terminal = Config.options?.apps?.terminal || "kitty -1";
        const cmd = terminal.split(" ").filter(part => part.length > 0);
        cmd.push("-e", "bash", `${root.guardDir}/qs-rebuild.sh`);
        Quickshell.execDetached(cmd);
    }

    Process {
        id: compatCheck
        command: ["qs", "--private-check-compat"]
        stdout: StdioCollector {
            id: compatOut
        }
        onExited: code => {
            root.qtCompat = code === 0 ? "ok" : (compatOut.text.replace(/\x1b\[[0-9;]*m/g, "").trim() || Translation.tr("Quickshell does not match the installed Qt."));
        }
    }
}
