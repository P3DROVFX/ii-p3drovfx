import QtQuick

/**
 * Base for one trigger of a mode or routine. A watcher instantiates one of
 * these per trigger entry and combines their `satisfied` flags.
 *
 * `params` is the normalized trigger object from the definition. `reason` is
 * a short human string for the UI ("23:00–07:00", "steam_app_123") so a
 * surprising start can be explained.
 *
 * State conditions bind `satisfied`. Event conditions (a notification
 * arrives, a shortcut is pressed) call pulse() instead: `satisfied` goes
 * true for a moment — longer than the watcher's debounce — and drops back,
 * which is the false→true edge a "when" routine fires on.
 */
QtObject {
    id: root
    property var params: ({})
    readonly property string type: root.params?.type ?? ""
    /// Id of the mode or routine this condition belongs to.
    property string ownerId: ""
    // False while the owning mode/routine cannot start automatically; a
    // condition with a standing cost (GPU polling) may idle then.
    property bool armed: true
    property bool satisfied: false
    property string reason: ""

    readonly property Timer pulseTimer: Timer {
        interval: 1500
        repeat: false
        onTriggered: root.satisfied = false
    }

    function pulse(why) {
        root.reason = why ?? "";
        root.satisfied = true;
        root.pulseTimer.restart();
    }
}
