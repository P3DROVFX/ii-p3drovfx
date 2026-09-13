pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root

    name: Translation.tr("Notes")
    hasStatusText: false
    toggled: GlobalStates.notesAppOpen
    icon: "note_stack"

    mainAction: () => {
        GlobalStates.sidebarRightOpen = false;
        GlobalStates.notesAppOpen = !GlobalStates.notesAppOpen;
    }

    tooltipText: Translation.tr("Notes")
}
