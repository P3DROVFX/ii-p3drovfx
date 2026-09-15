import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Sub-page for inspecting a preset in the Store, with large screenshot viewing,
 * metadata, compatibility status, changelog, and direct install/update actions.
 */
Item {
    id: root
    anchors.fill: parent

    signal goBack
    property bool showBackButton: true

    property var entry: null
    property var manifest: null
    property var compatibility: null
    property string loadError: ""
    property bool loading: false

    readonly property string repo: root.entry ? (root.entry.repo ?? "") : ""
    property string localInstalledAs: ""
    readonly property string installedAs: {
        if (root.localInstalledAs.length > 0)
            return root.localInstalledAs;
        const live = PresetStore.installedNameForRepo(root.repo);
        if (live.length > 0)
            return live;
        return root.entry ? (root.entry.installedAs ?? "") : "";
    }
    readonly property bool installed: root.installedAs.length > 0
    readonly property bool blocked: root.compatibility !== null && root.compatibility.ok === false
    readonly property var pending: root.installedAs.length > 0
        ? PresetStore.updateFor(root.installedAs) : null
    readonly property bool hasUpdate: root.pending !== null
    readonly property bool working: root.installed
        ? PresetStore.busyFor(root.installedAs) : PresetStore.busyFor(root.repo)

    function setEntry(result) {
        root.entry = result;
        root.localInstalledAs = (result && result.installedAs) ? result.installedAs : "";
        root.manifest = null;
        root.compatibility = null;
        root.loadError = "";
        root.loading = true;
        PresetStore.fetchManifest(result.repo);
    }

    Connections {
        target: PresetStore

        function onManifestReady(repoTarget, result) {
            if (repoTarget !== root.repo)
                return;
            root.loading = false;
            if (result.ok !== true) {
                root.loadError = result.error ?? "";
                return;
            }
            root.manifest = result.manifest;
            root.compatibility = result.compatibility;
        }

        function onInstallFinished(name, ok, err) {
            if (ok) {
                root.localInstalledAs = name;
            }
        }

        function onPullFinished(name, ok, changed, err) {
            if (ok) {
                root.localInstalledAs = name;
            }
        }

        function onRemoveFinished(name, ok, err) {
            if (ok && name === root.installedAs) {
                root.localInstalledAs = "";
            }
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

            // Author Avatar
            Item {
                implicitWidth: 40
                implicitHeight: 40
                visible: (root.entry && (root.entry.avatarUrl ?? "").length > 0)

                StyledImage {
                    id: headerAvatar
                    anchors.fill: parent
                    source: root.entry ? (root.entry.avatarUrl ?? "") : ""
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: headerAvatar.width
                            height: headerAvatar.height
                            radius: width / 2
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: (root.manifest && (root.manifest.name ?? "").length > 0)
                        ? root.manifest.name : (root.entry ? (root.entry.name ?? "") : "")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                RowLayout {
                    spacing: 8

                    StyledText {
                        text: Translation.tr("by %1").arg(root.entry ? (root.entry.author ?? "") : "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        text: "•"
                        color: Appearance.colors.colOutlineVariant
                    }

                    RowLayout {
                        spacing: 3
                        MaterialSymbol {
                            text: "star"
                            iconSize: 14
                            color: Appearance.colors.colTertiary
                        }
                        StyledText {
                            text: String(root.entry ? (root.entry.stars ?? 0) : 0)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledText {
                        text: "•"
                        color: Appearance.colors.colOutlineVariant
                        visible: root.manifest !== null || root.hasUpdate
                    }

                    StyledText {
                        visible: root.manifest !== null || root.hasUpdate
                        text: root.hasUpdate
                            ? Translation.tr("v%1").arg(root.pending.availableVersion ?? "")
                            : (root.manifest ? Translation.tr("v%1").arg(root.manifest.version) : "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            // GitHub external link button
            RippleButtonWithIcon {
                materialIcon: "open_in_new"
                mainText: Translation.tr("Repository")
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colSurfaceContainerHigh
                onClicked: {
                    let url = root.manifest ? (root.manifest.repoUrl || "") : (root.entry ? (root.entry.repoUrl || "") : "");
                    if (!url && root.repo)
                        url = `https://github.com/${root.repo.split(':')[0]}`;
                    if (url)
                        Quickshell.execDetached(["xdg-open", url]);
                }
            }
        }

        // Loading Bar
        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: root.loading
        }

        // Error Notice
        Rectangle {
            Layout.fillWidth: true
            visible: root.loadError.length > 0
            implicitHeight: errRow.implicitHeight + 20
            radius: Appearance.rounding.small
            color: Appearance.colors.colErrorContainer

            RowLayout {
                id: errRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 12
                spacing: 8

                MaterialSymbol {
                    text: "cloud_off"
                    iconSize: 18
                    color: Appearance.colors.colOnErrorContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.loadError
                    color: Appearance.colors.colOnErrorContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.Wrap
                }
            }
        }

        // Section: Visual Gallery & Screenshots
        ContentSection {
            title: Translation.tr("Visual preview")
            icon: "palette"
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                // Large Main Screenshot / Wallpaper Preview
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(360, width * 0.56)
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerLow
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "wallpaper"
                            iconSize: 48
                            color: Appearance.colors.colOnLayer1Inactive
                        }
                    }

                    StyledImage {
                        id: mainPreview
                        anchors.fill: parent
                        source: (root.manifest && root.manifest.screenshotUrls && root.manifest.screenshotUrls.length > 0)
                            ? root.manifest.screenshotUrls[selectedShotIndex.value]
                            : ((root.entry && root.entry.imageUrl)
                                ? root.entry.imageUrl
                                : ((root.entry && root.entry.wallpaperUrl)
                                    ? root.entry.wallpaperUrl
                                    : `${Directories.assetsPath}/images/default_wallpaper.png`))
                        fillMode: Image.PreserveAspectCrop
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: mainPreview.width
                                height: mainPreview.height
                                radius: Appearance.rounding.normal
                            }
                        }

                        onStatusChanged: {
                            if (status === Image.Error) {
                                if (root.entry && root.entry.wallpaperUrl && source !== root.entry.wallpaperUrl) {
                                    source = root.entry.wallpaperUrl;
                                } else if (source !== `${Directories.assetsPath}/images/default_wallpaper.png`) {
                                    source = `${Directories.assetsPath}/images/default_wallpaper.png`;
                                }
                            }
                        }
                    }

                    QtObject {
                        id: selectedShotIndex
                        property int value: 0
                    }
                }

                // Thumbnails strip if multiple screenshots exist
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.manifest && root.manifest.screenshotUrls && root.manifest.screenshotUrls.length > 1

                    Repeater {
                        model: root.manifest ? (root.manifest.screenshotUrls || []) : []

                        delegate: Rectangle {
                            id: thumbItem
                            required property string modelData
                            required property int index

                            width: 100
                            height: 60
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colSurfaceContainerHigh
                            border.width: selectedShotIndex.value === thumbItem.index ? 2 : 1
                            border.color: selectedShotIndex.value === thumbItem.index
                                ? Appearance.colors.colPrimary : "transparent"
                            clip: true

                            StyledImage {
                                anchors.fill: parent
                                source: thumbItem.modelData
                                fillMode: Image.PreserveAspectCrop
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: selectedShotIndex.value = thumbItem.index
                            }
                        }
                    }
                }
            }
        }

        // Section: Description
        ContentSection {
            title: Translation.tr("About this preset")
            icon: "description"
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: (root.manifest && (root.manifest.description ?? "").length > 0)
                    ? root.manifest.description
                    : (root.entry ? (root.entry.description || Translation.tr("No description provided.")) : "")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSurface
            }
        }

        // Section: Compatibility Notice
        ContentSection {
            title: Translation.tr("Compatibility")
            icon: "info"
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: compatRow.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: root.blocked
                        ? Appearance.colors.colErrorContainer
                        : Appearance.colors.colSecondaryContainer

                    RowLayout {
                        id: compatRow
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        MaterialSymbol {
                            text: root.blocked ? "error" : "check_circle"
                            iconSize: 18
                            color: root.blocked
                                ? Appearance.colors.colOnErrorContainer
                                : Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.blocked
                                ? Translation.tr("This preset was created for a newer version of the shell and cannot be installed on this version.")
                                : (root.compatibility && root.compatibility.status === "migrate"
                                    ? Translation.tr("This preset was created for an older version of the shell. It will be migrated automatically upon installation.")
                                    : Translation.tr("This preset is fully compatible with your current shell installation."))
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: root.blocked
                                ? Appearance.colors.colOnErrorContainer
                                : Appearance.colors.colOnSecondaryContainer
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }

        // Section: Changelog
        ContentSection {
            title: Translation.tr("Version history")
            icon: "history"
            Layout.fillWidth: true
            visible: root.manifest && root.manifest.changelog && root.manifest.changelog.length > 0

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.manifest ? (root.manifest.changelog || []) : []

                    delegate: Rectangle {
                        id: changelogCard
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: logCol.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainerLow

                        ColumnLayout {
                            id: logCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    text: `v${changelogCard.modelData.version ?? ""}`
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colPrimary
                                }

                                StyledText {
                                    text: changelogCard.modelData.date ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: changelogCard.modelData.notes ?? ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurface
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }

    FloatingActionButton {
        id: installFab
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 30
        }
        z: 100

        readonly property string actionLabel: root.working
            ? Translation.tr("Installing…")
            : (root.hasUpdate
                ? Translation.tr("Update preset")
                : (root.installed ? Translation.tr("Installed") : Translation.tr("Install preset")))

        iconText: root.working
            ? "sync"
            : (root.hasUpdate
                ? "download"
                : (root.installed ? "check" : "download"))

        buttonText: actionLabel
        expanded: true

        visible: opacity > 0
        opacity: (!root.blocked && root.entry !== null) ? 1 : 0
        scale: opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        colBackground: root.working
            ? Appearance.colors.colSecondaryContainer
            : (root.hasUpdate
                ? Appearance.colors.colSecondaryContainer
                : (root.installed
                    ? Appearance.colors.colTertiaryContainer
                    : Appearance.colors.colPrimaryContainer))

        colBackgroundHover: root.working
            ? Appearance.colors.colSecondaryContainerHover
            : (root.hasUpdate
                ? Appearance.colors.colSecondaryContainerHover
                : (root.installed
                    ? Appearance.colors.colTertiaryContainerHover
                    : Appearance.colors.colPrimaryContainerHover))

        colRipple: root.working
            ? Appearance.colors.colSecondaryContainerActive
            : (root.hasUpdate
                ? Appearance.colors.colSecondaryContainerActive
                : (root.installed
                    ? Appearance.colors.colTertiaryContainerActive
                    : Appearance.colors.colPrimaryContainerActive))

        colOnBackground: root.working
            ? Appearance.colors.colOnSecondaryContainer
            : (root.hasUpdate
                ? Appearance.colors.colOnSecondaryContainer
                : (root.installed
                    ? Appearance.colors.colTertiary
                    : Appearance.colors.colOnPrimaryContainer))

        Behavior on colBackground {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(installFab)
        }
        Behavior on colOnBackground {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(installFab)
        }

        onClicked: {
            if (root.working || root.blocked)
                return;
            if (root.hasUpdate) {
                PresetStore.pull(root.installedAs, false);
            } else if (root.installed) {
                PresetStore.applyPreset(root.installedAs);
            } else {
                PresetStore.install(root.repo, "", false);
            }
        }
    }
}
