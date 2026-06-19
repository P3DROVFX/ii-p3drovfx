import QtQuick
import Quickshell
import qs.services

AndroidSliderWidgetBase {
    id: root

    tooltipText: Translation.tr("Volume")
    materialSymbol: {
        const muted = (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false;
        const vol = root.sliderValue;
        if (muted) return "volume_off";
        if (vol <= 0.0) return "volume_mute";
        if (vol <= 0.33) return "volume_mute";
        if (vol <= 0.66) return "volume_down";
        return "volume_up";
    }
    sliderValue: (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.volume : 0
    onMoved: function(value) {
        if (Audio.sink && Audio.sink.audio) {
            Audio.sink.audio.volume = value;
        }
    }
}
