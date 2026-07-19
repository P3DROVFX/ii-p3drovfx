pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int readWriteDelay: 75 // milliseconds
    property bool blockWrites: false
    // Wall-clock time (ms) at singleton init. Used to detect legitimately missing
    // config.json (after the singleton has been alive long enough) vs. transient
    // inaccessibility (git pull, hot-reload timing, FS race) where we must NOT
    // overwrite the user's real config.json with the in-memory QML defaults.
    property real initTimestamp: Date.now()
    // Grace window during which a missing file is assumed transient and a
    // reload is retried before we ever dare to write defaults.
    // Increased from 2000 to 5000 to match writeGuardDelay — prevents
    // config.json from being clobbered with defaults during hot-reload.
    property int missingFileGracePeriod: 5000
    property int missingFileRetryInterval: 1500
    // Minimum time (ms) since singleton creation before ANY write is allowed,
    // even after `onLoaded` sets `ready = true`. This catches hot-reload races
    // where the file loads from page cache almost instantly but the
    // JsonAdapter hasn't fully merged values into all nested JsonObjects yet.
    // Increased from 3000 to 5000 to prevent config.json resets during
    // shell hot-reload while Phone services are initializing.
    property int writeGuardDelay: 5000

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            configFileView.reload();
        }
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            // Never overwrite the user's config.json with the in-memory
            // JsonAdapter state (which is mostly QML defaults until the file
            // is loaded). If the file has not loaded yet, defer the write and
            // keep retrying — once `onLoaded` flips `root.ready` the pending
            // write will fire with the file's real values merged in.
            if (root.blockWrites) {
                return;
            }
            if (!root.ready) {
                fileWriteTimer.restart();
                return;
            }
            // Extra guard: even after `ready`, if the singleton was created
            // less than `writeGuardDelay` ms ago, defer. This catches the
            // hot-reload race where `onLoaded` fires very fast (file is in
            // page cache) but the JsonAdapter hasn't fully merged the file's
            // values into all nested JsonObjects yet.
            const elapsed = Date.now() - root.initTimestamp;
            if (elapsed < root.writeGuardDelay) {
                fileWriteTimer.restart();
                return;
            }
            configFileView.writeAdapter();
        }
    }

    // If `onLoadFailed(FileNotFound)` fires, do NOT immediately call
    // `writeAdapter()` — during a git pull, hot-reload, or PC restart the file
    // can be briefly inaccessible and the QML defaults would clobber the user's
    // real config.json. Instead, retry `reload()` after the grace period; only
    // if the file is still genuinely missing after the singleton has been alive
    // for a while do we create defaults.
    Timer {
        id: missingFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: {
            configFileView.reload();
        }
    }

    function isWidgetActive(widgetId) {
        let list = root.options.background.activeWidgets || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].widgetId === widgetId) return true;
        }
        return false;
    }

    function getWidgetLockBehavior(widgetId) {
        let list = root.options.background.activeWidgets || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].widgetId === widgetId) return list[i].lockBehavior || "hide";
        }
        return "hide";
    }

    function setWidgetLockBehavior(widgetId, newLockBehavior) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].widgetId === widgetId) {
                cloned[i].lockBehavior = newLockBehavior;
                root.options.background.activeWidgets = cloned;
                return;
            }
        }
    }

    function addWidgetToDesktop(widgetId, defaultX, defaultY) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].widgetId === widgetId) return;
        }
        
        let startX = defaultX !== undefined ? defaultX : 200;
        let startY = defaultY !== undefined ? defaultY : 200;
        
        if (defaultX === undefined && defaultY === undefined) {
            let offset = 0;
            while (true) {
                let collision = false;
                for (let i = 0; i < cloned.length; i++) {
                    if (Math.abs(cloned[i].x - (startX + offset)) < 30 && Math.abs(cloned[i].y - (startY + offset)) < 30) {
                        collision = true;
                        break;
                    }
                }
                if (!collision) {
                    startX += offset;
                    startY += offset;
                    break;
                }
                offset += 80;
            }
        }
        
        let instanceId = "widget_" + widgetId + "_" + Date.now();
        cloned.push({
            "id": instanceId,
            "widgetId": widgetId,
            "x": startX,
            "y": startY,
            "placementStrategy": "free",
            "lockBehavior": "hide"
        });
        root.options.background.activeWidgets = cloned;
    }

    function removeWidgetFromDesktop(widgetId) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let indexToRemove = -1;
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].widgetId === widgetId) {
                indexToRemove = i;
                break;
            }
        }
        if (indexToRemove !== -1) {
            cloned.splice(indexToRemove, 1);
            root.options.background.activeWidgets = cloned;
        }
    }

    function updateWidgetPosition(instanceId, newX, newY) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let found = false;
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].id === instanceId) {
                cloned[i].x = newX;
                cloned[i].y = newY;
                found = true;
                break;
            }
        }
        if (found) {
            root.options.background.activeWidgets = cloned;
        }
    }

    function updateWidgetLockBehavior(instanceId, newLockBehavior) {
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let found = false;
        for (let i = 0; i < cloned.length; i++) {
            if (cloned[i].id === instanceId) {
                cloned[i].lockBehavior = newLockBehavior;
                found = true;
                break;
            }
        }
        if (found) {
            root.options.background.activeWidgets = cloned;
        }
    }

    function migrateRoundingConfig() {
        if (root.options.appearance.roundingValue >= 0) return;
        var oldMode = root.options.appearance.globalRounding || "large";
        if (oldMode === "sharp") {
            root.options.appearance.roundingValue = 0;
        } else if (oldMode === "normal") {
            root.options.appearance.roundingValue = 17;
        } else if (oldMode === "verylarge") {
            root.options.appearance.roundingValue = 32;
        } else {
            root.options.appearance.roundingValue = 24;
        }
        root.options.appearance.sharpMode = (root.options.appearance.roundingValue === 0);
    }

    function migrateWidgetLockBehavior() {
        if (Persistent.states.background.lockBehaviorMigrated) return;
        let cloned = JSON.parse(JSON.stringify(root.options.background.activeWidgets || []));
        let changed = false;
        for (let i = 0; i < cloned.length; i++) {
            if (!cloned[i].lockBehavior) {
                cloned[i].lockBehavior = "hide";
                changed = true;
            }
        }
        if (changed) {
            root.options.background.activeWidgets = cloned;
        }
        Persistent.states.background.lockBehaviorMigrated = true;
    }

    Component.onDestruction: {
        root.blockWrites = true;
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        // Atomic writes: write to a temp file then rename. Prevents mid-write
        // corruption if the process is killed mid-save (e.g. PC power loss,
        // SIGKILL during shell update).
        atomicWrites: true
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: { if (root.ready && !root.blockWrites) fileWriteTimer.restart(); }
        onLoaded: {
            root.ready = true;
            migrateRoundingConfig();
        }
        onLoadFailed: error => {
            if (error != FileViewError.FileNotFound) {
                return;
            }
            const elapsed = Date.now() - root.initTimestamp;
            if (elapsed > root.missingFileGracePeriod && !root.ready) {
                // Singleton has been alive past the grace window and the file
                // is still gone — legitimately missing (first-run install or
                // user manually deleted it). Safe to seed defaults.
                writeAdapter();
                // Mark ready so subsequent user-triggered writes go through
                // (fileWriteTimer guards on `root.ready`).
                root.ready = true;
            } else {
                // Likely transient: schedule a reload. If it succeeds,
                // `onLoaded` flips `root.ready` and nothing is overwritten. If
                // it still fails past the grace window, defaults are written.
                missingFileRetryTimer.restart();
            }
        }

        Component.onDestruction: {
            configFileView.blockWrites = true;
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property string panelFamily: "ii" // "ii", "waffle"

            property JsonObject policies: JsonObject {
                property int ai: 1 // 0: No | 1: Yes | 2: Local
                property int weeb: 0 // 0: No | 1: Open | 2: Closet
                property int wallpapers: 0 // 0: No | 1: Yes
                property int translator: 0 // 0: No | 1: Default (illogical-impulse) | 2: Expressive (reworked)
                property int player: 0 // 0: No | 1: Yes
                property int phone: 1 // 0: No | 1: Yes — Phone tab (future KDE Connect + scrcpy external)
            }

            property JsonObject phone: JsonObject {
                property bool showPeripheralCards: true
                property JsonObject scrcpy: JsonObject {
                    property bool stayAwake: false  // bare scrcpy default — don't add overhead
                    property bool turnScreenOff: false  // turning screen off causes input delay on Samsung (touch sampling rate drops)
                    property bool noPowerOn: false  // bare scrcpy default
                    property bool noAudio: false
                    property bool showTouches: false
                    property bool fullscreen: false
                    property bool alwaysOnTop: false
                    property int maxFps: 0  // 0 = use device's native frame rate (matches bare `scrcpy`)
                    property string bitRate: "8M"
                    property int maxSize: 0
                    property int videoBuffer: 0  // scrcpy 4.0 default is 0ms — 80ms adds visible latency
                    property bool useWireless: false
                    property string wirelessIp: ""
                    property string wirelessPort: "5555"
                    property bool showTerminal: false
                }
                property JsonObject webcam: JsonObject {
                    property bool enabled: false
                    property string cameraFacing: "front" // "front" | "back"
                    property string resolution: "1280x720" // "640x480" | "1280x720" | "1920x1080"
                    property int fps: 30
                    property string bitrate: "4M"
                    property bool mirrorHorizontally: false
                    property int rotateDegrees: 0 // 0 | 90 | 180 | 270
                    property string connection: "wifi" // "wifi" | "usb"
                    property string wifiIp: ""
                    property int port: 4747
                }
                property JsonObject microphone: JsonObject {
                    property bool enabled: false
                    property string connection: "wifi"
                    property string wifiIp: ""
                    property int port: 4748
                    property bool noiseSuppression: false
                    property bool echoCancellation: false
                    property bool autoGainControl: false
                    property int micGain: 100
                    property bool setAsDefault: false
                }
            }

            property JsonObject localsend: JsonObject {
                property bool autoStart: true
                property string downloadPath: Directories.localSendDownloadPath.replace("file://", "")
                property bool showNotifications: true
                property bool preferPopupOverNotification: true
            }

            property JsonObject ai: JsonObject {
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal!\n- Always be brief and to the point, unless asked otherwise\n- Don't repeat the user's question\n- Be approachable: Avoid using overly complicated, domain-specific terms and provide analogies when asked to explain a concept\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n\nThanks!\n"
                property string tool: "functions" // search, functions, or none
                property list<var> models: [
                    // Needed entries in the object: title, value, modelProvider (only for openrouter)
                    {
                        "openrouter": [
                            {
                                title: "Gemini 2.5 Flash",
                                value: "gemini-2.5-flash",
                                modelProvider: "google"
                            },
                        ]
                    },
                    {
                        "google": []
                    }
                ]
                property list<var> otherModels: [
                    // Available api_format(s): openai, gemini, mistral
                    {
                        "name": "Mistral Medium",
                        "model": "mistral-medium-2505",
                        "icon": "mistral-symbolic",
                        "endpoint": "https://api.mistral.ai/v1/chat/completions",
                        "requires_key": true,
                        "key_id": "mistral",
                        "api_format": "mistral"
                    }
                ]
            }

            property JsonObject appearance: JsonObject {
                property bool extraBackgroundTint: true
                property int fakeScreenRounding: 3 // 0: None | 1: Always | 2: When not fullscreen | 3: Wrapped
                property int wrappedFrameThickness: 10
                property bool sharpMode: false
                property string globalRounding: "large" // Legacy — migrated to roundingValue via onLoaded
                property int roundingValue: -1 // -1 = not yet migrated, 0-48 = active slider value (default 24 after migration)
                property int defaultBorderRadius: 18
                property bool toggleWindowRounding: true // Changes Hyprland window rounding to 0 if sharpMode is true
                property real iconTintPercentage: 0.6
                property JsonObject fonts: JsonObject {
                    property bool enableCustom: false
                    property string main: "Google Sans Flex" // xmpl: right sidebar, settings, system monitor, default clock, expressive weather
                    property string numbers: "Google Sans Flex" // xmpl: styled slider, config
                    property string title: "Google Sans Flex" // settings list item, popup titles
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF" // clipboard metadata
                    property string reading: "Readex Pro" // cookie clock quote
                    property string expressive: "Space Grotesk" // desktop widgets font, overview workspace number, user profile config
                    property bool roundnessFull: false
                }
                property JsonObject transparency: JsonObject {
                    property bool enable: false
                    property bool automatic: false
                    property bool popups: false
                    property real backgroundTransparency: 0.48
                    property real contentTransparency: 0.38
                }
                property int blurSize: 10
                property int borderWidth: 2
                property int gapsIn: 4
                property int gapsOut: 5
                property real ignoreAlpha: 0.4
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property bool autoRestartQuickshell: false
                    property JsonObject terminalGenerationProps: JsonObject {
                        property real harmony: 0.6
                        property real harmonizeThreshold: 100
                        property real termFgBoost: 0.35
                        property bool forceDarkMode: false
                    }
                }
                property JsonObject icons: JsonObject {
                    property bool enableThemed: false
                    property bool enableShapeMask: true
                    property string shapeMask: "Circle"
                }
                property string borderColorType: "primary" // Options: primary, secondary, tertiary, primaryContainer, surface
                property bool borderless: false
                property string colorEngine: "vynx" // "vynx" | "fork" — color generation engine
                property string iconTheme: "Papirus"
                property JsonObject palette: JsonObject {
                    property string type: "scheme-fidelity" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                    property string accentColor: ""
                }
                property list<string> customColorSchemes: []
                property real animationMultiplier: 1.0 // 0.25 = fast, 1.0 = default, 2.0 = slow
                property bool colorfulScrollbar: false
                property bool scrollAnimations: true
                property bool scrollFadeMask: false
                property JsonObject openrgb: JsonObject {
                    property bool enable: false
                    property bool applyOnStartup: true
                    property real fadeDuration: 0.5
                    property real interpolationSteps: 100
                    property list<var> devices: []
                }
            }

            property JsonObject audio: JsonObject {
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: false
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 99
                }
            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "kcmshell6 kcm_bluetooth"
                property string changePassword: "kitty -1 --hold=yes fish -i -c 'passwd'"
                property string network: "kcmshell6 kcm_networkmanagement"
                property string manageUser: "kcmshell6 kcm_users"
                property string networkEthernet: "kcmshell6 kcm_networkmanagement"
                property string taskManager: "plasma-systemmonitor --page-name Processes"
                property string terminal: "kitty -1" // This is only for shell actions
                property string update: "kitty -1 --hold=yes fish -i -c 'pkexec pacman -Syu'"
                property string volumeMixer: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"`
            }

            property list<var> bluetoothDeviceImages: []

            property JsonObject background: JsonObject {
                property bool enable: true // if someone wants to use an external wallpaper manager, note that its not fully tested but it should just disable background.qml from being loaded
                property bool blurGradientExperiment: false
                property JsonObject widgets: JsonObject {
                    property JsonObject clock: JsonObject {
                        property bool enable: true
                        property bool showOnlyWhenLocked: false
                        property bool disableAnimationOnLock: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 1518.98
                        property real y: 168.8
                        property string style: "cookie"        // Options: "cookie", "digital", "nagasaki", "dial"
                        property string styleLocked: "cookie"  // Options: "cookie", "digital", "nagasaki", "dial"
                        property JsonObject cookie: JsonObject {
                            property bool aiStyling: false
                            property string aiStylingModel: "gemini" // Options "gemini", "openrouter"
                            property int sides: 14
                            property string backgroundStyle: "cookie"     // Options: "cookie", "sine", "shape"
                            property string backgroundShape: "Arch"  // Options: MaterialShape.Shape enum values as string
                            property string dialNumberStyle: "full"   // Options: "dots" , "numbers", "full" , "none"
                            property string hourHandStyle: "fill"     // Options: "classic", "fill", "hollow", "hide"
                            property string minuteHandStyle: "medium" // Options "classic", "thin", "medium", "bold", "hide"
                            property string secondHandStyle: "dot"    // Options: "dot", "line", "classic", "hide"
                            property string dateStyle: "bubble"       // Options: "border", "rect", "bubble" , "hide"
                            property bool timeIndicators: true
                            property bool hourMarks: false
                            property bool dateInClock: true
                            property bool constantlyRotate: false
                        }
                        property JsonObject digital: JsonObject {
                            property bool adaptiveAlignment: true
                            property bool showDate: true
                            property bool animateChange: true
                            property bool vertical: false
                            property bool colorful: false
                            property bool showColon: true
                            property JsonObject font: JsonObject {
                                property string family: "Google Sans Flex"
                                property real weight: 350
                                property real width: 100
                                property real size: 90
                                property real roundness: 0
                            }
                        }
                        property JsonObject dial: JsonObject {
                            property bool showTicks: true
                            property bool showMinuteHand: true
                            property bool enableShadows: true
                            property bool enableInnerShadow: false
                        }
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                        }
                    }
                    property JsonObject media: JsonObject {
                        property bool enable: true
                        property string style: "circular" // circular, expressive
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 249.21
                        property real y: 612.92
                        property bool useAlbumColors: true
                        property bool hideAllButtons: false
                        property bool showPreviousToggle: true
                        property bool tintArtCover: false
                        property string backgroundShape: "Cookie12Sided"  // Options: MaterialShape.Shape enum values as string
                        property JsonObject glow: JsonObject {
                            property bool enable: true
                            property real brightness: 10
                        }
                        property JsonObject visualizer: JsonObject {
                            property bool enable: false
                            property real opacity: 0.15
                            property int smoothing: 2
                            property int blur: 1
                        }
                    }
                    property JsonObject circular_media: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 249.21
                        property real y: 612.92
                        property bool useAlbumColors: true
                        property bool enableGlassReflection: true
                    }
                    property JsonObject wearos_clock: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 400
                        property real y: 100
                        property bool useAlbumColors: true
                        property bool enableGlassReflection: true
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string style: "default" // default, expressive
                        property string backgroundShape: "Cookie9Sided"
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                    }
                    property JsonObject date: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                    }
                    property JsonObject photo: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 200
                        property real y: 200
                        property string imagePath: ""
                    }
                    property bool enableInnerShadow: true
                    property bool enableShadows: true
                    property bool enableGrid: false
                    property bool enableSnap: false
                    property real widgetsScale: 1.0
                    property bool lockWidgetPositions: false
                }
                property list<var> activeWidgets: [
                    { "id": "widget_clock_cookie", "widgetId": "clock_cookie", "x": 1518.98, "y": 168.8, "placementStrategy": "free", "lockBehavior": "center" },
                    { "id": "widget_media_circular", "widgetId": "media_circular", "x": 249.21, "y": 612.92, "placementStrategy": "free", "lockBehavior": "hide" }
                ]
                property bool scaleLargeWallpapers: true
                property bool animateWallpaperChanges: true
                property string wallpaperAnimation: ""
                property bool zoomOutEnabled: true  // master toggle for zoom-out animations
                property bool windowZoomOnOverview: false // fake window scale-out during overview (GNOME-like)
                property bool windowZoomLiveCapture: false // keep screencopy live instead of freezing on overview open
                property bool cheatsheetZoomOut: true
                property bool overviewZoomOut: true
                property bool workspaceBlur: false
                property string wallpaperPath: ""
                property string thumbnailPath: ""
                property bool hideWhenFullscreen: true
                property bool useWallpaperEngine: false
                property string wallpaperEngineId: ""
                property string wallpaperEngineAssetsPath: ""
                property bool wpeSilent: true
                property real wpeVolume: 50
                property bool wpeNoAutoMute: false
                property bool wpeNoAudioProcessing: false
                property int wpeFps: 30
                property string wpeScreenSpan: ""
                property string wpeScaling: "default"
                property bool wpeDisableMouse: false
                property bool wpeDisableParallax: false
                property bool wpeNoFullscreenPause: false
                property bool wpePauseWhenWindowsOpen: false
                property int zoomOutStyle: 0 // 0: Blurred Backing | 1: Mirrored Plane
                property bool blurWhenWindowsOpen: false
                property int blurWhenWindowsOpenRadius: 80
                property JsonObject gradientBlur: JsonObject {
                    property bool enable: false
                    property int radius: 50
                    property string direction: "top-to-bottom"
                }
                property JsonObject parallax: JsonObject {
                    property bool vertical: false
                    property bool autoVertical: false
                    property bool enableWorkspace: true
                    property real workspaceZoom: 1.05 // Relative to wallpaper size
                    property bool enableSidebar: true
                    property real widgetsFactor: 1.2
                    property bool loop: false
                    property bool invertHorizontal: false
                    property bool invertVertical: false
                    property int intensity: 4
                }
                property JsonObject mediaMode: JsonObject {
                    property bool togglePerMonitor: false
                    property string backgroundShape: "Square"
                    property bool enableBackgroundAnimation: true // It **may** cause nausea for someone
                    property bool changeShellColor: true // Changes the shell color to the album color
                    property int backgroundOpacity: 50 // In percent
                    property int backgroundBlurRadius: 120
                    property JsonObject backgroundAnimation: JsonObject {
                        property bool enable: true
                        property int speedScale: 10 // 1: very slow, 10: default, 20: 2x speed etc.
                    }
                    property JsonObject syllable: JsonObject {
                        property int textHighlightStyle: 0 // 0: vertical, 1: horizontal (not perfect bc its not synced in a word level, but a cool animation to have)
                    }
                }
            }

            property JsonObject bar: JsonObject {
                property bool borderless: false
                property JsonObject clock: JsonObject {
                    property bool showSeconds: true
                    property bool secondaryOpposite: false
                    property bool showPrimary: true
                    property bool showSecondary: true
                    property bool swapPrimaryWithSecondary: false
                }
                property JsonObject styles: JsonObject {
                    property string activeWindow: "default"
                    property string clock: "expressive" // default, expressive, material
                    property string media: "expressive"
                    property string notification: "default"
                    property string utilButtons: "expressive"
                    property string workspaces: "minimal"
                    property string weather: "expressive"
                    property string dashboard: "expressive"
                    property string resources: "expressive"
                    property string policies: "default"
                    property string power: "expressive"
                    property string battery: "expressive"
                    property string systray: "default"
                    property string bluetooth: "expressive"
                    property string keyboard: "expressive"
                    property string sports: "expressive"
                }

                property JsonObject activeWindow: JsonObject {
                    property bool fixedSize: false
                    property int customSize: 225
                }

                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    property int hoverRegionWidth: 2
                    property bool pushWindows: false
                    property JsonObject showWhenPressingSuper: JsonObject {
                        property bool enable: true
                        property int delay: 140
                    }
                }

                property bool bottom: false // Instead of top
                property int cornerStyle: 0 // 0: Hug | 1: Float | 2: Plain rectangle
                property bool floatStyleShadow: true // Show shadow behind bar when cornerStyle == 1 (Float)
                property bool dropShadow: true
                property int dynamicIslandSpacingHorizontal: 48
                property int dynamicIslandSpacingVertical: 16
                property bool dynamicIslandLoadBalance: true

                property JsonObject dynamicIsland: JsonObject {
                    property JsonObject notchMode: JsonObject {
                        property bool enable: false
                        property int expandAnimDuration: 250
                        property int fadeDelay: 0
                        property list<string> visibleWidgets: []
                        property bool overlapApps: false
                    }
                }

                property JsonObject floatingNotch: JsonObject {
                    property bool enable: false
                    property bool autoHide: false
                    property bool dropShadow: false
                    property bool onlyShowOnSingleMonitor: false
                    property string singleMonitorName: ""

                    // Disables
                    property bool disableWorkspaces: false
                    property bool disableKeyboard: false
                    property bool disableWifi: false
                    property bool disableBluetooth: false
                    property bool disableMedia: false
                    property bool disableNotification: false
                    property bool disableOsd: false
                    property bool disableRecording: false
                    property bool disableTimer: false
                    property bool disableClipboard: false
                    property bool disableLocalSend: false
                    property bool disableKdeConnectInLocalSend: false
                    property bool disableChecklist: true
                    property bool checklistAlwaysVisible: false
                    property bool checklistOnlyExpanded: false
                    property bool disableCalendar: false
                    property bool disableAudio: true
                    property bool disableProgress: false
                    property bool disableBattery: false
                    property bool clickToExpand: false

                    // Contracted Heights
                    property int heightHome: 36
                    property int heightWorkspaces: 36
                    property int heightKeyboard: 36
                    property int heightWifi: 36
                    property int heightBluetooth: 88
                    property int heightMedia: 52
                    property int heightNotification: 64
                    property int heightRecording: 36
                    property int heightTimer: 36
                    property int heightClipboard: 36
                    property int heightLocalSend: 42
                    property int heightChecklist: 36
                    property int heightCalendar: 48
                    property int heightAudio: 36
                    property int heightProgress: 48
                    property int heightBattery: 36
                }

                property int barGroupStyle: 1 // 0: Pills | 1: Island (opaque) | 2: Transparent (or maybe line-separated in the future)
                property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/ii/assets/icons
                property bool useMaterialSymbolForTopLeftIcon: false
                property int barBackgroundStyle: 1 // 0: Transparent | 1: Visible | 2: Adaptive
                property bool transparentGlow: true
                property bool expressiveColors: false
                property string expressiveColorTheme: "content"
                property bool verbose: true
                property bool vertical: false
                property bool enableVolumeScroll: true
                property bool enableBrightnessScroll: true

                property JsonObject mediaPlayer: JsonObject {
                    property string popupStyle: "default" // "default" | "expressive" | "android"
                    property bool expressivePopup: false
                    property bool useFixedSize: true
                    property int customSize: 200
                    property int maxSize: 400
                    property JsonObject artwork: JsonObject {
                        property bool enable: false
                    }
                    property JsonObject lyrics: JsonObject {
                        property bool enable: true
                        property int customSize: 300
                        property string style: "scroller" // Options: scroller, static
                        property bool useGradientMask: true
                    }
                }

                property JsonObject resources: JsonObject {
                    property bool showPercentageText: true
                    property bool alwaysShowRam: true
                    property bool alwaysShowCpu: true
                    property bool alwaysShowCpuTemp: false
                    property bool alwaysShowDisk: false
                    property bool alwaysShowSwap: false
                    property int memoryWarningThreshold: 95
                    property int swapWarningThreshold: 85
                    property int cpuWarningThreshold: 90
                    property bool expressivePopup: true
                    property bool showDocker: false
                }

                property JsonObject sports: JsonObject {
                    property bool enable: true
                    property bool showBRA: true
                    property bool showBUND: false
                    property bool showCL: true
                    property bool showCLA: true
                    property bool showEPL: true
                    property bool showLIGA: true
                    property bool showLIG1: false
                    property bool showSERA: false
                    property bool showUECL: false
                    property bool showUEL: false
                    property bool showWC: true
                    property bool showWWC: false
                    property list<var> monitoredLeagues: [
                        {
                            "sport": "soccer",
                            "league": "bra.1",
                            "name": "Brasileirão",
                            "enabled": true
                        },
                        {
                            "sport": "soccer",
                            "league": "eng.1",
                            "name": "Premier League",
                            "enabled": true
                        },
                        {
                            "sport": "soccer",
                            "league": "uefa.champions",
                            "name": "Champions League",
                            "enabled": true
                        },
                        {
                            "sport": "basketball",
                            "league": "nba",
                            "name": "NBA",
                            "enabled": true
                        },
                        {
                            "sport": "racing",
                            "league": "f1",
                            "name": "Formula 1",
                            "enabled": false
                        }
                    ]
                    property string teamFilter: ""
                    property int updateInterval: 60
                    property int maxCardsPopup: 4
                    property int showBeforeHours: 12
                    property int showAfterMinutes: 180
                    property string activeGameId: ""
                    property list<var> customOrder: []
                }
                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
                property bool onlyShowOnSingleMonitor: false
                property string singleMonitorName: ""

                property JsonObject timers: JsonObject {
                    property bool showPomodoro: true
                    property bool showStopwatch: true
                }
                property JsonObject utilButtons: JsonObject {
                    property bool showScreenSnip: false
                    property bool showColorPicker: true
                    property bool showMicToggle: false
                    property bool showKeyboardToggle: false
                    property bool showDarkModeToggle: false
                    property bool showPerformanceProfileToggle: false
                    property bool showScreenRecord: true
                    property bool isRecording: false
                    property bool showWallpaperToggle: true
                }
                property JsonObject workspaces: JsonObject {
                    property bool monochromeIcons: false
                    property int shown: 7
                    property bool showAppIcons: false
                    property bool alwaysShowNumbers: false
                    property int showNumberDelay: 300 // milliseconds
                    property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
                    property bool useWorkspaceMap: false
                    property list<var> workspaceMap: [0, 10]
                    property int maxWindowCount: 1 // Maximum windows to show in one workspace
                    property bool useNerdFont: false
                    property int activeIndicatorOpacity: 100 // 0-100
                    property bool dynamicWorkspaces: false
                    property bool useMaterialShapeForActiveIndicator: false
                    property bool useRandomShapeForActiveIndicator: true
                    property string activeIndicatorShape: "Pentagon"
                }
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property bool enableGPS: true // gps based location
                    property string city: "" // When 'enableGPS' is false
                    property bool useUSCS: false // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: true
                    }
                    property JsonObject record: JsonObject {
                        property bool minimal: false
                    }
                }
                property JsonObject dashboardButton: JsonObject {
                    property bool showVolume: true
                    property bool showMic: true
                    property bool showNetwork: true
                    property bool showBluetooth: true
                    property bool showNotifications: true
                }
                property JsonObject layouts: JsonObject {
                    // Only storing id and layout-specific flags (visible, centered)
                    // Component display info (icon, title) comes from BarComponentRegistry
                    property list<var> left: [
                        {
                            centered: false,
                            id: "policies_panel_button",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "workspaces",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "record_indicator",
                            visible: false
                        },
                        {
                            centered: false,
                            id: "timer",
                            visible: false
                        },
                        {
                            centered: false,
                            id: "system_monitor",
                            visible: true
                        }
                    ]
                    property list<var> center: [
                        {
                            centered: false,
                            id: "music_player",
                            visible: true
                        },
                        {
                            centered: true,
                            id: "clock",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "weather",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "utility_buttons",
                            visible: true
                        }
                    ]
                    property list<var> right: [
                        {
                            centered: false,
                            id: "system_tray",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "keyboard_layout",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "bluetooth_devices",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "battery",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "dashboard_panel_button",
                            visible: true
                        },
                        {
                            centered: false,
                            id: "power",
                            visible: true
                        }
                    ]
                }
                property JsonObject tooltips: JsonObject {
                    property bool clickToShow: false
                    property bool compactPopups: false
                    property bool enableColorPickerPopup: true
                    property bool enableBluetoothConnectionPopup: true
                    property bool enableKeyboardLayoutTransitionPopup: true
                }
                property JsonObject keyboardLayout: JsonObject {
                    property bool secondaryOpposite: false
                    property bool showSecondary: true
                    property bool showPrimary: true
                    property bool swapPrimaryWithSecondary: false
                    property bool uppercaseLayout: false
                }
                property JsonObject battery: JsonObject {
                    property bool secondaryOpposite: true
                    property bool showPrimary: true
                    property bool showSecondary: true
                    property bool swapPrimaryWithSecondary: false
                    property bool showPercentageInsideBattery: false
                    property string showPercentage: "off"
                }
                property string bluetoothDevicesLayout: "expressive" // Options: classic, expressive
                property JsonObject sizes: JsonObject {
                    property int height: 40 // horizontal mode
                    property int width: 45 // vertical mode
                }
            }

            property JsonObject battery: JsonObject {
                property string style: "android16"
                property string showPercentage: "off"
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
            }

            property JsonObject calendar: JsonObject {
                property string locale: "en-GB"
            }

            property JsonObject cheatsheet: JsonObject {
                // Use a nerdfont to see the icons
                // 0: 󰖳  | 1: 󰌽 | 2: 󰘳 | 3:  | 4: 󰨡
                // 5:  | 6:  | 7: 󰣇 | 8:  | 9: 
                // 10:  | 11:  | 12:  | 13:  | 14: 󱄛
                property string superKey: ""
                property bool useMacSymbol: false
                property bool splitButtons: false
                property bool useMouseSymbol: false
                property bool useFnSymbol: false
                property bool filterUnbinds: false
                property bool enableGmail: true
                property bool enableTimetable: true
                property bool timetableTodayFirst: false
                property bool enablePeriodicTable: false
                property bool enableCommands: true
                property bool commandsTagsSidebar: false
                property bool enableWorkspaceProfiles: false
                property JsonObject fontSize: JsonObject {
                    property int key: Appearance.font.pixelSize.smaller
                    property int comment: Appearance.font.pixelSize.smaller
                }
            }

            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }

            property JsonObject crosshair: JsonObject {
                // Valorant crosshair format. Use https://www.vcrdb.net/builder
                property string code: "0;P;d;1;0l;10;0o;2;1b;0"
            }

            property JsonObject dock: JsonObject {
                property bool enable: true
                property bool smartGrouping: false
                property bool isolateMonitors: false
                property bool monochromeIcons: false
                property bool dimInactiveIcons: false
                property bool enableShapeMask: false
                property string shapeMask: "Circle"
                property real height: 60
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool enablePreview: true
                property bool hoverToReveal: true
                property bool enableMediaWidget: true
                property bool enableWeatherWidget: true
                property bool showDividers: true
                property bool showOverviewButton: true
                property bool showPinButton: true
                property bool showTrashButton: true
                property bool showNotificationBadges: true
                property string position: "auto"
                property list<string> pinnedApps: ["org.kde.dolphin", "kitty",]
                property list<string> ignoredAppRegexes: []
                property list<string> pinnedFiles: []
                property list<string> order: ["pin", "app:org.kde.dolphin", "app:kitty", "runningApps", "media", "weather", "trash", "overview"]
            }

            property JsonObject hyprland: JsonObject {
                property string defaultHyprlandLayout: "dwindle" // Options: dwindle, monocle, master // It's best to not use scrolling
            }

            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false // Enable faster scrolling with touchpad
                    property int mouseScrollDeltaThreshold: 120 // delta >= this then it gets detected as mouse scroll rather than touchpad
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
                property JsonObject deadPixelWorkaround: JsonObject { // Hyprland leaves out 1 pixel on the right for interactions
                    property bool enable: false
                }
            }

            property JsonObject language: JsonObject {
                property string ui: "en_US" // UI language. "auto" for system locale, or specific language code like "zh_CN", "en_US"
                property JsonObject translator: JsonObject {
                    property string engine: "auto" // Run `trans -list-engines` for available engines. auto should use google
                    property string targetLanguage: "auto" // Run `trans -list-all` for available languages
                    property string sourceLanguage: "auto"
                    property string defaultTargetLanguage: "auto"
                    property string defaultSourceLanguage: "auto"
                }
            }

            property JsonObject userProfile: JsonObject {
                property string imageStyle: "initial" // "initial", "expressive", "custom"
                property string imagePath: Directories.home + "/.config/quickshell/ii/assets/profile.png"
                property string customName: ""
                property string customGreeting: ""
                property string customBio: ""
                property string avatarShape: "Cookie9Sided"
                property string avatarColor: "primary"
            }

            property JsonObject launcher: JsonObject {
                property list<string> pinnedApps: ["org.kde.dolphin", "kitty", "cmake-gui"]
            }

            property JsonObject light: JsonObject {
                property JsonObject darkMode: JsonObject {
                    property bool automatic: false
                    property string from: "18:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:00"   // Format: "HH:mm", 24-hour time
                }
                property JsonObject night: JsonObject {
                    property bool automatic: true
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
                property JsonObject antiFlashbang: JsonObject {
                    property bool enable: false
                }
            }

            property JsonObject lock: JsonObject {
                property bool useHyprlock: false
                property bool launchOnStartup: false
                property JsonObject blur: JsonObject {
                    property bool enable: true
                    property real radius: 100
                    property real extraZoom: 1.1
                }
                property JsonObject desaturate: JsonObject {
                    property bool enable: false
                    property real amount: 1.0
                }
                property JsonObject colorWash: JsonObject {
                    property bool enable: false
                    property real amount: 0.5
                }
                property JsonObject vignette: JsonObject {
                    property bool enable: false
                    property real amount: 0.7
                }

                property real centerSpacing: 20 // spacing between multiple centered widgets
                property string centerAlignment: "horizontal" // "vertical" | "horizontal"
                property bool showLockedText: true
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property bool materialShapeChars: true
                property bool rippleEffect: true
                property bool nowPlaying: true
                property bool showAlarm: true
                property bool showWeather: true
                property JsonObject zoomAnimation: JsonObject {
                    property bool enabled: true
                }
                property JsonObject notifications: JsonObject {
                    property bool enable: false // Off by default: showing notifications on the lock screen is a privacy trade-off
                    property string position: "top_right" // "top_left" | "top_right" | "bottom_left" | "bottom_right"
                    property string privacy: "redacted" // "full" | "redacted" | "countOnly"
                    property bool onlySinceLock: true // Only show notifications that arrived while locked
                    property int maxShown: 5
                    property int zoomPercent: 100 // 50-200, step 10
                    property string defaultPolicy: "show" // "show" | "hide" — apps without an explicit rule
                    property list<string> alwaysShowApps: [] // App names, case-insensitive match
                    property list<string> neverShowApps: []
                    property JsonObject filters: JsonObject {
                        property bool skipTransient: true
                        property bool skipLowUrgency: false
                        property string criticalOverride: "full" // "full" | "none" — critical notifications bypass privacy redaction
                    }
                }
            }

            property JsonObject media: JsonObject {
                property bool filterDuplicatePlayers: true
                property string priorityPlayer: ""
                property bool dynamicAlbumColors: true
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                property string position: "top_right"
                property int zoomPercent: 100 // 50-200, step 10
                property JsonObject monitor: JsonObject {
                    property bool enable: false
                    property string name: "" // Name of the monitor to show notifications on, like "eDP-1". Find out with 'hyprctl monitors' command
                }
            }

            property JsonObject oledSaver: JsonObject {
                property int cursorHideDelay: 5 // seconds of no mouse movement before the cursor hides again
                property int hintExtraDelay: 10 // extra seconds the dismiss hint stays visible after the cursor hides
            }

            property JsonObject osd: JsonObject {
                property int timeout: 2500
            }

            property JsonObject osk: JsonObject {
                property string layout: "qwerty_full"
                property bool pinnedOnStartup: false
            }

            property JsonObject overlay: JsonObject {
                property bool openingZoomAnimation: true
                property bool darkenScreen: true
                property real clickthroughOpacity: 0.8
                property JsonObject floatingImage: JsonObject {
                    property string imageSource: "https://media.tenor.com/H5U5bJzj3oAAAAAi/kukuru.gif"
                    property real scale: 0.5
                }
                property JsonObject notes: JsonObject {
                    property bool showTabs: true
                    property bool allowEditingIcon: true
                }
                property JsonObject media: JsonObject {
                    property int backgroundOpacityPercentage: 100
                    property bool useGradientMask: true
                    property bool showSlider: true
                    property int lyricSize: Appearance.font.pixelSize.larger
                }
            }

            property JsonObject overview: JsonObject {
                property bool enable: true
                property bool showWindowPreviews: true
                property real scale: 0.18 // Relative to screen size
                property real rows: 2
                property real columns: 5
                property bool orderRightLeft: false
                property bool orderBottomUp: false
                property bool showIcons: true
                property bool centerIcons: true
                property bool showOpeningAnimation: true
                property bool useWorkspaceMap: false

                property JsonObject scrollingStyle: JsonObject {

                    property int dimPercentage: 50 // 0-75
                    property string backgroundStyle: "blur" // Options: transparent, blur, dim
                    property string zoomStyle: "out"        // Options: in, out
                }
            }

            property JsonObject regionSelector: JsonObject {
                property bool showOnlyOnFocusedMonitor: false
                property JsonObject targetRegions: JsonObject {
                    property bool windows: true
                    property bool layers: true
                    property bool content: true
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                    property int selectionPadding: 5
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: false
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                property JsonObject annotation: JsonObject {
                    property bool useSatty: false
                    property bool enableInlineEditor: false
                }
            }

            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
                property int historyLength: 60
                // New keys (zero-cost on AMD; only NVIDIA/Intel invoke nvidia-smi one-shot)
                property int diskInterval: 30000
                property int gpuInterval: 3000
                // Which GPU to monitor on hybrid iGPU+dGPU systems.
                // "auto" (NVIDIA → AMD → Intel priority) | "nvidia" | "amd" | "intel"
                property string gpuPreference: "auto"
                // Toggle for Docker section popup. When false, all Docker
                // polls (docker stats, docker ps) are suppressed and the
                // events stream is not subscribed.
                property bool enableDocker: true
            }

            property JsonObject lyricsService: JsonObject {
                property bool enable: true
                property bool enableGenius: true
                property bool enableLrclib: true
            }

            property JsonObject tray: JsonObject {
                property bool monochromeIcons: true
                property bool showItemId: false
                property bool invertPinnedItems: true // Makes the below a whitelist for the tray and blacklist for the pinned area
                property list<var> pinnedItems: ["Fcitx"]
                property bool filterPassive: true
            }

            // Settings app memory management. After the user closes the
            // settings window, we wait `unloadAfterSeconds` and then drop
            // the SettingsWindow component from memory. The next open
            // rebuilds it (one-time cold-boot cost). Set to 0 to keep it
            // permanently warm (old behavior, ~70 MB of resident QML).
            property JsonObject settingsApp: JsonObject {
                property int unloadAfterSeconds: 300
            }

            property JsonObject update: JsonObject {
                property string scriptPath: ""
                property string scriptFlags: "--no-backup --no-confirm"
            }

            property JsonObject musicRecognition: JsonObject {
                property int timeout: 16
                property int interval: 4
            }

            property JsonObject search: JsonObject {
                property bool enableSystemControls: true
                property bool enableMathPreview: true
                property bool alwaysListApps: false
                property int nonAppResultDelay: 30
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property bool sloppy: false
                property bool levenshtein: false
                property bool frecency: false
                property list<var> aliases: []
                property string fileSearchDirectory: "/home"
                property bool blurFileSearchResultPreviews: false
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string bluetooth: "&"
                    property string clipboard: ";"
                    property string fileSearch: ","
                    property string emojis: ":"
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                    property string windowSearch: "#"
                    property string fileBrowser: "~"
                    property string translator: "@"
                    property string mediaDownloader: "!"
                    property string materialSymbols: "*"
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
                    property bool useCircleSelection: true
                }
                property JsonObject clipboard: JsonObject {
                    property int panelWidth: 860
                    property real listColumnRatio: 0.40
                    property bool showMetadata: true
                    property int imageHeight: 200
                    property int previewFontSize: 12
                    property bool enableSloppySearch: false
                    property JsonObject detectors: JsonObject {
                        property bool hexColor: true
                        property bool url: true
                        property bool email: true
                        property bool phone: true
                        property bool json: true
                        property bool filePath: true
                        property bool markdown: true
                        property bool number: true
                        property bool multiline: true
                    }
                }
                property bool showNowPlayingBubble: false
                property string connectStyle: "connect"  // Search rendered as embedded drop in Connect Mode
                property int baseWidth: 500
            }

            property JsonObject mediaDownloader: JsonObject {
                property bool enabled: true
                property string downloadPath: FileUtils.trimFileProtocol(`${Directories.home}/Downloads`)
                property int maxConcurrent: 2
                property string defaultFormat: "best"
                property bool embedMetadata: true
                property bool writeThumbnail: false
                property bool addChapters: true
                property string proxy: ""
                property int rateLimit: 0
                property bool throttleBypass: false
                property bool useAria2c: false
                property string extraArgs: ""
                property bool keepHistory: false
                property string lastUsedFormat: "best"
                property string videoResolution: "best"
                property string videoCodec: "any"
                property int audioBitrate: 0
                property string audioCodec: "any"
                property string lastUsedResolution: "best"
                property bool showAdvancedArgs: false
            }

            property JsonObject sidebar: JsonObject {
                property JsonObject dashboardHeader: JsonObject {
                    property string profileImageType: "custom" // "custom", "distro", "none"
                    property string profileImagePath: Directories.home + "/.config/quickshell/ii/assets/profile.png"
                    property string textMode: "username" // "username", "uptime", "none", "custom"
                    property string customText: ""
                }
                property string position: "default"
                property string sidebarStyle: "connect" // "default" | "connect"
                property bool keepRightSidebarLoaded: true
                property JsonObject translator: JsonObject {
                    property bool enable: false
                    property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                }
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                    property bool showProviderAndModelButtons: true
                    // When false, the Ai service never spawns its index
                    // probe at boot (saves one Python fork + ollama
                    // listing). The panel itself still loads on demand
                    // via policies.ai; this only gates the proactive
                    // model listing.
                    property bool enable: true
                }
                property JsonObject booru: JsonObject {
                    property bool allowNsfw: false
                    property string defaultProvider: "yandere"
                    property int limit: 20
                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                }
                property JsonObject cornerOpen: JsonObject {
                    property bool enable: false
                    property bool bottom: false
                    property bool valueScroll: true
                    property bool clickless: false
                    property int cornerRegionWidth: 250
                    property int cornerRegionHeight: 5
                    property bool visualize: false
                    property bool clicklessCornerEnd: true
                    property int clicklessCornerVerticalOffset: 1
                }

                property JsonObject quickToggles: JsonObject {
                    property string style: "android" // Options: classic, android
                    property bool useThreeWaySliders: true
                    property JsonObject android: JsonObject {
                        property int columns: 5
                        property list<var> pages: [[
                                {
                                    "size": 2,
                                    "type": "network"
                                },
                                {
                                    "size": 1,
                                    "type": "idleInhibitor"
                                },
                                {
                                    "size": 2,
                                    "type": "darkMode"
                                },
                                {
                                    "size": 1,
                                    "type": "mic"
                                },
                                {
                                    "size": 2,
                                    "type": "audio"
                                },
                                {
                                    "size": 2,
                                    "type": "nightLight"
                                },
                                {
                                    "size": 1,
                                    "type": "soundcoreAnc"
                                }
                            ]]
                    }
                }

                property JsonObject quickSliders: JsonObject {
                    property bool enable: true
                    property bool vertical: false
                    property bool showMic: true
                    property bool showGamma: true
                    property bool showVolume: true
                    property bool showBrightness: false // gamma setting also works for brightness
                }
            }

            property JsonObject screenRecord: JsonObject {
                property string savePath: Directories.videos.replace("file://", "") // strip "file://"
                property string service: "wf-recorder"
                property bool useGpu: true
                property string codec: "auto"
                property int bitrate: 8
                property int framerate: 60
                property bool showNotifications: true
            }

            property JsonObject screenSnip: JsonObject {
                property string savePath: "" // only copy to clipboard when empty
            }

            property JsonObject sounds: JsonObject {
                property bool enable: true
                property string theme: "freedesktop"
                property int volume: 100

                property bool notifications: true
                property bool volumeChange: true
                property bool battery: false
                property bool screenshot: true
                property bool pomodoro: false
                property bool alarm: true
                property bool session: false
                property bool devices: true
                property bool lock: false

                property bool alarmFadeIn: false
                property int alarmFadeInSeconds: 30

                property JsonObject notificationApps: JsonObject {
                    property string defaultPolicy: "play" // "play" | "mute"
                    property list<string> alwaysPlayApps: []
                    property list<string> neverPlayApps: []
                }

                // Per-event custom sound file overrides (absolute paths)
                property JsonObject custom: JsonObject {
                    property string notifications: ""
                    property string volumeChange: ""
                    property string battery: ""
                    property string screenshot: ""
                    property string pomodoro: ""
                    property string alarm: ""
                    property string session: ""
                    property string devices: ""
                    property string lock: ""
                }
            }

            property JsonObject soundcore: JsonObject {
                property string macAddress: ""
                property string model: "SoundcoreA3028"
            }

            property JsonObject time: JsonObject {
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "hh:mm"
                property string secondsFormat: "ss"
                property string shortDateFormat: "dd/MM"
                property string longDateFormat: "dd/MM/yyyy"
                property string dateWithYearFormat: "dd/MM/yyyy"
                property string dateFormat: "dd/MM, ddd"
                property int firstDayOfWeek: 6 // 0: Monday, 1: Tuesday, 2: Wednesday, 3: Thursday, 4: Friday, 5: Saturday, 6: Sunday

                property JsonObject pomodoro: JsonObject {
                    property int breakTime: 300
                    property int cyclesBeforeLongBreak: 4
                    property int focus: 1500
                    property int longBreak: 900
                }
                property list<var> worldClocks: []
                property bool secondPrecision: true

                property JsonObject alarms: JsonObject {
                    property bool useFullscreenPopup: false
                    property bool showAnalogClock: true
                    property bool showWorldClocks: true
                    property bool showAlarmsSection: true
                }
            }

            property JsonObject updates: JsonObject {
                property bool enableCheck: true
                property int checkInterval: 120 // minutes
                property int adviseUpdateThreshold: 75 // packages
                property int stronglyAdviseUpdateThreshold: 200 // packages
            }

            property JsonObject wallpaperSelector: JsonObject {
                property bool useSystemFileDialog: false
                property list<var> directories: []
                property bool useCustomDefaultPath: false
                property string customDefaultPath: FileUtils.trimFileProtocol(`${Directories.pictures}/Wallpapers`)
            }

            property JsonObject windows: JsonObject {
                property bool showTitlebar: true // Client-side decoration for shell apps
                property bool centerTitle: true
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }

            property JsonObject workSafety: JsonObject {
                property JsonObject enable: JsonObject {
                    property bool wallpaper: false
                    property bool clipboard: false
                }
                property JsonObject triggerCondition: JsonObject {
                    property list<string> networkNameKeywords: ["airport", "cafe", "college", "company", "eduroam", "free", "guest", "public", "school", "university"]
                    property list<string> fileKeywords: ["anime", "booru", "ecchi", "hentai", "yande.re", "konachan", "breast", "nipples", "pussy", "nsfw", "spoiler", "girl"]
                    property list<string> linkKeywords: ["hentai", "porn", "sukebei", "hitomi.la", "rule34", "gelbooru", "fanbox", "dlsite"]
                }
            }

            property JsonObject wallpapers: JsonObject {
                property string service: "wallhaven" // "unsplash" or "wallhaven"
                property string sort: "favourites"
                property bool showAnimeResults: false // only for wallhaven service
                property JsonObject paths: JsonObject {
                    property string download: FileUtils.trimFileProtocol(`${Directories.home}/Pictures/Wallpapers`)
                    property string nsfw: FileUtils.trimFileProtocol(`${Directories.home}/Pictures/Wallpapers/NSFW`)
                }
            }

            property JsonObject waffles: JsonObject {
                // Some spots are kinda janky/awkward. Setting the following to
                // false will make (some) stuff also be like that for accuracy.
                // Example: the right-click menu of the Start button
                property JsonObject tweaks: JsonObject {
                    property bool switchHandlePositionFix: true
                    property bool smootherMenuAnimations: true
                    property bool smootherSearchBar: true
                }
                property JsonObject bar: JsonObject {
                    property bool bottom: true
                    property bool leftAlignApps: false
                }
                property JsonObject actionCenter: JsonObject {
                    property list<string> toggles: ["network", "bluetooth", "easyEffects", "powerProfile", "idleInhibitor", "nightLight", "darkMode", "antiFlashbang", "cloudflareWarp", "mic", "musicRecognition", "notifications", "onScreenKeyboard", "gameMode", "screenSnip", "colorPicker", "videoEditor"]
                }
                property JsonObject calendar: JsonObject {
                    property bool force2CharDayOfWeek: true
                }
            }
        }
    }
}
