import qs.services
import qs.modules.common
import qs.modules.common.widgets

AkToggle {
    icon: "gamepad"
    on: GameMode.active
    onClicked: GameMode.toggle()
    StyledToolTip {
        text: Translation.tr("Game mode | Right-click to configure")
    }
}
