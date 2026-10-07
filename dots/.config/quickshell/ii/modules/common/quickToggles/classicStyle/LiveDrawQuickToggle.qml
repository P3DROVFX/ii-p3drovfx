import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

QuickToggleButton {
    id: root
    buttonIcon: "draw"
    toggled: LiveDraw.trayOpen

    onClicked: {
        if (!LiveDraw.trayOpen)
            GlobalStates.sidebarRightOpen = false;
        LiveDraw.toggle();
    }

    StyledToolTip {
        text: Translation.tr("Draw on screen")
    }
}
