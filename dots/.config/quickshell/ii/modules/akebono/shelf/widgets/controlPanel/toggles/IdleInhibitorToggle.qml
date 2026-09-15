import qs.services
import qs.modules.common.widgets

AkToggle {
    on: Idle.inhibit
    icon: "coffee"
    onClicked: Idle.toggleInhibit()
    StyledToolTip {
        text: Translation.tr("Keep system awake")
    }
}
