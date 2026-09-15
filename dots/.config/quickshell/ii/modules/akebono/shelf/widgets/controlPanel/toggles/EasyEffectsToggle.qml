import QtQuick
import Quickshell
import qs.services
import qs.modules.common.widgets

AkToggle {
    id: root
    shown: EasyEffects.available
    on: EasyEffects.active
    icon: "graphic_eq"
    Component.onCompleted: EasyEffects.fetchActiveState()
    onClicked: EasyEffects.toggle()
    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "flatpak run com.github.wwmm.easyeffects || easyeffects"]);
        root.panel?.closeRequested();
    }
    StyledToolTip {
        text: Translation.tr("EasyEffects | Right-click to configure")
    }
}
