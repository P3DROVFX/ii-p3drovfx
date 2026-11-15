pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.dock.utilities
import qs.services

FocusScope {
    id: root

    property bool active: false

    readonly property real dpr: Math.max(1, (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)
    readonly property var item: PhoneGalleryService.viewerItem
    readonly property string itemIdStr: item ? String(item.id) : ""
    readonly property bool isVideo: item ? item.kind === "video" : false
    readonly property string cachedThumb: (item && PhoneGalleryService.thumbRevision >= 0 && PhoneGalleryService.hasThumb(item.id))
        ? PhoneGalleryService.thumbPath(item.id)
        : ""
    readonly property string fullLocalPath: item ? (PhoneGalleryService.fullPaths[itemIdStr] ?? "") : ""
    readonly property bool actionReady: item !== null && (isVideo ? PhoneGalleryService.hasFilesCap : fullLocalPath.length > 0)
    readonly property bool isSaved: item !== null && (PhoneGalleryService.savedPaths[itemIdStr] ?? "") !== ""
    readonly property bool canShowInFolder: item !== null && (isSaved || (PhoneGalleryService.hasFilesCap && String(item.path ?? "") !== ""))
    readonly property var transferProgress: item ? (PhoneGalleryService.fullProgress[itemIdStr] ?? null) : null
    readonly property string transferError: item ? (PhoneGalleryService.fullErrors[itemIdStr] ?? "") : ""
    readonly property bool canPrev: PhoneGalleryService.viewerIndex > 0
    readonly property bool canNext: PhoneGalleryService.viewerIndex >= 0
        && PhoneGalleryService.viewerIndex < PhoneGalleryService.items.length - 1

    // The shape comes from the phone's metadata (already turned for orientation), not
    // from the loaded images: their size follows the box, which follows this.
    readonly property bool _metaSize: Number(item?.w ?? 0) > 0 && Number(item?.h ?? 0) > 0
    readonly property real mediaW: _metaSize ? Number(item.w)
        : (thumbPreview.status === Image.Ready ? thumbPreview.implicitWidth : 0)
    readonly property real mediaH: _metaSize ? Number(item.h)
        : (thumbPreview.status === Image.Ready ? thumbPreview.implicitHeight : 0)
    readonly property real _boxW: Math.max(1, stage.width - 16)
    readonly property real _boxH: Math.max(1, stage.height - 16)
    readonly property real _fitScale: (mediaW > 0 && mediaH > 0)
        ? Math.min(_boxW / mediaW, _boxH / mediaH)
        : 0
    readonly property real fittedWidth: _fitScale > 0 ? Math.max(1, Math.round(mediaW * _fitScale)) : _boxW
    readonly property real fittedHeight: _fitScale > 0 ? Math.max(1, Math.round(mediaH * _fitScale)) : _boxH

    property real _wheelAccum: 0

    focus: root.active
    onActiveChanged: {
        if (root.active) {
            root.forceActiveFocus();
            Qt.callLater(() => {
                if (root.active)
                    root.forceActiveFocus();
            });
        } else {
            root._wheelAccum = 0;
            wheelResetTimer.stop();
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if (!root.active || !root.activeFocus || event.modifiers !== Qt.NoModifier) {
            event.accepted = false;
            return;
        }
        if (event.key === Qt.Key_Escape) {
            PhoneGalleryService.closeViewer();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            PhoneGalleryService.stepViewer(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            PhoneGalleryService.stepViewer(1);
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    function formatBytes(bytes) {
        const n = Number(bytes || 0);
        if (n <= 0)
            return "";
        if (n < 1024)
            return n.toFixed(0) + " B";
        if (n < 1024 * 1024)
            return (n / 1024).toFixed(1) + " KB";
        if (n < 1024 * 1024 * 1024)
            return (n / (1024 * 1024)).toFixed(1) + " MB";
        return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
    }

    function stepByStageX(x) {
        if (stage.width <= 0)
            return;
        if (x < stage.width / 3)
            PhoneGalleryService.stepViewer(-1);
        else if (x > stage.width * 2 / 3)
            PhoneGalleryService.stepViewer(1);
    }

    Timer {
        id: wheelResetTimer
        interval: 250
        repeat: false
        onTriggered: root._wheelAccum = 0
    }

    // Wrap IconToolbarButton with a HoverHandler so disabled buttons still show their tooltip.
    component ViewerToolbarAction: Item {
        id: actionItem
        required property string icon
        required property string tooltip
        property string disabledTooltip: tooltip
        property bool buttonEnabled: true
        signal triggered()

        Layout.fillHeight: true
        Layout.preferredWidth: Math.max(height, Appearance.sizes.toolbarHeight - 6)
        implicitWidth: Appearance.sizes.toolbarHeight - 6

        IconToolbarButton {
            anchors.fill: parent
            text: actionItem.icon
            iconSize: 20
            enabled: actionItem.buttonEnabled
            onClicked: actionItem.triggered()
        }

        HoverHandler {
            id: actionHover
        }

        StyledToolTip {
            extraVisibleCondition: actionHover.hovered
            text: actionItem.buttonEnabled ? actionItem.tooltip : actionItem.disabledTooltip
        }
    }

    Rectangle {
        id: stage
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer3
        clip: true

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                if (delta === 0)
                    return;
                root._wheelAccum += delta;
                wheelResetTimer.restart();
                if (Math.abs(root._wheelAccum) >= 120) {
                    PhoneGalleryService.stepViewer(root._wheelAccum < 0 ? 1 : -1);
                    root._wheelAccum = 0;
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: mouse => root.stepByStageX(mouse.x)
        }

        ClippingRectangle {
            id: mediaClip
            anchors.centerIn: parent
            width: root.fittedWidth
            height: root.fittedHeight
            radius: Appearance.rounding.normal
            color: "transparent"
            visible: root.item !== null && (root.cachedThumb.length > 0 || root.fullLocalPath.length > 0)

            Image {
                id: thumbPreview
                anchors.fill: parent
                visible: root.cachedThumb.length > 0 && (root.isVideo || fullImage.status !== Image.Ready)
                source: root.cachedThumb
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                smooth: true
                sourceSize.width: Math.min(256, Math.max(1, Math.round(stage.width * root.dpr)))
                sourceSize.height: Math.min(256, Math.max(1, Math.round(stage.height * root.dpr)))
            }

            Image {
                id: fullImage
                anchors.fill: parent
                visible: !root.isVideo && root.fullLocalPath.length > 0
                source: (!root.isVideo && root.fullLocalPath.length > 0)
                    ? ("file://" + root.fullLocalPath)
                    : ""
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                smooth: true
                sourceSize.width: Math.max(1, Math.round(stage.width * root.dpr))
                sourceSize.height: Math.max(1, Math.round(stage.height * root.dpr))
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 140 }
                }
            }
        }

        FileDragArea {
            anchors.fill: mediaClip
            enabled: !root.isVideo
                && root.fullLocalPath.length > 0
                && fullImage.status === Image.Ready
            paths: root.fullLocalPath.length > 0 ? [root.fullLocalPath] : []
            dragIcon: "image"
            onClicked: mouse => {
                if (!dragging) {
                    const p = mapToItem(stage, mouse.x, mouse.y);
                    root.stepByStageX(p.x);
                }
            }
        }

        // Centered Play button for videos
        RippleButton {
            visible: root.isVideo
            anchors.centerIn: parent
            width: 68
            height: 68
            buttonRadius: Appearance.rounding.full
            colBackground: PhoneGalleryService.hasFilesCap
                ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colLayer2
            colBackgroundHover: PhoneGalleryService.hasFilesCap
                ? Appearance.colors.colPrimaryContainerHover
                : Appearance.colors.colLayer2Hover
            colBackgroundActive: PhoneGalleryService.hasFilesCap
                ? Appearance.colors.colPrimaryContainerActive
                : Appearance.colors.colLayer2Active
            enabled: PhoneGalleryService.hasFilesCap && !PhoneGalleryService.videoMounting
            onClicked: PhoneGalleryService.openItem(root.item)

            contentItem: Item {
                anchors.fill: parent

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !PhoneGalleryService.videoMounting
                    text: PhoneGalleryService.hasFilesCap ? "play_arrow" : "play_disabled"
                    iconSize: 34
                    color: PhoneGalleryService.hasFilesCap
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colSubtext
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: PhoneGalleryService.videoMounting
                    implicitSize: 28
                    loading: visible
                }
            }

            StyledToolTip {
                text: PhoneGalleryService.hasFilesCap
                    ? Translation.tr("Open video")
                    : Translation.tr("Turn on Phone files to play videos")
            }
        }

        // Above the toolbar: what the photo is waiting for, or why a video won't play.
        Rectangle {
            id: statusPill
            readonly property bool failed: root.transferError.length > 0
            readonly property bool waitingFull: !root.isVideo
                && root.item !== null
                && (root.fullLocalPath.length === 0 || fullImage.status !== Image.Ready)
            readonly property bool videoBlocked: root.isVideo && !PhoneGalleryService.hasFilesCap

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: toolbarRow.top
            anchors.bottomMargin: 10
            visible: waitingFull || videoBlocked
            radius: height / 2
            color: failed ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
            implicitWidth: Math.min(stage.width - 24, statusRow.implicitWidth + 24)
            implicitHeight: Math.max(34, statusRow.implicitHeight + 10)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                id: statusRow
                anchors.centerIn: parent
                spacing: 8

                readonly property color colContent: statusPill.failed
                    ? Appearance.colors.colOnErrorContainer
                    : Appearance.colors.colOnSecondaryContainer

                CircularProgress {
                    visible: statusPill.waitingFull && !statusPill.failed
                        && root.transferProgress !== null && root.transferProgress.size > 0
                    implicitSize: 18
                    lineWidth: 3
                    value: (root.transferProgress && root.transferProgress.size > 0)
                        ? Math.min(1, root.transferProgress.received / root.transferProgress.size)
                        : 0
                    colPrimary: statusRow.colContent
                    colSecondary: ColorUtils.transparentize(statusRow.colContent, 0.75)
                }

                MaterialLoadingIndicator {
                    visible: statusPill.waitingFull && !statusPill.failed
                        && (root.transferProgress === null || root.transferProgress.size <= 0)
                    implicitSize: 20
                    loading: visible
                }

                MaterialSymbol {
                    visible: statusPill.failed || statusPill.videoBlocked
                    text: statusPill.failed ? "error" : "folder_off"
                    iconSize: 16
                    color: statusRow.colContent
                }

                StyledText {
                    Layout.maximumWidth: stage.width - 130
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: statusRow.colContent
                    text: {
                        if (statusPill.videoBlocked)
                            return Translation.tr("Turn on Phone files to play videos");
                        if (statusPill.failed)
                            return Translation.tr("Download failed: %1").arg(root.transferError);
                        if (root.transferProgress && root.transferProgress.size > 0) {
                            return "%1 / %2"
                                .arg(root.formatBytes(root.transferProgress.received) || "0 B")
                                .arg(root.formatBytes(root.transferProgress.size));
                        }
                        return Translation.tr("Loading full resolution…");
                    }
                }

                RippleButton {
                    visible: statusPill.failed
                    implicitHeight: 24
                    implicitWidth: retryText.implicitWidth + 16
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colError
                    colBackgroundHover: Appearance.colors.colErrorHover ?? Appearance.colors.colError
                    colBackgroundActive: Appearance.colors.colErrorActive ?? Appearance.colors.colError
                    onClicked: {
                        if (root.item)
                            PhoneGalleryService.get(root.item.id);
                    }

                    contentItem: StyledText {
                        id: retryText
                        anchors.centerIn: parent
                        text: Translation.tr("Retry")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnError
                    }
                }
            }
        }

        // Clicks in the gaps of the toolbar row must not step the stage.
        MouseArea {
            anchors.fill: toolbarRow
            acceptedButtons: Qt.AllButtons
        }

        // M3 Expressive floating toolbar with its paired FAB: browsing and the
        // secondary actions in the bar, the main action (save a photo, play a video)
        // in the FAB beside it.
        Row {
            id: toolbarRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            spacing: 8

            Toolbar {
                id: floatingToolbar
                anchors.verticalCenter: parent.verticalCenter

                ViewerToolbarAction {
                    icon: "chevron_left"
                    tooltip: Translation.tr("Previous")
                    disabledTooltip: Translation.tr("First item")
                    buttonEnabled: root.canPrev
                    onTriggered: PhoneGalleryService.stepViewer(-1)
                }

                ViewerToolbarAction {
                    visible: root.isVideo
                    icon: "download"
                    tooltip: Translation.tr("Save to Pictures/Phone")
                    disabledTooltip: Translation.tr("Turn on Phone files to save videos")
                    buttonEnabled: root.actionReady
                    onTriggered: PhoneGalleryService.saveItem(root.item)
                }

                ViewerToolbarAction {
                    icon: "content_copy"
                    tooltip: Translation.tr("Copy")
                    disabledTooltip: root.isVideo
                        ? Translation.tr("Turn on Phone files to copy videos")
                        : Translation.tr("Waiting for full image")
                    buttonEnabled: root.actionReady
                    onTriggered: PhoneGalleryService.copyItem(root.item)
                }

                ViewerToolbarAction {
                    visible: !root.isVideo
                    icon: "open_in_new"
                    tooltip: Translation.tr("Open")
                    disabledTooltip: Translation.tr("Waiting for full image")
                    buttonEnabled: root.actionReady
                    onTriggered: PhoneGalleryService.openItem(root.item)
                }

                ViewerToolbarAction {
                    icon: "folder_open"
                    tooltip: Translation.tr("Show in folder")
                    disabledTooltip: Translation.tr("Save first or turn on Phone files to show in folder")
                    buttonEnabled: root.canShowInFolder
                    onTriggered: PhoneGalleryService.showInFolder(root.item)
                }

                ViewerToolbarAction {
                    icon: "chevron_right"
                    tooltip: Translation.tr("Next")
                    disabledTooltip: Translation.tr("Last item")
                    buttonEnabled: root.canNext
                    onTriggered: PhoneGalleryService.stepViewer(1)
                }
            }

            ToolbarPairedFab {
                id: mainFab
                readonly property bool ready: root.actionReady && !PhoneGalleryService.videoMounting
                iconText: root.isVideo ? "play_arrow" : (root.isSaved ? "download_done" : "download")
                enabled: mainFab.ready
                opacity: mainFab.ready ? 1 : 0.5
                onClicked: {
                    if (root.isVideo)
                        PhoneGalleryService.openItem(root.item);
                    else
                        PhoneGalleryService.saveItem(root.item);
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledToolTip {
                    text: {
                        if (root.isVideo)
                            return PhoneGalleryService.hasFilesCap
                                ? Translation.tr("Play on the PC")
                                : Translation.tr("Turn on Phone files to play videos");
                        if (!root.actionReady)
                            return Translation.tr("Waiting for full image");
                        return root.isSaved
                            ? Translation.tr("Saved to Pictures/Phone, save again")
                            : Translation.tr("Save to Pictures/Phone");
                    }
                }
            }
        }
    }
}
