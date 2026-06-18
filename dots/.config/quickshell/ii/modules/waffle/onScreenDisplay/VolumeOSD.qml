import QtQuick
import qs.services
import qs.modules.waffle.looks

OSDValue {
    id: root
    iconName: WIcons.volumeIcon
    materialSymbol: {
        const muted = Audio.sink?.audio.muted ?? false;
        const vol = root.value;
        if (muted) return "volume_off";
        if (vol <= 0.0) return "volume_mute";
        if (vol <= 0.33) return "volume_mute";
        if (vol <= 0.66) return "volume_down";
        return "volume_up";
    }
    value: Audio.sink?.audio.volume ?? 0

    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (Audio.ready)
                root.timer.restart();
        }
        function onMutedChanged() {
            if (Audio.ready)
                root.timer.restart();
        }
    }
}
