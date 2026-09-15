pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono

Item {
    id: root
    signal closeRequested()

    readonly property var player: MprisController.activePlayer
    readonly property var track: MprisController.activeTrack
    readonly property string artUrl: track?.artUrl ?? ""
    property var shelf

    readonly property bool lyricsWanted: (shelf?.mediaOpen ?? false) && (shelf?.mediaLyricsShown ?? false)
    onLyricsWantedChanged: LyricsService.setWant(root, lyricsWanted)
    Component.onCompleted: LyricsService.setWant(root, lyricsWanted)
    Component.onDestruction: LyricsService.setWant(root, false)

    function fmt(s) {
        if (!s || s < 0)
            return "0:00";
        const m = Math.floor(s / 60);
        const sec = Math.floor(s % 60);
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
    }

    Timer {
        running: root.visible && (root.player?.isPlaying ?? false)
        interval: 500
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            z: 50
            spacing: 8

            PlayerChip {}
            Item { Layout.fillWidth: true }
            ChevronToggle {}
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Squircle {
                id: art
                implicitWidth: 78
                implicitHeight: 78
                radius: 20
                smoothing: AkebonoAppearance.squircleSmoothing
                color: Appearance.colors.colSecondaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "music_note"
                    iconSize: 38
                    color: Appearance.colors.colOnSecondaryContainer
                    visible: root.artUrl.length === 0 || cover.status !== Image.Ready
                }
                Image {
                    id: cover
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    visible: root.artUrl.length > 0 && status === Image.Ready
                    layer.enabled: visible
                    layer.effect: OpacityMask {
                        maskSource: Squircle {
                            width: cover.width
                            height: cover.height
                            radius: art.radius
                            smoothing: AkebonoAppearance.squircleSmoothing
                            color: "white"
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: root.track?.title ?? Translation.tr("Nothing playing")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.track?.artist ?? ""
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.track?.album ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                    elide: Text.ElideRight
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledSlider {
                id: seekSlider
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.Wavy
                animateWave: (root.player?.isPlaying ?? false)
                from: 0
                to: 1
                readonly property real len: root.player?.length ?? 0
                usePercentTooltip: false
                tooltipContent: root.fmt(seekSlider.value * seekSlider.len)
                onPressedChanged: {
                    if (!pressed && root.player && seekSlider.len > 0)
                        root.player.position = seekSlider.value * seekSlider.len;
                }
                Binding {
                    target: seekSlider
                    property: "value"
                    value: seekSlider.len > 0 ? (root.player.position / seekSlider.len) : 0
                    when: !seekSlider.pressed
                }
            }

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: root.fmt(seekSlider.value * seekSlider.len)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: root.fmt(seekSlider.len)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            MediaControlButton {
                icon: "shuffle"
                active: MprisController.hasShuffle
                enabled: MprisController.shuffleSupported
                onActivated: MprisController.setShuffle(!MprisController.hasShuffle)
            }
            MediaControlButton {
                icon: "skip_previous"
                enabled: MprisController.canGoPrevious
                onActivated: MprisController.previous()
            }
            MediaControlButton {
                big: true
                icon: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                enabled: MprisController.canTogglePlaying
                onActivated: MprisController.togglePlaying()
            }
            MediaControlButton {
                icon: "skip_next"
                enabled: MprisController.canGoNext
                onActivated: MprisController.next()
            }
            MediaControlButton {
                icon: MprisController.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                active: MprisController.loopState !== MprisLoopState.None
                enabled: MprisController.loopSupported
                onActivated: {
                    const order = [MprisLoopState.None, MprisLoopState.Playlist, MprisLoopState.Track];
                    const i = order.indexOf(MprisController.loopState);
                    MprisController.setLoopState(order[(i + 1) % order.length]);
                }
            }
        }

        Squircle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.shelf?.mediaLyricsShown ?? true
            radius: 22
            smoothing: AkebonoAppearance.squircleSmoothing
            color: Appearance.colors.colLayer1
            clip: true

            ListView {
                id: lyrics
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                visible: LyricsService.hasLyrics
                model: LyricsService.model
                currentIndex: LyricsService.currentIndex
                highlightFollowsCurrentItem: true
                highlightMoveDuration: 400
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: height / 2 - 30
                preferredHighlightEnd: height / 2 + 30

                delegate: Item {
                    id: lrow
                    required property int index
                    required property string lyricLine
                    readonly property bool current: index === lyrics.currentIndex
                    width: lyrics.width
                    implicitHeight: ltext.implicitHeight + 12

                    StyledText {
                        id: ltext
                        anchors.centerIn: parent
                        width: parent.width - 20
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: lrow.lyricLine
                        font.pixelSize: lrow.current ? Appearance.font.pixelSize.hugeass : Appearance.font.pixelSize.larger
                        font.weight: lrow.current ? Font.DemiBold : Font.Normal
                        color: lrow.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        opacity: lrow.current ? 1 : 0.45
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 220 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: LyricsService.jumpTo(lrow.index)
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: !LyricsService.hasLyrics
                text: LyricsService.loading ? Translation.tr("Finding lyrics…")
                    : (LyricsService.instrumental ? Translation.tr("♪ Instrumental") : Translation.tr("No lyrics found"))
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colSubtext
            }
        }
    }

    component ChevronToggle: Rectangle {
        id: ct
        readonly property bool shown: root.shelf?.mediaLyricsShown ?? true
        implicitWidth: 28
        implicitHeight: 28
        radius: AkebonoAppearance.shelfPillRadius
        color: ctMa.containsMouse ? Appearance.colors.colLayer2 : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "expand_more"
            iconSize: 21
            color: Appearance.colors.colOnLayer0
            rotation: ct.shown ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            id: ctMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.shelf?.toggleMediaLyrics()
        }
    }

    component PlayerChip: Item {
        id: pc
        readonly property var players: MprisController.players
        readonly property var active: MprisController.activePlayer
        readonly property var activeEntry: {
            DesktopEntries.applications.values;
            const id = pc.active?.desktopEntry ?? "";
            return id ? DesktopEntries.byId(id) : null;
        }
        property bool open: false
        visible: players.length > 0
        implicitWidth: chipBg.implicitWidth
        implicitHeight: 26

        Rectangle {
            id: chipBg
            implicitWidth: chipRow.implicitWidth + 16
            height: 26
            radius: 13
            color: chipMa.containsMouse ? Appearance.colors.colLayer2 : Qt.alpha(Appearance.colors.colLayer2, 0.55)
            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 5
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    source: pc.activeEntry?.icon ? Quickshell.iconPath(pc.activeEntry.icon) : ""
                    implicitSize: 15
                    visible: status === Image.Ready
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !pc.activeEntry?.icon
                    text: "music_note"
                    iconSize: 15
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pc.active?.identity ?? Translation.tr("Player")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 140)
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pc.players.length > 1
                    text: "expand_more"
                    iconSize: 15
                    color: Appearance.colors.colOnLayer2
                    rotation: pc.open ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 150 } }
                }
            }
            MouseArea {
                id: chipMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pc.players.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (pc.players.length > 1)
                        pc.open = !pc.open;
                }
            }
        }

        Rectangle {
            visible: pc.open
            width: Math.max(chipBg.width, 170)
            height: listCol.implicitHeight + 8
            y: chipBg.height + 4
            radius: 14
            color: Appearance.colors.colLayer2
            z: 50

            Column {
                id: listCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 4
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 2

                Repeater {
                    model: pc.players
                    delegate: Rectangle {
                        id: pItem
                        required property var modelData
                        readonly property bool isActive: modelData === pc.active
                        readonly property var entry: {
                            DesktopEntries.applications.values;
                            const id = pItem.modelData.desktopEntry ?? "";
                            return id ? DesktopEntries.byId(id) : null;
                        }
                        width: parent.width
                        height: 30
                        radius: 10
                        color: pItemMa.containsMouse ? Appearance.colors.colLayer1Hover
                            : (pItem.isActive ? Appearance.colors.colPrimaryContainer : "transparent")
                        Behavior on color { ColorAnimation { duration: 100 } }

                        IconImage {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            source: pItem.entry?.icon ? Quickshell.iconPath(pItem.entry.icon) : ""
                            implicitSize: 16
                            visible: status === Image.Ready
                        }
                        MaterialSymbol {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !pItem.entry?.icon
                            text: "music_note"
                            iconSize: 16
                            color: pItem.isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 34
                            anchors.rightMargin: 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: pItem.modelData?.identity ?? Translation.tr("Player")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: pItem.isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                        }
                        MaterialSymbol {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pItem.isActive
                            text: "check"
                            iconSize: 15
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        MouseArea {
                            id: pItemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                MprisController.setActivePlayer(pItem.modelData);
                                pc.open = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
