import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Audio output")
    statusText: toggled ? Audio.friendlyDeviceName(Audio.sink) : Translation.tr("Muted")
    tooltipText: Translation.tr("Audio output | Right-click for volume mixer & device selector")
    toggled: !Audio.sink?.audio?.muted
    readonly property real volume: {
        const v = Audio.sink?.audio?.volume;
        return typeof v === "number" && !isNaN(v) ? v : 0;
    }
    heroLevel: Math.min(1, volume)
    heroValue: String(Math.round(volume * 100))
    heroUnit: "%"
    icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
    mainAction: () => {
        Audio.toggleMute()
    }
    hasMenu: true
}
