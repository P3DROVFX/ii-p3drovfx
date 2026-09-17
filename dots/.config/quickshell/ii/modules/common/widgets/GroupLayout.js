.pragma library

/**
 * Position of settings rows inside their container, worked out once per
 * container instead of once per row.
 *
 * A row is rounded like its neighbours: large corners at the ends of a run of
 * rounded siblings, small ones inside it. Each row used to find its own place
 * with four bindings that walked `parent.children`. Those bindings depend on
 * the children list and on every sibling's `visible`, so every row added
 * while a page is built re-ran all of them on every sibling - 100 switches in
 * one column took over a second to create.
 *
 * Here a container is walked in one pass and the result is written into each
 * row's GroupPosition. The run rules are the old ones: invisible children are
 * skipped, a visible child without `topLeftRadius` ends a run, and every other
 * visible child is part of it. Each row asks for a pass when its own
 * visibility or its container's children change; a separator toggling on its
 * own is not watched.
 */

// No registry keyed by container: a WeakMap/WeakSet keyed by QObject wrappers
// crashes the engine (SIGSEGV in sameValueZero), and a strong list would keep
// every container ever seen. Only the containers touched in the current
// event-loop turn are remembered, and the lists are emptied every turn.
var _fresh = [];
var _pending = [];

function _clearFresh() {
    _fresh = [];
}

function _flush() {
    const pending = _pending;
    _pending = [];
    for (let i = 0; i < pending.length; ++i)
        layout(pending[i], true);
}

function _assign(run, settle) {
    for (let i = 0; i < run.length; ++i) {
        const position = run[i].groupPosition;
        if (!position || !position.enabled)
            continue;
        const previous = i > 0 ? run[i - 1] : null;
        const next = i < run.length - 1 ? run[i + 1] : null;
        if (position.previous !== previous)
            position.previous = previous;
        if (position.next !== next)
            position.next = next;
        if (position.count !== run.length)
            position.count = run.length;
        if (position.index !== i)
            position.index = i;
        // Radius animations stay off until a deferred pass: rows created one
        // by one (a Repeater) are only all present by then, and the passes
        // before it would otherwise animate each row through wrong corners.
        if (settle && !position.settled)
            position.settled = true;
    }
}

function layout(container, settle) {
    let children;
    try {
        children = container ? container.children : null;
    } catch (error) {
        // Destroyed between scheduling and the flush.
        return;
    }
    if (!children)
        return;

    let run = [];
    for (let i = 0; i < children.length; ++i) {
        const child = children[i];
        if (!child.visible)
            continue;
        if (typeof child.topLeftRadius === "undefined") {
            _assign(run, settle);
            run = [];
            continue;
        }
        run.push(child);
    }
    _assign(run, settle);
}

/// Lays the container out now, at most once per event-loop turn, and settles
/// it on the next. A row that has just been created must be right before its
/// first frame.
function refresh(container) {
    if (!container || _fresh.indexOf(container) !== -1)
        return;
    _fresh.push(container);
    Qt.callLater(_clearFresh);
    layout(container, false);
    schedule(container);
}

/// Lays the container out on the next turn, however many rows ask.
function schedule(container) {
    if (!container)
        return;
    if (_pending.indexOf(container) === -1)
        _pending.push(container);
    Qt.callLater(_flush);
}
