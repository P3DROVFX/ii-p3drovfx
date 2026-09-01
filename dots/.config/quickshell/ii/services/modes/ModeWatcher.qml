import QtQuick
import Quickshell
import "ModeSchema.js" as ModeSchema

/**
 * Evaluates the triggers of one mode definition and reports debounced edges.
 *
 * Every trigger becomes a ModeCondition loaded by type; unknown types (phases
 * that have not landed yet) count as unsatisfied. A 1 s debounce keeps
 * workspace switches and Wi-Fi roams from reaching the engine as flaps.
 */
QtObject {
    id: root

    required property var modeDef
    readonly property string modeId: root.modeDef?.id ?? ""
    readonly property var triggerDefs: ModeSchema.toArray(root.modeDef?.triggers)
    readonly property bool matchAll: root.modeDef?.match === "all"
    readonly property bool hasSchedule: root.triggerDefs.some(t => t.type === "schedule")
    // Modes carry `auto`, routines `enabled`; either way: may this start on its own?
    readonly property bool armed: root.modeDef?.auto ?? root.modeDef?.enabled ?? true

    // Committed (debounced) state.
    property bool satisfied: false
    property bool scheduleSatisfied: false
    property bool evaluatedOnce: false
    // Type of the first satisfied trigger — shown as the start source.
    property string source: "manual"
    property string reason: ""
    // Epoch ms when a satisfied schedule window ends, 0 if none.
    property real scheduleEndsAt: 0

    // Raw state, before the debounce.
    property bool pending: false
    property bool pendingSchedule: false

    signal evaluated(bool satisfied, bool initial)
    signal scheduleEnded()

    property Timer debounce: Timer {
        interval: 1000
        repeat: false
        onTriggered: root.commit()
    }

    property Instantiator conditions: Instantiator {
        model: root.triggerDefs
        delegate: Loader {
            id: loader
            required property var modelData
            readonly property string conditionType: loader.modelData?.type ?? ""
            readonly property bool hasSource: ModeSchema.CONDITION_SOURCES[conditionType] !== undefined
            // An event trigger only makes sense where a false→true edge fires
            // something: a "when" routine. Elsewhere it stays unsatisfied.
            readonly property bool misplacedEvent: ModeSchema.isEventTrigger(conditionType)
                && root.modeDef?.kind !== "once"
            readonly property bool supported: loader.hasSource && !loader.misplacedEvent
            readonly property bool conditionSatisfied: loader.item?.satisfied ?? false
            readonly property bool negated: loader.modelData?.not === true
            // Seconds the verdict must hold before it counts (0: at once).
            readonly property int forSec: ModeSchema.durationSec(loader.modelData?.forSec)
            // The verdict before the dwell: satisfied, read through `not`.
            readonly property bool rawOk: loader.conditionSatisfied !== loader.negated
            // The verdict the watcher combines: rawOk once it has held long enough.
            readonly property bool ok: loader.forSec > 0 ? loader.held : loader.rawOk
            readonly property bool counting: loader.forSec > 0 && loader.rawOk && !loader.held
            property bool held: false
            property real heldSince: 0
            readonly property Timer hold: Timer {
                interval: Math.max(1, loader.forSec) * 1000
                repeat: false
                onTriggered: loader.held = true
            }

            function syncHold() {
                if (loader.forSec <= 0) {
                    loader.hold.stop();
                    loader.held = false;
                    return;
                }
                if (!loader.rawOk) {
                    loader.hold.stop();
                    loader.held = false;
                    loader.heldSince = 0;
                    return;
                }
                if (loader.held || loader.hold.running)
                    return;
                loader.heldSince = Date.now();
                loader.hold.restart();
            }

            onRawOkChanged: loader.syncHold()
            onForSecChanged: loader.syncHold()
            onOkChanged: root.recompute()
            Component.onCompleted: {
                if (!supported) {
                    console.log(`[Modes] ${root.modeId}: trigger "${conditionType}" `
                        + (loader.misplacedEvent ? "is an event and needs a \"when\" routine"
                            : "has no watcher yet") + ", treated as unsatisfied");
                    root.recompute();
                    return;
                }
                loader.setSource(ModeSchema.CONDITION_SOURCES[conditionType], {
                    params: loader.modelData,
                    ownerId: root.modeId,
                    armed: Qt.binding(() => root.armed)
                });
            }
            onLoaded: {
                loader.syncHold();
                root.recompute();
            }
        }
    }

    function conditionAt(i) {
        return root.conditions.objectAt(i);
    }

    function recompute() {
        const count = root.conditions.count;
        let anyTrue = false;
        let allTrue = count > 0;
        let scheduleAny = false;
        let scheduleAll = true;
        let scheduleCount = 0;
        let firstSource = "manual";
        let firstReason = "";
        let endsAt = 0;
        for (let i = 0; i < count; ++i) {
            const loader = root.conditionAt(i);
            const type = loader?.conditionType ?? "";
            const negated = loader?.negated ?? false;
            const ok = loader?.ok ?? false;
            if (ok) {
                anyTrue = true;
                if (firstSource === "manual") {
                    firstSource = type;
                    firstReason = loader.item?.reason ?? "";
                }
            } else {
                allTrue = false;
            }
            // A negated schedule ("outside 09:00–18:00") has no end to honour.
            if (type === "schedule" && !negated) {
                scheduleCount += 1;
                if (ok) {
                    scheduleAny = true;
                    const e = loader.item?.endsAt ?? 0;
                    if (e > 0 && (endsAt === 0 || e < endsAt))
                        endsAt = e;
                } else {
                    scheduleAll = false;
                }
            }
        }
        root.pending = root.matchAll ? allTrue : anyTrue;
        root.pendingSchedule = scheduleCount > 0 && (root.matchAll ? scheduleAll : scheduleAny);
        root.scheduleEndsAt = endsAt;
        if (root.pending) {
            root.source = firstSource;
            root.reason = firstReason;
        }
        const dirty = root.pending !== root.satisfied || root.pendingSchedule !== root.scheduleSatisfied;
        if (!root.evaluatedOnce || dirty) {
            root.debounce.restart();
        } else {
            root.debounce.stop();
        }
    }

    function commit() {
        const initial = !root.evaluatedOnce;
        const scheduleWasOn = root.scheduleSatisfied;
        root.scheduleSatisfied = root.pendingSchedule;
        const changed = root.satisfied !== root.pending;
        root.satisfied = root.pending;
        root.evaluatedOnce = true;
        if (initial || changed)
            root.evaluated(root.satisfied, initial);
        if (!initial && scheduleWasOn && !root.scheduleSatisfied)
            root.scheduleEnded();
    }

    Component.onCompleted: root.recompute()
}
