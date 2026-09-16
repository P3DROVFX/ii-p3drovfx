// Temporary memory-audit harness shell (II_MEMORY_ITEM selects one panel).
//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QSG_NO_DEPTH_BUFFER=1
//@ pragma Env MALLOC_CONF=dirty_decay_ms:1000,muzzy_decay_ms:1000,background_thread:true

import "modules/common"
import "modules/common/idleDim"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    ReloadPopup {}
    IdleDim {}

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Wallpapers.load();
        ConflictKiller.load();
        Hyprsunset.load();
        Cliphist.refresh();
        Updates.load();
    }

    LazyLoader {
        readonly property bool wanted: Config.ready
        source: wanted ? "panelFamilies/IllogicalImpulseFamilyMemoryEachTest.qml" : ""
        active: wanted && source !== ""
    }
}
