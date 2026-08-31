pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias states: persistentStatesJsonAdapter
    property string fileDir: Directories.state
    property string fileName: "states.json"
    property string filePath: `${root.fileDir}/${root.fileName}`

    property bool ready: false
    property string previousHyprlandInstanceSignature: ""
    property bool isNewHyprlandInstance: previousHyprlandInstanceSignature !== states.hyprlandInstanceSignature
    // See Config.qml for the rationale on these guards. Same pattern: avoid
    // clobbering the on-disk states.json with QML defaults during transient
    // file inaccessibility, and write atomically so a kill mid-save cannot
    // corrupt the file.
    property bool blockWrites: false
    property real initTimestamp: Date.now()
    property int missingFileGracePeriod: 5000
    property int missingFileRetryInterval: 1500
    // Same write guard as Config.qml — prevents hot-reload race condition.
    // Increased from 3000 to 5000 to match Config.qml.
    property int writeGuardDelay: 5000

    property bool applyingPersistentState: false

    function tryMigrateAndSyncUserData() {
        if (!root.ready || !Config.ready || root.applyingPersistentState) return;

        root.applyingPersistentState = true;
        try {
            // One-shot migration from Config to Persistent if never migrated
            if (root.states.migrations.presetUserDataVersion < 1) {
                // Search aliases
                if (Config.options.search && Config.options.search.aliases && Config.options.search.aliases.length > 0) {
                    if (!root.states.search.aliases || root.states.search.aliases.length === 0) {
                        root.states.search.aliases = Array.from(Config.options.search.aliases);
                    }
                }

                // Google Drive
                if (Config.options.googleDrive) {
                    const src = Config.options.googleDrive;
                    const dst = root.states.googleDrive;
                    if (src.enabled !== undefined) dst.enabled = src.enabled;
                    if (src.syncInterval) dst.syncInterval = src.syncInterval;
                    if (src.syncOnBoot !== undefined) dst.syncOnBoot = src.syncOnBoot;
                    if (src.syncOnNetworkChange !== undefined) dst.syncOnNetworkChange = src.syncOnNetworkChange;
                    if (src.bandwidthLimitKbps !== undefined) dst.bandwidthLimitKbps = src.bandwidthLimitKbps;
                    if (src.pauseOnMeteredConnection !== undefined) dst.pauseOnMeteredConnection = src.pauseOnMeteredConnection;
                    if (src.backupFolders && src.backupFolders.length > 0) dst.backupFolders = Array.from(src.backupFolders);
                    if (src.excludePatterns && src.excludePatterns.length > 0) dst.excludePatterns = Array.from(src.excludePatterns);
                    if (src.driveBasePath !== undefined) dst.driveBasePath = src.driveBasePath;
                    if (src.notifyOnComplete !== undefined) dst.notifyOnComplete = src.notifyOnComplete;
                    if (src.notifyOnError !== undefined) dst.notifyOnError = src.notifyOnError;
                    if (src.keepVersions !== undefined) dst.keepVersions = src.keepVersions;
                    if (src.deleteRemoteOrphans !== undefined) dst.deleteRemoteOrphans = src.deleteRemoteOrphans;
                    if (src.onlyModifiedSinceLastSync !== undefined) dst.onlyModifiedSinceLastSync = src.onlyModifiedSinceLastSync;
                    if (src.lastSyncTime) dst.lastSyncTime = src.lastSyncTime;
                    if (src.lastSyncStatus) dst.lastSyncStatus = src.lastSyncStatus;
                    if (src.lastSyncFileCount !== undefined) dst.lastSyncFileCount = src.lastSyncFileCount;
                    if (src.lastSyncSizeMb !== undefined) dst.lastSyncSizeMb = src.lastSyncSizeMb;
                    if (src.syncHistory && src.syncHistory.length > 0) dst.syncHistory = Array.from(src.syncHistory);
                    if (src.totalDriveUsageMb !== undefined) dst.totalDriveUsageMb = src.totalDriveUsageMb;
                    if (src.driveQuotaMb !== undefined) dst.driveQuotaMb = src.driveQuotaMb;
                    if (src.driveBackupUsageMb !== undefined) dst.driveBackupUsageMb = src.driveBackupUsageMb;
                }

                root.states.migrations.presetUserDataVersion = 1;
            }

            // Sync Persistent values to Config.options as a compatibility mirror
            if (Config.options.search) {
                Config.options.search.aliases = Array.from(root.states.search.aliases || []);
            }
            if (Config.options.googleDrive) {
                const src = root.states.googleDrive;
                const dst = Config.options.googleDrive;
                dst.enabled = src.enabled;
                dst.syncInterval = src.syncInterval;
                dst.syncOnBoot = src.syncOnBoot;
                dst.syncOnNetworkChange = src.syncOnNetworkChange;
                dst.bandwidthLimitKbps = src.bandwidthLimitKbps;
                dst.pauseOnMeteredConnection = src.pauseOnMeteredConnection;
                dst.backupFolders = Array.from(src.backupFolders || []);
                dst.excludePatterns = Array.from(src.excludePatterns || []);
                dst.driveBasePath = src.driveBasePath;
                dst.notifyOnComplete = src.notifyOnComplete;
                dst.notifyOnError = src.notifyOnError;
                dst.keepVersions = src.keepVersions;
                dst.deleteRemoteOrphans = src.deleteRemoteOrphans;
                dst.onlyModifiedSinceLastSync = src.onlyModifiedSinceLastSync;
                dst.lastSyncTime = src.lastSyncTime;
                dst.lastSyncStatus = src.lastSyncStatus;
                dst.lastSyncFileCount = src.lastSyncFileCount;
                dst.lastSyncSizeMb = src.lastSyncSizeMb;
                dst.syncHistory = Array.from(src.syncHistory || []);
                dst.totalDriveUsageMb = src.totalDriveUsageMb;
                dst.driveQuotaMb = src.driveQuotaMb;
                dst.driveBackupUsageMb = src.driveBackupUsageMb;
            }
        } finally {
            root.applyingPersistentState = false;
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root.ready) {
                root.tryMigrateAndSyncUserData();
            }
        }
    }

    onReadyChanged: {
        root.previousHyprlandInstanceSignature = root.states.hyprlandInstanceSignature;
        root.states.hyprlandInstanceSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "";
        root.migrateAiModelId();
        if (root.ready && Config.ready) {
            root.tryMigrateAndSyncUserData();
        }
    }

    /**
     * The AI provider and model used to be two keys, and half a pair aimed one
     * provider's endpoint at a model it did not serve. They are one id now.
     *
     * states.json has no raw pass the way config.json does — nothing reads it
     * except the adapter — so the only way to read a retired key is to keep it
     * declared. Both are emptied here once their value has been folded in, and
     * an empty pair is what tells this it has already run.
     */
    function migrateAiModelId() {
        const legacyProvider = root.states.ai.provider;
        const legacyModel = root.states.ai.model;
        if (legacyProvider.length === 0 || legacyModel.length === 0)
            return;
        root.states.ai.modelId = `${legacyProvider}:${legacyModel}`;
        root.states.ai.provider = "";
        root.states.ai.model = "";
        console.log(`[Persistent] Migrated states.ai to modelId ${root.states.ai.modelId}`);
    }

    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.reload();
        }
    }

    Timer {
        id: fileWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (root.blockWrites) {
                return;
            }
            if (!root.ready) {
                fileWriteTimer.restart();
                return;
            }
            // Extra guard: see Config.qml for rationale.
            const elapsed = Date.now() - root.initTimestamp;
            if (elapsed < root.writeGuardDelay) {
                fileWriteTimer.restart();
                return;
            }
            persistentStatesFileView.writeAdapter();
        }
    }

    Timer {
        id: missingFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: {
            persistentStatesFileView.reload();
        }
    }

    Component.onDestruction: {
        root.blockWrites = true;
    }

    FileView {
        id: persistentStatesFileView
        path: root.filePath

        watchChanges: true
        atomicWrites: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: { if (root.ready && !root.blockWrites) fileWriteTimer.restart(); }
        onLoaded: {
            root.ready = true;
            if (Config.ready) {
                root.tryMigrateAndSyncUserData();
            }
        }
        onLoadFailed: error => {
            console.log("Failed to load persistent states file:", error);
            if (error != FileViewError.FileNotFound) {
                return;
            }
            const elapsed = Date.now() - root.initTimestamp;
            if (elapsed > root.missingFileGracePeriod && !root.ready) {
                fileWriteTimer.restart();
                root.ready = true;
            } else {
                missingFileRetryTimer.restart();
            }
        }

        Component.onDestruction: {
            persistentStatesFileView.blockWrites = true;
        }

        adapter: JsonAdapter {
            id: persistentStatesJsonAdapter

            property string hyprlandInstanceSignature: ""

            property JsonObject migrations: JsonObject {
                property int presetUserDataVersion: 0
            }

            property JsonObject search: JsonObject {
                property list<var> aliases: []
                property list<string> recentEmojis: []
                property list<string> recentQueries: []
                property list<string> pinnedEntries: []
                property list<var> panelUsage: []
            }

            // Typing test scores. Only aggregate metrics are kept — never the
            // target text and never the keys that were actually pressed.
            property JsonObject typingTest: JsonObject {
                property list<var> recentResults: []
                property list<var> personalBests: []
                // Lifetime tallies. They outlive `recentResults`, which is
                // capped, so "tests completed" stays true after the oldest
                // results have been pruned away.
                property int testsStarted: 0
                property int testsCompleted: 0
                property real secondsTyping: 0
                // [{ d: "YYYY-MM-DD", n: tests }], one entry per active day,
                // bounded to roughly a year — enough for the activity map and
                // far smaller than keeping every result to derive it.
                property list<var> activity: []
            }

            property JsonObject googleDrive: JsonObject {
                property bool enabled: false
                property string syncInterval: "3d" // "1h", "4h", "1d", "2d", "3d"
                property bool syncOnBoot: true
                property bool syncOnNetworkChange: false
                property int bandwidthLimitKbps: 0
                property bool pauseOnMeteredConnection: true
                property list<string> backupFolders: []
                property list<string> excludePatterns: ["*.tmp", "*.swp", "*.lock", "node_modules/", ".git/", "__pycache__/"]
                property string driveBasePath: ""
                property bool notifyOnComplete: true
                property bool notifyOnError: true
                property int keepVersions: 3
                property bool deleteRemoteOrphans: false
                property bool onlyModifiedSinceLastSync: false
                property string lastSyncTime: ""
                property string lastSyncStatus: ""
                property int lastSyncFileCount: 0
                property real lastSyncSizeMb: 0.0
                property list<var> syncHistory: []
                property real totalDriveUsageMb: 0.0
                property real driveQuotaMb: 0.0
                property real driveBackupUsageMb: 0.0
            }

            property JsonObject ai: JsonObject {
                // Catalog id of the model that answers, "provider:model".
                property string modelId: "google:gemini-3.6-flash"
                // Defaults for a new chat. The older fields below are kept so
                // states written by the first AI rebuild can be migrated.
                property string defaultModelId: ""
                property real defaultTemperature: -1
                property string defaultThinkingLevel: ""
                property string defaultPersonaId: ""
                // Retired in favour of modelId, kept declared only so an old
                // file can be read once. See migrateAiModelId().
                property string provider: ""
                property string model: ""
                property real temperature: 0.5
                // How hard the model is asked to think: off, low, medium or
                // high. Each provider maps it to its own knob.
                property string thinkingLevel: "medium"
                // Catalog ids of the last few models picked, newest first, so
                // the picker can offer them without scrolling the whole list.
                property list<string> recentModels: []
                // Provider groups folded away in the model picker, so a long
                // list of accounts stays folded between openings.
                property list<string> collapsedModelGroups: []
                // Which persona new chats open with. Empty means the system
                // prompt from the settings, as before personas existed.
                property string personaId: ""
            }

            property JsonObject background: JsonObject {
                property bool widgetsMigrated: false
                property bool lockBehaviorMigrated: false
                property JsonObject mediaMode: JsonObject {
                    property real userScrollOffset: 0
                }
            }

            property JsonObject cheatsheet: JsonObject {
                property int tabIndex: 0
                property list<string> sectionOrder: []
                // Empty selects the generated Hyprland page. User page ids are
                // stable across edits and imports, so the last collection can
                // be restored without coupling it to its list position.
                property string keybindPageId: ""
                // The page rail follows the timetable sidebar pattern and
                // remembers whether the user left it expanded.
                property bool keybindSidebarVisible: true
                // "day" | "threeDay" | "week" | "month" — timetable range.
                property string timetableView: "month"
                property bool timetableShowUpcoming: true
                // "comfortable" | "compact" | "dots" — month-cell density.
                property string timetableMonthDensity: "compact"
                property bool timetableCollapseRecurring: true
                // Horizon buckets hidden in the month view's upcoming rail.
                property list<string> timetableCollapsedUpcomingGroups: []
                // Pixels per hour in the timetable grid. WeekView constrains
                // writes to its discrete zoom scale.
                property int timetableSlotHeight: 168
                // One-shot migrations can change the comfortable default
                // without overwriting a later zoom choice on every reopen.
                property int timetableSlotHeightVersion: 0
                // `occurrence-ms|uid|offset` and daily-summary keys. Pruned by
                // CalendarNotifier so notifications do not repeat after reload.
                property list<string> timetableNotified: []
                // Pending calendar reminder snoozes. Each DTO is reconstructed
                // by CalendarNotifier; no CalendarService object crosses disk.
                property list<var> timetableSnoozes: []
                // Gmail account + attachment identity for calendar files the
                // user opted into importing. Keeps periodic scans idempotent.
                property list<string> timetableGmailIcsImports: []
                // The Outlook equivalent. Each entry includes the account,
                // message attachment identity and a content digest.
                property list<string> timetableOutlookIcsImports: []
            }

            property JsonObject clipboard: JsonObject {
                property list<string> pinnedEntries: []
                // cliphist exposes stable IDs but no timestamps. These compact
                // records let its opt-in retention policy age entries without
                // guessing from their content or deleting pinned data.
                property list<var> historySeen: []
            }

            property JsonObject sidebar: JsonObject {
                property JsonObject policies: JsonObject {
                    property int tab: 0
                        property JsonObject phone: JsonObject {
                            property string activeDeviceId: ""
                            property list<string> recentDeviceIds: []
                            property string cachedNotificationsJson: ""
                            property JsonObject scrcpy: JsonObject {
                                property list<string> recentPackages: []
                            }
                        }
                }
                property JsonObject bottomGroup: JsonObject {
                    property bool collapsed: false
                    property int tab: 0
                    property int todoTab: 0
                    property int timerTab: 0
                }
            }

            property JsonObject booru: JsonObject {
                property bool allowNsfw: false
                property string provider: "yandere"
            }

            property JsonObject hyprland: JsonObject {
                property string layout: "dwindle"
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
                property real expiresAt: 0 // Epoch ms; 0 means indefinite. Must be real, not int
                property real durationMinutes: 0 // Preset the timed session started from, 0 if none
                property string sessionId: ""
            }

            property JsonObject keyboardBacklight: JsonObject {
                property bool idleOffActive: false // Whether the idle monitor is the reason it's off
                property int savedLevel: 0 // Level to return to once input resumes
            }

            property JsonObject nightLight: JsonObject {
                property bool hasManual: false // Whether a manual toggle is currently overriding automatic mode
                property bool manualActive: false
                property real manualSetAt: 0 // Epoch ms, used to tell whether the override has expired
                property int gamma: 100
                property string gammaByMonitorJson: "{}"
                property string sessionId: ""
            }

            property JsonObject displayColorFilter: JsonObject {
                property string profilesJson: "{}"
            }

            // Runtime state of services/Modes.qml: what is running and what
            // to put back when it ends. Definitions are in Config.
            property JsonObject modes: JsonObject {
                property string activeId: ""
                property string activeSource: "" // manual | schedule | app | game | …
                property real activeSince: 0 // Epoch ms; must be real
                property real activeEndsAt: 0 // Epoch ms, 0 = open-ended
                property list<var> snapshot: [] // [{type, was, set, extra, action}] in apply order
                property list<string> failed: []
                property string lastUsedModeId: ""
                property list<string> suppressed: [] // stopped by hand while triggers still held
                property list<string> suppressedRoutines: [] // same, for `while` routines
                property list<var> history: [] // newest first, capped
                // Running `while` routines: [{id, source, since, snapshot, failed}]
                property list<var> routineRuns: []
                // Last fire time of `once` routines for cooldowns: [{id, t}]
                property list<var> routineFired: []
                // Action sequences paused on a wait or a delay, resumed by the
                // engine when due: [{kind, id, index, dueAt, resumed, source, failed}]
                property list<var> pendingSteps: []
            }

            property JsonObject overlay: JsonObject {
                property list<string> open: ["crosshair", "recorder", "media", "volumeMixer", "resources"]
                property JsonObject crosshair: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 827
                    property real y: 441
                    property real width: 250
                    property real height: 100
                }
                property JsonObject media: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 827
                    property real y: 441
                    property real width: 250
                    property real height: 100
                }
                property JsonObject floatingImage: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1650
                    property real y: 390
                    property real width: 0
                    property real height: 0
                }
                property JsonObject fpsLimiter: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 1570
                    property real y: 615
                    property real width: 280
                    property real height: 80
                }
                property JsonObject recorder: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 80
                    property real width: 350
                    property real height: 130
                }
                property JsonObject resources: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1500
                    property real y: 770
                    property real width: 350
                    property real height: 200
                    property int tabIndex: 0
                }
                property JsonObject volumeMixer: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 280
                    property real width: 350
                    property real height: 600
                    property int tabIndex: 0
                }
                property JsonObject notes: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property real x: 1400
                    property real y: 42
                    property real width: 460
                    property real height: 330
                    property int tabIndex: 0
                }
                property JsonObject discordVoice: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property real x: 80
                    property real y: 600
                    property real width: 344
                    property real height: 200
                }
            }

            property JsonObject phoneCamera: JsonObject {
                property string lastMode: "wifi"   // "wifi" | "usb"
                property string lastIp: ""
                property int lastPort: 4747
            }

            property JsonObject phoneMic: JsonObject {
                property string originalDefaultSink: ""
                property string lastBackend: ""     // "scrcpy" | "droidcam"
                property string lastMode: "wifi"
                property string lastIp: ""
                property int lastPort: 4748
            }

            property JsonObject screenRecord: JsonObject {
                property bool active: false
                property int seconds: 0
                property bool loading: false
                property bool paused: false
            }

            property JsonObject settings: JsonObject {
                property list<string> collapsedGroups: []
                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrainsMono Nerd Font"
                    property string monospace: "JetBrainsMono Nerd Font"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk"
                    property bool roundnessFull: false
                }
            }

            property JsonObject timer: JsonObject {
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property int start: 0
                    property bool isBreak: false
                    property int cycle: 0
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    property int start: 0
                    property list<var> laps: []
                }
                property list<var> countdowns: []
                // Last duration dialled into the sidebar's timer picker.
                property JsonObject countdownDraft: JsonObject {
                    property int hours: 0
                    property int minutes: 5
                    property int seconds: 0
                }
            }
            property list<var> alarms: []
            property JsonObject water: JsonObject {
                property int glassesDrunk: 0
                property string lastDate: ""
                property real lastNotify: 0
            }
            property JsonObject media: JsonObject {
            }

            property JsonObject wallpaper: JsonObject {
                property list<string> favourites: []
                property list<string> favouriteDirectories: []
            }
        }
    }
}
