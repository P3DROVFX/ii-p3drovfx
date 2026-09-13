import qs.modules.common
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    toggled: Idle.inhibit
    buttonIcon: Idle.timed ? "hourglass_top" : "coffee"
    onClicked: {
        Idle.toggleInhibit()
    }

    StyledToolTip {
        text: Idle.timed ? Translation.tr("Keep system awake — %1 left | Right-click to change").arg(Idle.remainingText) : Translation.tr("Keep system awake | Right-click to set a duration")
    }
}
