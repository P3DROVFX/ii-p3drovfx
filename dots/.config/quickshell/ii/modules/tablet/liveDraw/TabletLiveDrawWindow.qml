import QtQuick

import qs
import qs.modules.common
import qs.modules.common.draw

/**
 * The tablet's live draw surface: the shared one, tucked under the tablet's own shell
 * surfaces and kept clear of its dock.
 */
LiveDrawWindow {
    namespace: "quickshell:tabletLiveDraw"
    coveredByShell: GlobalStates.appDrawerOpen
        || GlobalStates.recentsOpen
        || GlobalStates.sessionOpen
        || GlobalStates.screenLocked
    parallaxEnabled: Config.options?.tablet?.liveDraw?.workspaceParallax ?? true
}
