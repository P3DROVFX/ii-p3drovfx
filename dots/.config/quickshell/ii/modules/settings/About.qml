import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    // ── Script path — uses Directories.home so it works for any user ────────
    readonly property string setupScript: FileUtils.trimFileProtocol(`${Directories.home}/.local/share/ii-vynx/setup-ii-vynx.sh`)

    // ── Single process for all actions ──────────────────────────────────────
    Process {
        id: actionProc
        property string mode: ""
        property string logOutput: ""
        property int exitCode: -1
        property bool finished: false
        stdout: SplitParser {
            onRead: data => {
                actionProc.logOutput += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                actionProc.logOutput += data + "\n";
            }
        }
        onExited: code => {
            actionProc.exitCode = code;
            actionProc.finished = true;
            if (code === 0)
                actionProc.logOutput += "✓ Done\n";
            else
                actionProc.logOutput += "✗ Exited with code " + code + "\n";
        }
    }

    // ── Distro ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "box"
        title: Translation.tr("Distro")
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            IconImage {
                implicitSize: 80
                source: Quickshell.iconPath(SystemInfo.logo)
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                StyledText {
                    text: SystemInfo.distroName
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    text: SystemInfo.homeUrl
                    textFormat: Text.MarkdownText
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    PointingHandLinkHover {}
                }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: Qt.openUrlExternally(SystemInfo.documentationUrl)
            }
            RippleButtonWithIcon {
                materialIcon: "support"
                mainText: Translation.tr("Help & Support")
                onClicked: Qt.openUrlExternally(SystemInfo.supportUrl)
            }
            RippleButtonWithIcon {
                materialIcon: "bug_report"
                mainText: Translation.tr("Report a Bug")
                onClicked: Qt.openUrlExternally(SystemInfo.bugReportUrl)
            }
            RippleButtonWithIcon {
                materialIcon: "policy"
                materialIconFill: false
                mainText: Translation.tr("Privacy Policy")
                onClicked: Qt.openUrlExternally(SystemInfo.privacyPolicyUrl)
            }
        }
    }

    // ── Parent-Dots ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "folder_managed"
        title: Translation.tr("Parent-Dots")
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            IconImage {
                implicitSize: 80
                source: Quickshell.iconPath("illogical-impulse")
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                StyledText {
                    text: Translation.tr("illogical-impulse")
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    text: "https://github.com/end-4/dots-hyprland"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    textFormat: Text.MarkdownText
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    PointingHandLinkHover {}
                }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: Qt.openUrlExternally("https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/")
            }
            RippleButtonWithIcon {
                materialIcon: "adjust"
                materialIconFill: false
                mainText: Translation.tr("Issues")
                onClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland/issues")
            }
            RippleButtonWithIcon {
                materialIcon: "forum"
                mainText: Translation.tr("Discussions")
                onClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland/discussions")
            }
            RippleButtonWithIcon {
                materialIcon: "favorite"
                mainText: Translation.tr("Donate")
                onClicked: Qt.openUrlExternally("https://github.com/sponsors/end-4")
            }
        }


    }

    // ── Dotfiles ─────────────────────────────────────────────────────────────
    ContentSection {
        icon: "folder_data"
        title: Translation.tr("Dotfiles")
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            CustomIcon {
                width: 80
                height: 80
                source: "ii-vynx"
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                StyledText {
                    text: Translation.tr("ii-vynx")
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    text: "https://github.com/vaguesyntax/ii-vynx"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    textFormat: Text.MarkdownText
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    PointingHandLinkHover {}
                }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 5
            RippleButtonWithIcon {
                materialIcon: "adjust"
                materialIconFill: false
                mainText: Translation.tr("Issues")
                onClicked: Qt.openUrlExternally("https://github.com/vaguesyntax/ii-vynx/issues")
            }
            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: Qt.openUrlExternally("https://github.com/vaguesyntax/ii-vynx/wiki")
            }
            RippleButtonWithIcon {
                materialIcon: "bug_report"
                mainText: Translation.tr("Known Issues")
                onClicked: Qt.openUrlExternally("https://github.com/vaguesyntax/ii-vynx/wiki/Known-Issues-and-Limitations")
            }
        }


    }

    // ── Quickshell Source ────────────────────────────────────────────────────
    ContentSection {
        icon: "swap_horiz"
        title: Translation.tr("Quickshell Source")

        // ── Update buttons (top) ─────────────────────────────────────────
        ContentSubsection {
            title: Translation.tr("Update")
            tooltip: Translation.tr("Pull latest changes from GitHub for each source independently")

            Flow {
                Layout.fillWidth: true
                spacing: 5

                RippleButtonWithIcon {
                    materialIcon: actionProc.running && actionProc.mode === "update-fork" ? "sync" : "system_update_alt"
                    mainText: actionProc.running && actionProc.mode === "update-fork" ? Translation.tr("Updating fork...") : Translation.tr("Update Fork")
                    enabled: !actionProc.running
                    onClicked: {
                        actionProc.logOutput = "";
                        actionProc.finished = false;
                        actionProc.exitCode = -1;
                        actionProc.mode = "update-fork";
                        actionProc.command = ["bash", page.setupScript, "--update-only", "--no-confirm"];
                        actionProc.running = true;
                    }
                    StyledToolTip {
                        text: Translation.tr("Pull latest changes from your fork on GitHub")
                    }
                }

                RippleButtonWithIcon {
                    materialIcon: actionProc.running && actionProc.mode === "update-upstream" ? "sync" : "cloud_download"
                    mainText: actionProc.running && actionProc.mode === "update-upstream" ? Translation.tr("Updating...") : Translation.tr("Update ii-vynx")
                    enabled: !actionProc.running
                    onClicked: {
                        actionProc.logOutput = "";
                        actionProc.finished = false;
                        actionProc.exitCode = -1;
                        actionProc.mode = "update-upstream";
                        actionProc.command = ["bash", page.setupScript, "--update-only", "--ii-vynx", "--no-confirm"];
                        actionProc.running = true;
                    }
                    StyledToolTip {
                        text: Translation.tr("Pull latest official ii-vynx from GitHub")
                    }
                }
            }

            // Beautiful Status Banner when finished
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
                height: 40
                visible: actionProc.finished
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(actionProc.exitCode === 0 ? Appearance.colors.colPrimary : Appearance.colors.colError, 0.85)
                border.color: actionProc.exitCode === 0 ? Appearance.colors.colPrimary : Appearance.colors.colError
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    MaterialSymbol {
                        text: actionProc.exitCode === 0 ? "check_circle" : "error"
                        iconSize: 20
                        color: actionProc.exitCode === 0 ? Appearance.colors.colPrimary : Appearance.colors.colError
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: actionProc.exitCode === 0 ? Translation.tr("Update completed successfully! Reload the shell to apply.") : Translation.tr("Update failed! Please check the log below.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            // Log output area
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                height: Math.min(250, logText.implicitHeight + 16)
                visible: actionProc.logOutput !== ""
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer0
                border.color: !actionProc.finished ? Appearance.colors.colOutline :
                              (actionProc.exitCode === 0 ? Appearance.colors.colPrimary : Appearance.colors.colError)
                border.width: 1

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true

                    Text {
                        id: logText
                        width: parent.width
                        text: actionProc.logOutput
                        font.family: "monospace"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }

        // ── Switch buttons (bottom) ──────────────────────────────────────
        ContentSubsection {
            title: Translation.tr("Switch Source")
            tooltip: Translation.tr("Switch between sources using local repos — no network required")

            Flow {
                Layout.fillWidth: true
                spacing: 5

                RippleButtonWithIcon {
                    materialIcon: actionProc.running && actionProc.mode === "fork" ? "sync" : "fork_right"
                    mainText: actionProc.running && actionProc.mode === "fork" ? Translation.tr("Switching...") : Translation.tr("P3DROVFX Fork")
                    enabled: !actionProc.running
                    onClicked: {
                        actionProc.logOutput = "";
                        actionProc.finished = false;
                        actionProc.exitCode = -1;
                        actionProc.mode = "fork";
                        actionProc.command = ["bash", page.setupScript, "--force-install", "--no-pull", "--no-confirm"];
                        actionProc.running = true;
                    }
                    StyledToolTip {
                        text: Translation.tr("Switch to your fork (local, no network)")
                    }
                }

                RippleButtonWithIcon {
                    materialIcon: actionProc.running && actionProc.mode === "upstream" ? "sync" : "deployed_code"
                    mainText: actionProc.running && actionProc.mode === "upstream" ? Translation.tr("Switching...") : Translation.tr("ii-vynx Official")
                    enabled: !actionProc.running
                    onClicked: {
                        actionProc.logOutput = "";
                        actionProc.finished = false;
                        actionProc.exitCode = -1;
                        actionProc.mode = "upstream";
                        actionProc.command = ["bash", page.setupScript, "--force-install", "--no-pull", "--no-confirm", "--ii-vynx"];
                        actionProc.running = true;
                    }
                    StyledToolTip {
                        text: Translation.tr("Switch to official ii-vynx (local, no network)")
                    }
                }
            }
        }
    }

    // ── Changelog ────────────────────────────────────────────────────────────
    ContentSection {
        icon: "history"
        title: Translation.tr("Latest Commits")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                visible: ChangelogService.loading
                Layout.fillWidth: true
                spacing: 8
                MaterialLoadingIndicator {
                    implicitSize: 20
                }
                StyledText {
                    text: Translation.tr("Fetching commits...")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            StyledText {
                visible: !ChangelogService.loading && ChangelogService.commits.count === 0
                text: Translation.tr("No commits found or repository not available.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: ChangelogService.commits
                delegate: Rectangle {
                    id: entryRoot
                    
                    readonly property string commitHash: model.hash
                    readonly property string commitTitle: model.title
                    readonly property string commitDescription: model.description
                    readonly property string commitSmartId: model.smartId

                    Layout.fillWidth: true
                    Layout.preferredHeight: layout.implicitHeight + 24
                    
                    radius: Appearance.rounding.large
                    color: Appearance.m3colors.m3surfaceContainer
                    border.width: 0

                    ColumnLayout {
                        id: layout
                        anchors {
                            fill: parent
                            margins: 12
                        }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true

                            Rectangle {
                                visible: entryRoot.commitSmartId !== ""
                                radius: Appearance.rounding.small
                                color: {
                                    if (!entryRoot.commitSmartId) return Appearance.m3colors.m3surfaceContainerHighest;
                                    let prefix = entryRoot.commitSmartId.charAt(0);
                                    if (prefix === 'A') return Appearance.colors.colPrimaryContainer;
                                    if (prefix === 'B') return Appearance.colors.colErrorContainer || Appearance.colors.colSecondaryContainer;
                                    if (prefix === 'C' || prefix === 'D') return Appearance.colors.colTertiaryContainer || Appearance.colors.colSecondaryContainer;
                                    return Appearance.m3colors.m3surfaceContainerHighest;
                                }
                                border.width: 0
                                implicitWidth: idText.implicitWidth + 16
                                implicitHeight: idText.implicitHeight + 6

                                StyledText {
                                    id: idText
                                    anchors.centerIn: parent
                                    text: entryRoot.commitSmartId
                                    font.weight: Font.Bold
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: {
                                        if (!entryRoot.commitSmartId) return Appearance.colors.colOnSurface;
                                        let prefix = entryRoot.commitSmartId.charAt(0);
                                        if (prefix === 'A') return Appearance.colors.colOnPrimaryContainer;
                                        if (prefix === 'B') return Appearance.colors.colOnErrorContainer || Appearance.colors.colOnSecondaryContainer;
                                        if (prefix === 'C' || prefix === 'D') return Appearance.colors.colOnTertiaryContainer || Appearance.colors.colOnSecondaryContainer;
                                        return Appearance.colors.colOnSurface;
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: model.date
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                opacity: 0.7
                            }
                        }

                        StyledText {
                            text: entryRoot.commitTitle
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }

                        StyledText {
                            visible: entryRoot.commitDescription !== ""
                            text: entryRoot.commitDescription
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            opacity: 0.85
                        }
                    }
                }
            }
        }
    }
}
