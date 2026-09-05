import qs.modules.common
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    toggled: Modes.active
    buttonIcon: Modes.active ? Modes.activeMode.icon : "tune"
    onClicked: {
        if (Modes.active || Modes.lastUsedMode)
            Modes.toggleLast();
        else if (root.altAction)
            root.altAction();
    }

    StyledToolTip {
        text: Modes.active
            ? Translation.tr("%1 mode is on | Click to turn off, right-click to choose").arg(Modes.activeMode.name)
            : Translation.tr("Modes | Click to start the last mode, right-click to choose")
    }
}
