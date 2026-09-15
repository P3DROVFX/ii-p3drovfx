import qs.services
import qs.modules.common.widgets

AkToggle {
    on: !Audio.source?.audio?.muted
    icon: Audio.source?.audio?.muted ? "mic_off" : "mic"
    onClicked: Audio.toggleMicMute()
    StyledToolTip {
        text: Translation.tr("Microphone | Right-click to configure")
    }
}
