import QtQuick
import QtQuick.Layouts
import qs
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * About & Updates.
 *
 * What this shell is running, whether the fork's remote has moved on, and
 * what the waiting update contains — in that order, since that is what the
 * page is opened for. The checkout itself is only ever changed from a
 * terminal window (see ShellUpdates.launchInTerminal), so the log outlives
 * the shell restart the setup script performs. Switching fork or branch and
 * the lineage links live on sub-pages.
 */
Item {
    id: root
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function openSubPage(url) {
        subPageOverlay.open(Qt.resolvedUrl(url));
    }

    readonly property bool hasUpdate: ShellUpdates.hasUpdate
    readonly property bool checking: ShellUpdates.checking
    readonly property int behind: ShellUpdates.commitsBehind
    readonly property string forkLabel: ShellUpdates.forkLabel(ShellUpdates.activeFork)
    readonly property bool onP3drovfx: ShellUpdates.activeFork === "p3drovfx" || ShellUpdates.activeFork === "mine"
    readonly property string shortCommit: ShellUpdates.activeCommit.substring(0, 7)
    readonly property string repoUrl: {
        const slug = ShellUpdates.githubSlug(ShellUpdates.activeRemote);
        return slug === "" ? "" : `https://github.com/${slug}`;
    }

    // With AI summaries on, the summary is the headline and the commit list is
    // detail that folds away; without them the list is all there is to read,
    // so it stays open.
    readonly property bool listsFold: Config.options.update.aiSummary
    readonly property var listedCommits: root.hasUpdate ? ShellUpdates.commits : ShellUpdates.recentCommits
    readonly property bool listVisible: root.hasUpdate ? (ShellUpdates.commits.length > 0 || ShellUpdateSummary.current) : (ShellUpdates.recentCommits.length > 0 || ShellUpdates.recentLoading)

    function refreshRecent() {
        if (!root.visible || root.hasUpdate || root.checking)
            return;
        ShellUpdates.loadRecent();
    }

    Component.onCompleted: {
        ShellUpdates.reloadState();
        if (!ShellUpdates.probed)
            ShellUpdates.refresh();
        else
            root.refreshRecent();
    }

    // A page opened to see whether there is an update should not show a
    // shrug: if nothing has been asked of the remote since the shell started,
    // ask once now, whatever the automatic interval says.
    onVisibleChanged: {
        if (!visible)
            return;
        ShellUpdates.reloadState();
        if (!ShellUpdates.probed) {
            ShellUpdates.refresh();
            return;
        }
        root.refreshRecent();
    }

    onHasUpdateChanged: root.refreshRecent()
    onCheckingChanged: root.refreshRecent()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // ── Identity: fork, branch, commit, and whether the remote moved ──
        //
        // The logo is the card. It spans the card's height on the left, and
        // everything else - name, branch, status, actions - sits in one column
        // beside it, so the mark is never a small badge above a row of buttons.
        Rectangle {
            id: hero
            Layout.fillWidth: true
            implicitHeight: heroRow.implicitHeight + 48
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            readonly property real logoSize: 112

            RowLayout {
                id: heroRow
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 24
                }
                spacing: 24

                // The fork's own mark where it has one; a custom remote gets a
                // plain symbol rather than someone else's logo.
                Item {
                    Layout.preferredWidth: hero.logoSize
                    Layout.preferredHeight: hero.logoSize
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        anchors.fill: parent
                        visible: root.onP3drovfx
                        source: "file://" + Quickshell.shellPath("assets/icons/ii-p3drovfx.png")
                        sourceSize: Qt.size(hero.logoSize * 2, hero.logoSize * 2)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    IconImage {
                        anchors.fill: parent
                        visible: ShellUpdates.activeFork === "end4"
                        implicitSize: hero.logoSize
                        source: Quickshell.iconPath("illogical-impulse")
                    }

                    CustomIcon {
                        anchors.fill: parent
                        width: hero.logoSize
                        height: hero.logoSize
                        visible: ShellUpdates.activeFork === "vynx" || ShellUpdates.activeFork === "upstream"
                        source: "ii-vynx"
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !root.onP3drovfx && ShellUpdates.activeFork !== "end4" && ShellUpdates.activeFork !== "vynx" && ShellUpdates.activeFork !== "upstream"
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer2

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "hub"
                            iconSize: 56
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledText {
                                Layout.fillWidth: true
                                text: root.forkLabel
                                font.pixelSize: 32
                                font.weight: Font.Bold
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                spacing: 8

                                MaterialSymbol {
                                    text: "call_split"
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: ShellUpdates.activeBranch
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    visible: root.shortCommit !== ""
                                    text: root.shortCommit
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }

                                Rectangle {
                                    visible: root.onP3drovfx
                                    implicitWidth: channelText.implicitWidth + 16
                                    implicitHeight: channelText.implicitHeight + 6
                                    radius: Appearance.rounding.full
                                    color: ShellUpdates.activeBranch === "main" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colTertiaryContainer

                                    StyledText {
                                        id: channelText
                                        anchors.centerIn: parent
                                        text: ShellUpdates.activeBranch === "main" ? Translation.tr("Stable") : Translation.tr("New features")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: ShellUpdates.activeBranch === "main" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnTertiaryContainer
                                    }
                                }
                            }
                        }

                        // Status, top right, with the last check time under it.
                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                            Rectangle {
                                id: statusPill
                                Layout.alignment: Qt.AlignRight
                                implicitWidth: statusRow.implicitWidth + 24
                                implicitHeight: 36
                                radius: Appearance.rounding.full
                                color: root.checking ? Appearance.colors.colLayer2 : root.hasUpdate ? Appearance.colors.colTertiaryContainer : ShellUpdates.remoteCommit !== "" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

                                readonly property color fg: root.checking ? Appearance.colors.colOnLayer1 : root.hasUpdate ? Appearance.colors.colOnTertiaryContainer : ShellUpdates.remoteCommit !== "" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

                                Behavior on color {
                                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                }

                                RowLayout {
                                    id: statusRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    MaterialLoadingIndicator {
                                        visible: root.checking
                                        implicitSize: 16
                                    }

                                    MaterialSymbol {
                                        visible: !root.checking
                                        text: root.hasUpdate ? "deployed_code_update" : ShellUpdates.remoteCommit !== "" ? "check_circle" : ShellUpdates.probed ? "cloud_off" : "help"
                                        fill: 1
                                        iconSize: 18
                                        color: statusPill.fg
                                    }

                                    StyledText {
                                        text: {
                                            if (root.checking)
                                                return Translation.tr("Checking…");
                                            if (ShellUpdates.remoteCommit === "")
                                                return ShellUpdates.probed ? Translation.tr("Remote unreachable") : Translation.tr("Not checked yet");
                                            if (!root.hasUpdate)
                                                return Translation.tr("Up to date");
                                            return root.behind > 0 ? Translation.tr("%1 commits behind").arg(root.behind) : Translation.tr("Update available");
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: statusPill.fg
                                    }
                                }
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                Layout.rightMargin: 4
                                visible: text !== ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: {
                                    if (ShellUpdates.lastCheck <= 0)
                                        return "";
                                    return Translation.tr("Last checked %1").arg(new Date(ShellUpdates.lastCheck).toLocaleString(Qt.locale(), Locale.ShortFormat));
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RippleButtonWithIcon {
                            Layout.preferredHeight: 44
                            buttonRadius: Appearance.rounding.full
                            colBackground: root.hasUpdate ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                            colBackgroundHover: root.hasUpdate ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                            colRipple: root.hasUpdate ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
                            colText: root.hasUpdate ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            materialIcon: "terminal"
                            mainText: root.hasUpdate ? Translation.tr("Update now") : Translation.tr("Update")
                            onClicked: {
                                ShellUpdates.launchUpdate();
                                GlobalStates.settingsOpen = false;
                            }

                            StyledToolTip {
                                text: Translation.tr("Opens a terminal running the updater for %1 @ %2. It asks before applying, keeps your settings, and this window closes so the log stays readable while the shell restarts.").arg(root.forkLabel).arg(ShellUpdates.activeBranch)
                            }
                        }

                        RippleButtonWithIcon {
                            Layout.preferredHeight: 44
                            buttonRadius: Appearance.rounding.full
                            materialIcon: "refresh"
                            mainText: Translation.tr("Check now")
                            enabled: !root.checking
                            onClicked: ShellUpdates.refresh()
                        }

                        RippleButtonWithIcon {
                            visible: root.repoUrl !== ""
                            Layout.preferredHeight: 44
                            buttonRadius: Appearance.rounding.full
                            materialIcon: "open_in_new"
                            mainText: root.hasUpdate && ShellUpdates.compareUrl !== "" ? Translation.tr("Compare on GitHub") : Translation.tr("GitHub")
                            onClicked: Qt.openUrlExternally(root.hasUpdate && ShellUpdates.compareUrl !== "" ? ShellUpdates.compareUrl : root.repoUrl)
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

        // ── What the update contains, or what changed lately ──
        ContentSection {
            visible: root.listVisible
            icon: root.hasUpdate ? "new_releases" : "history"
            title: root.hasUpdate ? Translation.tr("What's new") : Translation.tr("Recent changes")
            tooltip: root.hasUpdate ? Translation.tr("The commits on the remote that this checkout does not have yet, grouped by kind. Click one to open it on GitHub.") : Translation.tr("The newest commits on this branch, grouped by kind. Click one to open it on GitHub.")

            ShellUpdateSummaryCard {
                visible: root.hasUpdate
                Layout.fillWidth: true
                showUnavailable: true
                boxColor: Appearance.colors.colLayer1
            }

            RowLayout {
                visible: !root.hasUpdate && ShellUpdates.recentLoading && ShellUpdates.recentCommits.length === 0
                Layout.fillWidth: true
                spacing: 8

                MaterialLoadingIndicator {
                    implicitSize: 20
                }

                StyledText {
                    text: Translation.tr("Fetching commits…")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            ContentSubsection {
                id: commitsBlock
                visible: root.listedCommits.length > 0
                Layout.fillWidth: true
                icon: "commit"
                title: root.hasUpdate ? Translation.tr("%1 new commits").arg(root.listedCommits.length) : Translation.tr("Last %1 commits on %2").arg(root.listedCommits.length).arg(ShellUpdates.activeBranch)
                collapsible: root.listsFold
                expanded: !root.listsFold || !(Persistent.states?.settings?.whatsNewCollapsed ?? true)
                onExpandedChanged: {
                    if (root.listsFold)
                        Persistent.states.settings.whatsNewCollapsed = !expanded;
                }

                // The header click assigns `expanded` and ends the binding
                // above, so a later change of the fold rule is applied by hand.
                Connections {
                    target: Config.options.update
                    function onAiSummaryChanged() {
                        commitsBlock.expanded = !root.listsFold || !(Persistent.states?.settings?.whatsNewCollapsed ?? true);
                    }
                }

                ShellUpdateChangelog {
                    Layout.fillWidth: true
                    commits: root.listedCommits
                    truncated: root.hasUpdate && ShellUpdates.commitsTruncated
                    rowColor: Appearance.colors.colLayer1
                    rowHoverColor: Appearance.colors.colLayer1Hover
                }
            }
        }

        // ── How updates are found and applied ──
        ContentSection {
            icon: "tune"
            title: Translation.tr("Update settings")

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Automatic check")
                icon: "schedule"
                tooltip: Translation.tr("How often the shell probes this fork's remote for new commits, plus once a few seconds after every shell start. The check is a single git ls-remote plus one GitHub API request — it never touches your config. Only the status above and the bar indicator react to it; nothing updates on its own.")

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
            }

            ContentSubsection {
                Layout.fillWidth: true
                Layout.topMargin: 8
                title: Translation.tr("Applying")
                icon: "system_update_alt"
                tooltip: Translation.tr("What the updater does besides refreshing the Quickshell config.")

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "settings_applications"
                    text: Translation.tr("Also replace Hyprland config")
                    checked: Config.options.update.replaceHyprConfig
                    onCheckedChanged: Config.options.update.replaceHyprConfig = checked

                    StyledToolTip {
                        text: Translation.tr("When enabled, updating also overlays this fork's ~/.config/hypr onto yours (custom/ is never touched, and anything replaced is backed up first). Disable to update only the Quickshell config.")
                    }
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                Layout.topMargin: 8
                title: Translation.tr("AI summary")
                icon: "auto_awesome"
                tooltip: Translation.tr("After a check finds enough new commits, asks the AI tab's current model for a short plain-language summary of them. Uses one request on your key per new remote version; the result is kept until the remote moves again. The Summarize button in What's new works without this.")

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Summarize new commits with AI")
                    checked: Config.options.update.aiSummary
                    onCheckedChanged: Config.options.update.aiSummary = checked
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    enabled: Config.options.update.aiSummary
                    icon: "filter_list"
                    text: Translation.tr("Only when at least this many commits behind")
                    value: Config.options.update.aiSummaryMinCommits
                    from: 1
                    to: 500
                    stepSize: 1
                    onValueChanged: Config.options.update.aiSummaryMinCommits = value
                }

                StyledText {
                    visible: Config.options.update.aiSummary && !ShellUpdateSummary.submitCheck?.allowed
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    text: {
                        switch (ShellUpdateSummary.unavailableReason) {
                        case "disabled":
                            return Translation.tr("AI is turned off in Policies, so nothing will be summarised until it is enabled.");
                        case "missing-key":
                            return Translation.tr("The AI tab's current model has no API key yet; add one or pick another model.");
                        case "model-unavailable":
                            return Translation.tr("No AI model is selected; pick one in the AI tab.");
                        case "remote-model-blocked":
                            return Translation.tr("Local-only AI mode blocks the current model; pick a local one.");
                        default:
                            return "";
                        }
                    }
                }
            }
        }

        // ── Where the checkout comes from ──
        ContentSection {
            icon: "hub"
            title: Translation.tr("Source")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ConfigSubpageRow {
                    buttonIcon: "fork_right"
                    title: Translation.tr("Fork & branch")
                    description: Translation.tr("Switch between stable and new features, move to another fork, or clone one by URL")
                    summary: `${root.forkLabel} · ${ShellUpdates.activeBranch}`
                    onClicked: root.openSubPage("widgets/ForkBranchConfig.qml")
                }

                ConfigSubpageRow {
                    buttonIcon: "account_tree"
                    title: Translation.tr("About this shell")
                    description: Translation.tr("The projects this configuration builds on, with their docs and issue trackers")
                    summary: `ii-p3drovfx · ii-vynx · illogical-impulse · ${SystemInfo.distroName}`
                    onClicked: root.openSubPage("widgets/ShellLineageConfig.qml")
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
