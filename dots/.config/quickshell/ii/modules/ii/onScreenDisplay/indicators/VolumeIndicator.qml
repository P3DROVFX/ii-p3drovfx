import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets
import qs.modules.common

OsdValueIndicator {
    id: osdValues
    value: Audio.sink?.audio.volume ?? 0
    icon: {
        const muted = (Audio.sink && Audio.sink.audio) ? Audio.sink.audio.muted : false;
        const vol = osdValues.value;
        if (muted) return "volume_off";
        if (vol <= 0.0) return "volume_mute";
        if (vol <= 0.33) return "volume_mute";
        if (vol <= 0.66) return "volume_down";
        return "volume_up";
    }
    name: Translation.tr("Volume")
    shape: MaterialShape.Shape.Cookie7Sided
    maxLimit: (Config.options.audio && Config.options.audio.protection) ? Config.options.audio.protection.maxAllowed / 100 : 1.0
}
