pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * What the app shows when the sampler has never been built.
 *
 * The QML ships with the config but the daemon does not — it is compiled on the
 * machine it runs on — so a fresh install would open on an empty chart with no way of
 * knowing why. This is that missing answer: the two commands, copyable, with the state
 * of each already checked rather than described.
 *
 * No shell restart is needed at the end. `checkInstall` relaunches the sampler the
 * moment it finds a binary, and the shell swaps this page for the real ones. While it
 * is on screen it asks again every few seconds, so a build finishing in a terminal
 * beside it is picked up without a click.
 */
Item {
    id: root

    // ── Page contract ───────────────────────────────────────────────────
    property bool compact: false
    readonly property string pageSubtitle: ""
    readonly property bool detailOpen: false
    readonly property string detailTitle: ""

    function closeDetail(): void {
    }

    function handleEscape(): bool {
        return false;
    }

    function handleKey(key: int, modifiers: int): bool {
        return false;
    }

    // Through rust-helpers.sh rather than three lines of cargo: it installs with a
    // rename, which a rebuild over the running sampler needs, and it records what the
    // binary was built from so a later update can tell that it has fallen behind.
    readonly property string buildCommand: `yay -S --needed rust
${Directories.rustHelpersScriptPath} build app_stats`

    // One line rather than the README's continuations: a backslash-wrapped rule is only
    // readable in a file, and this one has to survive a copy out of a label.
    readonly property string raplCommand: `sudo tee /etc/udev/rules.d/99-rapl-readable.rules >/dev/null <<'EOF'
SUBSYSTEM=="powercap", KERNEL=="intel-rapl:*", TEST=="/sys$devpath/energy_uj", RUN+="/usr/bin/chgrp wheel /sys$devpath/energy_uj", RUN+="/usr/bin/chmod g+r /sys$devpath/energy_uj"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=powercap`

    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property bool settled: AppStats.binaryPresent && AppStats.raplState !== 0

    function copy(text: string): void {
        Quickshell.execDetached(["bash", "-c", `wl-copy '${text.replace(/'/g, "'\\''")}'`]);
    }

    Component.onCompleted: AppStats.checkInstall()

    // One filesystem test every few seconds, only while this page is up and something
    // is still left to do.
    Timer {
        interval: 4000
        repeat: true
        running: !root.settled && (root.Window.window?.visible ?? false)
        onTriggered: AppStats.checkInstall()
    }

    /// `checkState` is 0 for a step still to do, 1 for one already done and 2 for one
    /// this machine has no use for.
    component SetupStep: Rectangle {
        id: step

        required property int number
        required property string heading
        required property string body
        required property string snippet
        required property int checkState

        readonly property bool done: step.checkState !== 0

        Layout.fillWidth: true
        implicitHeight: stepColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane

        ColumnLayout {
            id: stepColumn
            anchors.fill: parent
            anchors.margins: ClockStyle.cardPadding
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                Item {
                    implicitWidth: 40
                    implicitHeight: 40

                    MaterialShape {
                        anchors.fill: parent
                        // A finished step morphs from the idle circle into the bun.
                        shapeString: step.done ? "Bun" : "Circle"
                        color: step.done ? ClockStyle.colPrimary : ClockStyle.colPrimaryContainer
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: !step.done
                        text: `${step.number}`
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: 22
                        color: ClockStyle.colOnPrimaryContainer
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: step.done
                        text: step.checkState === 1 ? "check" : "remove"
                        iconSize: 20
                        fill: 1
                        color: ClockStyle.colOnPrimary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: step.heading
                    wrapMode: Text.WordWrap
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge + 2
                    color: ClockStyle.colOnSurface
                }

                Rectangle {
                    implicitWidth: statusLabel.implicitWidth + ClockStyle.gapLarge * 2
                    implicitHeight: 30
                    radius: ClockStyle.pill(30)
                    color: step.done ? ClockStyle.colSecondaryContainer : ClockStyle.colSurfaceHigh

                    StyledText {
                        id: statusLabel
                        anchors.centerIn: parent
                        text: step.checkState === 1 ? Translation.tr("Done")
                            : step.checkState === 2 ? Translation.tr("Not needed here") : Translation.tr("To do")
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                        color: step.done ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: step.body
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colSubtext
            }

            UsageCodeSnippet {
                Layout.fillWidth: true
                snippet: step.snippet
            }
        }

        StaggeredEntrance {
            index: step.number + 1
            active: !ClockStyle.reducedMotion
        }
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: setupColumn.implicitHeight + ClockStyle.gapHuge * 2
        clip: true

        ColumnLayout {
            id: setupColumn
            x: (flick.width - width) / 2
            y: ClockStyle.gapHuge
            width: Math.min(flick.width - root.padding * 2, ClockStyle.sheetMaxWidth * 1.4)
            spacing: ClockStyle.gapLarge

            // ── What this is ────────────────────────────────────────────
            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "query_stats"
                iconSize: 52
                padding: 30
                shape: MaterialShape.Shape.Puffy
                color: ClockStyle.colSecondaryContainer
                colSymbol: ClockStyle.colOnSecondaryContainer
                fill: 1

                StaggeredEntrance {
                    index: 0
                    active: !ClockStyle.reducedMotion
                    fromScale: 0.8
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Usage stats aren't installed yet")
                wrapMode: Text.WordWrap
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textTitle + 6
                color: ClockStyle.colOnBackground
            }

            StyledText {
                Layout.fillWidth: true
                Layout.bottomMargin: ClockStyle.gapSmall
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Everything here ships with the config except the sampler itself, a small daemon that is built on the machine it runs on. Two commands and it starts collecting — no shell restart, no reload.")
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textNormal + 1
                color: ClockStyle.colSubtext

                StaggeredEntrance {
                    index: 1
                    active: !ClockStyle.reducedMotion
                }
            }

            // ── Steps ───────────────────────────────────────────────────
            SetupStep {
                number: 1
                heading: Translation.tr("Build the sampler")
                body: Translation.tr("Rust is the only build requirement. The first build fetches two crates, so it needs network; what comes out is a ~530 KB binary that costs about 3.5 MB of memory to run.")
                snippet: root.buildCommand
                checkState: AppStats.binaryPresent ? 1 : 0
            }

            SetupStep {
                number: 2
                heading: Translation.tr("Let your user read the energy counters")
                body: AppStats.raplState === 2
                    ? Translation.tr("This machine exposes no intel-rapl counters — AMD, or a VM. Nothing to do: energy falls back to whole-battery drain on its own, which reads zero while on AC.")
                    : Translation.tr("energy_uj is root-only as the mitigation for CVE-2020-8694, a power side-channel. Opening it to wheel grants that group nothing it could not already read through sudo, and only that one file is touched. You have to be in wheel yourself, which takes a re-login. Skip it and energy is estimated from battery drain instead.")
                snippet: root.raplCommand
                checkState: AppStats.raplState
            }

            // ── Actions ─────────────────────────────────────────────────
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapTiny
                spacing: ClockStyle.gap

                ClockButton {
                    variant: "filled"
                    symbol: "refresh"
                    label: Translation.tr("Check again")
                    onClicked: AppStats.checkInstall()
                }

                ClockButton {
                    variant: "tonal"
                    symbol: "content_copy"
                    label: Translation.tr("Copy both steps")
                    onClicked: root.copy(`${root.buildCommand}\n\n${root.raplCommand}`)
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("The first day file is written one flush interval after the sampler starts, so a blank first minute is normal. Full notes: scripts/appStats/README.md")
                wrapMode: Text.WordWrap
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }
    }
}
