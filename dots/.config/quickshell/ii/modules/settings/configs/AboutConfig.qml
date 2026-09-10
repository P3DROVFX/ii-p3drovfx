import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import qs
import Quickshell
import Quickshell.Io
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
 * the shell restart the setup script performs. Fork and branch switching,
 * the projects this shell builds on and the people who built this fork
 * follow on the same page.
 */
Item {
    id: root
    anchors.fill: parent

    property alias contentY: page.contentY

    // People who contributed to this fork, as credited by its author, read
    // from CONTRIBUTORS.json at the top of the ii folder: GitHub login,
    // display name and a one-line role each; the avatar comes from GitHub.
    property var contributors: []

    FileView {
        path: Quickshell.shellPath("CONTRIBUTORS.json")
        onLoaded: {
            let parsed = null;
            try {
                parsed = JSON.parse(text());
            } catch (e) {
                console.warn("[About] CONTRIBUTORS.json is not valid JSON:", e);
                return;
            }
            const list = Array.isArray(parsed?.contributors) ? parsed.contributors : [];
            root.contributors = list.filter(c => c && typeof c.login === "string" && c.login !== "");
        }
        onLoadFailed: error => console.warn("[About] CONTRIBUTORS.json could not be read:", error)
    }

    readonly property var forkPresets: [
        { "id": "p3drovfx", "label": "II-P3DROVFX", "icon": "fork_right" },
        { "id": "end4", "label": "end-4", "icon": "deployed_code" },
        { "id": "vynx", "label": "ii-vynx", "icon": "cloud_download" }
    ]

    // What the confirmation dialog is about: "branch" or "fork", the
    // argument the script gets, and how the dialog names it.
    property string pendingKind: ""
    property string pendingTarget: ""
    property string pendingLabel: ""

    function confirm(kind, target, label) {
        root.pendingKind = kind;
        root.pendingTarget = target;
        root.pendingLabel = label;
        confirmDialog.show = true;
    }

    // Both switches replace the whole ii folder, so each is confirmed with
    // what exactly gets replaced, then handed to a terminal window and the
    // Settings window closes: the setup script restarts the shell partway
    // through, and only a terminal keeps the log readable across that.
    function runPending() {
        confirmDialog.show = false;
        if (root.pendingKind === "branch")
            ShellUpdates.launchBranchSwitch(root.pendingTarget);
        else if (root.pendingKind === "fork")
            ShellUpdates.launchForkSwitch(root.pendingTarget);
        else
            return;
        GlobalStates.settingsOpen = false;
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

    // One cell of the 2×2 lineage grid: the title on top, the project's mark
    // large in the middle, its name, home link and buttons under it. Corner
    // radii are set per cell by the caller.
    component LineageTile: ContentSubsection {
        id: tile
        property string name: ""
        property string url: ""
        property Component logo: null
        // [{icon, label, url, fill}]
        property var links: []

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        topLeftRadius: Appearance.rounding.verysmall
        topRightRadius: Appearance.rounding.verysmall
        bottomLeftRadius: Appearance.rounding.verysmall
        bottomRightRadius: Appearance.rounding.verysmall

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 12

            Loader {
                Layout.preferredWidth: 50
                Layout.preferredHeight: 50
                sourceComponent: tile.logo
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: tile.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: tile.url !== ""
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: `<a href='${tile.url}'>${tile.url.replace(/^https?:\/\/(www\.)?/, "")}</a>`
                    textFormat: Text.RichText
                    elide: Text.ElideRight
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    PointingHandLinkHover {}
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: tile.links

                delegate: RippleButtonWithIcon {
                    required property var modelData
                    materialIcon: modelData.icon
                    materialIconFill: modelData.fill ?? true
                    mainText: modelData.label
                    onClicked: Qt.openUrlExternally(modelData.url)
                }
            }
        }
    }

    // One credited person: GitHub avatar (initial until it loads), name, role.
    // The whole card opens the profile. Cards sit in a two-column grid, so
    // the big corners go on the grid's outer corners, not on each card.
    component ContributorRow: RippleButton {
        id: person
        property string login: ""
        property string name: ""
        property string role: ""
        // Position in the grid. Named apart from the delegate's `index`: a
        // property redeclared by the delegate is invisible to bindings here.
        property int slot: 0
        property int count: 1
        readonly property int lastRow: Math.ceil(count / 2) - 1
        readonly property int row: Math.floor(slot / 2)
        readonly property bool leftCol: slot % 2 === 0
        readonly property bool rightEdge: !leftCol || slot === count - 1

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: personLayout.implicitHeight + 20
        topLeftRadius: row === 0 && leftCol ? Appearance.rounding.large : Appearance.rounding.verysmall
        topRightRadius: row === 0 && rightEdge ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomLeftRadius: row === lastRow && leftCol ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomRightRadius: row === lastRow && rightEdge ? Appearance.rounding.large : Appearance.rounding.verysmall
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: Qt.openUrlExternally(`https://github.com/${person.login}`)

        StyledToolTip {
            text: `github.com/${person.login}`
        }

        contentItem: RowLayout {
            id: personLayout
            spacing: 12

            Item {
                Layout.leftMargin: 2
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colSecondaryContainer
                    visible: avatar.status !== Image.Ready

                    StyledText {
                        anchors.centerIn: parent
                        text: person.name.charAt(0).toUpperCase()
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                Image {
                    id: avatar
                    anchors.fill: parent
                    source: person.login !== "" ? `https://avatars.githubusercontent.com/${person.login}?s=96` : ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: avatar.width
                            height: avatar.height
                            radius: width / 2
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: person.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: person.role
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                Layout.rightMargin: 4
                text: "open_in_new"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
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

            ConfigSwitch {
                buttonIcon: "settings_applications"
                text: Translation.tr("Also replace Hyprland config")
                checked: Config.options.update.replaceHyprConfig
                onCheckedChanged: Config.options.update.replaceHyprConfig = checked

                StyledToolTip {
                    text: Translation.tr("When enabled, updating also overlays this fork's ~/.config/hypr onto yours (custom/ is never touched, and anything replaced is backed up first). Disable to update only the Quickshell config.")
                }
            }

            ConfigSwitch {
                buttonIcon: "auto_awesome"
                text: Translation.tr("Summarize new commits with AI")
                checked: Config.options.update.aiSummary
                onCheckedChanged: Config.options.update.aiSummary = checked

                StyledToolTip {
                    text: Translation.tr("After a check finds enough new commits, asks the AI tab's current model for a short plain-language summary of them. Uses one request on your key per new remote version; the result is kept until the remote moves again. The Summarize button in What's new works without this.")
                }
            }

            ConfigSpinBox {
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

        // ── Where the checkout comes from ──
        ContentSection {
            icon: "fork_right"
            title: Translation.tr("Fork & branch")
            tooltip: Translation.tr("A branch switch keeps your settings; a fork switch resets them to that fork's defaults, since its options differ. Both replace the ii folder, keep a backup of what they replaced, and run in a terminal window after a confirmation.")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { "icon": "hub", "text": root.forkLabel },
                        { "icon": "call_split", "text": ShellUpdates.activeBranch },
                        { "icon": "commit", "text": root.shortCommit }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        visible: modelData.text !== ""
                        implicitWidth: chipLayout.implicitWidth + 24
                        implicitHeight: 32
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer

                        RowLayout {
                            id: chipLayout
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: modelData.icon
                                iconSize: 16
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                text: modelData.text
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                StyledText {
                    visible: ShellUpdates.activeRemote !== ""
                    Layout.fillWidth: true
                    text: ShellUpdates.activeRemote
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignRight
                }
            }

            ContentSubsection {
                title: Translation.tr("Branch")
                icon: "call_split"
                tooltip: Translation.tr("main is what has been tested; dev gets features as they land.")

                ConfigSelectionArray {
                    currentValue: root.onP3drovfx ? ShellUpdates.activeBranch : null
                    onSelected: newValue => {
                        if (newValue === ShellUpdates.activeBranch)
                            return;
                        root.confirm("branch", newValue, newValue);
                    }
                    options: [
                        {
                            "displayName": Translation.tr("main") + " · " + Translation.tr("stable"),
                            "icon": "verified",
                            "value": "main",
                            "enabled": root.onP3drovfx
                        },
                        {
                            "displayName": Translation.tr("dev") + " · " + Translation.tr("new features"),
                            "icon": "science",
                            "value": "dev",
                            "enabled": root.onP3drovfx
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Fork")
                icon: "swap_horiz"

                ConfigSelectionArray {
                    currentValue: root.onP3drovfx ? "p3drovfx" : ShellUpdates.activeFork
                    onSelected: newValue => {
                        if (newValue === ShellUpdates.activeFork || (newValue === "p3drovfx" && root.onP3drovfx))
                            return;
                        const preset = root.forkPresets.find(p => p.id === newValue);
                        root.confirm("fork", newValue, preset ? preset.label : newValue);
                    }
                    options: root.forkPresets.map(p => ({ "displayName": p.label, "icon": p.icon, "value": p.id }))
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    text: root.onP3drovfx
                        ? Translation.tr("Other forks do not have this page: to come back, or to try a fork by URL, run 'II-P3DROVFX fork <name or URL>' in a terminal.")
                        : Translation.tr("Branches are only offered for II-P3DROVFX here. For this fork, run 'II-P3DROVFX branch <name>' in a terminal.")
                }
            }
        }

        // ── What this shell builds on ──
        ContentSection {
            icon: "account_tree"
            title: Translation.tr("About this shell")
            tooltip: Translation.tr("Each project builds on the next one.")

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 2
                columnSpacing: 2

                LineageTile {
                    topLeftRadius: Appearance.rounding.large
                    title: Translation.tr("This fork")
                    icon: "call_split"
                    name: "II-P3DROVFX"
                    url: "https://github.com/P3DROVFX/ii-p3drovfx"
                    links: [
                        { "icon": "code", "label": Translation.tr("GitHub"), "url": "https://github.com/P3DROVFX/ii-p3drovfx" },
                        { "icon": "auto_stories", "label": Translation.tr("Wiki"), "url": "https://github.com/P3DROVFX/ii-p3drovfx/wiki" },
                        { "icon": "adjust", "label": Translation.tr("Issues"), "url": "https://github.com/P3DROVFX/ii-p3drovfx/issues", "fill": false }
                    ]
                    logo: Image {
                        anchors.fill: parent
                        source: "file://" + Quickshell.shellPath("assets/icons/ii-p3drovfx.png")
                        sourceSize: Qt.size(width * 2, height * 2)
                        fillMode: Image.PreserveAspectFit
                    }
                }

                LineageTile {
                    topRightRadius: Appearance.rounding.large
                    title: Translation.tr("Upstream")
                    icon: "code"
                    name: "ii-vynx"
                    url: "https://github.com/vaguesyntax/ii-vynx"
                    links: [
                        { "icon": "auto_stories", "label": Translation.tr("Wiki"), "url": "https://github.com/vaguesyntax/ii-vynx/wiki" },
                        { "icon": "adjust", "label": Translation.tr("Issues"), "url": "https://github.com/vaguesyntax/ii-vynx/issues", "fill": false }
                    ]
                    logo: CustomIcon {
                        source: "ii-vynx"
                    }
                }

                LineageTile {
                    bottomLeftRadius: Appearance.rounding.large
                    title: Translation.tr("Parent dots")
                    icon: "deployed_code"
                    name: "illogical-impulse"
                    url: "https://github.com/end-4/dots-hyprland"
                    links: [
                        { "icon": "auto_stories", "label": Translation.tr("Wiki"), "url": "https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/" },
                        { "icon": "favorite", "label": Translation.tr("Sponsor"), "url": "https://github.com/sponsors/end-4" }
                    ]
                    logo: IconImage {
                        anchors.fill: parent
                        source: Quickshell.iconPath("illogical-impulse")
                    }
                }

                LineageTile {
                    bottomRightRadius: Appearance.rounding.large
                    title: Translation.tr("Distribution")
                    icon: "developer_board"
                    name: SystemInfo.distroName
                    url: SystemInfo.homeUrl
                    links: [
                        { "icon": "auto_stories", "label": Translation.tr("Docs"), "url": SystemInfo.documentationUrl },
                        { "icon": "bug_report", "label": Translation.tr("Bugs"), "url": SystemInfo.bugReportUrl }
                    ]
                    logo: IconImage {
                        anchors.fill: parent
                        source: Quickshell.iconPath(SystemInfo.logo)
                    }
                }
            }
        }

        // ── Who built this fork ──
        ContentSection {
            icon: "group"
            title: Translation.tr("Contributors")
            tooltip: Translation.tr("People credited by the fork's author. The list lives at the top of this page's source file.")

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 2
                columnSpacing: 2

                Repeater {
                    model: root.contributors

                    delegate: ContributorRow {
                        required property var modelData
                        required property int index
                        slot: index
                        login: modelData.login
                        name: modelData.name
                        role: modelData.role
                        count: root.contributors.length
                    }
                }
            }
        }
    }

    WindowDialog {
        id: confirmDialog
        parent: root
        anchors.fill: parent
        show: false
        backgroundWidth: 400
        z: 100000
        onDismiss: show = false

        WindowDialogTitle {
            text: Translation.tr("Switch to %1?").arg(root.pendingLabel)
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: root.pendingKind === "branch"
                ? Translation.tr("The ii folder is replaced with the %1 branch of %2. Your settings are kept and the shell restarts. The run happens in a terminal window and this window closes.").arg(root.pendingLabel).arg(root.forkLabel)
                : Translation.tr("The ii folder is replaced with that fork's latest and your settings are reset to its defaults, since its options differ. A backup of both is kept. The run happens in a terminal window and this window closes.")
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: confirmDialog.show = false
            }

            DialogButton {
                buttonText: Translation.tr("Switch")
                onClicked: root.runPending()
            }
        }
    }
}
