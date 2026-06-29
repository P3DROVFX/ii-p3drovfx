import qs.services
import QtQuick
import qs.modules.ii.topLayer.osd
import qs.modules.common.widgets
import qs.modules.common

OsdConnectValueIndicator {
    id: osdValues
    value: Audio.value
    icon: {
        const muted = Audio.muted;
        const vol = osdValues.value;
        if (muted) return "volume_off";
        if (vol <= 0.0) return "volume_mute";
        if (vol <= 0.33) return "volume_mute";
        if (vol <= 0.66) return "volume_down";
        return "volume_up";
    }
    name: Translation.tr("Volume")
    shape: MaterialShape.Shape.Cookie7Sided
    maxLimit: (Config.options.audio && Config.options.audio.protection && Config.options.audio.protection.enable) ? Config.options.audio.protection.maxAllowed / 100 : 1.5

    onValueUpdateRequested: (newValue) => {
        if (Audio.sink && Audio.sink.audio) {
            Audio.sink.audio.volume = newValue;
            if (Audio.sink.audio.muted && newValue > 0) {
                Audio.sink.audio.muted = false;
            }
        }
    }
}
