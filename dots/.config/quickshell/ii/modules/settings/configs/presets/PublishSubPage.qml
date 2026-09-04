import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Sub-page for publishing a preset to GitHub, featuring rich metadata controls,
 * screenshot capture, security scan preview, and integration with the FAB status widget.
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack
    property bool showBackButton: true

    property string presetName: ""
    property var shots: []
    property bool capturing: false
    property string captureError: ""
    property string lastCapturedMonitor: ""

    // "idle" | "publishing" | "success" | "error"
    property string publishStatus: "idle"
    property string publishError: ""
    property string publishedUrl: ""

    readonly property string shotDirectory: FileUtils.trimFileProtocol(`${Directories.state}/preset-screenshots`)
    readonly property bool signedIn: PresetStore.auth.authenticated === true

    property var previewData: null
    property bool previewLoading: false
    property bool showPreview: false

    function setPreset(name) {
        root.presetName = name;
        root.shots = [];
        root.captureError = "";
        root.previewData = null;
        root.showPreview = false;
        root.publishStatus = "idle";
        root.publishError = "";
        root.publishedUrl = "";
        repoField.text = "ii-presets";
        descriptionField.text = "";
        notesField.text = "";
        privateBox.checked = false;
        PresetStore.refreshAuth();
    }

    Component.onCompleted: {
        PresetStore.refreshAuth();
    }

    Connections {
        target: PresetStore

        function onPublishFinished(name, ok, repoUrl, error) {
            if (name !== root.presetName)
                return;
            if (ok) {
                root.publishStatus = "success";
                root.publishedUrl = repoUrl || "";
                root.publishError = "";
                autoDismissSuccessTimer.restart();
            } else {
                root.publishStatus = "error";
                root.publishError = error || Translation.tr("Could not publish the preset.");
            }
        }
    }

    Timer {
        id: autoDismissSuccessTimer
        interval: 3500
        repeat: false
        onTriggered: {
            if (root.publishStatus === "success")
                root.goBack();
        }
    }

    function capture() {
        if (root.capturing)
            return;
        root.capturing = true;
        root.captureError = "";
        captureTimeout.restart();
        root.lastCapturedMonitor = (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            ? Hyprland.focusedMonitor.name
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
        try {
            GlobalStates.settingsSuspendedForScreenshot = true;
            GlobalStates.settingsOpen = false;
        } catch (e) {
            console.error("Failed to hide settings for screenshot:", e);
        }
        captureDelay.restart();
    }

    Timer {
        id: captureDelay
        interval: 400
        repeat: false
        onTriggered: {
            try {
                let monitor = root.lastCapturedMonitor.length > 0
                    ? root.lastCapturedMonitor
                    : ((Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
                        ? Hyprland.focusedMonitor.name
                        : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""));
                let target = `${root.shotDirectory}/${Date.now()}.png`;
                let onScreen = monitor.length > 0
                    ? `-o '${StringUtils.shellSingleQuoteEscape(monitor)}' ` : "";
                captureProc.target = target;
                captureProc.command = ["bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.shotDirectory)}' && `
                    + `exec grim ${onScreen}'${StringUtils.shellSingleQuoteEscape(target)}'`];
                captureProc.running = true;
            } catch (e) {
                console.error("Screenshot capture error:", e);
                captureTimeout.stop();
                root.capturing = false;
                GlobalStates.settingsSuspendedForScreenshot = false;
                GlobalStates.settingsOpen = true;
                root.captureError = String(e);
            }
        }
    }

    Timer {
        id: captureTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (root.capturing) {
                root.capturing = false;
                GlobalStates.settingsSuspendedForScreenshot = false;
                GlobalStates.settingsOpen = true;
                if (root.captureError.length === 0) {
                    root.captureError = Translation.tr("Screenshot capture timed out.");
                }
            }
        }
    }

    Process {
        id: captureProc
        property string target: ""
        stderr: StdioCollector {
            id: captureStderr
        }

        onExited: (code, status) => {
            captureTimeout.stop();
            root.capturing = false;
            GlobalStates.settingsSuspendedForScreenshot = false;
            GlobalStates.settingsOpen = true;
            if (code !== 0) {
                const err = captureStderr.text ? captureStderr.text.trim() : "";
                root.captureError = err.length > 0
                    ? err
                    : Translation.tr("The screenshot could not be taken. Is grim installed?");
                return;
            }
            root.shots = root.shots.concat([captureProc.target]);
        }
    }

    Process {
        id: previewProc
        command: ["python3", PresetStore.storeScript, "preview", root.presetName]
        stdout: StdioCollector {
            onStreamFinished: {
                root.previewLoading = false;
                try {
                    root.previewData = JSON.parse(text.trim());
                    root.showPreview = true;
                } catch (e) {
                    root.previewData = null;
                }
            }
        }
        stderr: StdioCollector {}
        onExited: (code) => {
            root.previewLoading = false;
        }
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        // Top Navigation Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: Translation.tr("Publish preset")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    text: Translation.tr("Share \"%1\" to GitHub presets collection").arg(root.presetName)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.publishError.length > 0
            materialIcon: "error"
            text: root.publishError
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.publishStatus === "success"
            materialIcon: "check_circle"
            text: Translation.tr("\"%1\" published successfully to GitHub!").arg(root.presetName)
        }

        // Section: GitHub Authentication
        ContentSection {
            title: Translation.tr("GitHub account")
            icon: "account_circle"
            Layout.fillWidth: true

            GithubSignInPanel {
                Layout.fillWidth: true
            }
        }

        // Section: Repository & Metadata
        ContentSection {
            title: Translation.tr("Preset details & collection")
            icon: "folder_shared"
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Presets are organized in your collection repository. Existing repositories will be updated with this new preset.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.Wrap
                }

                MaterialTextField {
                    id: repoField
                    Layout.fillWidth: true
                    text: "ii-presets"
                    placeholderText: Translation.tr("Repository name (e.g. ii-presets)")
                    error: repoField.text.length > 0 && !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(repoField.text)
                }

                MaterialTextField {
                    id: descriptionField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("What does it look like? Description (optional)")
                }

                MaterialTextField {
                    id: notesField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Release notes for this version (optional)")
                }

                ConfigSwitch {
                    id: privateBox
                    buttonIcon: "lock"
                    text: Translation.tr("Make repository private")
                    checked: false
                }
            }
        }

        // Section: Screenshots
        ContentSection {
            title: Translation.tr("Screenshots (%1/5)").arg(root.shots.length)
            icon: "image"
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Include visual previews of your desktop and lockscreen.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    RippleButtonWithIcon {
                        materialIcon: "photo_camera"
                        mainText: root.capturing ? Translation.tr("Capturing…") : Translation.tr("Take screenshot")
                        buttonRadius: Appearance.rounding.small
                        enabled: !root.capturing && root.shots.length < 5
                        onClicked: root.capture()
                    }

                    StyledText {
                        visible: root.captureError.length > 0
                        text: root.captureError
                        color: Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }

                // Screenshots Preview Grid
                Flow {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: root.shots.length > 0

                    Repeater {
                        model: root.shots

                        delegate: Rectangle {
                            id: shotCard
                            required property string modelData
                            required property int index

                            width: 160
                            height: 100
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colSurfaceContainerHigh
                            clip: true

                            StyledImage {
                                anchors.fill: parent
                                source: shotCard.modelData.startsWith("file://") ? shotCard.modelData : ("file://" + shotCard.modelData)
                                fillMode: Image.PreserveAspectCrop
                            }

                            // Delete button
                            RippleButton {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: Appearance.rounding.full
                                colBackground: ColorUtils.transparentize(Appearance.colors.colSurface, 0.3)

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 14
                                    color: Appearance.colors.colError
                                }

                                onClicked: {
                                    let copy = root.shots.slice();
                                    copy.splice(shotCard.index, 1);
                                    root.shots = copy;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Section: Safety & Inspection
        ContentSection {
            title: Translation.tr("Security & exported data preview")
            icon: "security"
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Private tokens, API keys and personal paths are automatically stripped. You can inspect the sanitized output below.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.Wrap
                }

                RippleButtonWithIcon {
                    materialIcon: root.showPreview ? "visibility_off" : "visibility"
                    mainText: root.previewLoading
                        ? Translation.tr("Scanning…")
                        : (root.showPreview ? Translation.tr("Hide inspection") : Translation.tr("Inspect data"))
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    enabled: !root.previewLoading && root.presetName.length > 0
                    onClicked: {
                        if (root.showPreview) {
                            root.showPreview = false;
                        } else if (root.previewData) {
                            root.showPreview = true;
                        } else {
                            root.previewLoading = true;
                            previewProc.running = true;
                        }
                    }
                }

                // Inspection Panel
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.showPreview && root.previewData !== null
                    spacing: 8

                    NoticeBox {
                        Layout.fillWidth: true
                        materialIcon: "verified_user"
                        text: Translation.tr("Kept %1 settings keys. Stripped %2 personal or machine-specific keys.")
                            .arg(root.previewData ? root.previewData.total : 0)
                            .arg(root.previewData ? root.previewData.dropped.length : 0)
                    }

                    // Flagged values warning
                    NoticeBox {
                        Layout.fillWidth: true
                        visible: root.previewData && root.previewData.flagged && root.previewData.flagged.length > 0
                        materialIcon: "warning"
                        text: Translation.tr("%1 value(s) look like addresses, commands or paths. Make sure they are safe before publishing.")
                            .arg(root.previewData ? root.previewData.flagged.length : 0)
                    }

                    // Flagged items list
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.previewData && root.previewData.flagged && root.previewData.flagged.length > 0

                        Repeater {
                            model: (root.previewData && root.previewData.flagged) ? root.previewData.flagged : []

                            delegate: Rectangle {
                                id: flaggedCard
                                required property var modelData

                                Layout.fillWidth: true
                                implicitHeight: itemCol.implicitHeight + 20
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colSurfaceContainerHigh
                                border.width: 1
                                border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)

                                ColumnLayout {
                                    id: itemCol
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                        margins: 10
                                    }
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        MaterialSymbol {
                                            text: "flag"
                                            iconSize: 16
                                            color: Appearance.colors.colError
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: flaggedCard.modelData.path
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnSurface
                                            wrapMode: Text.WrapAnywhere
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 22
                                        implicitHeight: valText.implicitHeight + 10
                                        radius: Appearance.rounding.tiny ?? 4
                                        color: Appearance.colors.colSurfaceContainerLow

                                        StyledText {
                                            id: valText
                                            anchors {
                                                left: parent.left
                                                right: parent.right
                                                verticalCenter: parent.verticalCenter
                                                margins: 8
                                            }
                                            text: flaggedCard.modelData.value
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnSurfaceVariant
                                            wrapMode: Text.WrapAnywhere
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    FloatingActionButton {
        id: publishFab
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 30
        }
        z: 100

        readonly property bool isPublishing: root.publishStatus === "publishing" || PresetStore.busyFor(root.presetName)
        readonly property bool isSuccess: root.publishStatus === "success"
        readonly property bool isError: root.publishStatus === "error"
        readonly property bool canPublish: root.signedIn && repoField.text.length > 0 && !repoField.error && !isPublishing

        iconText: isPublishing
            ? "sync"
            : (isSuccess
                ? "check"
                : (isError ? "priority_high" : "upload"))

        buttonText: isPublishing
            ? Translation.tr("Publishing…")
            : (isSuccess
                ? Translation.tr("Published!")
                : (isError
                    ? Translation.tr("Try again")
                    : Translation.tr("Publish to GitHub")))

        expanded: true

        visible: opacity > 0
        opacity: (canPublish || isPublishing || isSuccess || isError) ? 1.0 : 0.5
        scale: (canPublish || isPublishing || isSuccess || isError) ? 1.0 : 0.95

        colBackground: isPublishing
            ? Appearance.colors.colSecondaryContainer
            : (isSuccess
                ? Appearance.colors.colTertiaryContainer
                : (isError
                    ? Appearance.colors.colErrorContainer
                    : Appearance.colors.colPrimaryContainer))

        colBackgroundHover: isPublishing
            ? Appearance.colors.colSecondaryContainerHover
            : (isSuccess
                ? Appearance.colors.colTertiaryContainerHover
                : (isError
                    ? Appearance.colors.colErrorContainerHover
                    : Appearance.colors.colPrimaryContainerHover))

        colRipple: isPublishing
            ? Appearance.colors.colSecondaryContainerActive
            : (isSuccess
                ? Appearance.colors.colTertiaryContainerActive
                : (isError
                    ? Appearance.colors.colErrorContainerActive
                    : Appearance.colors.colPrimaryContainerActive))

        colOnBackground: isPublishing
            ? Appearance.colors.colOnSecondaryContainer
            : (isSuccess
                ? Appearance.colors.colTertiary
                : (isError
                    ? Appearance.colors.colOnErrorContainer
                    : Appearance.colors.colOnPrimaryContainer))

        Behavior on colBackground {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(publishFab)
        }
        Behavior on colOnBackground {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(publishFab)
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
            }
        }

        enabled: (canPublish || isSuccess || isError) && !isPublishing

        onClicked: {
            if (isSuccess) {
                autoDismissSuccessTimer.stop();
                root.goBack();
                return;
            }
            if (isPublishing || !canPublish)
                return;
            root.publishStatus = "publishing";
            root.publishError = "";
            const repoName = repoField.text.trim();
            const desc = descriptionField.text.trim();
            const notes = notesField.text.trim();
            const isPrivate = privateBox.checked;
            const shotsList = root.shots.slice();

            PresetStore.publish(root.presetName, repoName, desc, notes, isPrivate, shotsList);
        }
    }
}
