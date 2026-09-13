pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtCore
import QtQuick
import Quickshell

Singleton {
    // XDG Dirs, with "file://"
    readonly property string home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0] || ""
    readonly property string config: StandardPaths.standardLocations(StandardPaths.ConfigLocation)[0] || ""
    readonly property string state: StandardPaths.standardLocations(StandardPaths.StateLocation)[0] || ""
    readonly property string cache: StandardPaths.standardLocations(StandardPaths.CacheLocation)[0] || ""
    readonly property string genericCache: StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0] || ""
    readonly property string documents: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0] || ""
    readonly property string downloads: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0] || ""
    readonly property string pictures: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0] || ""
    readonly property string music: StandardPaths.standardLocations(StandardPaths.MusicLocation)[0] || ""
    readonly property string videos: StandardPaths.standardLocations(StandardPaths.MoviesLocation)[0] || ""
    readonly property string runtime: FileUtils.trimFileProtocol(StandardPaths.standardLocations(StandardPaths.RuntimeLocation)[0] || "/run/user/1000")

    readonly property string losslessCutDesktopPath: FileUtils.trimFileProtocol(`${Directories.home}/.local/share/applications/losslesscut.desktop`)

    readonly property string cliPath: FileUtils.trimFileProtocol(`${Directories.home}/.local/bin/vynx`)

    // Config paths

    property string generalConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/GeneralConfig.qml`)
    property string barConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/BarConfig.qml`)
    property string backgroundConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/BackgroundConfig.qml`)
    property string interfaceConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/InterfaceConfig.qml`)
    property string hyprlandConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/HyprlandConfig.qml`)
    property string servicesConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/ServicesConfig.qml`)
    property string advancedConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/modules/settings/AdvancedConfig.qml`)

    // Other dirs used by the shell, without "file://"
    property string assetsPath: Quickshell.shellPath("assets")
    property string scriptPath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts"))
    property string favicons: FileUtils.trimFileProtocol(`${Directories.cache}/media/favicons`)
    property string coverArt: FileUtils.trimFileProtocol(`${Directories.cache}/media/coverart`)
    // Reconstructible artwork extracted from files selected by the local
    // player. It must not share the remote-cover directory that is cleared at
    // startup, otherwise reopening an offline local session loses its art.
    property string localMediaCoverCache: FileUtils.trimFileProtocol(`${Directories.cache}/media/local-media/covers`)
    property string tempImages: `/tmp/quickshell-${SystemInfo.username}/media/images`
    property string booruPreviews: FileUtils.trimFileProtocol(`${Directories.cache}/media/boorus`)
    property string booruDownloads: FileUtils.trimFileProtocol(Directories.pictures + "/homework")
    property string booruDownloadsNsfw: FileUtils.trimFileProtocol(Directories.pictures + "/homework/🌶️")
    property string latexOutput: FileUtils.trimFileProtocol(`${Directories.cache}/media/latex`)
    property string shellConfig: FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse`)
    property string shellConfigName: "config.json"
    property string shellConfigPath: `${Directories.shellConfig}/${Directories.shellConfigName}`
    // The setup script's standing request to run the Welcome once, consumed
    // and deleted by shell.qml. Written only when the install was a first
    // install AND no running shell answered the IPC call that would have
    // opened it on the spot.
    property string welcomeRequestPath: FileUtils.trimFileProtocol(`${Directories.state}/user/welcome_pending`)
    property string todoPath: FileUtils.trimFileProtocol(`${Directories.state}/user/todo.json`)
    property string todoDoneHistoryPath: FileUtils.trimFileProtocol(`${Directories.state}/user/todo_done.json`)
    property string appUsagePath: FileUtils.trimFileProtocol(`${Directories.state}/user/app_usage.json`)
    // One file per local day, written by the app_stats sampler.
    property string appStats: FileUtils.trimFileProtocol(`${Directories.state}/user/app_stats`)
    property string commandsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/commands.json`)
    // User-authored shortcut collections. Hyprland remains a generated,
    // read-only page and is deliberately not duplicated into this file.
    property string keybindsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/keybinds.json`)
    property string keybindTemplatesPath: FileUtils.trimFileProtocol(Quickshell.shellPath("defaults/keybinds/templates.json"))
    property string keybindImporterPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/keybinds/import_keybinds.py`)
    property string keybindAiCategorizerPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/keybinds/ai_categorize.py`)
    property string notesPath: FileUtils.trimFileProtocol(`${Directories.state}/user/notes.json`)
    /// Where a note's drawing is written. Beside notes.json rather than in Pictures: a
    /// sketch here is part of a note, not a file the user filed anywhere.
    property string noteSketchesDir: FileUtils.trimFileProtocol(`${Directories.state}/user/note_sketches`)

    // ── Notes store ─────────────────────────────────────────────────────────
    /// Where the notes app keeps everything.
    ///
    /// An index plus one document per note, rather than the single `notes.json` above.
    /// That file is read and rewritten whole on every keystroke, which is already why a
    /// sketch is stored there as a path instead of pixels; with drawings, images and
    /// history in it, one file would mean megabytes travelling through the typing loop.
    /// Splitting it also means the note list, the desktop widgets and search read only
    /// the small index, and typing in one note never rewrites another.
    ///
    /// Assets are filed under the note that owns them, so deleting a note deletes a
    /// folder — today a sketch is orphaned forever because nothing records whose it was.
    ///
    /// Nothing is created here. The store creates its own directories on first write: a
    /// shell whose owner never opens Notes should not grow the folder.
    property string notesDir: FileUtils.trimFileProtocol(`${Directories.state}/user/notes`)
    property string notesIndexPath: `${Directories.notesDir}/index.json`
    property string notesDocsDir: `${Directories.notesDir}/docs`
    property string notesAssetsDir: `${Directories.notesDir}/assets`
    property string notesRevisionsDir: `${Directories.notesDir}/revisions`
    /// Where `notes.json` is moved once it has been migrated. Renamed rather than deleted:
    /// it is the only copy of everything written before the app existed.
    property string notesLegacyBackupPath: `${Directories.notesPath}.migrated`
    property string notesLinkPreviewsCacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/media/link_previews`)
    property string conflictCachePath: FileUtils.trimFileProtocol(`${Directories.cache}/conflict-killer`)
    property string notificationsPath: FileUtils.trimFileProtocol(`${Directories.cache}/notifications/notifications.json`)
    property string lyricsPath: FileUtils.trimFileProtocol(`${Directories.cache}/lyrics/lyrics.json`)
    // Hand-written .lrc keyed by track. Lives in state, not cache: it can't be
    // re-fetched from anywhere if it gets cleared.
    property string customLyricsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/custom-lyrics.json`)
    property string generatedMaterialThemePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/colors.json`)
    property string wallpaperPreviewColorsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/wallpaper_preview_colors.json`)
    property string lockscreenColorsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/lockscreen_colors.json`)
    // Public holidays fetched from Nager.Date, one entry per "<COUNTRY>-<YEAR>".
    property string holidaysCachePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/holidays.json`)
    // AI summary of the commits behind the fork's remote, keyed by the range.
    property string shellUpdateSummaryPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/shell_update_summary.json`)
    // ESPN scoreboards and per-game summaries shared by the sports widgets
    // and the timetable. Kept outside calendar storage by design.
    property string sportsCachePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/sports.json`)
    // iCalUID -> Google colorId, plus the account palette. The synced .ics files
    // carry no COLOR, so this is the only place that mapping can live locally.
    property string googleCalendarColorsPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/google_calendar_colors.json`)
    property string generateLockscreenColorsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/generate-lockscreen-colors.sh`)
    property string gammaControlScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/brightness/ii-gamma-control`)
    property string displayColorFilterWriterPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/display/write_color_filter.py`)
    property string displayColorFilterGeneratedPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/display-color-filter`)
    property string generatedWallpaperCategoryPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/wallpaper/category.txt`)
    property string cliphistDecode: FileUtils.trimFileProtocol(`/tmp/quickshell-${SystemInfo.username}/media/cliphist`)
    property string screenshotTemp: `/tmp/quickshell-${SystemInfo.username}/media/screenshot`
    property string wallpaperSwitchScriptPath: FileUtils.trimFileProtocol(
        `${Directories.scriptPath}/colors/switchwall.sh`
    )
    property string defaultAiPrompts: Quickshell.shellPath("defaults/ai/prompts")
    property string defaultThemes: Quickshell.shellPath("defaults/themes")
    property string customThemes: `${Directories.shellConfig}/themes`
    property string userAiPrompts: FileUtils.trimFileProtocol(`${Directories.shellConfig}/ai/prompts`)
    property string userActions: FileUtils.trimFileProtocol(`${Directories.shellConfig}/actions`)
    property string aiChats: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/chats`)
    property string aiUsage: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/usage.json`)
    // Composer drafts are intentionally isolated from settings and transcript
    // files; the store owns atomic writes and recovery for this directory.
    property string aiDrafts: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/drafts`)
    // One file per conversation, plus the index that lists them. The flat
    // chats above are what came before, and are imported once.
    property string aiSessions: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/sessions`)
    property string aiExports: FileUtils.trimFileProtocol(`${Directories.documents}/ai-chats`)
    property string aiSessionsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/ai_sessions.py`)
    property string aiDraftsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/ai_drafts.py`)
    property string aiAttachScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/ai_attach.py`)
    property string aiSettingsIndexPath: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/settings_index.json`)
    property string aiLastAnswer: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/last_answer.json`)
    property string aiSettingsIndexScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/ai_settings_index.py`)
    property string aiWebScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/ai_web.py`)
    property string aiRagScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/ai_rag.py`)
    property string aiRagIndexDir: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/rag_index`)
    property string aiTranslationScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/gemini-translate.sh`)
    property string recordScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/record.sh`)
    property string processVideoScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/compress_video.py`)
    property string extractColorsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/wallpapers/extract-colors.sh`)
    property string colorCachePath: FileUtils.trimFileProtocol(`${Directories.cache}/wallpapers/colors.json`)
    property string userAvatarPathAccountsService: FileUtils.trimFileProtocol(`/var/lib/AccountsService/icons/${SystemInfo.username}`)
    property string userAvatarPathRicersAndWeirdSystems: FileUtils.trimFileProtocol(`${Directories.home}.face`)
    property string userAvatarPathRicersAndWeirdSystems2: FileUtils.trimFileProtocol(`${Directories.home}.face.icon`)
    property string screenshareStateScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/screenShare/screensharestate.sh`)
    property string screenshareStatePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/screenshare/apps.txt`)
    property string geniusLyricsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/lyrics/genius-lyrics.js`)
    property string ytmusicLyricsScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/lyrics/ytmusic-lyrics-wrapper.sh`)
    property string localSendDownloadPath: FileUtils.trimFileProtocol(`${Directories.home}/Downloads/localsend`)
    // Widget extensions
    property string userWidgetsPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/user_widgets`)
    property string widgetExtensionsPath: `${Directories.shellConfig}/widget_extensions.json`
    property string widgetBackupsPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/user_widgets/.backups`)
    property string userProfileImagePath: FileUtils.trimFileProtocol(`${Directories.shellConfig}/profile.png`)

    // Cleanup on init
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", `${shellConfig}`]);
        Quickshell.execDetached(["mkdir", "-p", `${favicons}`]);
        Quickshell.execDetached(["bash", "-c", `rm -rf '${coverArt}'; mkdir -p '${coverArt}'`]);
        Quickshell.execDetached(["bash", "-c", `rm -rf '${booruPreviews}'; mkdir -p '${booruPreviews}'`]);
        Quickshell.execDetached(["bash", "-c", `rm -rf '${latexOutput}'; mkdir -p '${latexOutput}'`]);
        Quickshell.execDetached(["bash", "-c", `rm -rf '${cliphistDecode}'; mkdir -p '${cliphistDecode}'`]);
        Quickshell.execDetached(["mkdir", "-p", `${aiChats}`]);
        Quickshell.execDetached(["mkdir", "-p", `${FileUtils.parentDirectory(aiUsage)}`]);
        Quickshell.execDetached(["mkdir", "-p", `${FileUtils.parentDirectory(keybindsPath)}`]);
        Quickshell.execDetached(["mkdir", "-p", `${aiRagIndexDir}`]);
        Quickshell.execDetached(["mkdir", "-p", `${aiDrafts}`]);
        Quickshell.execDetached(["mkdir", "-p", `${appStats}`]);
        Quickshell.execDetached(["mkdir", "-p", `${FileUtils.parentDirectory(holidaysCachePath)}`]);
        Quickshell.execDetached(["mkdir", "-p", `${FileUtils.parentDirectory(customLyricsPath)}`]);
        Quickshell.execDetached(["mkdir", "-p", `${userActions}`]);
        Quickshell.execDetached(["mkdir", "-p", `${userWidgetsPath}`]);
        Quickshell.execDetached(["rm", "-rf", `${tempImages}`]);
        Quickshell.execDetached(["mkdir", "-p", `${screenshotTemp}`]);
    }

    // The name of the user is read by a process, so for the first moments of
    // a session it is still the placeholder and every /tmp path above points
    // at a folder for a user who does not exist. The pass above therefore made
    // the wrong folder; this one makes the right one as soon as the name lands.
    onCliphistDecodeChanged: Quickshell.execDetached(["bash", "-c", `rm -rf '${cliphistDecode}'; mkdir -p '${cliphistDecode}'`])
}
