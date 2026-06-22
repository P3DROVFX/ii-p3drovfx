import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
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

    property bool editMode: false
    property bool isUnused: false
    property bool isDragging: false
    property real dragAbsX: 0
    property real dragAbsY: 0
    property int pageIndex: 0
    property int gridColumns: 4
    property var panel: null
    property var gridRef: null

    property string tooltipText: {
        var player = MprisController.activePlayer;
        if (player && player.trackTitle) {
            var artist = player.trackArtist ? player.trackArtist : Translation.tr("Unknown Artist");
            return player.trackTitle + " - " + artist;
        }
        return Translation.tr("Media Player");
    }

    // Effective sizes for live preview during resize
    readonly property int effectiveSizeW: {
        if (root.editMode && visualButton.editingRight) {
            var delta = root.baseCellWidth > 0 ? Math.round(visualButton.editDragX / root.baseCellWidth) : 0;
            var w = (root.buttonData.sizeW ?? 2) + delta;
            return Math.max(1, Math.min(8, w));
        }
        return root.buttonData.sizeW ?? 2;
    }
    readonly property int effectiveSizeH: {
        if (root.editMode && visualButton.editingBottom) {
            var delta = root.baseCellHeight > 0 ? Math.round(visualButton.editDragY / root.baseCellHeight) : 0;
            var h = (root.buttonData.sizeH ?? 2) + delta;
            return Math.max(1, Math.min(8, h));
        }
        return root.buttonData.sizeH ?? 2;
    }

    property bool hovered: hoverHandler.hovered || (root.editMode && editModeInteraction.containsMouse)

    HoverHandler {
        id: hoverHandler
    }

    Layout.columnSpan: root.effectiveSizeW
    Layout.rowSpan: root.effectiveSizeH
    Layout.preferredWidth: root.implicitWidth
    Layout.preferredHeight: root.implicitHeight
    Layout.fillWidth: false
    Layout.fillHeight: false


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

        parent: root.pageIndex === -1 ? root : (root.parent ? root.parent.parent : root)

        x: root.isDragging ? dragAbsX : (root.pageIndex === -1 ? 0 : (root.parent ? root.parent.x + root.x : root.x))
        y: root.isDragging ? dragAbsY : (root.pageIndex === -1 ? 0 : (root.parent ? root.parent.y + root.y : root.y))

        Behavior on x {
            enabled: !root.isDragging
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on y {
            enabled: !root.isDragging
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(visualButton)
        }

        width: root.width
        height: root.height

        scale: root.isDragging ? 1.05 : 1.0
        opacity: {
            if (root.isUnused)
                return 0.5;
            if (root.editMode && !root.isDragging)
                return 0.9;
            if (root.isDragging)
                return 0.95;
            return 1.0;
        }
        z: root.isDragging ? 99 : 1

        Behavior on scale {
            animation: Appearance.animation.clickBounce.numberAnimation.createObject(visualButton)
        }
        Behavior on opacity {
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
            MediaCtrl.PlayerControl {
                player: MprisController.activePlayer
                anchors.fill: parent
                radius: Appearance.rounding.large
                compactMode: true
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
                property string artUrl: player?.trackArtUrl || ""
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
                property string artUrl: player?.trackArtUrl || ""
                property bool isLocalArt: artUrl.startsWith("file://")
                property string artFilePath: artUrl.length > 0 && !isLocalArt ? `${Directories.coverArt}/${Qt.md5(artUrl)}` : ""
                property string artTempPath: artFilePath + ".tmp"
                property string artSource: {
                    if (artUrl.length === 0) return "";
                    if (isLocalArt) return artUrl;
                    if (coverDownloader.running) return "";
                    return `file://${artFilePath}`;
                }

                Process {
                    id: coverDownloader
                    property string targetFile: widgetRoot.artUrl
                    property string artFilePath: widgetRoot.artFilePath
                    property string artTempPath: widgetRoot.artTempPath
                    command: ["bash", "-c", `[ -f '${artFilePath}' ] || (curl -4 -sSL '${targetFile}' -o '${artTempPath}' && mv '${artTempPath}' '${artFilePath}')`]
                    onExited: {
                        // Force reload by briefly clearing source
                        widgetRoot.artSource = "";
                    }
                }

                onArtUrlChanged: {
                    if (artUrl.length === 0 || isLocalArt) return;
                    coverDownloader.targetFile = artUrl;
                    coverDownloader.artFilePath = artFilePath;
                    coverDownloader.artTempPath = artTempPath;
                    coverDownloader.running = true;
                }

                StyledImage {
                    id: blurredBg
                    anchors.fill: parent
                    source: widgetRoot.artSource
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

        // --- Edit Mode Logic ---
        property real editDragX: 0
        property real editDragY: 0
        property bool editingRight: false
        property bool editingBottom: false

        MouseArea {
            id: editModeInteraction
            visible: root.editMode
            anchors.fill: parent
            cursorShape: root.isDragging ? Qt.ClosedHandCursor : (root.isUnused ? Qt.PointingHandCursor : Qt.OpenHandCursor)
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton

            property real pressAbsX: 0
            property real pressAbsY: 0
            property real initialVisualX: 0
            property real initialVisualY: 0

            function mutatePages(mutatorFn) {
                if (root.panel && root.panel.mutatePages) {
                    root.panel.mutatePages(mutatorFn);
                } else {
                    var cloned = JSON.parse(JSON.stringify(Config.options.sidebar.quickToggles.android.pages));
                    mutatorFn(cloned);
                    Config.options.sidebar.quickToggles.android.pages = cloned;
                }
            }

            function toggleEnabled() {
                const buttonType = root.buttonData.type;
                const pi = root.pageIndex;

                mutatePages(function (pages) {
                    if (pi < 0 || pi >= pages.length)
                        return;
                    var page = pages[pi];
                    var existingIdx = -1;
                    for (var i = 0; i < page.length; i++) {
                        if (page[i].type === buttonType) {
                            existingIdx = i;
                            break;
                        }
                    }
                    if (existingIdx === -1) {
                        page.push({
                            type: buttonType,
                            sizeW: 2,
                            sizeH: 2,
                            size: 2
                        });
                    } else {
                        page.splice(existingIdx, 1);
                    }
                });
            }

            function setSize(newW, newH) {
                const buttonType = root.buttonData.type;
                const pi = root.pageIndex;
                mutatePages(function (pages) {
                    if (pi < 0 || pi >= pages.length)
                        return;
                    var page = pages[pi];
                    for (var i = 0; i < page.length; i++) {
                        if (page[i].type === buttonType) {
                            page[i].sizeW = newW;
                            page[i].sizeH = newH;
                            page[i].size = newW;
                            return;
                        }
                    }
                });
            }

            function resolveLayoutConflicts() {
                if (root.panel && root.panel.resolveLayoutConflicts) {
                    root.panel.resolveLayoutConflicts(root.pageIndex, root.gridColumns);
                }
            }

            function checkForSwap(gridX, gridY) {
                if (!root.parent)
                    return;
                var layout = root.parent;
                for (var i = 0; i < layout.children.length; i++) {
                    var sibling = layout.children[i];
                    if (sibling === root || !sibling.visible)
                        continue;

                    if (gridX >= sibling.x && gridX < sibling.x + sibling.width && gridY >= sibling.y && gridY < sibling.y + sibling.height) {
                        if (sibling.buttonData && sibling.buttonData.type) {
                            var targetType = sibling.buttonData.type;
                            var myType = root.buttonData.type;

                            mutatePages(function (pages) {
                                var page = pages[root.pageIndex];
                                if (!page)
                                    return;

                                var myIdx = -1;
                                var targetIdx = -1;
                                for (var j = 0; j < page.length; j++) {
                                    if (page[j].type === myType)
                                        myIdx = j;
                                    if (page[j].type === targetType)
                                        targetIdx = j;
                                }

                                if (myIdx !== -1 && targetIdx !== -1 && myIdx !== targetIdx) {
                                    var temp = page[myIdx];
                                    page[myIdx] = page[targetIdx];
                                    page[targetIdx] = temp;
                                }
                            });
                            break;
                        }
                    }
                }
            }

            onPressed: event => {
                var absPos = visualButton.parent.mapFromItem(editModeInteraction, event.x, event.y);
                pressAbsX = absPos.x;
                pressAbsY = absPos.y;
                initialVisualX = visualButton.x;
                initialVisualY = visualButton.y;
                root.isDragging = false;
            }

            onPositionChanged: event => {
                if (pressed) {
                    var absPos = visualButton.parent.mapFromItem(editModeInteraction, event.x, event.y);
                    var dx = absPos.x - pressAbsX;
                    var dy = absPos.y - pressAbsY;

                    if (!root.isDragging && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
                        root.isDragging = true;
                    }

                    if (root.isDragging) {
                        root.dragAbsX = initialVisualX + dx;
                        root.dragAbsY = initialVisualY + dy;

                        var centerX = root.dragAbsX + visualButton.width / 2;
                        var centerY = root.dragAbsY + visualButton.height / 2;

                        var gridPos = root.parent.mapFromItem(visualButton.parent, centerX, centerY);
                        checkForSwap(gridPos.x, gridPos.y);
                    }
                }
            }

            onReleased: event => {
                if (root.isDragging) {
                    root.isDragging = false;
                } else {
                    if (!visualButton.editingRight && !visualButton.editingBottom)
                        toggleEnabled();
                }
            }
        }

        // Edit Border and Resize Handles
        Rectangle {
            id: editBorder
            anchors.fill: parent
            visible: root.editMode && !root.isDragging
            color: "transparent"
            border.width: 2
            radius: Appearance.rounding.large
            
            border.color: {
                if (root.isUnused) {
                    return root.hovered ? Appearance.colors.colPrimary : "transparent";
                } else {
                    return root.hovered ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7);
                }
            }
            
            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(editBorder)
            }
            
            MouseArea {
                id: editBorderMouseArea
                anchors.fill: parent
                visible: root.isUnused
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            Rectangle {
                id: rightDragHandle
                width: 8
                height: 24
                radius: 4
                color: Appearance.colors.colPrimary
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: -width / 2
                visible: !root.isUnused

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    cursorShape: Qt.SizeHorCursor
                    preventStealing: true
                    property real pressAbsX: 0
                    onPressed: event => {
                        var absPos = visualButton.mapFromItem(rightDragHandle, event.x, event.y);
                        pressAbsX = absPos.x;
                        visualButton.editingRight = true;
                    }
                    onPositionChanged: event => {
                        var absPos = visualButton.mapFromItem(rightDragHandle, event.x, event.y);
                        var dx = absPos.x - pressAbsX;
                        visualButton.editDragX = Math.max(-root.baseCellWidth * 2, Math.min(dx, root.baseCellWidth * 2));
                    }
                    onReleased: event => {
                        visualButton.editingRight = false;
                        var threshold = root.baseCellWidth / 2;
                        var newSizeW = root.buttonData.sizeW ?? 2;
                        if (visualButton.editDragX > threshold)
                            newSizeW = 4;
                        else if (visualButton.editDragX < -threshold)
                            newSizeW = 2;
                        newSizeW = Math.max(2, Math.min(4, newSizeW));
                        if (newSizeW == 3)
                            newSizeW = 2; // snap to 2 or 4

                        visualButton.editDragX = 0;
                        if (newSizeW !== (root.buttonData.sizeW ?? 2)) {
                            // Automatically adjust height if switching to 4x (4x1 is not supported, 4x2 instead)
                            var currentH = root.buttonData.sizeH ?? 2;
                            if (newSizeW == 4 && currentH == 1)
                                currentH = 2;
                            editModeInteraction.setSize(newSizeW, currentH);
                            editModeInteraction.resolveLayoutConflicts();
                        }
                    }
                }
            }

            Rectangle {
                id: bottomDragHandle
                width: 24
                height: 8
                radius: 4
                color: Appearance.colors.colPrimary
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -height / 2
                visible: !root.isUnused && (root.buttonData.sizeW ?? 2) <= 2 // Only allow height resize for 2x width

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    cursorShape: Qt.SizeVerCursor
                    preventStealing: true
                    property real pressAbsY: 0
                    onPressed: event => {
                        var absPos = visualButton.mapFromItem(bottomDragHandle, event.x, event.y);
                        pressAbsY = absPos.y;
                        visualButton.editingBottom = true;
                    }
                    onPositionChanged: event => {
                        var absPos = visualButton.mapFromItem(bottomDragHandle, event.x, event.y);
                        var dy = absPos.y - pressAbsY;
                        var limit = root.baseCellHeight > 0 ? root.baseCellHeight * 2 : 100;
                        visualButton.editDragY = Math.max(-limit, Math.min(dy, limit));
                    }
                    onReleased: event => {
                        visualButton.editingBottom = false;
                        var currentH = root.buttonData.sizeH ?? 2;
                        var deltaRows = root.baseCellHeight > 0 ? Math.round(visualButton.editDragY / root.baseCellHeight) : 0;
                        var newSizeH = currentH + deltaRows;
                        if (isNaN(newSizeH))
                            newSizeH = currentH;
                        newSizeH = Math.max(1, Math.min(2, newSizeH));

                        visualButton.editDragY = 0;
                        if (newSizeH !== currentH) {
                            editModeInteraction.setSize(root.buttonData.sizeW ?? 2, newSizeH);
                            editModeInteraction.resolveLayoutConflicts();
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: addBadge
        width: 20
        height: 20
        radius: 10
        color: Appearance.m3colors.m3success
        anchors.top: parent.top
        anchors.topMargin: -6
        anchors.right: parent.right
        anchors.rightMargin: -6
        visible: root.isUnused
        z: 10
        
        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 14
            color: Appearance.m3colors.m3onSuccess
        }
    }

    StyledToolTip {
        parent: root
        extraVisibleCondition: root.tooltipText !== "" && root.hovered
        text: root.tooltipText
    }
}
