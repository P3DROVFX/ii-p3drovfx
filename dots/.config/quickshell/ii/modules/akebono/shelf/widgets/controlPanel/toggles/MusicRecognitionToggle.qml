import qs.services
import qs.modules.common.widgets

AkToggle {
    id: root
    readonly property bool sourceIsMonitor: SongRec.monitorSource === SongRec.MonitorSource.Monitor
    on: SongRec.running
    icon: on ? "music_cast" : (sourceIsMonitor ? "music_note" : "frame_person_mic")
    onClicked: SongRec.toggleRunning()
    altAction: () => SongRec.toggleMonitorSource()
    StyledToolTip {
        text: Translation.tr("Recognize music | Right-click to switch source")
    }
}
