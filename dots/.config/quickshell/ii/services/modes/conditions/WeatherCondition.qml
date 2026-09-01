import QtQuick
import qs.services
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * The weather at the bar's location is of a `kind` (clear, cloudy, fog,
 * rain, snow, storm — `any` for no preference) and/or the temperature is
 * below `tempBelow` / above `tempAbove` in the bar's unit. Needs the
 * weather widget's data; until it has loaded this never holds.
 */
ModeCondition {
    id: root
    readonly property string kind: root.params?.kind ?? "any"
    readonly property var tempBelow: root.params?.tempBelow ?? null
    readonly property var tempAbove: root.params?.tempAbove ?? null

    readonly property bool loaded: (Weather.data?.wDesc ?? "").length > 0
    readonly property string current: ModeSchema.weatherKind(Weather.data?.wCode)
    readonly property var temp: {
        const m = /-?\d+(\.\d+)?/.exec(String(Weather.data?.temp ?? ""));
        return m ? Number(m[0]) : null;
    }

    readonly property bool kindOk: root.kind === "any" || root.current === root.kind
    readonly property bool tempOk: root.temp !== null
        && (root.tempBelow === null || root.temp < Number(root.tempBelow))
        && (root.tempAbove === null || root.temp > Number(root.tempAbove))
    readonly property bool needsTemp: root.tempBelow !== null || root.tempAbove !== null

    satisfied: root.loaded && root.kindOk && (!root.needsTemp || root.tempOk)
    reason: root.loaded ? `${Weather.data.wDesc}, ${Weather.data.temp}` : "no weather data"
}
