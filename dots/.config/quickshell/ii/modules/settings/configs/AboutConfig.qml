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

    // ── Active-fork state (owned by ShellUpdates so the bar indicator sees it too) ──
    readonly property string activeRemote: ShellUpdates.activeRemote
    readonly property string activeBranch: ShellUpdates.activeBranch
    readonly property string activeFork: ShellUpdates.activeFork
    readonly property string activeCommit: ShellUpdates.activeCommit
    readonly property string remoteCommit: ShellUpdates.remoteCommit
    readonly property bool hasUpdate: ShellUpdates.hasUpdate
    readonly property bool checkingUpdates: ShellUpdates.checking
    property bool logAutoScroll: true

    // ── Custom fork URL input for the Fork Switcher ──
    property string customForkUrl: ""

    readonly property string setupScript: FileUtils.trimFileProtocol(Directories.home + "/.local/share/ii-p3drovfx/setup-ii-p3drovfx.sh")

    // The transient unit writes here instead of to a pipe: a pipe back into this
    // process dies with it, and the script keeps running long after that.
    readonly property string actionLogPath: FileUtils.trimFileProtocol(Directories.home + "/.local/state/ii-p3drovfx/ui-action.log")
    property bool hasSystemdRun: true

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

    Component.onCompleted: {
        ShellUpdates.reloadState();
    }

    onVisibleChanged: {
        if (visible) {
            ShellUpdates.reloadState();
        }
    }

    // ── Action process (run setup-ii-p3drovfx.sh, log into the UI) ──
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
            // The tail is a line behind the unit it follows, so let it drain
            // before it is stopped, or the last few lines never arrive.
            logTailStop.restart();
            if (code === 0) {
                actionProc.logOutput += "✓ Done\n";
                // Re-read state in case the fork/branch changed.
                ShellUpdates.reloadState();
            } else {
                actionProc.logOutput += "✗ Exited with code " + code + "\n";
            }
        }
    }

    // ── Live log: systemd-run's own stdout is empty, so follow the unit's file ──
    Process {
        id: logTailProc
        // -c +1 rather than -n 0: nothing written between the unit starting and
        // the tail attaching is missed. -F re-reads across the truncation the
        // unit does when it opens the file.
        command: ["tail", "-c", "+1", "-F", page.actionLogPath]
        stdout: SplitParser {
            onRead: data => { actionProc.logOutput += data + "\n"; }
        }
    }

    Timer {
        id: logTailStart
        interval: 400
        onTriggered: logTailProc.running = true
    }

    Timer {
        id: logTailStop
        interval: 1200
        onTriggered: logTailProc.running = false
    }

    // Whether the actions can be handed to systemd. Probed once, because the
    // fallback below is meaningfully worse and should not be the default.
    Process {
        id: systemdRunProbe
        running: true
        command: ["bash", "-c", "command -v systemd-run >/dev/null && [ -d /run/systemd/system ]"]
        onExited: code => page.hasSystemdRun = (code === 0)
    }

    // Helper to run an action.
    //
    // apply/update/switch all kill Quickshell partway through — they have to,
    // since swapping the config tree under a live shell makes it hot-reload onto
    // a half-written tree and persist QML defaults over config.json. A plain
    // Process is a child of Quickshell, so it used to be torn down by that same
    // kill, one line after it: the clone was staged, the shell was stopped, and
    // the script died on SIGTERM before the swap ever ran. Its own TERM trap then
    // removed the staging dir, leaving the config untouched and no shell running.
    // A transient systemd unit lives in its own cgroup, outside this process'
    // lifetime, so the script survives the kill and reaches the swap and the
    // restart. KillMode=process matters just as much: at the default,
    // control-group, systemd cleans the unit's cgroup up when the script exits
    // and takes the Quickshell it just started down with it.
    //
    // Which is also why the unit is named per run rather than once. The shell
    // the script leaves behind keeps living in the unit's cgroup, and a unit
    // whose cgroup is not empty is never released, dead or not — a fixed name
    // is free exactly once and then refuses every run after it. The stale unit
    // is collected on its own the moment the next run stops that shell.
    function runAction(modeName, args) {
        Config.blockWrites = true;
        actionProc.logOutput = "";
        actionProc.finished = false;
        actionProc.exitCode = -1;
        actionProc.mode = modeName;
        logTailProc.running = false;
        logTailStop.stop();

        if (!page.hasSystemdRun) {
            actionProc.logOutput += "⚠ systemd-run unavailable — Quickshell may not come back on its own.\n";
            actionProc.command = ["bash", page.setupScript, ...args];
            actionProc.running = true;
            return;
        }

        // The wrapper empties the log before systemd-run replaces it, so a run
        // that never reaches the unit — the name taken, the script missing —
        // shows its own error instead of the last run's output scrolling under
        // it. exec keeps systemd-run's exit code as this Process' exit code.
        const cmd = ["bash", "-c", 'mkdir -p "${1%/*}"; : > "$1"; shift; exec "$@"', "ii-p3drovfx-action", page.actionLogPath, "systemd-run", "--user", "--collect", "--wait", "--quiet", "--unit=ii-p3drovfx-action-" + Date.now(), "--property=KillMode=process", "--property=StandardOutput=file:" + page.actionLogPath, "--property=StandardError=inherit",
            // systemd hands a unit with no TTY TERM=dumb, which the script reads
            // as "strip colour" — the log box parses those SGR codes.
            "--setenv=TERM=xterm-256color", "--setenv=COLORTERM=truecolor"];
        // The user manager's copies of these go stale across a compositor
        // restart, and the script needs them live to start the shell back up.
        ["PATH", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_RUNTIME_DIR"].forEach(name => {
            const value = Quickshell.env(name);
            if (value)
                cmd.push("--setenv=" + name + "=" + value);
        });
        cmd.push("--", "bash", page.setupScript, ...args);

        actionProc.command = cmd;
        actionProc.running = true;
        logTailStart.restart();
    }

    // ── ANSI → rich text for the log box (the setup script colors its stdout for a terminal) ──
    function colorToHex(c) {
        return "#" + [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("");
    }

    // Foreground color per ANSI SGR code, matched to the semantics the setup script uses them for.
    // Mapped to theme roles (not fixed hex) so it stays legible across light/dark and dynamic accents.
    function ansiFgColor(code) {
        switch (code) {
            case "31": return colorToHex(Appearance.colors.colError);     // red     — errors
            case "32": return colorToHex(Appearance.colors.colPrimary);   // green   — success
            case "33": return colorToHex(Appearance.colors.colTertiary);  // yellow  — warnings
            case "34": return colorToHex(Appearance.colors.colSecondary); // blue    — steps
            case "35": return colorToHex(Appearance.colors.colTertiary);  // magenta — accents
            case "36": return colorToHex(Appearance.colors.colSecondary); // cyan    — headers (bolded too)
            case "90": return colorToHex(Appearance.colors.colSubtext);   // bright  — detail, box frames
            default: return "";
        }
    }

    function escapeHtml(s) {
        return s
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/ {2,}/g, m => "&nbsp;".repeat(m.length))
            .replace(/\n/g, "<br>");
    }

    function ansiToRich(raw) {
        // `install` forwards the base installer's output verbatim, so anything
        // can arrive here. Drop OSC and stray non-CSI escapes before parsing,
        // otherwise they survive escapeHtml and render as literal garbage.
        raw = raw.replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
                 .replace(/\x1b[()][@-~]/g, "")
                 .replace(/\x1b[^\[]/g, "")
                 .replace(/\x1b$/, "");
        // Full CSI grammar: private/parameter bytes, intermediates, final byte.
        const csiPattern = /\x1b\[([0-9;:<=>?]*)([ -\/]*)([@-~])/g;
        let out = "";
        let last = 0;
        let openSpan = false;
        let bold = false;
        let dim = false;
        let italic = false;
        let underline = false;
        let match;
        while ((match = csiPattern.exec(raw)) !== null) {
            out += escapeHtml(raw.substring(last, match.index));
            last = csiPattern.lastIndex;
            // Drop everything that is not a plain SGR sequence: cursor moves,
            // clears, and private-parameter forms such as ESC[?25l.
            if (match[3] !== "m" || match[1].indexOf("?") !== -1) continue;
            const codes = match[1].split(";").filter(c => c !== "");
            if (codes.length === 0) codes.push("0");
            for (const code of codes) {
                if (code === "0") {
                    if (underline) { out += "</u>"; underline = false; }
                    if (italic) { out += "</i>"; italic = false; }
                    if (dim) { out += "</font>"; dim = false; }
                    if (openSpan) { out += "</font>"; openSpan = false; }
                    if (bold) { out += "</b>"; bold = false; }
                } else if (code === "1") {
                    if (!bold) { out += "<b>"; bold = true; }
                } else if (code === "2") {
                    // Dim has no rich-text equivalent; render it as subtext.
                    if (!dim) { out += "<font color=\"" + colorToHex(Appearance.colors.colSubtext) + "\">"; dim = true; }
                } else if (code === "3") {
                    if (!italic) { out += "<i>"; italic = true; }
                } else if (code === "4") {
                    if (!underline) { out += "<u>"; underline = true; }
                } else {
                    const hex = ansiFgColor(code);
                    if (hex !== "") {
                        if (openSpan) out += "</font>";
                        out += "<font color=\"" + hex + "\">";
                        openSpan = true;
                    }
                }
            }
        }
        out += escapeHtml(raw.substring(last));
        if (underline) out += "</u>";
        if (italic) out += "</i>";
        if (dim) out += "</font>";
        if (openSpan) out += "</font>";
        if (bold) out += "</b>";
        return out;
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
                title: Translation.tr("This fork info")
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
                            text: Translation.tr("ii-p3drovfx")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                        }
                        StyledText {
                            text: "<a href='https://github.com/P3DROVFX/ii-p3drovfx'>github.com/P3DROVFX/...</a>"
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
                    RippleButtonWithIcon { materialIcon: "code"; mainText: Translation.tr("GitHub"); onClicked: Qt.openUrlExternally("https://github.com/P3DROVFX/ii-p3drovfx") }
                    RippleButtonWithIcon { materialIcon: "adjust"; materialIconFill: false; mainText: Translation.tr("Issues"); onClicked: Qt.openUrlExternally("https://github.com/P3DROVFX/ii-p3drovfx/issues") }
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
                            const label = (page.activeFork === "p3drovfx" || page.activeFork === "mine") ? "P3DROVFX"
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
                        visible: page.hasUpdate && ShellUpdates.commitsBehind > 0
                        iconText: "commit"
                        chipText: Translation.tr("%1 behind").arg(ShellUpdates.commitsBehind)
                        chipColor: Appearance.colors.colErrorContainer
                        textColor: Appearance.colors.colOnErrorContainer
                    }

                    StatusChip {
                        visible: page.activeFork === "p3drovfx" || page.activeFork === "mine"
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
                            const label = (page.activeFork === "p3drovfx" || page.activeFork === "mine") ? "P3DROVFX"
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
                        page.runAction("update", ["update", "--yes", "--keep-config",
                            Config.options.update.replaceHyprConfig ? "--hypr" : "--no-hypr"]);
                    }
                }

                // ── Circle Badge next to the button ──
                Rectangle {
                    visible: page.hasUpdate && !(actionProc.running && actionProc.mode === "update") && !(actionProc.finished && actionProc.mode === "update")
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

                // ── Feedback Badge next to the button (success/error) ──
                Rectangle {
                    visible: actionProc.finished && actionProc.mode === "update"
                    radius: width / 2
                    color: actionProc.exitCode === 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer
                    Layout.preferredHeight: 48
                    Layout.preferredWidth: 48
                    Layout.alignment: Qt.AlignVCenter

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: actionProc.exitCode === 0 ? "done" : "close"
                        iconSize: 22
                        color: actionProc.exitCode === 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                        fill: 1
                    }

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            // ── Toggle: whether the update also overlays this fork's Hyprland config ──
            ConfigSwitch {
                id: replaceHyprConfigSwitch
                Layout.fillWidth: true
                Layout.topMargin: 8
                buttonIcon: "settings_applications"
                text: Translation.tr("Also replace Hyprland config")
                checked: Config.options.update.replaceHyprConfig
                onCheckedChanged: Config.options.update.replaceHyprConfig = checked

                StyledToolTip {
                    text: Translation.tr("When enabled, updating also overlays this fork's ~/.config/hypr onto yours (custom/ is never touched, and anything replaced is backed up first). Disable to update only the Quickshell config.")
                }
            }

            // ── Status + log box (inline) ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.preferredHeight: 40
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
                    Layout.preferredHeight: Math.min(250, logText.implicitHeight + 16)
                    visible: actionProc.logOutput !== ""
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer0
                    border.width: 0

                    StyledFlickable {
                        id: logFlickable
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        contentHeight: logText.implicitHeight
                        // The script draws fixed-width boxes, so the log must
                        // scroll sideways rather than wrap and shred the frames.
                        contentWidth: logText.implicitWidth
                        flickableDirection: Flickable.HorizontalAndVerticalFlick

                        Connections {
                            target: logFlickable
                            function onContentYChanged() {
                                page.logAutoScroll = logFlickable.contentY >= Math.max(0, logFlickable.contentHeight - logFlickable.height) - 2;
                            }
                        }

                        Text {
                            id: logText
                            textFormat: Text.RichText
                            text: page.ansiToRich(actionProc.logOutput)
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            wrapMode: Text.NoWrap

                            onTextChanged: Qt.callLater(() => {
                                if (page.logAutoScroll)
                                    logFlickable.contentY = Math.max(0, logFlickable.contentHeight - logFlickable.height);
                            });
                        }
                    }
                }
            }
        }

        // ── Automatic check for new commits on the active fork + branch ──
        ContentSubsection {
            Layout.fillWidth: true
            Layout.topMargin: 8
            title: Translation.tr("Automatic update check")
            icon: "schedule"
            tooltip: Translation.tr("How often the shell probes this fork's remote for new commits, plus once a few seconds after every shell start. The check is a single git ls-remote plus one GitHub API request — it never touches your config. Only the bar indicator and the badge above react to it; nothing updates on its own.")

            ConfigSelectionArray {
                currentValue: Config.options.update.autoCheckInterval
                onSelected: newValue => {
                    Config.options.update.autoCheckInterval = newValue;
                }
                options: [
                    {
                        "displayName": Translation.tr("Disabled"),
                        "icon": "block",
                        "value": "disabled"
                    },
                    {
                        "displayName": Translation.tr("Every 10 min"),
                        "icon": "bolt",
                        "value": "10min"
                    },
                    {
                        "displayName": Translation.tr("Hourly"),
                        "icon": "avg_pace",
                        "value": "hourly"
                    },
                    {
                        "displayName": Translation.tr("Daily"),
                        "icon": "today",
                        "value": "daily"
                    },
                    {
                        "displayName": Translation.tr("Weekly"),
                        "icon": "date_range",
                        "value": "weekly"
                    }
                ]
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.leftMargin: 4
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: {
                        if (page.checkingUpdates)
                            return Translation.tr("Checking…");
                        if (ShellUpdates.lastCheck <= 0)
                            return Translation.tr("Never checked");
                        return Translation.tr("Last checked %1").arg(new Date(ShellUpdates.lastCheck).toLocaleString(Qt.locale(), Locale.ShortFormat));
                    }
                }

                RippleButtonWithIcon {
                    materialIcon: "refresh"
                    mainText: Translation.tr("Check now")
                    enabled: !page.checkingUpdates
                    onClicked: ShellUpdates.refresh()
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
                currentValue: (page.activeFork === "p3drovfx" || page.activeFork === "mine") ? page.activeBranch : null
                onSelected: newValue => {
                    if (newValue === page.activeBranch) return;
                    page.runAction("branch-" + newValue,
                        ["switch", "--branch", newValue, "--fork", page.activeFork,
                         "--yes", "--keep-config"]);
                }
                options: [
                    {
                        displayName: Translation.tr("main") + " · " + Translation.tr("stable"),
                        icon: (page.activeBranch === "main" && (page.activeFork === "p3drovfx" || page.activeFork === "mine")) ? "check" : "verified",
                        value: "main",
                        enabled: !actionProc.running && (page.activeFork === "p3drovfx" || page.activeFork === "mine")
                    },
                    {
                        displayName: Translation.tr("dev") + " · " + Translation.tr("new features"),
                        icon: (page.activeBranch === "dev" && (page.activeFork === "p3drovfx" || page.activeFork === "mine")) ? "check" : "science",
                        value: "dev",
                        enabled: !actionProc.running && (page.activeFork === "p3drovfx" || page.activeFork === "mine")
                    }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: visible ? 6 : 0
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                visible: page.activeFork !== "p3drovfx" && page.activeFork !== "mine"
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
                                ["switch", "--fork", modelData.id, "--yes"]);
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
                            ["switch", "--fork", page.customForkUrl, "--yes"]);
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
                                     "Or run the setup script directly:\n" +
                                     "  ~/.local/share/ii-p3drovfx/setup-ii-p3drovfx.sh switch --fork p3drovfx\n\n" +
                                     "Useful subcommands and flags:\n" +
                                     "  switch                 : Switch fork/branch instantly without reinstalling dependencies.\n" +
                                     "  update                 : Refresh the fork and branch you are already on.\n" +
                                     "  --fork <name|url>      : Specify preset (e.g. p3drovfx, end4, vynx) or a custom GitHub URL.\n" +
                                     "  --branch <name>        : Switch branch (e.g. main, dev).\n" +
                                     "  --keep-config          : Retain your current configuration settings.")
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

                // ChangelogService returns newest-first: the first delegate
                // owns the top outer corners and the last owns the bottom.
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

    ContentSection {
        icon: "tune"
        title: Translation.tr("Advanced")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("User agent string")
            text: Config.options.networking.userAgent
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.networking.userAgent = text;
            }
        }

        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr("Free Settings memory after closing")
            checked: Config.options.settingsApp.unloadAfterSeconds > 0
            onCheckedChanged: {
                Config.options.settingsApp.unloadAfterSeconds = checked ? 5 : 0;
            }

            StyledToolTip {
                text: Translation.tr("When enabled, the Settings app is removed from memory 5 seconds after it is closed. The next opening will have a short cold-start delay.")
            }
        }
    }
}
