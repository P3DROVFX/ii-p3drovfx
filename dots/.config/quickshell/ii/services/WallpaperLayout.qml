import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Per-screen wallpapers and how each screen frames its picture.
 *
 * Two things the shell used to have one of per desktop: the wallpaper, and the
 * way it is cropped (the cover fit, centred). Edit Mode's Wallpaper catalogue
 * gives each screen its own of both, and this is where they are stored, read
 * back and changed.
 *
 * Colours. The palette comes from ONE picture - matugen and the colour scripts
 * read `background.wallpaperPath` (or the light-mode one) and nothing else - so
 * that stays the "shared" wallpaper, and a screen either shows it or has its
 * own. The shared one is by construction the colour source, and the screens
 * still showing it are the ones it colours from: picking another screen's
 * wallpaper as the colour source is a swap (makeColourSource), never a second
 * palette. That keeps every script, preset and settings page that reads
 * `wallpaperPath` exactly as it was.
 *
 * Framing. A screen keeps one framing per picture it has shown (a few of them,
 * most recent first), so going back to a wallpaper finds it as it was left and
 * a new one starts square. While Edit Mode's Wallpaper catalogue is open over a
 * screen, that screen's framing is previewed live from the values below
 * instead of the stored ones: the overlay on the desktop drags them, and only
 * the release is written to the config (one history entry per gesture).
 *
 * Off entirely while another process paints the desktop (mpvpaper, Wallpaper
 * Engine): there is no plane in this shell to frame, and a screen's own image
 * would fight that process for the same layer.
 */
