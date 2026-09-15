pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Local playlist surface for Media Mode.
 *
 * The caller owns eligibility: this component must only be instantiated for a
 * local playlist, never for an application MPRIS player or a single file.
 * `queueSnapshot` comes from the helper's authoritative state, so duplicate
 * tracks remain distinct through their entryId even when their metadata ties.
 */
Item {
    id: root

    property var queueSnapshot: ({})
    property bool expanded: true
    property bool lyricsExpanded: true
    property bool lyricsToggleAvailable: true
    property color accentColor: Appearance.colors.colPrimary
    property color accentContainerColor: Appearance.colors.colPrimaryContainer
    property color onAccentContainerColor: Appearance.colors.colOnPrimaryContainer

    property var entries: []
    readonly property string currentEntryId: String(queueSnapshot?.currentEntryId ?? "")
    readonly property int currentIndex: {
        for (let i = 0; i < entries.length; ++i) {
            if (String(entries[i]?.entryId ?? "") === currentEntryId)
                return i;
        }
        return -1;
    }
    readonly property bool shuffleActive: Boolean(queueSnapshot?.shuffle ?? false)
    readonly property real headerButtonSize: Appearance.sizes.minimumTouchTarget - Appearance.sizes.elevationMargin
    readonly property real headerHeight: Appearance.sizes.minimumTouchTarget
        + Appearance.sizes.elevationMargin * 2
    readonly property real rowHeight: Appearance.sizes.minimumTouchTarget
        + Appearance.sizes.elevationMargin
    implicitHeight: headerHeight

    signal expandedToggled()
    signal lyricsExpandedToggled()
    signal openFileBrowserRequested(bool audioOnly)

    property bool initialCenterDone: false
    property bool sortPanelOpen: false
    property string sortCriterion: Persistent.states.background.mediaMode.queueSortCriterion || "title"
    property bool sortDescending: Persistent.states.background.mediaMode.queueSortDescending ?? false

    readonly property var sortOptions: [
        { value: "title", label: Translation.tr("Title"), icon: "sort_by_alpha" },
        { value: "artist", label: Translation.tr("Artist"), icon: "person" },
        { value: "mtime", label: Translation.tr("Date modified"), icon: "update" },
        { value: "ctime", label: Translation.tr("Date created"), icon: "calendar_add_on" },
        { value: "duration", label: Translation.tr("Duration"), icon: "schedule" }
    ]

    function openSortDialog() {
        sortDialog.open();
    }

    function closeSortDialog() {
        sortDialog.close();
    }

    onExpandedChanged: {
        if (!expanded && sortDialog.visible)
            sortDialog.close();
        if (root.expanded && !root.initialCenterDone)
            root.tryInitialCenter();
    }

    function applySort(criterion, descending) {
        root.sortCriterion = criterion;
        root.sortDescending = descending;
        Persistent.states.background.mediaMode.queueSortCriterion = criterion;
        Persistent.states.background.mediaMode.queueSortDescending = descending;
        LocalMediaService.sortQueue(criterion, descending);
    }

    function _syncEntries(): void {
        const rawEntries = root.queueSnapshot?.entries;
        if (!rawEntries || !Array.isArray(rawEntries)) {
            if (root.entries.length > 0)
                root.entries = [];
            return;
        }

        const current = root.entries;
        if (current.length === rawEntries.length) {
            let same = true;
            for (let i = 0; i < current.length; ++i) {
                if ((current[i]?.entryId ?? "") !== (rawEntries[i]?.entryId ?? "")) {
                    same = false;
                    break;
                }
            }
            if (same)
                return;
        }

        const savedContentY = queueList ? queueList.contentY : 0;
        root.entries = rawEntries;
        if (savedContentY > 0) {
            Qt.callLater(() => {
                if (queueList && !queueList.dragging && !queueList.moving) {
                    queueList.contentY = Math.max(0, Math.min(queueList.contentHeight - queueList.height, savedContentY));
                }
            });
        }
    }

    onQueueSnapshotChanged: {
        root._syncEntries();
    }

    function centerCurrentTrack(force = false) {
        if (root.currentIndex < 0 || root.currentIndex >= root.entries.length)
            return false;
        if (!root.expanded || !root.visible || queueList.height <= 0 || queueList.count <= 0)
            return false;
        if (!force && (queueList.dragging || queueList.moving))
            return false;

        queueList.currentIndex = root.currentIndex;
        queueList.positionViewAtIndex(root.currentIndex, ListView.Center);
        return true;
    }

    function tryInitialCenter() {
        if (root.initialCenterDone)
            return;
        if (root.centerCurrentTrack()) {
            root.initialCenterDone = true;
            initialCenterTimer.stop();
        } else if (root.expanded && root.visible && root.currentIndex >= 0) {
            initialCenterTimer.restart();
        }
    }

    Timer {
        id: initialCenterTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (!root.initialCenterDone)
                root.tryInitialCenter();
        }
    }

    Component.onCompleted: {
        root._syncEntries();
        root.tryInitialCenter();
    }

    onVisibleChanged: {
        if (visible && !root.initialCenterDone)
            root.tryInitialCenter();
    }

    onCurrentIndexChanged: {
        if (!root.initialCenterDone)
            root.tryInitialCenter();
    }

    Rectangle {
        id: queueCard
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.55)

        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: queueCard.width
                height: queueCard.height
                radius: queueCard.radius
                antialiasing: true
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Item {
            id: headerItem
            z: 85
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.headerHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Appearance.sizes.elevationMargin * 2
                anchors.rightMargin: Appearance.sizes.elevationMargin * 2
                spacing: Appearance.sizes.elevationMargin

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "queue_music"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.accentColor
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Up next")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: String(root.entries.length)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                Item {
                    Layout.fillWidth: true
                }

                RippleButton {
                    visible: root.expanded
                    enabled: root.entries.length > 1
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.headerButtonSize
                    implicitHeight: root.headerButtonSize
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: LocalMediaService.clearFutureQueueEntries()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "playlist_remove"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    PopupToolTip {
                        text: Translation.tr("Clear upcoming tracks")
                    }
                }

                RippleButton {
                    visible: root.expanded
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.headerButtonSize
                    implicitHeight: root.headerButtonSize
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: root.openFileBrowserRequested(true)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "playlist_add"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    PopupToolTip {
                        text: Translation.tr("Add music to queue")
                    }
                }

                RippleButton {
                    visible: root.expanded
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.headerButtonSize
                    implicitHeight: root.headerButtonSize
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: root.openFileBrowserRequested(false)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "create_new_folder"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    PopupToolTip {
                        text: Translation.tr("Add folder to queue")
                    }
                }

                RippleButton {
                    visible: root.expanded && root.entries.length > 0
                    enabled: root.currentIndex >= 0
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.headerButtonSize
                    implicitHeight: root.headerButtonSize
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: root.centerCurrentTrack(true)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "center_focus_strong"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    PopupToolTip {
                        text: Translation.tr("Center on current track")
                    }
                }

                RippleButton {
                    id: sortButton
                    visible: root.expanded && root.entries.length > 1
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.headerButtonSize
                    implicitHeight: root.headerButtonSize
                    buttonRadius: Appearance.rounding.full
                    toggled: sortDialog.visible
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    colBackgroundToggled: root.accentColor
                    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                    colBackgroundToggledActive: Appearance.colors.colPrimaryActive
                    colRipple: Appearance.colors.colLayer2Active
                    colRippleToggled: Appearance.colors.colPrimaryActive
                    onClicked: {
                        if (sortDialog.visible)
                            root.closeSortDialog();
                        else
                            root.openSortDialog();
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "sort"
                        iconSize: Appearance.font.pixelSize.normal
                        color: sortButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }

                    PopupToolTip {
                        text: Translation.tr("Sort queue")
                    }
                }

                RippleButton {
                    visible: root.lyricsToggleAvailable
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.headerButtonSize
                    implicitHeight: root.headerButtonSize
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: root.lyricsExpandedToggled()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.lyricsExpanded ? "lyrics" : "keyboard_arrow_down"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    PopupToolTip {
                        text: root.lyricsExpanded ? Translation.tr("Collapse lyrics") : Translation.tr("Expand lyrics")
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.headerButtonSize
                    implicitHeight: root.headerButtonSize
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.accentContainerColor
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                    onClicked: root.expandedToggled()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.expanded ? "keyboard_arrow_down" : "keyboard_arrow_up"
                        iconSize: Appearance.font.pixelSize.large
                        color: root.onAccentContainerColor
                    }

                    PopupToolTip {
                        text: root.expanded ? Translation.tr("Collapse queue") : Translation.tr("Expand queue")
                    }
                }
            }
        }

        Item {
            id: listContainer
            anchors.top: headerItem.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Appearance.sizes.elevationMargin * 2
            anchors.rightMargin: Appearance.sizes.elevationMargin * 2
            anchors.bottomMargin: 0
            visible: root.expanded
            opacity: visible ? 1 : 0
            clip: true

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            ListView {
                id: queueList
                anchors.fill: parent
                clip: true
                model: root.entries
                currentIndex: -1
                highlightFollowsCurrentItem: false
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true
                spacing: Appearance.sizes.elevationMargin / 2

                onMovementStarted: root.initialCenterDone = true
                onContentYChanged: {
                    if (queueList.dragging || queueList.moving || queueList.flicking)
                        root.initialCenterDone = true;
                }

                readonly property real startGap: Math.max(0, (queueList.contentY ?? 0) - ((queueList.originY ?? 0) - (queueList.topMargin ?? 0)))
                readonly property real endGap: Math.max(0, ((queueList.originY ?? 0) + (queueList.contentHeight ?? 0) + (queueList.bottomMargin ?? 0))
                    - ((queueList.contentY ?? 0) + (queueList.height ?? 0)))
                readonly property bool overflowing: (queueList.contentHeight ?? 0) > (queueList.height ?? 0) + 2
                readonly property real fadeSize: Math.round(Appearance.font.pixelSize.huge * 1.8)
                readonly property real topFadeProgress: overflowing ? Math.max(0, Math.min(1, startGap / 36)) : 0
                readonly property real bottomFadeProgress: overflowing ? Math.max(0, Math.min(1, endGap / 36)) : 0

                layer.enabled: root.expanded
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: Math.max(1, queueList.width)
                        height: Math.max(1, queueList.height)
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: Qt.rgba(1, 1, 1, 1 - queueList.topFadeProgress)
                            }
                            GradientStop {
                                position: queueList.height > 0
                                    ? Math.min(0.35, queueList.fadeSize / Math.max(1, queueList.height)) : 0
                                color: "white"
                            }
                            GradientStop {
                                position: queueList.height > 0
                                    ? Math.max(0.65, 1 - queueList.fadeSize / Math.max(1, queueList.height)) : 1
                                color: "white"
                            }
                            GradientStop {
                                position: 1.0
                                color: Qt.rgba(1, 1, 1, 1 - queueList.bottomFadeProgress)
                            }
                        }
                    }
                }

                onHeightChanged: {
                    if (!root.initialCenterDone && queueList.height > 0)
                        root.tryInitialCenter();
                }

                onCountChanged: {
                    if (!root.initialCenterDone && queueList.count > 0)
                        root.tryInitialCenter();
                }

                    delegate: Item {
                        id: queueRow
                        required property int index
                        required property var modelData

                        readonly property var entry: modelData ?? ({})
                        readonly property string entryId: String(entry.entryId ?? "")
                        readonly property bool current: entryId === root.currentEntryId
                        readonly property bool isCurrent: current
                        readonly property bool isFirst: queueRow.index === 0
                        readonly property bool isLast: queueRow.index === root.entries.length - 1
                        readonly property bool aboveCurrent: root.currentIndex !== -1 && queueRow.index === root.currentIndex - 1
                        readonly property bool belowCurrent: root.currentIndex !== -1 && queueRow.index === root.currentIndex + 1
                        readonly property bool rowHovered: rowHoverHandler.hovered
                            || rowHoverArea.containsMouse
                            || trackInfoMouseArea.containsMouse
                            || artClickArea.containsMouse

                        HoverHandler {
                            id: rowHoverHandler
                        }

                        readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : (height / 2)
                        readonly property real rDynamicFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)
                        readonly property real rOuter: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.large
                        readonly property real rInner: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.verysmall

                        readonly property real targetTopRadius: isCurrent
                            ? rFull
                            : (rowHovered
                                ? rDynamicFull
                                : (belowCurrent
                                    ? rDynamicFull
                                    : (isFirst ? rOuter : rInner)))

                        readonly property real targetBottomRadius: isCurrent
                            ? rFull
                            : (rowHovered
                                ? rDynamicFull
                                : (aboveCurrent
                                    ? rDynamicFull
                                    : (isLast ? rOuter : rInner)))

                        width: queueList.width
                        height: root.rowHeight

                        Rectangle {
                            id: rowBackground
                            anchors.fill: parent
                            topLeftRadius: queueRow.targetTopRadius
                            topRightRadius: queueRow.targetTopRadius
                            bottomLeftRadius: queueRow.targetBottomRadius
                            bottomRightRadius: queueRow.targetBottomRadius
                            color: queueRow.current
                                ? ColorUtils.transparentize(root.accentContainerColor, 0.34)
                                : (queueRow.rowHovered
                                    ? Appearance.colors.colLayer2Hover
                                    : Appearance.colors.colLayer2)

                            Behavior on topLeftRadius {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(rowBackground)
                            }
                            Behavior on topRightRadius {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(rowBackground)
                            }
                            Behavior on bottomLeftRadius {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(rowBackground)
                            }
                            Behavior on bottomRightRadius {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(rowBackground)
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(rowBackground)
                            }
                        }

                        MouseArea {
                            id: rowHoverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: LocalMediaService.playQueueEntry(queueRow.entryId)
                        }

                        RowLayout {
                            id: queueRowContent
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            spacing: Appearance.sizes.elevationMargin

                            Item {
                                id: artPreviewContainer
                                Layout.preferredWidth: Appearance.sizes.minimumTouchTarget - Appearance.sizes.elevationMargin
                                Layout.preferredHeight: width

                                readonly property real previewRadius: queueRow.current
                                    ? Appearance.rounding.full
                                    : Math.min(width / 2, Math.max(0, Appearance.rounding.scale === 0 ? 0 : (Appearance.rounding.windowRounding - Appearance.sizes.elevationMargin)))

                                Rectangle {
                                    id: artMask
                                    anchors.fill: parent
                                    radius: artPreviewContainer.previewRadius
                                    color: queueRow.current
                                        ? ColorUtils.transparentize(root.accentColor, 0.75)
                                        : Appearance.colors.colLayer3
                                    clip: true

                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: artMask.width
                                            height: artMask.height
                                            radius: artPreviewContainer.previewRadius
                                        }
                                    }

                                    Image {
                                        id: artThumb
                                        anchors.fill: parent
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        source: String(queueRow.entry.artUrl ?? "")
                                        visible: status === Image.Ready
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: artThumb.status !== Image.Ready
                                        text: queueRow.current ? "graphic_eq" : "music_note"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: queueRow.current ? root.accentColor : Appearance.colors.colOnLayer2
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: artPreviewContainer.previewRadius
                                        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
                                        visible: opacity > 0
                                        opacity: (artClickArea.containsMouse && !queueRow.current) ? 1 : 0

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                        }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "play_arrow"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colOnLayer0
                                        }
                                    }

                                    MouseArea {
                                        id: artClickArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: LocalMediaService.playQueueEntry(queueRow.entryId)
                                    }
                                }
                            }

                            Item {
                                id: trackInfoContainer
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(queueRow.entry.title ?? Translation.tr("Untitled"))
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: queueRow.current ? Font.Bold : Font.Medium
                                        color: queueRow.current
                                            ? (ColorUtils.contrastRatio(root.accentColor, Appearance.colors.colLayer1Base) >= 3.0
                                                ? root.accentColor
                                                : ColorUtils.adaptToAccent(Appearance.colors.colOnLayer0, root.accentColor))
                                            : (queueRow.rowHovered
                                                ? Appearance.colors.colOnLayer0
                                                : Appearance.colors.colOnLayer2)
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(queueRow.entry.artist ?? "")
                                            || String(queueRow.entry.album ?? "")
                                            || Translation.tr("Unknown artist")
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: queueRow.current
                                            ? ColorUtils.mix(root.accentColor, Appearance.colors.colSubtext, 0.4)
                                            : (queueRow.rowHovered
                                                ? Appearance.colors.colOnLayer1
                                                : Appearance.colors.colSubtext)
                                    }
                                }

                                MouseArea {
                                    id: trackInfoMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: LocalMediaService.playQueueEntry(queueRow.entryId)
                                }
                            }

                            RippleButton {
                                enabled: !root.shuffleActive && queueRow.index > 0
                                implicitWidth: Appearance.sizes.minimumTouchTarget - Appearance.sizes.elevationMargin
                                implicitHeight: implicitWidth
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer2Hover
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colBackgroundActive: Appearance.colors.colLayer2Active
                                onClicked: LocalMediaService.moveQueueEntry(queueRow.entryId, queueRow.index - 1)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "keyboard_arrow_up"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer2
                                }
                            }

                            RippleButton {
                                enabled: !root.shuffleActive && queueRow.index < root.entries.length - 1
                                implicitWidth: Appearance.sizes.minimumTouchTarget - Appearance.sizes.elevationMargin
                                implicitHeight: implicitWidth
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer2Hover
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colBackgroundActive: Appearance.colors.colLayer2Active
                                onClicked: LocalMediaService.moveQueueEntry(queueRow.entryId, queueRow.index + 1)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "keyboard_arrow_down"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer2
                                }
                            }

                            RippleButton {
                                enabled: root.entries.length > 1
                                implicitWidth: Appearance.sizes.minimumTouchTarget - Appearance.sizes.elevationMargin
                                implicitHeight: implicitWidth
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colLayer2Hover
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                colBackgroundActive: Appearance.colors.colErrorContainerActive
                                onClicked: LocalMediaService.removeQueueEntries([queueRow.entryId])

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer2
                                }
                            }
                        }
                    }
                }
            }

        Popup {
            id: sortDialog
            parent: queueCard
            x: Math.max(0, queueCard.width - width - (Appearance.sizes.elevationMargin * 2))
            y: headerItem.height + Appearance.sizes.hyprlandGapsOut
            width: Math.min(Appearance.sizes.wallpaperSelectorSortDialogWidth, queueCard.width - 24)
            padding: Appearance.font.pixelSize.smaller
            modal: false
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

            onOpened: root.sortPanelOpen = true
            onClosed: {
                Qt.callLater(() => root.sortPanelOpen = false);
            }

            background: Rectangle {
                color: Appearance.m3colors.m3surfaceContainerHigh
                radius: Appearance.rounding.large
            }

            enter: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        target: sortDialog
                        property: "y"
                        from: headerItem.height
                        to: headerItem.height + Appearance.sizes.hyprlandGapsOut
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardDecel
                    }
                    NumberAnimation {
                        target: sortDialog
                        property: "opacity"
                        from: 0.0
                        to: 1.0
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardDecel
                    }
                }
            }

            exit: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        target: sortDialog
                        property: "y"
                        from: headerItem.height + Appearance.sizes.hyprlandGapsOut
                        to: headerItem.height
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardAccel
                    }
                    NumberAnimation {
                        target: sortDialog
                        property: "opacity"
                        from: 1.0
                        to: 0.0
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.standardAccel
                    }
                }
            }

            contentItem: ColumnLayout {
                spacing: Appearance.sizes.hyprlandGapsOut

                Repeater {
                    model: root.sortOptions

                    delegate: RippleButton {
                        id: sortOptionButton
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut * 2
                        buttonRadius: Appearance.rounding.large
                        buttonRadiusPressed: Appearance.rounding.large
                        useDynamicRadius: true
                        toggled: modelData.value === root.sortCriterion
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colBackgroundActive: Appearance.colors.colLayer2Active
                        colBackgroundToggled: root.accentColor
                        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
                        colRipple: Appearance.colors.colLayer2Active
                        colRippleToggled: Appearance.colors.colPrimaryActive

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.font.pixelSize.small
                            anchors.rightMargin: Appearance.font.pixelSize.small
                            spacing: Appearance.font.pixelSize.small

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                                iconSize: Appearance.font.pixelSize.huge
                                text: sortOptionButton.modelData.icon
                                color: sortOptionButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                                text: sortOptionButton.modelData.label
                                color: sortOptionButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                visible: sortOptionButton.modelData.value === root.sortCriterion
                                iconSize: Appearance.font.pixelSize.huge
                                text: root.sortDescending ? "arrow_downward" : "arrow_upward"
                                color: Appearance.colors.colOnPrimary
                            }
                        }

                        onClicked: {
                            if (root.sortCriterion === sortOptionButton.modelData.value) {
                                root.applySort(sortOptionButton.modelData.value, !root.sortDescending);
                            } else {
                                root.applySort(sortOptionButton.modelData.value, false);
                            }
                        }
                    }
                }
            }
        }
    }
}
