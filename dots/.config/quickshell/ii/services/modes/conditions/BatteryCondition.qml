import QtQuick
import qs.services
import ".."

/**
 * Battery level and/or charger state. `below` / `above` are percentages with
 * 3 % hysteresis so a threshold does not flap while the level hovers on it;
 * `pluggedIn` is null (ignore), true or false. Desktops without a battery
 * evaluate false.
 */
ModeCondition {
    id: root
    readonly property int hysteresis: 3
    readonly property var below: root.params?.below ?? null
    readonly property var above: root.params?.above ?? null
    readonly property var pluggedIn: root.params?.pluggedIn ?? null
    readonly property real percent: Battery.percentage * 100

    property bool levelOk: false

    function reevaluateLevel() {
        const pct = root.percent;
        if (root.below !== null) {
            root.levelOk = root.levelOk ? pct < root.below + root.hysteresis : pct < root.below;
            return;
        }
        if (root.above !== null) {
            root.levelOk = root.levelOk ? pct > root.above - root.hysteresis : pct > root.above;
            return;
        }
        root.levelOk = true;
    }

    onPercentChanged: root.reevaluateLevel()
    onBelowChanged: root.reevaluateLevel()
    onAboveChanged: root.reevaluateLevel()
    Component.onCompleted: root.reevaluateLevel()

    readonly property bool plugOk: root.pluggedIn === null || Battery.isPluggedIn === root.pluggedIn
    satisfied: Battery.available && root.levelOk && root.plugOk
    reason: `${Math.round(root.percent)} %${Battery.isPluggedIn ? ", plugged in" : ""}`
}
