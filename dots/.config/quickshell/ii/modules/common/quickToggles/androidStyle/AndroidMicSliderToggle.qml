import QtQuick
import Quickshell
import qs.services

AndroidSliderWidgetBase {
    id: root

    tooltipText: Translation.tr("Microphone")
    materialSymbol: "mic"
    sliderValue: (Audio.source && Audio.source.audio) ? Audio.source.audio.volume : 0
    onMoved: function(value) {
        if (Audio.source && Audio.source.audio) {
            Audio.source.audio.volume = value;
        }
    }
}
