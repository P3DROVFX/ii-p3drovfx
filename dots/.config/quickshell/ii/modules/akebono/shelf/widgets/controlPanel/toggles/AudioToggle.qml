import qs.services
import qs.modules.common.widgets

AkToggle {
    on: !Audio.sink?.audio?.muted
    icon: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
    onClicked: Audio.toggleMute()
    StyledToolTip {
        text: Translation.tr("Audio output | Right-click to configure")
    }
}