Singleton {
    id: root

    // How many pictures a screen remembers a framing for.
    readonly property int framingMemory: 12

    readonly property bool available: Config.ready && !Wallpapers.videoWallpaperActive
    readonly property var screenNames: Array.from(Quickshell.screens).map(screen => screen.name)
    readonly property bool multiScreen: root.screenNames.length > 1

    readonly property var entries: Config.ready
        ? Array.from(Config.options.background.monitorWallpapers ?? []).filter(entry => entry && entry.monitor)
        : []

    // Which physical monitor a screen is, beyond its connector: the same
    // monitor on another port (a dock, a different cable) keeps its wallpaper
    // and framings, and another monitor on the same port does not inherit
    // them. "" when the screen reports no model or serial, or when two
    // connected screens report the same one (twin monitors without serials):
    // those fall back to the connector name.
    readonly property var screenKeys: {
        const screens = Array.from(Quickshell.screens);
        const raw = screens.map(screen => {
            const model = String(screen.model ?? "").trim();
            const serial = String(screen.serialNumber ?? "").trim();
            return model === "" && serial === "" ? "" : model + "/" + serial;
        });
        const keys = {};
        screens.forEach((screen, i) => {
            const key = raw[i];
            keys[screen.name] = key !== "" && raw.filter(other => other === key).length === 1 ? key : "";
        });
        return keys;
    }

    function keyFor(name) {
        return root.screenKeys[name] ?? "";
    }

    // The entry a screen reads and writes: its monitor's own first, then one
    // stored under its connector - an entry from before monitors were told
    // apart, or one for a screen that cannot be told apart now - unless that
    // entry belongs to another monitor.
    function matchEntry(list, name) {
        const key = root.keyFor(name);
        if (key !== "") {
            const own = list.find(entry => String(entry.key ?? "") === key);
            if (own)
                return own;
        }
        return list.find(entry => entry.monitor === name
            && (String(entry.key ?? "") === "" || key === "")) ?? null;
    }

    function cleanPath(path) {
        return FileUtils.trimFileProtocol(String(path ?? ""));
    }

    function isImagePath(path) {
        const clean = root.cleanPath(path).toLowerCase();
        return clean !== "" && Images.isValidImageByName(clean) && !Wallpapers.isVideoFile(clean);
    }

    // The picture the colours come from, as the screens that show the shared
    // wallpaper display it: the light-mode one in light mode when there is a
    // separate one, else the desktop's, else the shipped default.
    readonly property string sharedSourcePath: {
        const background = Config.options?.background;
        if (!background || background.useWallpaperEngine)
            return "";
        const light = root.cleanPath(background.lightModeWallpaperPath);
        if (!Appearance.m3colors.darkmode && background.useSeparateLightModeWallpaper && light !== "")
            return light;
        const path = root.cleanPath(background.wallpaperPath);
        return path !== "" ? path : root.cleanPath(Directories.defaultWallpaperImagePath);
    }
    readonly property bool sharedIsVideo: Wallpapers.isVideoFile(root.sharedSourcePath)

    function entryFor(name) {
        return root.matchEntry(root.entries, name);
    }

    // The screen's own wallpaper, "" while it shows the shared one.
    function ownPathFor(name) {
        if (!root.available || !name)
            return "";
        const path = root.cleanPath(root.entryFor(name)?.path);
        return root.isImagePath(path) ? path : "";
    }

    function hasOwn(name) {
        return root.ownPathFor(name) !== "";
    }

    // The file the screen shows: what its framings are keyed by, and what the
    // panel names.
    function sourcePathFor(name) {
        const own = root.ownPathFor(name);
        return own !== "" ? own : root.sharedSourcePath;
    }

    // The screens on this machine that show the shared wallpaper - the ones the
    // colours visibly come from. Empty when every screen has its own, which a
    // monitor being unplugged can leave behind.
    readonly property var colourScreens: root.screenNames.filter(name => root.ownPathFor(name) === "")
    readonly property string colourScreen: root.colourScreens.length > 0 ? root.colourScreens[0] : ""
    // Whether more than one picture is on screen, which is when "which one do
    // the colours come from" is a question at all.
    readonly property bool distinctWallpapers: {
        const shown = new Set(root.screenNames.map(name => root.sourcePathFor(name)));
        return shown.size > 1;
    }

    // A screen may only go its own way while another screen keeps showing the
    // colour wallpaper: otherwise the palette would come from a picture that is
    // on no screen at all.
    function canDetach(name) {
        if (!root.available || !root.multiScreen || root.hasOwn(name))
            return false;
        return root.screenNames.some(other => other !== name && root.ownPathFor(other) === "");
    }

    // ── Framing ──────────────────────────────────────────────────────────────

    function savedFramingFor(name, path) {
        const clean = root.cleanPath(path);
        if (!root.available || !name || clean === "")
            return WallpaperFraming.defaults();
        const hit = (root.entryFor(name)?.framings ?? []).find(f => f && root.cleanPath(f.path) === clean);
        return hit ? WallpaperFraming.normalize(hit) : WallpaperFraming.defaults();
    }

    function isLive(name, path) {
        return root.liveScreen !== "" && root.liveScreen === name && root.livePath === root.cleanPath(path);
    }

    // What the screen draws right now: the live preview while the overlay is
    // on it, the stored framing otherwise.
    function framingFor(name, path) {
        if (root.isLive(name, path))
            return root.liveFraming;
        return root.savedFramingFor(name, path);
    }

    // The angle to draw at: continuous while a quarter turn animates.
    function angleFor(name, path) {
        if (root.isLive(name, path))
            return root.liveAngle;
        return root.savedFramingFor(name, path).rotation;
    }

    // The wallpaper plane's geometry, published by each screen's wallpaper
    // surface: the plane a framed picture is laid out in (the screen at the
    // workspace zoom) and the picture's own pixel size. The overlay and the
    // panel's buttons need it to turn a gesture into a position.
    property var geometry: ({})

    function publishGeometry(name, planeWidth, planeHeight, imageWidth, imageHeight) {
        if (!name)
            return;
        const current = root.geometry[name];
        if (current && current.planeWidth === planeWidth && current.planeHeight === planeHeight
                && current.imageWidth === imageWidth && current.imageHeight === imageHeight)
            return;
        const next = Object.assign({}, root.geometry);
        next[name] = {
            "planeWidth": planeWidth,
            "planeHeight": planeHeight,
            "imageWidth": imageWidth,
            "imageHeight": imageHeight
        };
        root.geometry = next;
    }

    function geometryFor(name) {
        const g = root.geometry[name];
        return g && g.planeWidth > 0 && g.planeHeight > 0 && g.imageWidth > 0 && g.imageHeight > 0 ? g : null;
    }

    // ── The live preview ─────────────────────────────────────────────────────
    // On while Edit Mode's Wallpaper catalogue is open on the Desktop tab, for
    // the screen the mode is on.
    readonly property string framingScreen: (root.available && GlobalStates.editMode && GlobalStates.editDrawerOpen
            && GlobalStates.editDrawerSection === "wallpaper" && !GlobalStates.editLockPreview)
        ? GlobalStates.editModeMonitor : ""
    readonly property string framingPath: root.framingScreen !== "" ? root.sourcePathFor(root.framingScreen) : ""

    property string liveScreen: ""
    property string livePath: ""
    property real liveZoom: 1
    property real liveX: 0
    property real liveY: 0
    property real liveAngle: 0
    property bool liveFlipH: false
    property bool liveFlipV: false
    // A gesture owns the live values: a config change arriving meanwhile (the
    // release's own write) must not animate them out from under the pointer.
    property bool interacting: false

    readonly property var liveFraming: ({
        "zoom": root.liveZoom,
        "x": root.liveX,
        "y": root.liveY,
        "rotation": WallpaperFraming.snapRotation(root.liveAngle),
        "flipH": root.liveFlipH,
        "flipV": root.liveFlipV
    })

    onFramingScreenChanged: root.restartLive()
    // Ctrl+Z inside the wheel's commit window: the steps are written first,
    // so the undo takes them back rather than being written over by them.
    Connections {
        target: GlobalStates
        function onEditHistoryWillReplay() {
            root.flushGesture();
        }
    }

    onFramingPathChanged: {
        root.restartLive();
        root.requestPointOfInterest(root.framingPath);
    }

    // ── Point of interest ────────────────────────────────────────────────────
    // Where the eye goes in the picture being framed - a face, else its most
    // salient detail (scripts/images/point_of_interest.py) - so a drag can
    // snap that point, not just the picture's centre, onto the screen's
    // centre and thirds. Asked once per picture per session, only while the
    // overlay is up; { x, y, kind } in the picture's 0..1 coordinates, null
    // while unknown or when there is no answer.
    property var pointsOfInterest: ({})

    function pointOfInterestFor(path) {
        return root.pointsOfInterest[root.cleanPath(path)] ?? null;
    }

    property string _poiPending: ""
    function requestPointOfInterest(path) {
        const clean = root.cleanPath(path);
        if (clean === "" || !root.isImagePath(clean) || clean in root.pointsOfInterest)
            return;
        if (poiProcess.running) {
            root._poiPending = clean;
            return;
        }
        poiProcess.path = clean;
        poiProcess.running = true;
    }

    Process {
        id: poiProcess
        property string path: ""
        command: [FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/images/point-of-interest-venv.sh")), poiProcess.path]
        stdout: StdioCollector {
            onStreamFinished: {
                let found = null;
                try {
                    const parsed = JSON.parse(this.text.trim() || "{}");
                    if (isFinite(parsed.x) && isFinite(parsed.y))
                        found = {
                            "x": Math.max(0, Math.min(1, Number(parsed.x))),
                            "y": Math.max(0, Math.min(1, Number(parsed.y))),
                            "kind": parsed.kind === "face" ? "face" : "detail"
                        };
                } catch (e) {
                    found = null;
                }
                const next = Object.assign({}, root.pointsOfInterest);
                next[poiProcess.path] = found;
                root.pointsOfInterest = next;
            }
        }
        onExited: {
            const pending = root._poiPending;
            root._poiPending = "";
            if (pending !== "")
                Qt.callLater(() => root.requestPointOfInterest(pending));
        }
    }

    function setLive(framing, angle) {
        const f = WallpaperFraming.normalize(framing);
        root.liveZoom = f.zoom;
        root.liveX = f.x;
        root.liveY = f.y;
        root.liveAngle = angle === undefined ? f.rotation : angle;
        root.liveFlipH = f.flipH;
        root.liveFlipV = f.flipV;
    }

    function restartLive() {
        // A run of wheel steps still waiting to be written belongs to the
        // screen and picture it was made on: written before either changes.
        root.flushGesture();
        liveAnimation.stop();
        root.interacting = false;
        if (root.framingScreen === "" || root.framingPath === "") {
            root.liveScreen = "";
            root.livePath = "";
            return;
        }
        root.setLive(root.savedFramingFor(root.framingScreen, root.framingPath));
        // Path first: with the screen set and the path stale, isLive() would
        // briefly answer for the wrong picture.
        root.livePath = root.framingPath;
        root.liveScreen = root.framingScreen;
    }

    // Undo, redo and the panel's buttons write the config; the preview follows
    // with an animation rather than a jump.
    Connections {
        target: Config.ready ? Config.options.background : null
        function onMonitorWallpapersChanged() {
            if (root.liveScreen === "" || root.interacting)
                return;
            root.animateLiveTo(root.savedFramingFor(root.liveScreen, root.livePath), false);
        }
    }

    function animateLiveTo(framing, fast) {
        const target = WallpaperFraming.normalize(framing);
        liveAnimation.stop();
        const flipped = target.flipH !== root.liveFlipH || target.flipV !== root.liveFlipV;
        // A mirror cannot be animated without the picture passing through zero
        // width, which shows the plane behind it - so it lands at once, and so
        // does the offset it mirrors, or the picture would slide after jumping.
        if (flipped) {
            root.liveFlipH = target.flipH;
            root.liveFlipV = target.flipV;
            root.liveX = target.x;
            root.liveY = target.y;
        }
        const angle = WallpaperFraming.animationTarget(root.liveAngle, target.rotation);
        if (Appearance.reducedMotion) {
            root.setLive(target);
            return;
        }
        liveAnimation.fast = fast === true;
        zoomAnim.to = target.zoom;
        xAnim.to = target.x;
        yAnim.to = target.y;
        angleAnim.to = angle;
        liveAnimation.start();
    }

    ParallelAnimation {
        id: liveAnimation
        property bool fast: false
        readonly property var tier: liveAnimation.fast ? Appearance.animation.elementMoveFast : Appearance.animation.elementMove

        NumberAnimation {
            id: zoomAnim
            target: root
            property: "liveZoom"
            duration: liveAnimation.tier.duration
            easing.type: liveAnimation.tier.type
            easing.bezierCurve: liveAnimation.tier.bezierCurve
        }
        NumberAnimation {
            id: xAnim
            target: root
            property: "liveX"
            duration: liveAnimation.tier.duration
            easing.type: liveAnimation.tier.type
            easing.bezierCurve: liveAnimation.tier.bezierCurve
        }
        NumberAnimation {
            id: yAnim
            target: root
            property: "liveY"
            duration: liveAnimation.tier.duration
            easing.type: liveAnimation.tier.type
            easing.bezierCurve: liveAnimation.tier.bezierCurve
        }
        NumberAnimation {
            id: angleAnim
            target: root
            property: "liveAngle"
            duration: liveAnimation.tier.duration
            easing.type: liveAnimation.tier.type
            easing.bezierCurve: liveAnimation.tier.bezierCurve
        }

        // Keep the angle in one turn: 270 -> 0 animates to 360, which is the
        // same picture and is folded back here.
        onFinished: root.liveAngle = WallpaperFraming.snapRotation(root.liveAngle)
    }

    // ── Gestures (the overlay) ───────────────────────────────────────────────
    // Stops a landing animation where it was heading. The angle goes to the
    // turn's destination, not the nearest quarter: a turn caught less than
    // half-way would otherwise snap back, and the gesture's release would
    // write the old orientation over the one the button just stored.
    function settleLive() {
        if (!liveAnimation.running)
            return;
        const angle = angleAnim.to;
        liveAnimation.stop();
        root.liveAngle = WallpaperFraming.snapRotation(angle);
    }

    function beginGesture() {
        if (root.liveScreen === "")
            return;
        root.settleLive();
        commitTimer.stop();
        root.liveAngle = WallpaperFraming.snapRotation(root.liveAngle);
        root.interacting = true;
    }

    function updateGesture(framing) {
        if (root.liveScreen === "")
            return;
        const f = WallpaperFraming.normalize(framing);
        root.liveZoom = f.zoom;
        root.liveX = f.x;
        root.liveY = f.y;
    }

    function endGesture() {
        if (root.liveScreen === "")
            return;
        root.interacting = false;
        root.commitFraming(root.liveScreen, root.livePath, root.liveFraming);
    }

    // A wheel or a pinch step: animated to, and written once the steps stop,
    // so a spin of the wheel is one history entry rather than twenty.
    function stepGesture(framing) {
        if (root.liveScreen === "")
            return;
        root.interacting = true;
        root.animateLiveTo(framing, true);
        commitTimer.restart();
    }

    // A touchpad scroll's pan: lands at once (the fingers are already a
    // continuous motion) and is written once they stop, like the wheel.
    function nudgeGesture(framing) {
        if (root.liveScreen === "")
            return;
        root.interacting = true;
        root.settleLive();
        const f = WallpaperFraming.normalize(framing);
        root.liveZoom = f.zoom;
        root.liveX = f.x;
        root.liveY = f.y;
        commitTimer.restart();
    }

    // Where a run of steps is heading: the next step builds on it rather than
    // on a value still animating towards it.
    function gestureTarget() {
        if (!liveAnimation.running)
            return root.liveFraming;
        return WallpaperFraming.normalize({
            "zoom": zoomAnim.to,
            "x": xAnim.to,
            "y": yAnim.to,
            "rotation": angleAnim.to,
            "flipH": root.liveFlipH,
            "flipV": root.liveFlipV
        });
    }

    Timer {
        id: commitTimer
        interval: 450
        repeat: false
        onTriggered: root.flushGesture()
    }

    // Writes a run of steps now instead of when the timer would have: before
    // a button builds on the framing (or it would build on the stored one and
    // the timer would then write the steps over the button's change), and
    // before the preview moves to another screen or picture.
    function flushGesture() {
        if (!commitTimer.running)
            return;
        commitTimer.stop();
        if (root.liveScreen === "")
            return;
        const target = root.gestureTarget();
        root.interacting = false;
        root.commitFraming(root.liveScreen, root.livePath, target);
    }

    // ── Writes ───────────────────────────────────────────────────────────────
    // Every write replaces the whole list (a `list<var>` only notifies on
    // reassignment) and records the pair for Edit Mode's history. Outside the
    // mode the history ignores the push, which is the same contract every
    // other store the mode edits keeps.

    function listCopy() {
        return root.entries.map(entry => ({
            "monitor": String(entry.monitor),
            "key": String(entry.key ?? ""),
            "path": root.cleanPath(entry.path),
            "framings": Array.from(entry.framings ?? [])
                .filter(f => f && root.cleanPath(f.path) !== "")
                .map(f => Object.assign({ "path": root.cleanPath(f.path) }, WallpaperFraming.normalize(f)))
        }));
    }

    // The screen's entry in a copy of the list, created when it has none,
    // and stamped with the connector and monitor it is on now.
    function entryIn(list, name) {
        const key = root.keyFor(name);
        let entry = root.matchEntry(list, name);
        if (!entry) {
            entry = { "monitor": name, "key": key, "path": "", "framings": [] };
            list.push(entry);
        }
        entry.monitor = name;
        if (key !== "")
            entry.key = key;
        return entry;
    }

    function writeList(next) {
        const before = root.listCopy();
        // An entry with nothing in it is the default and is not kept.
        const after = next.filter(entry => entry.path !== "" || entry.framings.length > 0);
        if (JSON.stringify(before) === JSON.stringify(after))
            return false;
        Config.options.background.monitorWallpapers = after;
        GlobalStates.editHistoryPush({
            "undo": () => {
                Config.options.background.monitorWallpapers = before;
            },
            "redo": () => {
                Config.options.background.monitorWallpapers = after;
            }
        });
        return true;
    }

    // A framing for one picture into an entry of a list copy: most recent
    // first, the identity not kept.
    function setFramingIn(entry, path, framing) {
        const clean = root.cleanPath(path);
        const f = WallpaperFraming.normalize(framing);
        entry.framings = entry.framings.filter(item => item.path !== clean);
        if (!WallpaperFraming.isIdentity(f))
            entry.framings.unshift(Object.assign({ "path": clean }, f));
        entry.framings = entry.framings.slice(0, root.framingMemory);
    }

    function commitFraming(name, path, framing) {
        const clean = root.cleanPath(path);
        if (!root.available || !name || clean === "")
            return;
        const list = root.listCopy();
        root.setFramingIn(root.entryIn(list, name), clean, framing);
        root.writeList(list);
    }

    // The framing a button starts from: the gesture's destination while one
    // is landing, so two quick clicks add up instead of the second undoing the
    // first.
    function currentFraming(name) {
        const path = root.sourcePathFor(name);
        if (root.isLive(name, path))
            return root.gestureTarget();
        return root.savedFramingFor(name, path);
    }

    function setZoom(name, zoom) {
        root.flushGesture();
        const current = root.currentFraming(name);
        const g = root.geometryFor(name);
        const next = g
            ? WallpaperFraming.zoomAt(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight, current, zoom, 0, 0)
            : Object.assign({}, current, { "zoom": zoom });
        root.commitFraming(name, root.sourcePathFor(name), next);
    }

    function rotate(name, turns) {
        root.flushGesture();
        const current = root.currentFraming(name);
        const g = root.geometryFor(name);
        const next = g
            ? WallpaperFraming.rotateBy(g.planeWidth, g.planeHeight, g.imageWidth, g.imageHeight, current, turns)
            : Object.assign({}, current, { "rotation": WallpaperFraming.snapRotation(current.rotation + turns * 90) });
        root.commitFraming(name, root.sourcePathFor(name), next);
    }

    function flip(name, axis) {
        root.flushGesture();
        root.commitFraming(name, root.sourcePathFor(name), WallpaperFraming.flip(root.currentFraming(name), axis));
    }

    function centre(name) {
        root.flushGesture();
        const next = Object.assign({}, root.currentFraming(name), { "x": 0, "y": 0 });
        root.commitFraming(name, root.sourcePathFor(name), next);
    }

    function resetFraming(name) {
        root.flushGesture();
        root.commitFraming(name, root.sourcePathFor(name), WallpaperFraming.defaults());
    }

    // A picture picked for one screen. A screen showing the shared wallpaper
    // changes the shared one - and with it the colours and every other screen
    // still showing it, which is what "shared" means; a screen with its own
    // changes only itself. Images only for a screen of its own: a video is
    // played or painted for the whole desktop.
    function setScreenWallpaper(name, path) {
        const clean = root.cleanPath(path);
        if (clean === "")
            return false;
        if (!root.hasOwn(name)) {
            Wallpapers.select(clean);
            return true;
        }
        return root.setOwnWallpaper(name, clean);
    }

    // A picture of the screen's own, whether or not it had one: the pick that
    // gives a screen its own wallpaper when the shared one is a video and
    // cannot simply be copied over (detach below).
    function setOwnWallpaper(name, path) {
        const clean = root.cleanPath(path);
        if (!root.available || !root.multiScreen || !root.isImagePath(clean))
            return false;
        if (!root.hasOwn(name) && !root.canDetach(name))
            return false;
        const list = root.listCopy();
        root.entryIn(list, name).path = clean;
        root.writeList(list);
        // The selector closes on this, as it does for any other pick.
        Wallpapers.changed();
        return true;
    }

    // Gives a screen a wallpaper of its own, starting from the one it already
    // shows so nothing on screen changes. A shared video cannot be copied to
    // one screen; the caller has one picked instead (setOwnWallpaper).
    function detach(name) {
        if (!root.canDetach(name) || !root.isImagePath(root.sharedSourcePath))
            return false;
        const list = root.listCopy();
        root.entryIn(list, name).path = root.sharedSourcePath;
        return root.writeList(list);
    }

    // Back to the shared wallpaper.
    function attach(name) {
        if (!root.hasOwn(name))
            return;
        const list = root.listCopy();
        root.entryIn(list, name).path = "";
        root.writeList(list);
    }

    // The colours from another screen's picture. That picture becomes the
    // shared one - through Wallpapers, so the colour scripts run as for any
    // other pick - and every screen that was showing the old shared wallpaper
    // keeps it as its own, so not one screen changes what it shows. One
    // history entry for the whole swap.
    function canMakeColourSource(name) {
        return root.hasOwn(name) && root.isImagePath(root.sharedSourcePath);
    }

    function makeColourSource(name) {
        if (!root.canMakeColourSource(name))
            return false;
        const picture = root.ownPathFor(name);
        const previous = root.sharedSourcePath;
        const list = root.listCopy();
        for (const other of root.screenNames) {
            if (other !== name && root.ownPathFor(other) === "")
                root.entryIn(list, other).path = previous;
        }
        root.entryIn(list, name).path = "";
        GlobalStates.editHistoryBeginBatch();
        root.writeList(list);
        Wallpapers.select(picture);
        GlobalStates.editHistoryEndBatch();
        return true;
    }

    // A random picture from the selector's folder, for one screen.
    function randomForScreen(name) {
        const model = Wallpapers.folderModel;
        const current = root.sourcePathFor(name);
        const own = root.hasOwn(name);
        const candidates = [];
        for (let i = 0; i < model.count; i++) {
            if (Boolean(model.get(i, "fileIsDir")))
                continue;
            const path = root.cleanPath(model.get(i, "filePath"));
            if (path === "" || path === current)
                continue;
            if (own ? !root.isImagePath(path) : !Wallpapers.extensions.some(ext => path.toLowerCase().endsWith("." + ext)))
                continue;
            candidates.push(path);
        }
        if (candidates.length === 0)
            return;
        root.setScreenWallpaper(name, candidates[Math.floor(Math.random() * candidates.length)]);
    }

    // ── Screens, by name and by place ────────────────────────────────────────

    // A screen as a person knows it: the panel of a laptop, a monitor's model,
    // its maker - the connector only when nothing better is known, and added
    // when two screens would otherwise read the same.
    function baseDisplayName(name) {
        if (/^(eDP|LVDS|DSI)/.test(name))
            return Translation.tr("Built-in display");
        const monitor = HyprlandData.monitors.find(m => m?.name === name);
        const model = String(monitor?.model ?? "").trim();
        if (model !== "" && !/^0x[0-9a-f]+$/i.test(model))
            return model;
        const make = String(monitor?.make ?? "").trim();
        return make !== "" ? make : name;
    }

    function displayName(name) {
        const base = root.baseDisplayName(name);
        if (base === name)
            return name;
        const twin = root.screenNames.some(other => other !== name && root.baseDisplayName(other) === base);
        return twin ? base + " · " + name : base;
    }

    // The screens where they stand (logical pixels), and the box around them.
    readonly property var screenRects: Array.from(Quickshell.screens).map(screen => ({
        "name": screen.name,
        "x": screen.x,
        "y": screen.y,
        "width": screen.width,
        "height": screen.height
    }))
    readonly property var screensBox: {
        const rects = root.screenRects;
        if (rects.length === 0)
            return { "x": 0, "y": 0, "width": 0, "height": 0 };
        const left = Math.min(...rects.map(r => r.x));
        const top = Math.min(...rects.map(r => r.y));
        const right = Math.max(...rects.map(r => r.x + r.width));
        const bottom = Math.max(...rects.map(r => r.y + r.height));
        return { "x": left, "y": top, "width": right - left, "height": bottom - top };
    }

    // ── Two screens at once ──────────────────────────────────────────────────

    // Whether two screens can trade pictures: they must show different ones,
    // and the shared one stays on a screen either way (it moves to the other).
    function canSwap(a, b) {
        if (!root.available || !a || !b || a === b)
            return false;
        return root.ownPathFor(a) !== root.ownPathFor(b);
    }

    // The two screens trade pictures, each picture keeping the framing it had
    // where it came from. One history entry.
    function swapWallpapers(a, b) {
        if (!root.canSwap(a, b))
            return false;
        root.flushGesture();
        const ownA = root.ownPathFor(a);
        const ownB = root.ownPathFor(b);
        const shownA = root.sourcePathFor(a);
        const shownB = root.sourcePathFor(b);
        const framingA = root.savedFramingFor(a, shownA);
        const framingB = root.savedFramingFor(b, shownB);
        const list = root.listCopy();
        const entryA = root.entryIn(list, a);
        const entryB = root.entryIn(list, b);
        entryA.path = ownB;
        entryB.path = ownA;
        root.setFramingIn(entryA, shownB, framingB);
        root.setFramingIn(entryB, shownA, framingA);
        return root.writeList(list);
    }

    // One screen's framing on another, for whatever picture that one shows:
    // a framing is relative (zoom over the cover fit, position within the
    // room left), so it means the same on a screen of another size.
    function canCopyFraming(from, to) {
        return root.available && from !== "" && to !== "" && from !== to
            && !WallpaperFraming.equal(root.currentFraming(from), root.currentFraming(to));
    }

    function copyFraming(from, to) {
        if (!root.canCopyFraming(from, to))
            return;
        root.flushGesture();
        root.commitFraming(to, root.sourcePathFor(to), root.currentFraming(from));
    }

    // ── One picture across every screen ─────────────────────────────────────
    // The picture covers the box around all the screens, and each screen is
    // framed onto its own piece of it, so the picture runs on from one screen
    // to the next. Every screen shows the same file, so it is the shared one
    // (and the colours come from it). Monitor bezels and gaps in the layout
    // are not modelled: the layout's logical pixels are the picture's.

    // The framing that puts a screen on its piece of the spanned picture.
    // The plane is larger than the screen by the workspace zoom; the framing
    // compensates so the picture runs on at the seams with the parallax at
    // rest. null when the screen or the picture's size is unknown.
    function spanFramingFor(name, imageWidth, imageHeight) {
        const rect = root.screenRects.find(r => r.name === name);
        const box = root.screensBox;
        if (!rect || !(imageWidth > 0) || !(imageHeight > 0) || !(box.width > 0) || !(box.height > 0))
            return null;
        const g = root.geometryFor(name);
        const base = g && rect.width > 0 ? g.planeWidth / rect.width : 1;
        const planeWidth = rect.width * base;
        const planeHeight = rect.height * base;
        // Image pixels to screen pixels for the whole box.
        const boxScale = Math.max(box.width / imageWidth, box.height / imageHeight);
        const cover = Math.max(planeWidth / imageWidth, planeHeight / imageHeight);
        const zoom = boxScale / cover;
        // The picture's centre from the screen's centre.
        const cx = (box.x + box.width / 2) - (rect.x + rect.width / 2);
        const cy = (box.y + box.height / 2) - (rect.y + rect.height / 2);
        const framing = WallpaperFraming.normalize({ "zoom": zoom });
        const at = WallpaperFraming.layout(planeWidth, planeHeight, imageWidth, imageHeight, framing);
        framing.x = at.rangeX > 0.5 ? Math.max(-1, Math.min(1, -cx / at.rangeX)) : 0;
        framing.y = at.rangeY > 0.5 ? Math.max(-1, Math.min(1, -cy / at.rangeY)) : 0;
        return framing;
    }

    // The size of the picture `name` shows, from its surface's probe.
    function imageSizeFor(name) {
        const g = root.geometryFor(name);
        return g ? { "width": g.imageWidth, "height": g.imageHeight } : null;
    }

    function canSpanFrom(name) {
        return root.available && root.multiScreen && root.isImagePath(root.sourcePathFor(name))
            && root.imageSizeFor(name) !== null;
    }

    // Whether the screens show one picture spanned across them.
    readonly property bool spanned: {
        if (!root.available || !root.multiScreen || root.screenNames.some(name => root.hasOwn(name)))
            return false;
        const size = root.imageSizeFor(root.screenNames[0]);
        if (size === null)
            return false;
        return root.screenNames.every(name => {
            const target = root.spanFramingFor(name, size.width, size.height);
            return target !== null && WallpaperFraming.equal(root.savedFramingFor(name, root.sharedSourcePath), target);
        });
    }

    function spanFrom(name) {
        if (!root.canSpanFrom(name))
            return false;
        root.flushGesture();
        const picture = root.sourcePathFor(name);
        const size = root.imageSizeFor(name);
        const becomesShared = root.hasOwn(name);
        const list = root.listCopy();
        for (const other of root.screenNames) {
            const entry = root.entryIn(list, other);
            entry.path = "";
            const framing = root.spanFramingFor(other, size.width, size.height);
            if (framing !== null)
                root.setFramingIn(entry, picture, framing);
        }
        GlobalStates.editHistoryBeginBatch();
        root.writeList(list);
        if (becomesShared)
            Wallpapers.select(picture);
        GlobalStates.editHistoryEndBatch();
        return true;
    }

    // Each screen back to the whole picture.
    function unspan() {
        if (!root.spanned)
            return;
        root.flushGesture();
        const list = root.listCopy();
        for (const name of root.screenNames)
            root.setFramingIn(root.entryIn(list, name), root.sharedSourcePath, WallpaperFraming.defaults());
        root.writeList(list);
    }
}
