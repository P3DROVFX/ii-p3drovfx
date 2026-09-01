import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarDashboard
import "QuickToggleCatalog.js" as QuickToggleCatalog
import Quickshell.Services.Mpris
import Quickshell.Io
import "../../../mediaControls" as MediaCtrl
import "../../../bar" as Bar

Item {
    id: root

    required property int buttonIndex
    required property var buttonData
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    readonly property var catalogSize: QuickToggleCatalog.normalizeSize(root.buttonData.type, root.buttonData.sizeW, root.buttonData.sizeH, root.gridColumns)

    property bool editMode: false
    property bool isUnused: false
    property bool isDragging: false
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null
    property var gridRef: null

    // Active pages and the drawer use one explicit packed coordinate system.
    // Bind only when geometry is present so fixed sliders can still be owned by
    // their Column positioner.
    readonly property bool hasExplicitGeometry: root.buttonData
        && root.buttonData.layoutX !== undefined
        && root.buttonData.layoutY !== undefined
    Binding on x {
        when: root.hasExplicitGeometry
        value: Number(root.buttonData.layoutX)
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding on y {
        when: root.hasExplicitGeometry
        value: Number(root.buttonData.layoutY)
        restoreMode: Binding.RestoreBindingOrValue
    }
    z: root.isDragging ? 100 : 0

    Behavior on x {
        enabled: root.hasExplicitGeometry && !root.isDragging
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on y {
        enabled: root.hasExplicitGeometry && !root.isDragging
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
    readonly property bool entrancePageActive: root.pageIndex === -1 || !root.panel
        || root.panel.currentPage === root.pageIndex

    DashboardEntranceProgress {
        id: entranceProgress
        animationSpec: Appearance.animation.elementMove
        animationsEnabled: root.entranceAnimationsEnabled
        trigger: root.entranceTrigger
        pageActive: root.entrancePageActive
        delayIndex: Math.min(Math.max(root.buttonIndex, 0), 15)
        staggerRatio: 0.08
    }

    property string tooltipText: {
        var player = MprisController.activePlayer;
        if (player && player.trackTitle) {
            var artist = player.trackArtist ? player.trackArtist : Translation.tr("Unknown Artist");
            return player.trackTitle + " - " + artist;
        }
        return Translation.tr("Media Player");
    }

    // Effective sizes for live preview during resize
    readonly property int effectiveSizeW: root.catalogSize[0]
    readonly property int effectiveSizeH: root.catalogSize[1]

    property bool hovered: hoverHandler.hovered || (root.editMode && editableItem.containsMouse)

    HoverHandler {
        id: hoverHandler
    }

    property real baseWidth: root.baseCellWidth * root.effectiveSizeW + cellSpacing * (root.effectiveSizeW - 1)
    property real baseHeight: root.baseCellHeight * root.effectiveSizeH + cellSpacing * (root.effectiveSizeH - 1)

    implicitWidth: baseWidth
    implicitHeight: baseHeight

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainer
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1
        visible: root.isDragging
        opacity: 0.5
    }

    Item {
        id: visualButton

        x: 0
        y: 0
        
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

        width: root.width
        height: root.height

        scale: (root.isDragging ? 1.05 : 1.0) * (0.85 + 0.15 * entranceProgress.progress)
        opacity: {
            if (entranceProgress.progress < 1) return entranceProgress.progress;
            if (root.isUnused)
                return 0.5;
            if (root.editMode && !root.isDragging)
                return 0.9;
            if (root.isDragging)
                return 0.95;
            return 1.0;
        }
        z: root.isDragging ? 99 : 1

        transform: Translate {
            x: root.isDragging ? root.dragOffsetX : 0
            y: (root.isDragging ? root.dragOffsetY : 0) + 20 * (1 - entranceProgress.progress)
        }

        Behavior on scale {
            enabled: !entranceProgress.running
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
        Behavior on opacity {
            enabled: !entranceProgress.running
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            sourceComponent: {
                if (MprisController.players.length === 0) {
                    return emptyStateComp;
                }
                var w = root.effectiveSizeW || 2;
                var h = root.effectiveSizeH || 2;
                if (w >= 4) {
                    return layout4x2StandardComp;
                } else if (h === 1) {
                    return layout2x1Comp;
                } else {
                    return layout2x2Comp;
                }
            }
        }

        Component {
            id: emptyStateComp
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.large

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "music_note"
                        iconSize: 32
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: Translation.tr("No media")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        Component {
            id: layout4x2StandardComp
            MediaCtrl.AndroidMediaPopup {
                player: MprisController.activePlayer
                showShadow: false
                anchors.fill: parent
            }
        }

        Component {
            id: layout2x1Comp
            Rectangle {
                id: widgetRoot2x1
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2
                clip: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: widgetRoot2x1.width
                        height: widgetRoot2x1.height
                        radius: widgetRoot2x1.radius
                    }
                }

                property MprisPlayer player: MprisController.activePlayer

                // Track downloader
                property string artUrl: MprisController.artUrl
                property bool isLocalArt: artUrl.startsWith("file://")
                property string artFilePath: artUrl.length > 0 && !isLocalArt ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
                property string artTempPath: artFilePath + ".tmp"
                property string artSource: {
                    if (artUrl.length === 0) return "";
                    if (isLocalArt) return artUrl;
                    if (coverDownloader2x1.running) return "";
                    return `file://${artFilePath}`;
                }

                Process {
                    id: coverDownloader2x1
                    property string targetFile: widgetRoot2x1.artUrl
                    property string artFilePath: widgetRoot2x1.artFilePath
                    property string artTempPath: widgetRoot2x1.artTempPath
                    command: ["bash", "-c", `[ -f '${artFilePath}' ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
                    onExited: {
                        // Force reload by briefly clearing source
                        widgetRoot2x1.artSource = "";
                    }
                }

                onArtUrlChanged: {
                    if (artUrl.length === 0 || isLocalArt) return;
                    coverDownloader2x1.targetFile = artUrl;
                    coverDownloader2x1.artFilePath = artFilePath;
                    coverDownloader2x1.artTempPath = artTempPath;
                    coverDownloader2x1.running = true;
                }

                StyledImage {
                    id: blurredBg2x1
                    anchors.fill: parent
                    source: widgetRoot2x1.artSource
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    opacity: 0.8

                    layer.enabled: true
                    layer.effect: StyledBlurEffect {
                        source: blurredBg2x1
                        blurMax: 32
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
                    }
                }

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        Layout.alignment: Qt.AlignVCenter
                        buttonRadius: 12
                        colBackground: Appearance.colors.colPrimary
                        colRipple: Appearance.colors.colPrimaryActive
                        contentItem: MaterialSymbol {
                            text: widgetRoot2x1.player?.isPlaying ? "pause" : "play_arrow"
                            color: Appearance.colors.colOnPrimary
                            fill: 1
                            iconSize: 22
                            horizontalAlignment: Text.AlignHCenter
                        }
                        onClicked: widgetRoot2x1.player?.togglePlaying()
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: widgetRoot2x1.player?.trackTitle || Translation.tr("Untitled")
                            color: widgetRoot2x1.artFilePath.length > 0 ? "white" : Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: 600
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: widgetRoot2x1.player?.trackArtist || Translation.tr("Unknown Artist")
                            color: widgetRoot2x1.artFilePath.length > 0 ? ColorUtils.transparentize("white", 0.3) : Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Component {
            id: layout2x2Comp
            Rectangle {
                id: widgetRoot
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2
                clip: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: widgetRoot.width
                        height: widgetRoot.height
                        radius: widgetRoot.radius
                    }
                }

                property MprisPlayer player: MprisController.activePlayer

                // Track downloader
                property string artUrl: MprisController.artUrl
                property bool isLocalArt: artUrl.startsWith("file://")
                property string artFilePath: artUrl.length > 0 && !isLocalArt ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
                property string artTempPath: artFilePath + ".tmp"
                property bool cachedArtReady: false
                property string artSource: {
                    if (artUrl.length === 0) return "";
                    if (isLocalArt) return cachedArtReady ? artUrl : "";
                    if (coverDownloader.running) return "";
                    if (!cachedArtReady) return "";
                    return `file://${artFilePath}`;
                }

                Process {
                    id: coverDownloader
                    property string targetFile: widgetRoot.artUrl
                    property string artFilePath: widgetRoot.artFilePath
                    property string artTempPath: widgetRoot.artTempPath
                    command: ["bash", "-c", `[ -f '${artFilePath}' ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
                    onExited: (exitCode, exitStatus) => {
                        // The binding exposes the cached file only after the download
                        // has completed, avoiding a failed image load on every change.
                        widgetRoot.cachedArtReady = exitCode === 0;
                    }
                }

                onArtUrlChanged: {
                    cachedArtReady = false;
                    if (artUrl.length === 0) return;
                    if (isLocalArt) {
                        cachedArtReady = true;
                        return;
                    }
                    coverDownloader.targetFile = artUrl;
                    coverDownloader.artFilePath = artFilePath;
                    coverDownloader.artTempPath = artTempPath;
                    coverDownloader.running = true;
                }

                StyledImage {
                    id: blurredBg
                    anchors.fill: parent
                    source: (widgetRoot.artSource && widgetRoot.artSource.length > 0 && widgetRoot.artSource !== "file://" && widgetRoot.artSource !== "file:///") ? widgetRoot.artSource : ""
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    opacity: 0.8

                    layer.enabled: true
                    layer.effect: StyledBlurEffect {
                        source: blurredBg
                        blurMax: 32
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16

                    StyledText {
                        Layout.fillWidth: true
                        text: widgetRoot.player?.trackTitle || Translation.tr("Untitled")
                        color: widgetRoot.artFilePath.length > 0 ? "white" : Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: 600
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: widgetRoot.player?.trackArtist || Translation.tr("Unknown Artist")
                        color: widgetRoot.artFilePath.length > 0 ? ColorUtils.transparentize("white", 0.3) : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: 16
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            contentItem: MaterialSymbol {
                                text: "skip_previous"
                                color: widgetRoot.artFilePath.length > 0 ? "white" : Appearance.colors.colOnSecondaryContainer
                                iconSize: 24
                                horizontalAlignment: Text.AlignHCenter
                            }
                            onClicked: widgetRoot.player?.previous()
                        }
                        RippleButton {
                            implicitWidth: 44
                            implicitHeight: 44
                            buttonRadius: 22
                            colBackground: Appearance.colors.colPrimary
                            colRipple: Appearance.colors.colPrimaryActive
                            contentItem: MaterialSymbol {
                                text: widgetRoot.player?.isPlaying ? "pause" : "play_arrow"
                                color: Appearance.colors.colOnPrimary
                                fill: 1
                                iconSize: 28
                                horizontalAlignment: Text.AlignHCenter
                            }
                            onClicked: widgetRoot.player?.togglePlaying()
                        }
                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: 16
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            contentItem: MaterialSymbol {
                                text: "skip_next"
                                color: widgetRoot.artFilePath.length > 0 ? "white" : Appearance.colors.colOnSecondaryContainer
                                iconSize: 24
                                horizontalAlignment: Text.AlignHCenter
                            }
                            onClicked: widgetRoot.player?.next()
                        }
                    }
                }
            }
        }

    }

    EditableQuickToggleItem {
        id: editableItem
        target: root
        visualItem: visualButton
    }
}
