pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Tracks window move and resize gestures so the tiling overlay knows when to
 * appear, and resolves the cursor into a tiling zone on the monitor it is over.
 *
 * The gesture itself is detected by scripts/hyprland/drag_monitor.py, which
 * watches Hyprland far more tightly than a QML timer could. It knows about a
 * drag only through the companion keybinds below, which report Hyprland's own
 * drag binds - so a client-side titlebar drag, which fires no bind, is not a
 * gesture this reacts to at all. See the script's header for why.
 *
 * On drop the window is floated and given the zone's exact geometry, and the
 * geometry it had before is kept so dragging it back out can undo that. The
 * same thing happens without the mouse through the quick-tile shortcuts below.
 *
 * Resizing a tiled window past its zone drags the divider it shares with its
 * neighbours instead of overlapping them, and they follow.
 */

import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services
import "../modules/common/functions/tiling.js" as Tiling
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property var options: Config.options?.tiling ?? null
    readonly property bool enabled: Config.ready && (root.options?.enable ?? false)

    // Gesture state, mirrored from the detector.
    property bool dragging: false
    property string dragKind: ""       // "move" | "resize"
    property string dragAddress: ""
    property var dragWindow: null      // geometry captured when the drag started
    property var dragWindowBefore: null // geometry from just before it started, for restoring later
    property var dragWindowAfter: null  // geometry as it ended, for co-resize
    property int cursorX: 0
    property int cursorY: 0

    signal dragStarted(string kind)
    signal dragMoved(int x, int y)
    signal dragEnded(string kind, int zoneIndex)

    // Hyprland's own gaps, so a tiled window sits exactly where a real one would.
    property int hyprGapsOuter: 5
    property int hyprGapsInner: 4
    // Hyprland reports and accepts window geometry without the border, so zone
    // rects have to lose it. Taken from the shell rather than from Hyprland,
    // because the shell is what pushes the value and Hyprland briefly reports
    // the config file's own number after a reload.
    readonly property int hyprBorderSize: Appearance.borderless ? 0 : (Appearance.borderWidth ?? 0)
    readonly property var gaps: {
        const configured = root.options?.gaps ?? null;
        if (configured?.followHyprland ?? true)
            return {
                outer: root.hyprGapsOuter,
                inner: root.hyprGapsInner
            };
        return {
            outer: configured?.outer ?? 8,
            inner: configured?.inner ?? 4
        };
    }

    // The shared monitor list comes from `hyprctl monitors all`, so it also
    // carries outputs that are switched off - a closed laptop lid, a display
    // unplugged earlier in the session. Those report an origin of 0,0 and a
    // stale size, which is close enough to a real monitor to win the hit test
    // below and send a whole drop to a screen that is not there. Everywhere
    // else in the shell looks monitors up by name or id and never notices.
    readonly property var liveMonitors: (HyprlandData.monitors ?? []).filter(candidate => candidate && !candidate.disabled)

    // The monitor under the cursor, straight from hyprctl so scale, transform
    // and reserved space are all available.
    readonly property var monitor: {
        const monitors = root.liveMonitors;
        for (const candidate of monitors) {
            const rect = Tiling.monitorLogicalRect(candidate);
            if (Tiling.rectContains(rect, root.cursorX, root.cursorY))
                return candidate;
        }
        return monitors.length > 0 ? monitors[0] : null;
    }
    readonly property string monitorName: root.monitor?.name ?? ""
    readonly property var usable: root.monitor ? Tiling.usableArea(root.monitor) : null

    readonly property var zones: root.zonesFor(root.monitorName)
    readonly property var effectiveGaps: root.gapsFor(root.monitorName)
    readonly property var zoneRects: root.usable ? Tiling.zoneRects(root.zones, root.usable, root.effectiveGaps) : []

    readonly property int hoveredZone: {
        if (!root.dragging || !root.usable) return -1;
        return Tiling.zoneIndexAt(root.zones, root.usable, root.cursorX, root.cursorY);
    }

    // Whether a grabbed window is tiled at all. The keyboard is the other way
    // in and stands on its own, so turning this off leaves quick-tile, the
    // layouts and neighbour resizing exactly where they were - a drag simply
    // goes back to being Hyprland's business.
    readonly property bool dragTileEnabled: root.enabled && (root.options?.dragQuickTile ?? true)

    // The overlay is a move-drag affordance: a resize drag keeps its own
    // neighbours, so painting zone targets over it would only mislead. The
    // keyboard has no drag to hang it on, so it is flashed afterwards instead.
    readonly property bool overlayVisible: root.enabled && ((root.dragTileEnabled && root.dragging && root.dragKind === "move" && (root.options?.showOnDragStart ?? true)) || root.flashVisible)

    // The marker on zones holding more than one window, shown while nothing is
    // being dragged. It steps aside for the overlay rather than being drawn
    // twice, since the overlay carries the same counts.
    readonly property bool stackIndicatorEnabled: root.enabled && (root.options?.overlay?.stackIndicator ?? true) && !root.overlayVisible

    // Which zone the overlay picks out, and on which screen: the one under the
    // cursor during a drag, the one a window just landed in after a keypress.
    readonly property string highlightMonitor: root.flashVisible ? root.flashMonitor : root.monitorName
    readonly property int highlightZone: root.flashVisible ? root.flashZone : root.hoveredZone

    // Hyprland announces monitors and workspaces, but not the space a layer
    // surface reserves. A bar that changed side or height therefore leaves the
    // cached monitor list describing the old usable area, and zones would be
    // laid out against a bar that is no longer there. Re-reading the list at the
    // start of a gesture is one cheap hyprctl call and lands long before a drop;
    // a quick-tile is over sooner than that, so the press right after a bar
    // change still uses the previous area and the one after it is correct.
    function refreshMonitors() {
        HyprlandData.updateMonitors();
    }

    function monitorByName(name) {
        for (const candidate of root.liveMonitors) {
            if (candidate.name === name) return candidate;
        }
        return null;
    }

    // Dividers the user has dragged, per monitor name. Runtime only: a resize
    // says where this session's windows go, and rewriting the saved layout from
    // under a mouse drag would be a much bigger promise than the gesture makes.
    property var zoneOverrides: ({})

    // Editing the layout in settings is the more deliberate statement of the
    // two, so it drops whatever the dividers were dragged to.
    readonly property string layoutKey: `${JSON.stringify(Array.from(root.options?.monitors ?? []))}|${root.options?.defaultPreset ?? ""}`
    onLayoutKeyChanged: root.zoneOverrides = ({})

    function zonesFor(name) {
        return root.zoneOverrides[name] ?? Tiling.zonesForMonitor(root.options?.monitors, name, root.options?.defaultPreset ?? "kde");
    }

    function gapsFor(name) {
        return Tiling.gapsForMonitor(root.options?.monitors, name, root.gaps);
    }

    // How many windows the assistant has in each zone of a monitor, counting
    // only the workspace that monitor is showing. Two windows in one zone is a
    // layout that can be asked for - dropping onto an occupied zone is
    // allowed - but one window ends up behind the other with nothing on screen
    // to say so, which is the whole reason this is counted.
    function zoneOccupancy(name, exceptAddress) {
        // Read so the overlay's counts re-evaluate when the map changes; the
        // map itself announces nothing.
        const revision = root.zoneMemoryRevision;
        const counts = [];
        const zones = root.zonesFor(name);
        for (let i = 0; i < zones.length; i++) counts.push(0);

        const workspace = root.monitorByName(name)?.activeWorkspace?.id ?? null;
        const known = HyprlandData.windowByAddress ?? {};
        for (const address in root.zoneMemory) {
            if (address === exceptAddress) continue;
            const zone = root.zoneMemory[address];
            if (zone.monitor !== name || zone.index < 0 || zone.index >= counts.length) continue;
            // A window the layout changed under is not in the zone it
            // remembers, so it is not standing in anyone's way there.
            if (root.zoneDrifted(address)) continue;
            const window = known[address];
            if (!window) continue;
            if (workspace !== null && (window.workspace?.id ?? null) !== workspace) continue;
            counts[zone.index]++;
        }
        return counts;
    }

    // Zones of one monitor as drawable rects, relative to that monitor's own
    // origin. Every coordinate conversion the overlay needs lives here so the
    // overlay itself stays presentational.
    function overlayZonesFor(name) {
        const monitor = root.monitorByName(name);
        if (!monitor) return [];
        const origin = Tiling.monitorLogicalRect(monitor);
        const zones = root.zonesFor(name);
        const rects = Tiling.zoneRects(zones, Tiling.usableArea(monitor), root.gapsFor(name));
        // The window being dragged is on its way out of wherever it was, so it
        // is not counted as being in the way of where it is going.
        const occupancy = root.zoneOccupancy(name, root.dragging ? root.dragAddress : "");
        const out = [];
        for (let i = 0; i < rects.length; i++) {
            out.push({
                x: rects[i].x - origin.x,
                y: rects[i].y - origin.y,
                width: rects[i].width,
                height: rects[i].height,
                label: Tiling.labelFor(zones[i]),
                occupants: occupancy[i] ?? 0
            });
        }
        return out;
    }

    // The zones of a monitor that hold more than one window, for the marker that
    // stands there while nothing is being dragged. A stack of windows in a zone
    // looks exactly like a single window in that zone, so without this the only
    // hint that something is buried is that it is missing.
    function crowdedZonesFor(name) {
        if (!root.stackIndicatorEnabled) return [];
        return root.overlayZonesFor(name).filter(zone => zone.occupants > 1);
    }

    // Whether a fullscreen window is on the workspace the monitor is showing.
    // Nothing of ours belongs on top of one, marker included. Read from the
    // window list rather than the workspace list because only the former is
    // refreshed when Hyprland reports a fullscreen change.
    function monitorHasFullscreen(name) {
        const workspace = root.monitorByName(name)?.activeWorkspace?.id ?? null;
        if (workspace === null) return false;
        for (const window of HyprlandData.windowList ?? []) {
            if ((window.workspace?.id ?? null) === workspace && (window.fullscreen ?? 0) > 0) return true;
        }
        return false;
    }

    function zoneLabel(index) {
        if (index < 0 || index >= root.zones.length) return "";
        return Tiling.labelFor(root.zones[index]);
    }

    // ------------------------------------------------------------ applying

    // "quickTile" | "preview" | "hybrid"
    readonly property string mode: root.options?.mode ?? "quickTile"

    // Where each window we tiled came from, keyed by address. Only windows this
    // service moved are in here, so nothing else can be "restored" out of a
    // position the user put it in themselves.
    property var tileRecords: ({})

    // Which zone each window was last put in. Hyprland emits no event when a
    // floating window is moved or resized, so the shared window list keeps
    // reporting the previous geometry indefinitely after a quick-tile - it is
    // only refreshed by events like a float toggle. Remembering the zone is
    // therefore the only way a second arrow press can resolve from where the
    // window actually is.
    property var zoneMemory: ({})

    // Writing to a plain object notifies nothing, so anything bound to what is
    // in the map - the occupancy counts the overlay draws - watches this
    // instead. Bumped by every write and every forget.
    property int zoneMemoryRevision: 0

    function forgetZone(address) {
        delete root.zoneMemory[address];
        root.zoneMemoryRevision++;
    }

    // Zone rects as windows rather than as boxes: Hyprland positions and sizes a
    // window inside its border, so the border comes off every side.
    function windowRectForZone(name, index) {
        const monitor = root.monitorByName(name);
        const zones = root.zonesFor(name);
        if (!monitor || index < 0 || index >= zones.length) return null;
        const box = Tiling.zoneRect(zones[index], Tiling.usableArea(monitor), root.gapsFor(name));
        const rect = Tiling.insetRect(box, root.hyprBorderSize);
        return (rect.width > 0 && rect.height > 0) ? rect : null;
    }

    // Whether a geometry sample is already sitting in one of that monitor's
    // zones. Growing it by the border undoes the inset above, putting it back in
    // the same space the zone boxes are measured in.
    function sampleZoneIndex(name, sample) {
        const monitor = root.monitorByName(name);
        if (!monitor || !sample) return -1;
        const rect = Tiling.makeRect(sample.x, sample.y, sample.width, sample.height);
        const grown = Tiling.insetRect(rect, -root.hyprBorderSize);
        const usable = Tiling.usableArea(monitor);
        return Tiling.zoneIndexForRect(root.zonesFor(name), usable, root.gapsFor(name), grown, 4);
    }

    // Whether the zone a window remembers has moved out from under it. That
    // happens when the layout is changed and the windows on it are left alone,
    // which is on purpose - but the index they remember then points at a
    // different piece of screen, and everything that steps or resizes from it
    // would be working off a zone the window was never in.
    //
    // Compared by geometry rather than by a "the layout changed" flag, because
    // dragging a divider changes the zones on purpose and the windows follow,
    // and a change on one monitor says nothing about the other.
    function zoneDrifted(address) {
        const zone = root.zoneMemory[address];
        // Nothing recorded, or recorded before the rect was kept: neither is a
        // window that has drifted, so neither is one to move.
        if (!zone?.rect) return false;
        const rect = root.windowRectForZone(zone.monitor, zone.index);
        return !rect || !Tiling.rectsEqual(rect, zone.rect, 2);
    }

    // The zone of the current layout closest to where a window actually is.
    function nearestZoneToRect(name, rect) {
        const monitor = root.monitorByName(name);
        if (!monitor || !rect) return -1;
        const rects = Tiling.zoneRects(root.zonesFor(name), Tiling.usableArea(monitor), root.gapsFor(name));
        const centre = Tiling.rectCenter(rect);
        let best = -1;
        let bestDistance = Infinity;
        for (let i = 0; i < rects.length; i++) {
            const candidate = Tiling.rectCenter(rects[i]);
            const dx = candidate.x - centre.x;
            const dy = candidate.y - centre.y;
            const distance = dx * dx + dy * dy;
            if (distance >= bestDistance) continue;
            bestDistance = distance;
            best = i;
        }
        return best;
    }

    // Hyprland's float dispatcher is a toggle and takes no target state, so the
    // current state decides whether to flip it. Callers pass what they know -
    // the pre-drag sample beats the shared window list, which can be a refresh
    // behind - and an unknown state is left alone rather than guessed at.
    function setFloating(address, floating, current) {
        const known = current ?? HyprlandData.windowByAddress?.[address]?.floating;
        if (known === undefined || known === floating) return;
        root.dispatchWindow(address, "float");
    }

    function dispatchWindow(address, dispatcher, args) {
        const call = [`window = "address:${address}"`].concat(args ?? []).join(", ");
        Hyprland.dispatch(`hl.dsp.window.${dispatcher}({${call}})`);
    }

    // Position alone does not put a window on another screen. Hyprland draws a
    // floating window wherever its coordinates say, but it keeps the workspace
    // it came from, so a window dropped across the gap looks right until that
    // workspace changes and takes it away. Handing it to the target monitor
    // first is what makes a cross-monitor drop stick.
    function moveToMonitor(address, name, currentId) {
        if (!name) return;
        const id = (currentId !== undefined && currentId !== null && currentId >= 0) ? currentId : HyprlandData.windowByAddress?.[address]?.monitor;
        const current = root.monitorById(id)?.name ?? "";
        if (!current || current === name) return;
        root.dispatchWindow(address, "move", [`monitor = "${name}"`]);
    }

    function applyZone(address, name, index, before, floating) {
        const rect = root.windowRectForZone(name, index);
        if (!rect) return;

        // A window already floating in a zone is one of ours from before a
        // reload: its geometry says nothing about where it came from, so it goes
        // unrecorded rather than recorded uselessly. One the layout put there is
        // a different matter - restoring it means handing it back to the layout.
        const ours = (before?.floating ?? false) && root.sampleZoneIndex(name, before) >= 0;
        if (!root.tileRecords[address] && before && !ours) {
            root.tileRecords[address] = {
                x: before.x,
                y: before.y,
                width: before.width,
                height: before.height,
                floating: before.floating ?? false,
                monitor: root.monitorById(before.monitor)?.name ?? ""
            };
        }

        // The rect goes in with the index. Changing the layout deliberately
        // leaves tiled windows where they are, so an index on its own stops
        // describing anything once the zone behind it has moved - and the
        // window list cannot settle that, since Hyprland never reports a
        // floating window moving. What it was actually given can.
        root.zoneMemory[address] = {
            monitor: name,
            index: index,
            rect: rect
        };
        root.zoneMemoryRevision++;

        root.setFloating(address, true, floating);
        root.moveToMonitor(address, name, before?.monitor);
        // Resizing keeps the centre, so the move has to come second.
        root.dispatchWindow(address, "resize", [`x = ${rect.width}`, `y = ${rect.height}`]);
        root.dispatchWindow(address, "move", [`x = ${rect.x}`, `y = ${rect.y}`]);
    }

    function restoreWindow(address, floating) {
        const record = root.tileRecords[address];
        root.forgetZone(address);
        if (!record) return;
        delete root.tileRecords[address];

        // Back to the screen it came from first, or a window tiled across the
        // gap would be handed back to the layout tree of the wrong monitor.
        root.moveToMonitor(address, record.monitor);
        if (!record.floating) {
            // Back into the layout tree, which decides the geometry itself.
            root.setFloating(address, false, floating);
            return;
        }
        root.setFloating(address, true, floating);
        root.dispatchWindow(address, "resize", [`x = ${record.width}`, `y = ${record.height}`]);
        root.dispatchWindow(address, "move", [`x = ${record.x}`, `y = ${record.y}`]);
    }

    // Closed windows would otherwise pile up in the record map for the lifetime
    // of the shell.
    function pruneRecords() {
        const known = HyprlandData.windowByAddress ?? {};
        // An empty list means the window data has not arrived, not that every
        // window closed at once.
        if (Object.keys(known).length === 0) return;
        for (const address in root.tileRecords) {
            if (!known[address]) delete root.tileRecords[address];
        }
        for (const address in root.zoneMemory) {
            if (!known[address]) root.forgetZone(address);
        }
    }

    function handleDrop(kind, zoneIndex) {
        if (kind !== "move" || !root.dragTileEnabled || root.mode === "preview") return;
        const address = root.dragAddress;
        if (!address) return;
        const before = root.dragWindowBefore;
        // Hyprland floats a tiled window for the duration of a drag and puts it
        // back on release, so the sample from *before* the drag is the one that
        // describes the window now that the drag is over.
        const floating = before?.floating;

        // Nothing under the cursor: the window was dragged out of its zone, so
        // put it back the way it was found.
        if (zoneIndex < 0) {
            root.forgetZone(address);
            if (!(root.options?.restoreOnUntile ?? true)) return;
            root.restoreWindow(address, floating);
            root.releaseWorkspace(address);
            return;
        }
        // Hybrid leaves windows that live in the layout tree to Hyprland and
        // only quick-tiles ones that were already floating.
        if (root.mode === "hybrid" && !(before?.floating ?? false) && !root.tileRecords[address]) return;

        root.applyZone(address, root.monitorName, zoneIndex, before, floating);
        root.adoptWorkspace(address, root.monitorName, zoneIndex);
    }

    onDragStarted: {
        // A flash still up would be pointing at the wrong zone for the rest of
        // its life: the drag decides what is highlighted from here.
        root.flashVisible = false;
        root.refreshMonitors();
        root.pruneRecords();
    }
    onDragEnded: (kind, zoneIndex) => {
        if (kind === "resize") root.handleResize(root.dragAddress, root.dragWindowAfter);
        else root.handleDrop(kind, zoneIndex);
    }

    // ----------------------------------------------------------- co-resize

    readonly property bool coResizeEnabled: root.enabled && root.mode !== "preview" && (root.options?.coResize?.enable ?? true)
    readonly property bool adoptWorkspaceEnabled: root.coResizeEnabled && (root.options?.coResize?.adoptWorkspace ?? false)
    readonly property bool releaseWorkspaceEnabled: root.coResizeEnabled && (root.options?.coResize?.releaseWorkspace ?? false)

    // The reverse of adoptWorkspace: taking one window out of the layout takes
    // the whole workspace out with it, every window the assistant put there
    // going back to where it was before. A workspace tiled in one gesture is
    // worth being able to undo in one gesture.
    //
    // Only ever reached from the two untile paths. A window closing is not an
    // untile - the arrangement it leaves behind is still the one that was
    // asked for, so pruning a dead window pulls nothing else apart.
    function releaseWorkspace(anchorAddress) {
        if (!root.releaseWorkspaceEnabled) return;
        const known = HyprlandData.windowByAddress ?? {};
        // A workspace belongs to one monitor, so matching on it is already
        // matching on the screen. Without one there is nothing to scope the
        // release to, and releasing everything would reach other screens.
        const workspace = known[anchorAddress]?.workspace?.id ?? null;
        if (workspace === null) return;

        for (const address of Object.keys(root.zoneMemory)) {
            if (address === anchorAddress) continue;
            const window = known[address];
            if (!window || (window.workspace?.id ?? null) !== workspace) continue;
            root.restoreWindow(address, window.floating);
        }
    }

    // Tiling one window takes its whole workspace with it: every other window
    // on it is floated and given a zone of its own, so all of them share edges
    // and one divider drag moves the lot. Without this only the windows the
    // assistant placed take part, which on a fresh workspace is the single one
    // that was just dropped - which is what makes the resizing look broken.
    //
    // Each window goes to the free zone it is already nearest, so the workspace
    // snaps into shape rather than being shuffled, and a zone can be left empty
    // rather than a window dragged the width of the screen to fill it. Windows
    // past the last free zone are left exactly as they were: piling two into
    // one zone would hide one behind the other, which is worse than not tiling.
    function adoptWorkspace(anchorAddress, name, anchorZone) {
        if (!root.adoptWorkspaceEnabled || !name) return;
        const monitor = root.monitorByName(name);
        const zones = root.zonesFor(name);
        if (!monitor || zones.length === 0) return;

        const windows = HyprlandData.windowList ?? [];
        const anchor = windows.find(candidate => candidate?.address === anchorAddress) ?? null;
        // No anchor means no workspace to adopt: the window list has not
        // arrived, and guessing at a workspace would tile the wrong screenful.
        if (!anchor) return;
        const workspace = anchor.workspace?.id;
        if (workspace === undefined) return;

        const taken = {};
        if (anchorZone >= 0) taken[anchorZone] = true;
        const candidates = [];
        for (const window of windows) {
            if (!window || window.address === anchorAddress) continue;
            if ((window.workspace?.id ?? null) !== workspace) continue;
            // Hidden and fullscreen windows are not part of the arrangement the
            // user is looking at, so they are not part of the one being made.
            if (window.hidden || window.fullscreen) continue;
            const remembered = root.zoneMemory[window.address];
            // Already ours: it keeps the zone it has rather than being dealt a
            // new one, so tiling a second window does not reshuffle the first.
            // Unless the layout has changed since - then the zone it remembers
            // is not where it is, and it is dealt one like anything else.
            if (remembered && remembered.monitor === name && !root.zoneDrifted(window.address)) {
                taken[remembered.index] = true;
                continue;
            }
            candidates.push(window);
        }
        if (candidates.length === 0) return;

        const rects = Tiling.zoneRects(zones, Tiling.usableArea(monitor), root.gapsFor(name));
        const free = [];
        for (let index = 0; index < rects.length; index++) {
            if (!taken[index]) free.push(index);
        }

        // Closest pair first, over and over, rather than filling the zones in
        // order: a window belongs in the zone it is already nearest, even when
        // that leaves an earlier zone empty. Packing the layout tight by
        // dragging a window across the screen is the opposite of the point.
        while (free.length > 0 && candidates.length > 0) {
            let bestZone = 0;
            let bestWindow = 0;
            let bestDistance = Infinity;
            for (let z = 0; z < free.length; z++) {
                const centre = Tiling.rectCenter(rects[free[z]]);
                for (let i = 0; i < candidates.length; i++) {
                    const sample = root.windowSample(candidates[i]);
                    const dx = sample.x + sample.width / 2 - centre.x;
                    const dy = sample.y + sample.height / 2 - centre.y;
                    const distance = dx * dx + dy * dy;
                    if (distance >= bestDistance) continue;
                    bestDistance = distance;
                    bestZone = z;
                    bestWindow = i;
                }
            }
            const index = free.splice(bestZone, 1)[0];
            const window = candidates.splice(bestWindow, 1)[0];
            root.applyZone(window.address, name, index, root.windowSample(window), window.floating);
        }
    }

    // Every window the assistant put on this monitor moves with the divider,
    // not just the one under the mouse - that is what a shared edge means. The
    // resized one is in here too, so a drag that overshot snaps back onto it.
    //
    // `only` is the set of windows that were standing in their zones before the
    // dividers moved. It has to be worked out beforehand, because moving them
    // is exactly what makes every stored rect disagree with its zone.
    function reapplyZones(name, only) {
        const known = HyprlandData.windowByAddress ?? {};
        const alive = Object.keys(known).length > 0;
        for (const address in root.zoneMemory) {
            const zone = root.zoneMemory[address];
            if (zone.monitor !== name || (alive && !known[address])) continue;
            if (only && !only[address]) continue;
            root.applyZone(address, name, zone.index, null, true);
        }
    }

    // Widening a tiled window past its zone drags the divider it shares with its
    // neighbours, rather than leaving it overlapping them. Only windows the
    // assistant tiled take part: one the user sized by hand is in no zone, so
    // there is no edge to share and nothing else moves.
    function handleResize(address, sample) {
        if (!root.coResizeEnabled || !address || !sample) return;
        const zone = root.zoneMemory[address];
        const monitor = zone ? root.monitorByName(zone.monitor) : null;
        if (!monitor) return;
        // The layout changed under this window: it is not in the zone it
        // remembers, so there is no divider between it and anything else. The
        // resize is left as a resize and nothing follows it.
        if (root.zoneDrifted(address)) return;

        let zones = root.zonesFor(zone.monitor);
        if (zone.index < 0 || zone.index >= zones.length) return;
        const usable = Tiling.usableArea(monitor);
        const gaps = root.gapsFor(zone.monitor);
        const before = Tiling.zoneRect(zones[zone.index], usable, gaps);
        // Undoing the border inset puts the window back in the space the zone
        // boxes are measured in.
        const after = Tiling.insetRect(Tiling.makeRect(sample.x, sample.y, sample.width, sample.height), -root.hyprBorderSize);

        // A corner drag moves two edges at once, so every side is considered
        // rather than just the one that moved furthest.
        const tolerance = root.options?.coResize?.edgeTolerancePx ?? 8;
        const sides = [
            {
                side: "left",
                delta: after.x - before.x,
                pixel: after.x
            },
            {
                side: "right",
                delta: (after.x + after.width) - (before.x + before.width),
                pixel: after.x + after.width
            },
            {
                side: "top",
                delta: after.y - before.y,
                pixel: after.y
            },
            {
                side: "bottom",
                delta: (after.y + after.height) - (before.y + before.height),
                pixel: after.y + after.height
            }
        ];

        let moved = false;
        for (const candidate of sides) {
            if (Math.abs(candidate.delta) <= tolerance) continue;
            const fraction = Tiling.edgeFraction(usable, gaps, candidate.side, candidate.pixel);
            const updated = Tiling.moveEdge(zones, zone.index, candidate.side, fraction);
            if (!updated) continue;
            zones = updated;
            moved = true;
        }
        if (!moved) return;

        // Who follows the divider, decided while the old zones are still the
        // ones in force. Windows a layout change left behind are not in this
        // layout at all and are not dragged into it by someone else's resize.
        const following = {};
        for (const other in root.zoneMemory) {
            if (root.zoneMemory[other].monitor === zone.monitor && !root.zoneDrifted(other)) following[other] = true;
        }

        // A new object rather than a mutated one: the zone bindings only notice
        // the property being reassigned.
        const overrides = Object.assign({}, root.zoneOverrides);
        overrides[zone.monitor] = zones;
        root.zoneOverrides = overrides;
        root.reapplyZones(zone.monitor, following);
    }

    // -------------------------------------------------------- quick-tile flash

    // A keyboard quick-tile has no drag for the overlay to appear during, so
    // the zones are shown for a moment after it instead, with the one the
    // window landed in picked out. Without it a press says nothing about what
    // is already in the zone the window went to - the other window is simply
    // covered up. Deliberately not tied to showOnDragStart: turning the drag
    // overlay off is what leaves the keyboard as the only place it appears.
    property string flashMonitor: ""
    property int flashZone: -1
    property bool flashVisible: false

    Timer {
        id: flashTimer
        interval: root.options?.overlay?.quickTileDuration ?? 500
        onTriggered: root.flashVisible = false
    }

    function flashZones(name, index) {
        if (!name) return;
        root.flashMonitor = name;
        root.flashZone = index;
        root.flashVisible = true;
        flashTimer.restart();
    }

    // ------------------------------------------------------- layout cycling

    // Which layout the strip is describing, and for how long. The layout has
    // already changed by the time this is up: the zones themselves are the real
    // feedback, and this only names what they became, because on an empty
    // workspace a preset changing is otherwise completely silent.
    property string layoutHintMonitor: ""
    property bool layoutHintVisible: false

    Timer {
        id: layoutHintTimer
        interval: root.options?.overlay?.layoutHintDuration ?? 1400
        onTriggered: root.layoutHintVisible = false
    }

    function entryFor(name) {
        for (const entry of Array.from(root.options?.monitors ?? [])) {
            if (entry?.name === name) return entry;
        }
        return null;
    }

    function presetFor(name) {
        return root.entryFor(name)?.preset ?? (root.options?.defaultPreset ?? "kde");
    }

    // A monitor with a hand-drawn layout keeps it in the ring, so cycling past
    // it and back does not quietly throw the drawing away.
    function layoutRing(name) {
        const ring = Array.from(Tiling.PRESET_IDS);
        if (root.presetFor(name) === "custom") ring.push("custom");
        return ring;
    }

    // The monitor list is stored rather than derived, so one entry cannot be
    // changed in place: the adapter only notices the array being reassigned.
    function setPreset(name, preset) {
        if (!name) return;
        const list = Array.from(root.options?.monitors ?? []).map(entry => Object.assign({}, entry));
        const index = list.findIndex(entry => entry?.name === name);
        if (index < 0) list.push({
            "name": name,
            "preset": preset
        });
        else list[index] = Object.assign({}, list[index], {
            "preset": preset
        });
        Config.options.tiling.monitors = list;
    }

    // The cursor is only sampled during a drag, so between gestures it is the
    // focused monitor rather than the pointer that says which screen is meant.
    function hintMonitorName() {
        return Hyprland.focusedMonitor?.name ?? root.monitorName;
    }

    function cycleLayout(step) {
        if (!root.enabled) return;
        const name = root.hintMonitorName();
        if (!name) return;
        const ring = root.layoutRing(name);
        const current = ring.indexOf(root.presetFor(name));
        // A preset the ring does not know is not somewhere to step from, so the
        // first press lands on its start rather than nowhere.
        const next = current < 0 ? 0 : (current + step + ring.length) % ring.length;
        root.setPreset(name, ring[next]);
        root.layoutHintMonitor = name;
        root.layoutHintVisible = true;
        layoutHintTimer.restart();
    }

    // ------------------------------------------------------------ keyboard

    readonly property bool keyboardEnabled: root.enabled && (root.options?.keyboardQuickTile ?? true)

    // Hyprland numbers windows by how recently they were focused, so the one at
    // zero is the focused one. Taking it out of the shared list beats asking
    // hyprctl for the active window: no extra process, and the geometry that
    // comes with it is the same snapshot the zone helpers work from.
    function focusedWindow() {
        const windows = HyprlandData.windowList ?? [];
        for (const window of windows) {
            if (window.focusHistoryID === 0) return window;
        }
        return null;
    }

    function monitorById(id) {
        for (const candidate of root.liveMonitors) {
            if (candidate.id === id) return candidate;
        }
        return null;
    }

    // A raw hyprctl client in the shape the zone helpers expect. The monitor id
    // rides along so a window restored later is handed back to the screen it
    // came from rather than to whichever one it happens to be on.
    function windowSample(window) {
        if (!window) return null;
        return {
            x: window.at?.[0] ?? 0,
            y: window.at?.[1] ?? 0,
            width: window.size?.[0] ?? 0,
            height: window.size?.[1] ?? 0,
            floating: window.floating ?? false,
            monitor: window.monitor
        };
    }

    // Remembered zone first, geometry only as a fallback: see zoneMemory. A
    // window in the layout tree counts as being in no zone at all, even where
    // its geometry happens to line up with one - the layout put it there, so a
    // press towards that side should tile it rather than read as "already here,
    // take me out". Float state, unlike geometry, does come with an event.
    function currentZone(address, name, sample) {
        if (!(sample?.floating ?? false)) {
            root.forgetZone(address);
            return -1;
        }
        const remembered = root.zoneMemory[address];
        if (remembered && remembered.monitor === name) return remembered.index;
        return root.sampleZoneIndex(name, sample);
    }

    // Puts a window the layout changed under into the zone of the current
    // layout nearest where it is sitting, and says whether it did. A window
    // whose zone came through the change in the same place has not drifted and
    // is not touched, so a change on one monitor costs the other nothing.
    function adoptCurrentLayout(address, name, sample) {
        if (!(sample?.floating ?? false)) return false;
        const zone = root.zoneMemory[address];
        if (!zone || zone.monitor !== name || !root.zoneDrifted(address)) return false;
        const index = root.nearestZoneToRect(name, zone.rect);
        if (index < 0) return false;

        root.applyZone(address, name, index, null, sample.floating);
        root.flashZones(name, index);
        return true;
    }

    // Tiles the focused window one zone over. Unlike a drag, this is explicit
    // enough to act on a window living in the layout tree even in hybrid mode,
    // which has no preview of its own to fall back on.
    function quickTile(direction) {
        if (!root.keyboardEnabled || root.mode === "preview") return;
        const window = root.focusedWindow();
        if (!window) return;
        root.refreshMonitors();
        const name = root.monitorById(window.monitor)?.name ?? "";
        const zones = root.zonesFor(name);
        if (!name || zones.length === 0) return;

        const address = window.address;
        const sample = root.windowSample(window);
        // The layout changed under this window and it was left where it was, so
        // the press hands it to the layout in force rather than stepping
        // through one it was never in - which is what untiled it before, the
        // window reading as against an edge it was nowhere near. It has
        // visibly moved, which is as much as one press should do; the next one
        // steps from there.
        if (root.adoptCurrentLayout(address, name, sample)) return;

        const from = root.currentZone(address, name, sample);
        const target = (from < 0) ? Tiling.edgeZoneIndex(zones, direction) : Tiling.resolveDirection(zones, from, direction);
        if (target < 0) return;

        // Nowhere further that way, on any of the four sides: a window already
        // against the edge it is being pushed towards has nothing else to want
        // in that direction, so the press means "out of the layout" instead.
        if (target === from) {
            if (!(root.options?.restoreOnUntile ?? true)) return;
            root.restoreWindow(address, sample.floating);
            root.releaseWorkspace(address);
            return;
        }
        root.applyZone(address, name, target, sample, sample.floating);
        root.adoptWorkspace(address, name, target);
        root.flashZones(name, target);
    }

    function send(message) {
        if (!detector.running) return;
        detector.write(`${JSON.stringify(message)}\n`);
    }

    function sendConfig() {
        const detection = root.options?.detection ?? null;
        root.send({
            cmd: "config",
            idleHz: detection?.idleHz ?? 5,
            activeHz: detection?.activeHz ?? 90,
            tolerance: detection?.trackingTolerancePx ?? 2,
            keybinds: detection?.useKeybinds ?? true
        });
    }

    function handleEvent(event) {
        switch (event.event) {
        case "ready":
            root.sendConfig();
            break;
        case "gaps":
            root.hyprGapsOuter = event.outer;
            root.hyprGapsInner = event.inner;
            break;
        case "dragStart":
            root.cursorX = event.x;
            root.cursorY = event.y;
            root.dragAddress = event.address ?? "";
            root.dragWindow = event.window ?? null;
            root.dragWindowBefore = event.before ?? event.window ?? null;
            root.dragKind = event.kind;
            root.dragging = true;
            root.dragStarted(event.kind);
            break;
        case "dragMove":
            root.cursorX = event.x;
            root.cursorY = event.y;
            root.dragMoved(event.x, event.y);
            break;
        case "dragEnd":
            root.cursorX = event.x;
            root.cursorY = event.y;
            const zone = root.hoveredZone;
            root.dragWindowAfter = event.window ?? null;
            root.dragging = false;
            // Releasing the modifier before the button makes Hyprland drop the
            // gesture and put the window back, which is a cancel and not a drop:
            // the overlay goes away and nothing is tiled.
            if (!event.cancelled) root.dragEnded(event.kind, zone);
            root.dragKind = "";
            break;
        }
    }

    // Reconfiguring is cheap, so the detector is told about setting changes
    // rather than being restarted.
    readonly property string detectionKey: {
        const detection = root.options?.detection ?? null;
        return [detection?.idleHz, detection?.activeHz, detection?.trackingTolerancePx, detection?.useKeybinds].join("|");
    }
    onDetectionKeyChanged: {
        root.sendConfig();
        if (root.enabled) root.checkKeybinds();
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.checkKeybinds();
            return;
        }
        root.dragging = false;
        root.dragKind = "";
        root.flashVisible = false;
    }

    // ------------------------------------------------------- keybind check

    // The drag binds are not part of the shell: they live in the Hyprland
    // config, and the fork's installer only overlays ~/.config/hypr when it is
    // asked to - the update button inside Settings deliberately never does. So
    // a perfectly up-to-date shell can have nothing bound to these shortcuts,
    // and since the binds are now the only thing that detects a drag at all,
    // the whole feature is silently inert rather than merely degraded.
    property bool keybindsChecked: false
    property bool keybindsFound: true
    readonly property bool keybindsMissing: root.enabled && (root.options?.detection?.useKeybinds ?? true) && root.keybindsChecked && !root.keybindsFound

    function checkKeybinds() {
        root.keybindsChecked = false;
        keybindProbe.running = false;
        keybindProbe.running = true;
    }

    Process {
        id: keybindProbe

        // `hyprctl binds` cannot answer this. Under the Lua config every bind
        // reports a dispatcher of "__lua" with an opaque numeric argument, so
        // no shortcut name ever appears in it. The config text can be read
        // instead, which also covers custom/ overrides and the older syntax.
        // -s so a missing directory is simply "not bound" rather than noise.
        command: ["grep", "-rqsF", "quickshell:tilingDragMove", `${FileUtils.trimFileProtocol(Directories.config)}/hypr`]

        onExited: (code, status) => {
            root.keybindsFound = (code === 0);
            root.keybindsChecked = true;
            if (root.keybindsMissing)
                console.log("[TilingAssistant] nothing in ~/.config/hypr binds quickshell:tilingDragMove - Super+drag and Super+Alt+arrow will do nothing until the fork's Hyprland config is installed (setup script, --hypr)");
        }
    }

    Process {
        id: detector
        running: root.enabled
        stdinEnabled: true
        command: ProcUtils.pdeath(ProcUtils.nativeHelper(Quickshell.shellPath("scripts/hyprland/drag_monitor")))

        stdout: SplitParser {
            onRead: line => {
                if (!line || line.length === 0) return;
                try {
                    root.handleEvent(JSON.parse(line));
                } catch (error) {
                    console.warn("[TilingAssistant] bad event:", error.message);
                }
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line && line.length > 0) console.log("[TilingAssistant]", line);
            }
        }

        // Exiting clears `running` imperatively, which drops the binding above,
        // so a detector that dies would otherwise stay dead until a reload. It
        // also takes with it the only thing that can report the end of a drag,
        // so the overlay has to be taken down here or it stays up for good.
        onExited: (code, status) => {
            root.dragging = false;
            root.dragKind = "";
            if (!root.enabled) return;
            console.log("[TilingAssistant] detector exited with", code, "- restarting");
            detectorRestart.restart();
        }
    }

    Timer {
        id: detectorRestart
        interval: 2000
        onTriggered: detector.running = Qt.binding(() => root.enabled)
    }

    // Hyprland's drag binds fire these alongside their own dispatcher, which is
    // the only exact signal for "the user grabbed a window". Dropped when
    // tiling by grab is off, so the detector is never woken to follow a move it
    // has nothing to do with - the bind still runs Hyprland's own drag.
    Loader {
        active: root.dragTileEnabled && (root.options?.detection?.useKeybinds ?? true)

        sourceComponent: Item {
            GlobalShortcut {
                name: "tilingDragMove"
                description: "Reports a window move drag to the tiling assistant"
                onPressed: root.send({
                    cmd: "hint",
                    kind: "move",
                    state: "down"
                })
                onReleased: root.send({
                    cmd: "hint",
                    kind: "move",
                    state: "up"
                })
            }
        }
    }

    // Resizing is kept apart from the switch above: pulling a neighbour along
    // adjusts a layout that is already there rather than putting a window into
    // it, so it belongs to co-resize and survives drag-to-tile being off.
    Loader {
        active: root.enabled && (root.options?.detection?.useKeybinds ?? true)

        sourceComponent: Item {
            GlobalShortcut {
                name: "tilingDragResize"
                description: "Reports a window resize drag to the tiling assistant"
                onPressed: root.send({
                    cmd: "hint",
                    kind: "resize",
                    state: "down"
                })
                onReleased: root.send({
                    cmd: "hint",
                    kind: "resize",
                    state: "up"
                })
            }
        }
    }

    // Quick-tile without the mouse. Bound to SUPER + ALT + arrow, which leaves
    // SUPER + SHIFT + arrow to Hyprland's own move-in-direction.
    Loader {
        active: root.keyboardEnabled

        // Instantiator rather than a Repeater inside an Item: a shortcut is not
        // an item and has nothing to be laid out in.
        sourceComponent: Instantiator {
            model: ["Left", "Right", "Up", "Down"]

            delegate: GlobalShortcut {
                required property string modelData
                name: `tilingTile${modelData}`
                description: `Quick-tiles the focused window ${modelData.toLowerCase()}`
                onPressed: root.quickTile(modelData.toLowerCase())
            }
        }
    }

    // Switching layouts without opening settings. Not gated on quick-tile: this
    // changes what the zones are rather than what is put in them, so preview
    // mode has just as much use for it.
    Loader {
        active: root.enabled

        sourceComponent: Item {
            GlobalShortcut {
                name: "tilingLayoutCycle"
                description: "Switches the focused monitor to the next tiling layout"
                onPressed: root.cycleLayout(1)
            }

            GlobalShortcut {
                name: "tilingLayoutCyclePrev"
                description: "Switches the focused monitor to the previous tiling layout"
                onPressed: root.cycleLayout(-1)
            }
        }
    }
}
