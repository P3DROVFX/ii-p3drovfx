import qs
import qs.services
import qs.modules.common.widgets

AkToggle {
    on: GlobalStates.oskOpen
    icon: on ? "keyboard_hide" : "keyboard"
    onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
    StyledToolTip {
        text: Translation.tr("On-screen keyboard")
    }
}
