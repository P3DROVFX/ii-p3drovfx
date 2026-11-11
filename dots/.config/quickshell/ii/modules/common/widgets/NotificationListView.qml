pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false
    property int entranceTrigger: -1
    property bool entranceAnimationsEnabled: false
    // Only the floating popup is user-resizable; the sidebar notification
    // center and phone mirror always render at their normal size.
    property real zoom: popup ? (Config.options.notifications.zoomPercent / 100) : 1.0
    dismissToLeft: popup && (Config.options.notifications.position ?? "top_right").endsWith("left")
    useSlideInAnimation: popup
    // The sidebar has its own entrance choreography (NotificationGroup's
    // entrance properties); every ListView transition stays off there.
    //
    // The popup owns its motion in the delegate instead (NotificationGroup): a
    // vertical slide in from the nearest screen edge, and every later shift
    // (a card added above, one removed, a reorder, a height change) played as a
    // visual offset over the position the ListView already settled. ListView y
    // transitions capture their target when they start, so two cards arriving
    // together — each still resolving its height — finished on stale slots and
    // painted over each other. Only the exit stays a ListView transition: the
    // `remove` x slide to the side the popup is anchored to.
    popin: false
    animateAppearance: popup
    animateAdd: false
    animatePopulate: false
    animateDisplacement: false
    animateMovement: false
    // Groups reorder by latest activity (Notifications.appNameList), and reused delegates
    // leak per-item UI state (expanded, lazyLimit, implicitHeight animation) across
    // different notification groups, causing stuck height/overlap glitches.
    reuseItems: false

    spacing: 3

    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        zoom: root.zoom
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        readonly property var currentGroup: popup ?
            Notifications.popupGroupsByAppName[modelData] :
            Notifications.groupsByAppName[modelData]
        // A popup row stays alive through its exit slide after the group left the
        // model; keep drawing the last group instead of collapsing to an empty card.
        property var lastGroup: null
        onCurrentGroupChanged: if (currentGroup) lastGroup = currentGroup
        Component.onCompleted: lastGroup = currentGroup ?? null
        notificationGroup: currentGroup ?? (popup ? lastGroup : null)
        entranceTrigger: root.entranceTrigger
        entranceAnimationsEnabled: root.entranceAnimationsEnabled
        globalIndex: index
    }
}
