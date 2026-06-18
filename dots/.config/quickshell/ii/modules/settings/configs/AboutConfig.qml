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
    forceWidth: false

    property string activeRemote: ""

    Process {
        id: checkRemoteProc
        command: ["bash", "-c", "for dir in \"$HOME/Downloads/ii-vynx\" \"$HOME/.local/share/ii-vynx-fork\" \"$HOME/.local/share/ii-vynx-upstream\" \"$HOME/.local/share/ii-vynx\" \"$HOME/dotfiles\"; do if git -C \"$dir\" rev-parse --is-inside-work-tree >/dev/null 2>&1; then git -C \"$dir\" remote get-url origin; break; fi; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                page.activeRemote = text.trim();
            }
        }
    }

    Component.onCompleted: checkRemoteProc.running = true

    readonly property string setupScript: FileUtils.trimFileProtocol(`${Directories.home}/.local/share/ii-vynx/setup-ii-vynx.sh`)

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

    ContentSection {
        icon: "info"
        title: Translation.tr("System Info")

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 2
            columnSpacing: 2

            ContentSubsection {
                Layout.fillWidth: true
                Layout.fillHeight: true
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.verysmall
                bottomLeftRadius: Appearance.rounding.verysmall
                bottomRightRadius: Appearance.rounding.verysmall
                title: Translation.tr("Distro Info")
                icon: "developer_board"
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Layout.topMargin: 10
                    Layout.bottomMargin: 10
                    IconImage {
                        implicitSize: 50
                        source: Quickshell.iconPath(SystemInfo.logo)
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        StyledText {
                            text: SystemInfo.distroName
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: "<a href='" + SystemInfo.homeUrl + "'>" + SystemInfo.homeUrl.replace(/^https?:\/\/(www\.)?/, '') + "</a>"
                            textFormat: Text.RichText
                            onLinkActivated: link => Qt.openUrlExternally(link)
                            PointingHandLinkHover {}
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 5
                    RippleButtonWithIcon { materialIcon: "auto_stories"; mainText: Translation.tr("Docs"); onClicked: Qt.openUrlExternally(SystemInfo.documentationUrl) }
                    RippleButtonWithIcon { materialIcon: "bug_report"; mainText: Translation.tr("Bugs"); onClicked: Qt.openUrlExternally(SystemInfo.bugReportUrl) }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                Layout.fillHeight: true
                topLeftRadius: Appearance.rounding.verysmall
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.verysmall
                bottomRightRadius: Appearance.rounding.verysmall
                title: Translation.tr("Parent-Dots Info")
                icon: "account_tree"
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Layout.topMargin: 10
                    Layout.bottomMargin: 10
                    IconImage {
                        implicitSize: 50
                        source: Quickshell.iconPath("illogical-impulse")
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        StyledText {
                            text: Translation.tr("illogical-impulse")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                        }
                        StyledText {
                            text: "<a href='https://github.com/end-4/dots-hyprland'>github.com/end-4/dots-hyprland</a>"
                            font.pixelSize: Appearance.font.pixelSize.small
                            textFormat: Text.RichText
                            onLinkActivated: link => Qt.openUrlExternally(link)
                            PointingHandLinkHover {}
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 5
                    RippleButtonWithIcon { materialIcon: "auto_stories"; mainText: Translation.tr("Wiki"); onClicked: Qt.openUrlExternally("https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/") }
                    RippleButtonWithIcon { materialIcon: "favorite"; mainText: Translation.tr("Sponsor"); onClicked: Qt.openUrlExternally("https://github.com/sponsors/end-4") }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                Layout.fillHeight: true
                topLeftRadius: Appearance.rounding.verysmall
                topRightRadius: Appearance.rounding.verysmall
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.verysmall
                title: Translation.tr("Upstream Info")
                icon: "code"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Layout.topMargin: 10
                    Layout.bottomMargin: 10
                    CustomIcon {
                        width: 50
                        height: 50
                        source: "ii-vynx"
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        StyledText {
                            text: Translation.tr("Upstream (ii-vynx)")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                        }
                        StyledText {
                            text: "<a href='https://github.com/vaguesyntax/ii-vynx'>github.com/vaguesyntax/ii-vynx</a>"
                            font.pixelSize: Appearance.font.pixelSize.small
                            textFormat: Text.RichText
                            onLinkActivated: link => Qt.openUrlExternally(link)
                            PointingHandLinkHover {}
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 5
                    RippleButtonWithIcon { materialIcon: "auto_stories"; mainText: Translation.tr("Wiki"); onClicked: Qt.openUrlExternally("https://github.com/vaguesyntax/ii-vynx/wiki") }
                    RippleButtonWithIcon { materialIcon: "adjust"; materialIconFill: false; mainText: Translation.tr("Issues"); onClicked: Qt.openUrlExternally("https://github.com/vaguesyntax/ii-vynx/issues") }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                Layout.fillHeight: true
                topLeftRadius: Appearance.rounding.verysmall
                topRightRadius: Appearance.rounding.verysmall
                bottomLeftRadius: Appearance.rounding.verysmall
                bottomRightRadius: Appearance.rounding.large
                title: Translation.tr("My Fork Info")
                icon: "call_split"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Layout.topMargin: 10
                    Layout.bottomMargin: 10
                    Image {
                        source: "file://" + Quickshell.shellPath("assets/icons/ii-p3drovfx.png")
                        sourceSize: Qt.size(50, 50)
                        fillMode: Image.PreserveAspectFit
                        width: 50
                        height: 50
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        StyledText {
                            text: Translation.tr("My Fork (ii-p3drovfx)")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                        }
                        StyledText {
                            text: "<a href='https://github.com/P3DROVFX/ii-vynx-fork'>github.com/P3DROVFX/...</a>"
                            font.pixelSize: Appearance.font.pixelSize.small
                            textFormat: Text.RichText
                            onLinkActivated: link => Qt.openUrlExternally(link)
                            PointingHandLinkHover {}
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 5
                    RippleButtonWithIcon { materialIcon: "code"; mainText: Translation.tr("GitHub"); onClicked: Qt.openUrlExternally("https://github.com/P3DROVFX/ii-vynx-fork") }
                    RippleButtonWithIcon { materialIcon: "adjust"; materialIconFill: false; mainText: Translation.tr("Issues"); onClicked: Qt.openUrlExternally("https://github.com/P3DROVFX/ii-vynx-fork/issues") }
                }
            }
        }
    }

    ContentSection {
        icon: "swap_horiz"
        title: Translation.tr("Git Source & Update Controls")

        ContentSubsection {
            title: Translation.tr("Source updater")
            icon: "update"
            tooltip: Translation.tr("Pull latest changes from GitHub for each source independently")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 45
                    buttonRadius: Appearance.rounding.large
                    materialIcon: actionProc.running && actionProc.mode === "update-fork" ? "sync" : "system_update_alt"
                    mainText: actionProc.running && actionProc.mode === "update-fork" ? Translation.tr("Updating fork...") : Translation.tr("Update My Fork (ii-p3drovfx)")
                    enabled: !actionProc.running
                    onClicked: {
                        Config.blockWrites = true;
                        actionProc.logOutput = "";
                        actionProc.finished = false;
                        actionProc.exitCode = -1;
                        actionProc.mode = "update-fork";
                        actionProc.command = ["bash", page.setupScript, "--update-only", "--no-confirm"];
                        actionProc.running = true;
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 45
                    buttonRadius: Appearance.rounding.large
                    materialIcon: actionProc.running && actionProc.mode === "update-upstream" ? "sync" : "cloud_download"
                    mainText: actionProc.running && actionProc.mode === "update-upstream" ? Translation.tr("Updating...") : Translation.tr("Update Upstream (ii-vynx)")
                    enabled: !actionProc.running
                    onClicked: {
                        Config.blockWrites = true;
                        actionProc.logOutput = "";
                        actionProc.finished = false;
                        actionProc.exitCode = -1;
                        actionProc.mode = "update-upstream";
                        actionProc.command = ["bash", page.setupScript, "--update-only", "--ii-vynx", "--no-confirm"];
                        actionProc.running = true;
                    }
                }
            }

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

                StyledFlickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    contentHeight: logText.implicitHeight
                    contentWidth: width
                    flickableDirection: Flickable.VerticalFlick

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

        ContentSubsection {
            title: Translation.tr("Source Switcher")
            icon: "swap_horiz"
            tooltip: Translation.tr("Switch between sources using local repos — no network required")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 45
                    buttonRadius: Appearance.rounding.small
                    colBackground: page.activeRemote.indexOf("P3DROVFX") !== -1 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                    materialIcon: actionProc.running && actionProc.mode === "fork" ? "sync" : "fork_right"
                    mainText: {
                        if (actionProc.running && actionProc.mode === "fork") return Translation.tr("Switching...");
                        if (page.activeRemote.indexOf("P3DROVFX") !== -1) return Translation.tr("Current (My Fork)");
                        return Translation.tr("Switch to My Fork (ii-p3drovfx)");
                    }
                    enabled: !actionProc.running && page.activeRemote.indexOf("P3DROVFX") === -1
                    onClicked: {
                        Config.blockWrites = true;
                        actionProc.logOutput = "";
                        actionProc.finished = false;
                        actionProc.exitCode = -1;
                        actionProc.mode = "fork";
                        actionProc.command = ["bash", page.setupScript, "--force-install", "--no-pull", "--no-confirm", "--preserve-config"];
                        actionProc.running = true;
                    }
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 45
                    buttonRadius: Appearance.rounding.small
                    colBackground: page.activeRemote.indexOf("vaguesyntax") !== -1 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                    materialIcon: actionProc.running && actionProc.mode === "upstream" ? "sync" : "deployed_code"
                    mainText: {
                        if (actionProc.running && actionProc.mode === "upstream") return Translation.tr("Switching...");
                        if (page.activeRemote.indexOf("vaguesyntax") !== -1) return Translation.tr("Current (Upstream)");
                        return Translation.tr("Switch to Upstream (ii-vynx)");
                    }
                    enabled: !actionProc.running && page.activeRemote.indexOf("vaguesyntax") === -1
                    onClicked: {
                        Config.blockWrites = true;
                        actionProc.logOutput = "";
                        actionProc.finished = false;
                        actionProc.exitCode = -1;
                        actionProc.mode = "upstream";
                        actionProc.command = ["bash", page.setupScript, "--force-install", "--no-pull", "--no-confirm", "--ii-vynx", "--preserve-config"];
                        actionProc.running = true;
                    }
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "deployed_code_update"
            text: Translation.tr("Enable update checks")
            checked: Config.options.updates.enableCheck
            onCheckedChanged: {
                Config.options.updates.enableCheck = checked;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.updates.enableCheck
            icon: "av_timer"
            text: Translation.tr("Check interval (mins)")
            value: Config.options.updates.checkInterval
            from: 60
            to: 1440
            stepSize: 60
            onValueChanged: {
                Config.options.updates.checkInterval = value;
            }
        }
    }

    ContentSection {
        icon: "history"
        title: Translation.tr("Commit History")

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
                        
                        readonly property int itemIndex: {
                            var p = parent;
                            if (!p) return 0;
                            var idx = 0;
                            for (var i = 0; i < p.children.length; ++i) {
                                if (p.children[i] === entryRoot) return idx;
                                if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined") idx++;
                            }
                            return 0;
                        }

                        readonly property int totalItems: {
                            var p = parent;
                            if (!p) return 1;
                            var count = 0;
                            for (var i = 0; i < p.children.length; ++i) {
                                if (p.children[i].visible && typeof p.children[i].topLeftRadius !== "undefined") count++;
                            }
                            return count;
                        }

                        property bool isFirst: itemIndex === 0
                        property bool isLast: itemIndex === totalItems - 1

                        topLeftRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                        topRightRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                        bottomLeftRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
                        bottomRightRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall

                        
                        readonly property string commitHash: model.hash
                        readonly property string commitTitle: model.title
                        readonly property string commitDescription: model.description
                        readonly property string commitSmartId: model.smartId

                        Layout.fillWidth: true
                        Layout.preferredHeight: layout.implicitHeight + 24
                        
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer2
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
