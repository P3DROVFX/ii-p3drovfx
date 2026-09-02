import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.configs.presets

ContentPage {
    id: page
    forceWidth: false

    // 0 the presets on this machine · 1 what other people published · 2 yours
    property alias currentTab: tabBar.currentIndex

    SecondaryTabBar {
        id: tabBar
        Layout.fillWidth: true

        SecondaryTabButton {
            buttonIcon: "style"
            buttonText: Translation.tr("My presets")
        }

        SecondaryTabButton {
            buttonIcon: "storefront"
            buttonText: PresetStore.updateCount > 0
                ? Translation.tr("Store (%1)").arg(PresetStore.updateCount)
                : Translation.tr("Store")
        }

        SecondaryTabButton {
            buttonIcon: "cloud_upload"
            buttonText: Translation.tr("Published")
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Presets")
        Layout.fillWidth: true
        visible: page.currentTab === 0

        ConfigPresetsView {
            id: presetsView
            text: Translation.tr("Preset Manager")
            onApplyRequested: (name, scanResult) => {
                page.pendingPreset = name;
                page.pendingScan = scanResult;
                page.scanDetailsShown = false;
                applyDialog.show = true;
            }
            onPublishRequested: name => {
                // A preset that already has a repository is released again;
                // one that does not gets a repository made for it.
                if (PresetStore.isOwned(name))
                    pushDialog.openFor(name);
                else
                    publishDialog.openFor(name);
            }
            onUpdateRequested: name => PresetStore.pull(name, false)
        }
    }

    Loader {
        Layout.fillWidth: true
        active: page.currentTab === 1
        visible: active
        sourceComponent: storeTabComponent
    }

    Component {
        id: storeTabComponent

        PresetStoreTab {
            onOpenDetails: entry => detailDialog.openFor(entry)
        }
    }

    Loader {
        Layout.fillWidth: true
        active: page.currentTab === 2
        visible: active
        sourceComponent: publishedTabComponent
    }

    Component {
        id: publishedTabComponent

        PublishedPresetsTab {
            onPushRequested: name => pushDialog.openFor(name)
            onDiffRequested: name => diffDialog.openFor(name, false)
        }
    }

    // Anything the store refused, wherever it was pressed. Without this a
    // failed install or update is simply a button that did nothing.
    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: -20
        visible: PresetStore.lastError.length > 0
        materialIcon: "error"
        text: PresetStore.lastError

        RippleButtonWithIcon {
            buttonRadius: Appearance.rounding.small
            materialIcon: "close"
            mainText: Translation.tr("Dismiss")
            onClicked: PresetStore.lastError = ""
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: -20
        visible: page.currentTab === 0
        text: Translation.tr('Not all options are available in this app. You should also check the config file by hitting the "Config file" button on the topleft corner or opening ~/.config/illogical-impulse/config.json manually.')

        RippleButtonWithIcon {
            id: copyPathButton
            property bool justCopied: false
            buttonRadius: Appearance.rounding.small
            materialIcon: justCopied ? "check" : "content_copy"
            mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
            onClicked: {
                copyPathButton.justCopied = true;
                Quickshell.clipboardText = FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                revertTextTimer.restart();
            }
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            Timer {
                id: revertTextTimer
                interval: 1500
                onTriggered: {
                    copyPathButton.justCopied = false;
                }
            }
        }
    }

    Connections {
        target: Config.options.appearance.palette
        function onTypeChanged() {
            page.showRestartFab = true;
        }
    }

    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            page.showRestartFab = true;
        }
    }

    // ── Apply confirmation ────────────────────────────────────────
    // A preset is a whole config file, and a few config keys are commands the
    // shell runs. Nothing is written until what those commands are has been
    // put in front of whoever is applying it.
    property string pendingPreset: ""
    property var pendingScan: null
    property bool scanDetailsShown: false

    readonly property bool scanUsable: page.pendingScan && page.pendingScan.ok === true
    readonly property var scanGroups: page.scanUsable ? page.pendingScan.groups : []
    readonly property int scanTotal: page.scanUsable ? page.pendingScan.total : 0

    // Migrate up, block newer. An older preset is carried forward by the
    // shell's own migrations; a newer one names settings this build does not
    // have, and there is no honest way to guess what they were meant to mean.
    readonly property var scanCompat: (page.scanUsable && page.pendingScan.compatibility)
        ? page.pendingScan.compatibility : null
    readonly property bool compatBlocked: page.scanCompat !== null && page.scanCompat.ok === false
    readonly property bool compatMigrates: page.scanCompat !== null && page.scanCompat.status === "migrate"

    // How many findings of one group are spelled out before the rest are
    // summed up, so one crowded preset cannot push the buttons off screen.
    readonly property int scanDetailLimit: 6

    function riskIcon(groupId) {
        if (groupId === "shell") return "terminal";
        if (groupId === "ai") return "smart_toy";
        if (groupId === "network") return "public";
        return "help";
    }

    function riskLabel(group) {
        if (group.id === "shell")
            return Translation.tr("Commands it can run on your system: %1").arg(group.count);
        if (group.id === "ai")
            return Translation.tr("Assistant permissions it widens: %1").arg(group.count);
        if (group.id === "network")
            return Translation.tr("Servers and search engines it redirects: %1").arg(group.count);
        return Translation.tr("Other settings that read like commands: %1").arg(group.count);
    }

    WindowDialog {
        id: applyDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        preferredDialogWidth: 520
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr('Apply "%1"?').arg(page.pendingPreset)
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            visible: page.applyBecauseUpdated
            text: Translation.tr("This is the preset your settings came from, and a new version of it was just downloaded.")
            color: Appearance.colors.colOnSurface
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Your current settings are saved first. Anything tied to this machine — API keys, save folders, monitor names and your profile — is kept as it is.")
        }

        Rectangle {
            Layout.fillWidth: true
            visible: page.compatBlocked
            implicitHeight: blockedRow.implicitHeight + 20
            radius: Appearance.rounding.small
            color: Appearance.colors.colErrorContainer

            RowLayout {
                id: blockedRow
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "system_update_alt"
                    iconSize: 18
                    color: Appearance.colors.colOnErrorContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("This preset was made for a newer version of the shell. Update the shell first — settings this build does not have would be mangled rather than applied.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            visible: page.compatMigrates
            text: Translation.tr("This preset was made for an older version of the shell. Its settings are brought up to date as it is applied.")
            color: Appearance.colors.colOnSurfaceVariant
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: !page.scanUsable
            materialIcon: "help"
            text: Translation.tr("This preset could not be inspected, so there is no telling what it changes. Apply it only if you trust where it came from.")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            visible: page.scanUsable && page.scanTotal === 0
            text: Translation.tr("Nothing in this preset runs commands or sends your data anywhere new.")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: page.scanTotal > 0

            Repeater {
                model: page.scanGroups

                delegate: Rectangle {
                    id: riskCard
                    required property var modelData
                    readonly property bool severe: riskCard.modelData.severity === "high"

                    Layout.fillWidth: true
                    implicitHeight: riskColumn.implicitHeight + 20
                    radius: Appearance.rounding.small
                    color: riskCard.severe ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer

                    ColumnLayout {
                        id: riskColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialSymbol {
                                text: page.riskIcon(riskCard.modelData.id)
                                iconSize: 18
                                color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: page.riskLabel(riskCard.modelData)
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 26
                            spacing: 6
                            visible: page.scanDetailsShown

                            Repeater {
                                model: riskCard.modelData.items.slice(0, page.scanDetailLimit)

                                delegate: ColumnLayout {
                                    required property var modelData

                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        wrapMode: Text.Wrap
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                                        opacity: 0.8
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: riskCard.modelData.count > page.scanDetailLimit
                                text: Translation.tr("and %1 more").arg(riskCard.modelData.count - page.scanDetailLimit)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: riskCard.severe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                                opacity: 0.8
                            }
                        }
                    }
                }
            }
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Presets shared by other people are used at your own discretion. They are not reviewed by this project, and no responsibility is taken for what one does to your system.")
            color: Appearance.colors.colOnSurfaceVariant
            font.italic: true
        }

        WindowDialogButtonRow {
            Layout.fillWidth: true

            DialogButton {
                visible: page.scanTotal > 0
                buttonText: page.scanDetailsShown ? Translation.tr("Hide details") : Translation.tr("Show details")
                onClicked: page.scanDetailsShown = !page.scanDetailsShown
            }

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: {
                    page.applyBecauseUpdated = false;
                    applyDialog.show = false;
                }
            }

            DialogButton {
                buttonText: Translation.tr("Apply")
                enabled: !page.compatBlocked
                colEnabled: page.scanTotal > 0 ? Appearance.colors.colError : Appearance.colors.colPrimary
                onClicked: {
                    page.applyBecauseUpdated = false;
                    presetsView.applyPreset(page.pendingPreset);
                    applyDialog.show = false;
                }
            }
        }
    }

    property bool showRestartFab: false

    FloatingActionButton {
        id: restartFab
        parent: page.parent
        anchors {
            right: parent ? parent.right : undefined
            bottom: parent ? parent.bottom : undefined
            margins: 30
        }
        z: 100
        iconText: "restart_alt"
        buttonText: Translation.tr("Restart Shell")
        expanded: false
        visible: opacity > 0
        opacity: page.showRestartFab ? 1 : 0
        scale: opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        colBackground: Appearance.colors.colTertiaryContainer
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colRipple: Appearance.colors.colTertiaryContainerActive
        colOnBackground: Appearance.colors.colOnTertiaryContainer

        onClicked: {
            Quickshell.execDetached(["bash", "-c", "qs kill -c ii && qs -c ii &"]);
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: restartFab.expanded = true
            onExited: restartFab.expanded = false
        }
    }

    // ── The store ────────────────────────────────────────────────────────────

    // Set when the apply dialog was opened by an update landing rather than by
    // the preset being clicked, so it can say so.
    property bool applyBecauseUpdated: false

    property string statusText: ""

    Timer {
        id: statusTimer
        interval: 8000
        repeat: false
        onTriggered: page.statusText = ""
    }

    function report(text) {
        page.statusText = text;
        statusTimer.restart();
    }

    Connections {
        target: PresetStore

        function onInstallFinished(name, ok, error): void {
            page.report(ok ? Translation.tr('"%1" was added to your presets.').arg(name) : error);
        }

        function onRemoveFinished(name, ok, error): void {
            if (!ok)
                page.report(error);
        }

        function onPublishFinished(name, ok, repoUrl, error): void {
            if (!ok) {
                page.report(error);
                return;
            }
            page.publishedUrl = repoUrl;
            publishedDialog.show = true;
        }

        function onPushFinished(name, ok, changed, error): void {
            if (!ok) {
                page.report(error);
                return;
            }
            page.report(changed
                ? Translation.tr('"%1" was updated for everyone who installed it.').arg(name)
                : Translation.tr("Nothing has changed since the last release."));
        }

        function onPullFinished(name, ok, changed, error): void {
            if (!ok) {
                page.report(error);
                return;
            }
            if (!changed) {
                page.report(Translation.tr('"%1" was already up to date.').arg(name));
                return;
            }
            page.report(Translation.tr('"%1" was updated.').arg(name));
            // Downloading an update never changes the running settings. It is
            // only worth asking about when the settings came from this very
            // preset, because then the new version is what the machine is
            // meant to look like.
            if (name !== PresetStore.activePreset)
                return;
            page.applyBecauseUpdated = true;
            presetsView.requestApply(name);
        }

        function onRevertFinished(ok): void {
            page.report(ok ? Translation.tr("Your previous settings are back.")
                : Translation.tr("There was nothing to go back to."));
        }
    }

    property string publishedUrl: ""

    PresetDetailDialog {
        id: detailDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        z: 100000
        onInstallRequested: repo => PresetStore.install(repo, "", false)
        onUpdateRequested: name => PresetStore.pull(name, false)
    }

    PublishDialog {
        id: publishDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        z: 100000
        onPreviewRequested: name => previewDialog.openFor(name)
    }

    PublishPreviewDialog {
        id: previewDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        z: 100001
    }

    PushUpdateDialog {
        id: pushDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        z: 100000
        onDiffRequested: name => diffDialog.openFor(name, false)
    }

    PresetDiffDialog {
        id: diffDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        z: 100001
    }

    WindowDialog {
        id: publishedDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        preferredDialogWidth: 520
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr("It is published")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("The repository is tagged with the store's topic, so it shows up in the Store tab for everyone. Searching GitHub for a brand new repository can take a few minutes.")
        }

        HelperCodeBox {
            Layout.fillWidth: true
            icon: "link"
            title: Translation.tr("Its address")
            codeSnippet: page.publishedUrl
        }

        WindowDialogButtonRow {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Open on GitHub")
                onClicked: {
                    if (page.publishedUrl.length > 0)
                        Quickshell.execDetached(["xdg-open", page.publishedUrl]);
                }
            }

            DialogButton {
                buttonText: Translation.tr("Done")
                onClicked: publishedDialog.show = false
            }
        }
    }

    // Applying snapshots the settings first, and until now the only way back
    // was the command line.
    FloatingActionButton {
        id: revertFab
        parent: page.parent
        anchors {
            right: parent ? parent.right : undefined
            bottom: parent ? parent.bottom : undefined
            rightMargin: 30
            bottomMargin: restartFab.visible ? 30 + restartFab.height + 12 : 30
        }
        z: 100
        iconText: "undo"
        buttonText: Translation.tr("Undo preset")
        expanded: false
        visible: opacity > 0
        opacity: (PresetStore.activePreset.length > 0 && !PresetStore.busy) ? 1 : 0
        scale: opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        colOnBackground: Appearance.colors.colOnSecondaryContainer

        onClicked: revertDialog.show = true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: revertFab.expanded = true
            onExited: revertFab.expanded = false
        }

        StyledToolTip {
            text: Translation.tr("Go back to the settings you had before applying %1")
                .arg(PresetStore.activePreset)
        }
    }

    WindowDialog {
        id: revertDialog
        parent: page.parent ? page.parent : page
        anchors.fill: parent
        show: false
        preferredDialogWidth: 460
        onDismiss: show = false
        z: 100000

        WindowDialogTitle {
            Layout.fillWidth: true
            text: Translation.tr("Undo the preset?")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("Your settings go back to the snapshot taken just before the last preset was applied. Anything changed since then goes with it.")
        }

        WindowDialogButtonRow {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: revertDialog.show = false
            }

            DialogButton {
                buttonText: Translation.tr("Undo")
                colEnabled: Appearance.colors.colError
                onClicked: {
                    PresetStore.revert();
                    revertDialog.show = false;
                }
            }
        }
    }

    // One line of feedback for work that happens without a dialog in front of
    // it — an install finishing, an update landing, a push refused.
    Rectangle {
        parent: page.parent
        anchors {
            left: parent ? parent.left : undefined
            right: parent ? parent.right : undefined
            bottom: parent ? parent.bottom : undefined
            margins: 20
        }
        z: 99
        implicitHeight: statusRow.implicitHeight + 20
        radius: Appearance.rounding.small
        color: Appearance.colors.colSurfaceContainerHighest
        visible: opacity > 0
        opacity: page.statusText.length > 0 ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            id: statusRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 12
            spacing: 8

            MaterialSymbol {
                text: "info"
                iconSize: 18
                color: Appearance.colors.colOnSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: page.statusText
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
            }

            RippleButton {
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 15
                    color: Appearance.colors.colOnSurface
                }

                onClicked: page.statusText = ""
            }
        }
    }
}
