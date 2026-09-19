import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Sub-page for the pictures of a preset you already published. Saving pushes
 * them on their own: no new version, and the settings people install stay the
 * ones last released.
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack
    property bool showBackButton: true

    property string presetName: ""
    // What the repository ships right now, as files in the local clone.
    property var published: []
    property bool loading: false
    property bool saving: false
    property string error: ""
    property string savedMessage: ""

    readonly property var link: PresetStore.linkFor(root.presetName)
    readonly property bool signedIn: PresetStore.auth.authenticated === true
    readonly property bool dirty: JSON.stringify(shotsEditor.shots) !== JSON.stringify(root.published)
    readonly property bool canSave: root.dirty && root.signedIn && !root.loading && !root.saving

    function setPreset(name) {
        root.presetName = name;
        root.published = [];
        root.error = "";
        root.savedMessage = "";
        root.saving = false;
        shotsEditor.shots = [];
        shotsEditor.notice = "";
        root.reload();
        PresetStore.refreshAuth();
    }

    function reload() {
        if (root.presetName.length === 0)
            return;
        root.loading = true;
        PresetStore.listScreenshots(root.presetName);
    }

    Connections {
        target: PresetStore

        function onScreenshotsListed(name, result) {
            if (name !== root.presetName)
                return;
            root.loading = false;
            if (!result || result.ok !== true) {
                root.error = (result && result.error) || Translation.tr("Could not read the published screenshots.");
                return;
            }
            root.published = result.screenshots || [];
            shotsEditor.maxShots = result.max || shotsEditor.maxShots;
            shotsEditor.maxBytes = result.maxBytes || shotsEditor.maxBytes;
            shotsEditor.shots = root.published.slice();
        }

        function onScreenshotsSaved(name, ok, changed, error) {
            if (name !== root.presetName)
                return;
            root.saving = false;
            if (!ok) {
                root.error = error || Translation.tr("Could not publish the screenshots.");
                return;
            }
            root.savedMessage = changed
                ? Translation.tr("Screenshots published. The store shows them once GitHub refreshes its cache.")
                : Translation.tr("These are already the published screenshots.");
            // The clone now holds the new set under new names.
            root.reload();
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
                    text: Translation.tr("Screenshots")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                StyledText {
                    text: root.link
                        ? Translation.tr("%1 · %2 (v%3)").arg(root.presetName).arg(root.link.repo).arg(root.link.version)
                        : root.presetName
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.error.length > 0
            materialIcon: "error"
            text: root.error
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.savedMessage.length > 0 && !root.dirty
            materialIcon: "check_circle"
            text: root.savedMessage
        }

        ContentSection {
            title: Translation.tr("GitHub account")
            icon: "account_circle"
            Layout.fillWidth: true
            visible: !root.signedIn

            GithubSignInPanel {
                Layout.fillWidth: true
            }
        }

        ContentSection {
            title: root.loading ? Translation.tr("Screenshots (loading…)") : Translation.tr("Published screenshots")
            icon: "photo_library"
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Saving replaces the pictures on GitHub right away. It does not release a new version or publish your current settings; use Push update for that. The first picture is the store's cover.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            PresetScreenshotsEditor {
                id: shotsEditor
                Layout.fillWidth: true
                interactive: !root.loading && !root.saving
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.loading && shotsEditor.shots.length === 0
                text: root.published.length > 0
                    ? Translation.tr("Saving now removes every screenshot from the published preset.")
                    : Translation.tr("This preset ships no screenshots yet.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                visible: root.dirty && !root.loading
                enabled: !root.saving
                materialIcon: "undo"
                mainText: Translation.tr("Discard changes")
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    shotsEditor.shots = root.published.slice();
                    shotsEditor.notice = "";
                }
            }
        }
    }

    FloatingActionButton {
        id: saveFab
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 30
        }
        z: 100

        iconText: root.saving ? "sync" : "cloud_upload"
        buttonText: root.saving ? Translation.tr("Publishing…") : Translation.tr("Save & push")
        expanded: true
        enabled: root.canSave
        visible: opacity > 0
        opacity: (root.canSave || root.saving) ? 1.0 : 0.5

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
            }
        }

        onClicked: {
            if (!root.canSave)
                return;
            root.saving = true;
            root.error = "";
            root.savedMessage = "";
            PresetStore.setScreenshots(root.presetName, shotsEditor.shots.slice());
        }
    }
}
