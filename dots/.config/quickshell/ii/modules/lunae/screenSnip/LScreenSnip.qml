pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property string activeFamily: "lunae"

    property int mediaType: LRegionSelectionPanel.MediaType.Image
    property int imageAction: LRegionSelectionPanel.ImageAction.Copy
    property int videoAction: LRegionSelectionPanel.VideoAction.Record

    readonly property string primaryScreen: Quickshell.screens.some(s => s.name === GlobalStates.overlayScreen)
        ? GlobalStates.overlayScreen
        : (Quickshell.screens[0]?.name ?? "")
    property bool primaryRevealed: false

    readonly property var targetScreens: Config.options.screenSnip.monitorScope === "focused"
        ? Quickshell.screens.filter(s => s.name === root.primaryScreen)
        : Quickshell.screens

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
    }

    Connections {
        target: GlobalStates
        function onRegionSelectorOpenChanged() {
            if (!GlobalStates.regionSelectorOpen)
                root.primaryRevealed = false;
        }
    }

    Variants {
        model: root.targetScreens

        delegate: Loader {
            id: snipLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen

            sourceComponent: LRegionSelectionPanel {
                snip: root
                screen: snipLoader.modelData
                onCloseRequested: root.dismiss()
            }
        }
    }

    function _image(action) {
        root.mediaType = LRegionSelectionPanel.MediaType.Image
        root.imageAction = action
        GlobalStates.regionSelectorOpen = true
    }

    function _record(action) {
        if (Persistent.states.screenRecord.active) {
            Quickshell.execDetached([Directories.recordScriptPath])
            return
        }
        root.mediaType = LRegionSelectionPanel.MediaType.Video
        root.videoAction = action
        GlobalStates.regionSelectorOpen = true
    }

    function screenshot() { root._image(LRegionSelectionPanel.ImageAction.Copy) }
    function ocr() { root._image(LRegionSelectionPanel.ImageAction.CharRecognition) }
    function search() { root._image(LRegionSelectionPanel.ImageAction.Search) }
    function translate() { root._image(LRegionSelectionPanel.ImageAction.Translate) }
    function record() { root._record(LRegionSelectionPanel.VideoAction.Record) }
    function recordWithSound() { root._record(LRegionSelectionPanel.VideoAction.RecordWithSound) }

    IpcHandler {
        target: "region"

        function screenshot(): void { root.screenshot() }
        function ocr(): void { root.ocr() }
        function record(): void { root.record() }
        function recordWithSound(): void { root.recordWithSound() }
        function search(): void { root.search() }
        function translate(): void { root.translate() }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: { if (Config.options.panelFamily !== root.activeFamily) return; root.screenshot() }
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: { if (Config.options.panelFamily !== root.activeFamily) return; root.search() }
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: { if (Config.options.panelFamily !== root.activeFamily) return; root.ocr() }
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: { if (Config.options.panelFamily !== root.activeFamily) return; root.record() }
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: { if (Config.options.panelFamily !== root.activeFamily) return; root.recordWithSound() }
    }
    GlobalShortcut {
        name: "regionTranslate"
        description: "Translates text in the selected region"
        onPressed: { if (Config.options.panelFamily !== root.activeFamily) return; root.translate() }
    }
}
