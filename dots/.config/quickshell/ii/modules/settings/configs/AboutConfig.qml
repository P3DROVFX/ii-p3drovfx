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

    // ── Active-fork state (read from state files in ~/.config/quickshell/ii/) ──
    property string activeRemote: ""
    property string activeBranch: "main"
    property string activeFork: "p3drovfx"
    property string activeCommit: ""
    property string remoteCommit: ""
    property bool hasUpdate: activeCommit !== "" && remoteCommit !== "" && activeCommit !== remoteCommit
    property bool checkingUpdates: false

    // ── Custom fork URL input for the Fork Switcher ──
    property string customForkUrl: ""

    readonly property string setupScript: FileUtils.trimFileProtocol(Directories.home + "/.local/share/ii-vynx/setup-ii-vynx.sh")

    component StatusChip: Rectangle {
        id: chipRoot
        property string iconText: ""
        property string chipText: ""
        property color chipColor: Appearance.colors.colLayer2
        property color textColor: Appearance.colors.colOnLayer1

        implicitWidth: layout.implicitWidth + 24
        implicitHeight: 32
        radius: Config.options.appearance.sharpMode ? 0 : 16
        color: chipColor
        border.width: 0

        RowLayout {
            id: layout
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                visible: chipRoot.iconText !== ""
                text: chipRoot.iconText
                iconSize: 16
                color: chipRoot.textColor
            }

            StyledText {
                text: chipRoot.chipText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: chipRoot.textColor
            }
        }
    }

    // ── Read state files: .active-remote | .active-branch | .active-fork | .active-commit ──
    Process {
        id: stateReadProc
command: ["bash", "-c",
            "dir=\"$HOME/.config/quickshell/ii\"; " +
            "out=\"\"; " +
            "[ -f \"$dir/.active-remote\" ] && out+=\"$(cat \"$dir/.active-remote\")\"; " +
            "out+=\"---\"; " +
            "[ -f \"$dir/.active-branch\" ] && out+=\"$(cat \"$dir/.active-branch\")\"; " +
            "out+=\"---\"; " +
            "[ -f \"$dir/.active-fork\" ] && out+=\"$(cat \"$dir/.active-fork\")\"; " +
            "out+=\"---\"; " +
            "[ -f \"$dir/.active-commit\" ] && out+=\"$(cat \"$dir/.active-commit\")\"; " +
            "printf '%s' \"$out\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.split("---");
                page.activeRemote = (parts[0] || "").trim();
                page.activeBranch = (parts[1] || "main").trim() || "main";
                page.activeFork   = (parts[2] || "p3drovfx").trim() || "p3drovfx";
                page.activeCommit = (parts[3] || "").trim();
                // After loading state, kick off the remote-head probe to compute hasUpdate.
                remoteHeadProc.running = true;
            }
        }
    }

    // ── Remote HEAD probe: shows SHA of origin/<branch> so we can compute hasUpdate ──
    Process {
        id: remoteHeadProc
                command: ["bash", "-c",
            "if [ -z \"" + page.activeRemote + "\" ] || [ -z \"" + page.activeBranch + "\" ]; then exit 0; fi; " +
            "git ls-remote --heads \"" + page.activeRemote + "\" \"" + page.activeBranch + "\" 2>/dev/null | awk '{print $1; exit}'"]
        onStarted: page.checkingUpdates = true
        stdout: StdioCollector {
            onStreamFinished: {
                page.remoteCommit = text.trim();
                page.checkingUpdates = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    page.checkingUpdates = false;
                    page.remoteCommit = "";
                }
            }
        }
    }

    Component.onCompleted: {
        stateReadProc.running = true;
    }

    onVisibleChanged: {
        if (visible) {
            stateReadProc.running = true;
        }
    }

    // ── Action process (run setup-ii-vynx.sh, log into the UI) ──
    Process {
        id: actionProc
        property string mode: ""
        property string logOutput: ""
        property int exitCode: -1
        property bool finished: false
        stdout: SplitParser {
            onRead: data => { actionProc.logOutput += data + "\n"; }
        }
        stderr: SplitParser {
            onRead: data => { actionProc.logOutput += data + "\n"; }
        }
        onExited: code => {
            actionProc.exitCode = code;
            actionProc.finished = true;
            if (code === 0) {
                actionProc.logOutput += "✓ Done\n";
                // Re-read state in case the fork/branch changed.
                stateReadProc.running = true;
            } else {
                actionProc.logOutput += "✗ Exited with code " + code + "\n";
            }
        }
    }

    // Helper to run an action.
    function runAction(modeName, args) {
        Config.blockWrites = true;
        actionProc.logOutput = "";
        actionProc.finished = false;
        actionProc.exitCode = -1;
        actionProc.mode = modeName;
        const cmd = ["bash", page.setupScript, ...args];
        actionProc.command = cmd;
        actionProc.running = true;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Section: System Info (kept verbatim from previous design)
    // ──────────────────────────────────────────────────────────────────────────
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

    // ──────────────────────────────────────────────────────────────────────────
    // Section: Update
    // ──────────────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "system_update_alt"
        title: Translation.tr("Update")

        ContentSubsection {
            title: Translation.tr("Source updater")
            icon: "update"
            tooltip: Translation.tr("Pull latest changes for the current fork + branch from GitHub and replace the ii folder")

            headerExtra: Component {
                RowLayout {
                    spacing: 6
                    StatusChip {
                        iconText: "hub"
                        chipText: {
                            const label = page.activeFork === "p3drovfx" ? "P3DROVFX"
                                       : page.activeFork === "end4" ? "end-4"
                                       : page.activeFork === "vynx" || page.activeFork === "upstream"
                                         ? "ii-vynx" : (page.activeFork || "fork");
                            return label;
                        }
                        chipColor: Appearance.colors.colSecondaryContainer
                        textColor: Appearance.colors.colOnSecondaryContainer
                    }

                    StatusChip {
                        iconText: "call_split"
                        chipText: page.activeBranch
                        chipColor: Appearance.colors.colSecondaryContainer
                        textColor: Appearance.colors.colOnSecondaryContainer
                    }

                    StatusChip {
                        visible: page.activeCommit !== ""
                        iconText: "description"
                        chipText: page.activeCommit.substring(0, 7)
                        chipColor: Appearance.colors.colLayer2
                        textColor: Appearance.colors.colOnLayer1
                    }

                    StatusChip {
                        visible: page.activeFork === "p3drovfx"
                        iconText: page.activeBranch === "main" ? "verified" : "science"
                        chipText: page.activeBranch === "main" ? Translation.tr("Stable") : Translation.tr("Dev (New Features)")
                        chipColor: page.activeBranch === "main" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colTertiaryContainer
                        textColor: page.activeBranch === "main" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnTertiaryContainer
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Main update button — single button, fork+branch current.
                RippleButton {
                    id: updateBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    buttonRadius: Appearance.rounding.large
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive

                    contentItem: StyledText {
                        text: {
                            if (actionProc.running && actionProc.mode === "update")
                                return Translation.tr("Updating…");
                            const label = page.activeFork === "p3drovfx" ? "P3DROVFX"
                                       : page.activeFork === "end4" ? "end-4"
                                       : page.activeFork === "vynx" || page.activeFork === "upstream"
                                         ? "ii-vynx" : (page.activeFork || "fork");
                            return Translation.tr("Update ") + label + " @ " + page.activeBranch;
                        }
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    enabled: !actionProc.running
                    onClicked: {
                        page.runAction("update", ["--update", "--no-confirm", "--preserve-config"]);
                    }
                }

                // ── Circle Badge next to the button ──
                Rectangle {
                    visible: page.hasUpdate && !(actionProc.running && actionProc.mode === "update")
                    radius: width / 2
                    color: Appearance.colors.colErrorContainer
                    Layout.preferredHeight: 48
                    Layout.preferredWidth: 48
                    Layout.alignment: Qt.AlignVCenter

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "deployed_code_update"
                        iconSize: 22
                        color: Appearance.colors.colOnErrorContainer
                        fill: 1
                    }

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            // ── Status + log box (inline) ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    height: 40
                    visible: actionProc.finished
                    radius: Appearance.rounding.small
                    color: ColorUtils.transparentize(actionProc.exitCode === 0 ? Appearance.colors.colPrimary : Appearance.colors.colError, 0.85)
                    border.width: 0

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
                            text: actionProc.exitCode === 0
                                  ? Translation.tr("Update completed successfully! Reload the shell to apply.")
                                  : Translation.tr("Update failed! Check the log below.")
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
                    border.width: 0

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
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Section: Branch
    // ──────────────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "call_split"
        title: Translation.tr("Branch")

        ContentSubsection {
            title: Translation.tr("Branch switcher")
            icon: "fork_right"
            tooltip: Translation.tr("Switch between main (stable) and dev (new features) on the current fork")

            ConfigSelectionArray {
                id: branchSelector
                currentValue: page.activeFork === "p3drovfx" ? page.activeBranch : null
                onSelected: newValue => {
                    if (newValue === page.activeBranch) return;
                    page.runAction("branch-" + newValue,
                        ["--switch", "--branch", newValue, "--fork", "p3drovfx",
                         "--no-confirm", "--preserve-config"]);
                }
                options: [
                    {
                        displayName: Translation.tr("main") + " · " + Translation.tr("stable"),
                        icon: (page.activeBranch === "main" && page.activeFork === "p3drovfx") ? "check" : "verified",
                        value: "main",
                        enabled: !actionProc.running && page.activeFork === "p3drovfx"
                    },
                    {
                        displayName: Translation.tr("dev") + " · " + Translation.tr("new features"),
                        icon: (page.activeBranch === "dev" && page.activeFork === "p3drovfx") ? "check" : "science",
                        value: "dev",
                        enabled: !actionProc.running && page.activeFork === "p3drovfx"
                    }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: visible ? 6 : 0
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                visible: page.activeFork !== "p3drovfx"
                text: Translation.tr("Branch switcher is only available on the P3DROVFX fork. Use the CLI for other forks: 'vynx branch <name>'.")
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Section: Fork Switcher
    // ──────────────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "swap_horiz"
        title: Translation.tr("Fork Switcher")

        ContentSubsection {
            title: Translation.tr("Switch fork")
            icon: "hub"
            tooltip: Translation.tr("Replace your ~/.config/quickshell/ii with the chosen fork's latest from GitHub")

            // Preset buttons.
            Flow {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { id: "p3drovfx", icon: "fork_right",     label: Translation.tr("My Fork (P3DROVFX)") },
                        { id: "end4",     icon: "deployed_code",   label: Translation.tr("end-4 (dots-hyprland)") },
                        { id: "vynx",     icon: "cloud_download",  label: Translation.tr("Upstream (ii-vynx)") }
                    ]
                    delegate: RippleButtonWithIcon {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        buttonRadius: Appearance.rounding.large
                        readonly property bool isActive: page.activeFork === modelData.id
                        colBackground: isActive ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                        colText: isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        materialIcon: isActive ? "check" : modelData.icon
                        mainText: modelData.label
                        enabled: !actionProc.running && !isActive
                        onClicked: {
                            // Switching forks: NOT preserving config to avoid structural conflict crashes.
                            page.runAction("fork-" + modelData.id,
                                ["--switch", "--fork", modelData.id, "--no-confirm"]);
                        }
                    }
                }
            }

            // Custom fork URL field + button.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8

                MaterialTextField {
                    id: customUrlField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    placeholderText: Translation.tr("https://github.com/USER/REPO")
                    color: Appearance.colors.colOnSurface
                    onTextChanged: page.customForkUrl = text.trim()
                }

                RippleButtonWithIcon {
                    Layout.preferredHeight: 48
                    buttonRadius: Appearance.rounding.large
                    colBackground: Appearance.colors.colPrimary
                    colText: Appearance.colors.colOnPrimary
                    materialIcon: "play_arrow"
                    mainText: Translation.tr("Clone & Switch")
                    enabled: !actionProc.running
                             && customUrlField.text.trim() !== ""
                             && /^https?:\/\/github\.com\//.test(customUrlField.text.trim())
                    onClicked: {
                        page.runAction("fork-custom",
                            ["--switch", "--fork", page.customForkUrl, "--no-confirm"]);
                    }
                }
            }

            // Warning box explaining the consequences of switching forks.
            NoticeBox {
                Layout.fillWidth: true
                Layout.topMargin: 8
                materialIcon: "info"
                text: Translation.tr("Switching forks replaces your ii folder. You'll lose these visual buttons until you return.\n\n" +
                                     "To return/switch via CLI, run:\n" +
                                     "  vynx fork p3drovfx\n\n" +
                                     "Or run the setup script using the --switch flag:\n" +
                                     "  ~/Downloads/ii-vynx/setup-ii-vynx.sh --switch --fork p3drovfx\n\n" +
                                     "Useful script flags:\n" +
                                     "  --switch               : Switch fork/branch instantly without reinstalling dependencies.\n" +
                                     "  --fork <name|url>      : Specify preset (e.g. p3drovfx, end4, vynx) or a custom GitHub URL.\n" +
                                     "  --branch <name>        : Switch branch (e.g. main, dev).\n" +
                                     "  --preserve-config      : Retain your current configuration settings.")
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Section: Commit History (kept verbatim)
    // ──────────────────────────────────────────────────────────────────────────
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
            id: commitsRepeater
            model: ChangelogService.commits
            delegate: Rectangle {
                id: entryRoot

                readonly property bool isFirst: index === 0
                readonly property bool isLast: index === commitsRepeater.count - 1

                topLeftRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
                topRightRadius: isLast ? Appearance.rounding.large : Appearance.rounding.verysmall
                bottomLeftRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall
                bottomRightRadius: isFirst ? Appearance.rounding.large : Appearance.rounding.verysmall


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