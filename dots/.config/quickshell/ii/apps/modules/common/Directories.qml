pragma Singleton
pragma ComponentBehavior: Bound
import QtCore
import QtQuick
import Quickshell
import qs.modules.common.functions

/**
 * Paths for standalone apps. Same names and values as the shell's Directories,
 * without its startup work: that one runs `rm -rf` on shell caches (cover art,
 * cliphist, previews) and mkdirs a dozen folders, which an app must never do
 * while the shell is using them.
 */
Singleton {
    // XDG dirs, with "file://"
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
    readonly property string desktop: StandardPaths.standardLocations(StandardPaths.DesktopLocation)[0] || (home + "/Desktop")

    // Plain paths
    readonly property string shellConfig: FileUtils.trimFileProtocol(`${config}/illogical-impulse`)
    readonly property string generatedMaterialThemePath: FileUtils.trimFileProtocol(`${state}/user/generated/colors.json`)
    // apps/ links these back to the shell's folders.
    readonly property string assetsPath: Quickshell.shellPath("assets")
    readonly property string scriptPath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts"))
    // Per-app state, e.g. `${appsState}/files.json`.
    readonly property string appsState: FileUtils.trimFileProtocol(`${state}/user/apps`)
}
