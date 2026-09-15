import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

AkToggle {
    on: Persistent.states.screenRecord.active
    icon: "screen_record"
    onClicked: Quickshell.execDetached([Directories.recordScriptPath, "--fullscreen"])
    StyledToolTip {
        text: on ? Translation.tr("Recording... Click to stop") : Translation.tr("Record | Right-click to configure")
    }
}
