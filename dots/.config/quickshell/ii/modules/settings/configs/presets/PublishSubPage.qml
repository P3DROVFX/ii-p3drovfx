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

    // "idle" | "publishing" | "success" | "error"
    property string publishStatus: "idle"
    property string publishError: ""
    property string publishedUrl: ""

    readonly property bool signedIn: PresetStore.auth.authenticated === true

    property var previewData: null
    property bool previewLoading: false
    property bool showPreview: false

    function setPreset(name) {
        root.presetName = name;
        shotsEditor.shots = [];
        shotsEditor.notice = "";
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
            title: Translation.tr("Screenshots")
            icon: "image"
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Include visual previews of your desktop and lockscreen. The first one is the store's cover.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            PresetScreenshotsEditor {
                id: shotsEditor
                Layout.fillWidth: true
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
            const shotsList = shotsEditor.shots.slice();

            PresetStore.publish(root.presetName, repoName, desc, notes, isPrivate, shotsList);
        }
    }
}
