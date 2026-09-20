import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * What the overlay shows when the sampler has never been built.
 *
 * The QML ships with the config but the daemon does not — it is compiled on the
 * machine it runs on — so a fresh install opens on an empty chart with no way of
 * knowing why. This is that missing answer: the two commands, copyable, with the
 * state of each already checked rather than described.
 *
 * No shell restart is needed at the end. `checkInstall` relaunches the sampler the
 * moment it finds a binary, and this screen gives way to the real one.
 */
Item {
    id: root

    // Through rust-helpers.sh rather than three lines of cargo: it installs with a
    // rename, which a rebuild over the running sampler needs, and it records what the
    // binary was built from so a later update can tell that it has fallen behind.
    readonly property string buildCommand: `yay -S --needed rust
${Directories.rustHelpersScriptPath} build app_stats`

    // One line rather than the README's continuations: a backslash-wrapped rule is
    // only readable in a file, and this one has to survive a copy out of a label.
    readonly property string raplCommand: `sudo tee /etc/udev/rules.d/99-rapl-readable.rules >/dev/null <<'EOF'
SUBSYSTEM=="powercap", KERNEL=="intel-rapl:*", TEST=="/sys$devpath/energy_uj", RUN+="/usr/bin/chgrp wheel /sys$devpath/energy_uj", RUN+="/usr/bin/chmod g+r /sys$devpath/energy_uj"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=powercap`

    function copy(text) {
        Quickshell.execDetached(["bash", "-c", `wl-copy '${text.replace(/'/g, "'\\''")}'`]);
    }

    component CopyButton: RippleButton {
        required property string snippet
        property bool copied: false

        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSurfaceContainerHighest
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover

        onClicked: {
            root.copy(snippet);
            copied = true;
            copyResetTimer.restart();
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: parent.copied ? "check" : "content_copy"
            iconSize: 18
            color: parent.copied ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
        }

        Timer {
            id: copyResetTimer
            interval: 1500
            onTriggered: parent.copied = false
        }
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

        readonly property bool settled: step.checkState !== 0

        Layout.fillWidth: true
        implicitHeight: stepColumn.implicitHeight + 32
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: stepColumn

            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: Appearance.rounding.full
                    color: step.settled ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer

                    StyledText {
                        anchors.centerIn: parent
                        visible: !step.settled
                        text: `${step.number}`
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: step.settled
                        text: step.checkState === 1 ? "check" : "remove"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: step.heading
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                Rectangle {
                    implicitWidth: statusLabel.implicitWidth + 20
                    implicitHeight: 26
                    radius: Appearance.rounding.full
                    color: step.settled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh

                    StyledText {
                        id: statusLabel

                        anchors.centerIn: parent
                        text: {
                            if (step.checkState === 1)
                                return Translation.tr("Done");
                            if (step.checkState === 2)
                                return Translation.tr("Not needed here");
                            return Translation.tr("To do");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: step.settled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: step.body
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: snippetRow.implicitHeight + 20
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerHigh

                RowLayout {
                    id: snippetRow

                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    StyledText {
                        Layout.fillWidth: true
                        text: step.snippet
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurface
                        // Breaks the udev rule at its spaces where it can, mid-token
                        // only when a single argument is wider than the box.
                        wrapMode: Text.Wrap
                    }

                    CopyButton {
                        Layout.alignment: Qt.AlignTop
                        snippet: step.snippet
                    }
                }
            }
        }
    }

    StyledFlickable {
        anchors.fill: parent
        contentHeight: setupColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: setupColumn

            width: parent.width
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                spacing: 6

                StyledText {
                    text: Translation.tr("Usage stats aren't installed yet")
                    font.pixelSize: 32
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Everything on this screen ships with the config except the sampler itself, a small daemon that is built on the machine it runs on. Two commands and it starts collecting — no shell restart, no reload.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }

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
                body: AppStats.raplState === 2 ? Translation.tr("This machine exposes no intel-rapl counters — AMD, or a VM. Nothing to do: energy falls back to whole-battery drain on its own, which reads zero while on AC.") : Translation.tr("energy_uj is root-only as the mitigation for CVE-2020-8694, a power side-channel. Opening it to wheel grants that group nothing it could not already read through sudo, and only that one file is touched. You have to be in wheel yourself, which takes a re-login. Skip it and energy is estimated from battery drain instead.")
                snippet: root.raplCommand
                checkState: AppStats.raplState
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12

                RippleButton {
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: AppStats.checkInstall()

                    contentItem: RowLayout {
                        spacing: 8

                        MaterialSymbol {
                            Layout.leftMargin: 18
                            text: "refresh"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            Layout.rightMargin: 18
                            text: Translation.tr("Check again")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                RippleButton {
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.copy(`${root.buildCommand}\n\n${root.raplCommand}`)

                    contentItem: RowLayout {
                        spacing: 8

                        MaterialSymbol {
                            Layout.leftMargin: 18
                            text: "content_copy"
                            iconSize: 20
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.rightMargin: 18
                            text: Translation.tr("Copy both steps")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    Layout.maximumWidth: 420
                    text: Translation.tr("The first day file is written one flush interval after the sampler starts, so a blank first minute is normal. Full notes: scripts/appStats/README.md")
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
