import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.ii.editMode

/**
 * Edit Mode's chrome: a surface on the ONE screen the mode is on.
 *
 * The mode is focused-monitor only (decision D4): the desktop that shrinks is
 * the one that had focus at entry, and the chrome frames that desktop. Every
 * other screen keeps its desktop at full size and gets no surface at all.
 *
 * The surface exists only while the mode is on the way in, on, or on the way
 * out. A full-screen Overlay surface left mapped with a stale mask eats
 * clicks on a desktop nobody is editing, and that is the state nobody looks
 * at - so the loader is the first of the chrome's two stand-down gates; the
 * content's opacity on the same scalar is the second.
 *
 * A special workspace is summoned OVER the desktop rather than instead of it,
 * which is exactly what a mode about the desktop must yield to. Rather than
 * standing down - a chrome popping out of existence while everything around
 * it dims - the surface drops to the desktop's own layer and takes the
 * compositor's treatment together with it (`underneath`).
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: surfaceLoader
            required property var modelData

            readonly property string screenName: modelData ? modelData.name : ""
            readonly property bool isEditScreen: GlobalStates.editModeMonitor !== ""
                && GlobalStates.editModeMonitor === surfaceLoader.screenName
            // Found by name rather than by index: Quickshell.screens and
            // HyprlandData.monitors are two lists that agree today and are not
            // promised to stay in the same order.
            readonly property var thisMonitorData: HyprlandData.monitors.find(monitor =>
                monitor.name === surfaceLoader.screenName)
            readonly property bool specialShown:
                (surfaceLoader.thisMonitorData?.specialWorkspace?.name ?? "") !== ""

            active: surfaceLoader.isEditScreen
                && (GlobalStates.editMode || GlobalStates.editProgress > 0)

            component: EditModeChromeSurface {
                screen: surfaceLoader.modelData
                underneath: surfaceLoader.specialShown
            }
        }
    }
}
