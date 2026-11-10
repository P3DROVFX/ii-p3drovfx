import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "./widgets"

/**
 * Right-click menu of the dock's media widget: the transport controls, the
 * media window, the widget's shape and its settings.
 */
DockContextMenuBase {
    id: root

    readonly property bool hasTrack: root.anchorItem?.hasTrack ?? false
    readonly property bool isPlaying: root.anchorItem?.isPlaying ?? false
    readonly property bool isSquare: root.anchorItem?.square ?? false
    readonly property bool isVertical: root.anchorItem?.isVertical ?? false
    readonly property bool inStack: root.anchorItem?.dockContent?._inWidgetStack("media") ?? false
    readonly property string artSource: root.anchorItem?.effectiveArtSource ?? ""

    menuId: "dockMedia"
    headerText: root.hasTrack ? (root.anchorItem?.title ?? "") : Translation.tr("No media")
    headerSubtitle: root.hasTrack ? (root.anchorItem?.artist ?? "") : ""
    headerSymbol: "music_note"
    headerIcon: root.artSource !== "" ? artComponent : null

    Component {
        id: artComponent
        Image {
            source: root.artSource
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
        }
    }

    menuGroups: root.menuOpen ? [
        [
            {
                id: "playPause",
                icon: root.isPlaying ? "pause" : "play_arrow",
                text: root.isPlaying ? Translation.tr("Pause") : Translation.tr("Play"),
                enabled: root.hasTrack
            },
            { id: "next", icon: "skip_next", text: Translation.tr("Next"), enabled: root.hasTrack },
            { id: "previous", icon: "skip_previous", text: Translation.tr("Previous"), enabled: root.hasTrack }
        ],
        [
            {
                id: "controls",
                icon: "queue_music",
                text: GlobalStates.mediaControlsOpen ? Translation.tr("Close media controls") : Translation.tr("Open media controls")
            }
        ],
        root.isVertical || root.inStack ? [] : [
            root.isSquare
                ? { id: "wide", icon: "crop_16_9", text: Translation.tr("Make wide") }
                : { id: "square", icon: "crop_square", text: Translation.tr("Make square") }
        ],
        [
            { id: "settings", icon: "settings", text: Translation.tr("Widget settings") },
            { id: "remove", icon: "remove_circle", text: Translation.tr("Remove from dock"), destructive: true }
        ]
    ].filter(group => group.length > 0) : []

    onActionTriggered: actionId => {
        root.close();
        switch (actionId) {
        case "playPause": MprisController.togglePlaying(); break;
        case "next": MprisController.next(); break;
        case "previous": MprisController.previous(); break;
        case "controls": GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen; break;
        case "square": Config.options.dock.mediaSquare = true; break;
        case "wide": Config.options.dock.mediaSquare = false; break;
        case "settings": GlobalStates.openSettingsPage("dock", "widgets/DockUtilitiesConfig.qml"); break;
        case "remove":
            Config.options.dock.enableMediaWidget = false;
            Config.options.dock.widgetStackItems = Array.from(Config.options.dock.widgetStackItems ?? []).filter(m => m !== "media");
            break;
        }
    }
}
