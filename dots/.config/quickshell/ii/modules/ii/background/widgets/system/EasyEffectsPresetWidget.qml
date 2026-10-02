import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.modules.ii.easyEffects
import qs.modules.ii.easyEffects.tabs

/**
 * The EasyEffects app's preset hero on the desktop: the same card (texture, shape, name,
 * chain, buttons), standing (portrait) or lying (landscape). The buttons work: "Edit
 * effects" opens the app on its Effects page, "Bypass" switches the effects off or on.
 *
 * What it shows is in Config.options.easyEffects.widget and shared by both shapes, down to
 * the texture alone for a quiet desktop. The texture drifts (and follows the music) only
 * while nothing covers it: a program open on the workspace being shown stops it, since
 * nobody is looking and the shader would run for nothing.
 */
AbstractBackgroundWidget {
    id: root

    /// Lying on its side: art left, the rest beside it.
    property bool landscape: false
    property bool wallpaperSafetyTriggered: false

    readonly property var options: Config.options.easyEffects.widget

    configEntryName: root.landscape ? "easyeffects_preset_landscape" : "easyeffects_preset_portrait"
    implicitWidth: root.landscape ? 720 : 360
    implicitHeight: root.landscape ? 320 : 640

    // ── Is anything on top of it? ───────────────────────────────────────
    // The monitor this copy is drawn on, and the workspaces it is showing now (the normal
    // one, plus a special one pulled over it). A window that is mapped on any of them
    // covers the desktop; a preview in the widget catalogue never counts as covered.
    readonly property var monitor: HyprlandData.monitors.find(candidate => candidate?.name === root.monitorName)
        ?? HyprlandData.monitors.find(candidate => candidate?.focused === true) ?? null
    readonly property var shownWorkspaces: root.monitor
        ? [root.monitor.activeWorkspace?.id, root.monitor.specialWorkspace?.id]
            .map(id => Number(id ?? NaN)).filter(id => isFinite(id) && id !== 0) : []
    readonly property bool covered: !root.isPreview && (root.options.pauseOnWindows ?? true)
        && HyprlandData.windowList.some(win => win && win.mapped !== false && win.hidden !== true
            && root.shownWorkspaces.includes(Number(win.workspace?.id ?? NaN)))

    readonly property string holdKey: `presetWidget:${root.widgetInstance?.id ?? (root.landscape ? "landscape" : "portrait")}:${root.isPreview ? "preview" : "desktop"}`

    Component.onCompleted: EasyEffects.hold(root.holdKey, true)
    Component.onDestruction: EasyEffects.hold(root.holdKey, false)

    EasyEffectsEditor {
        id: editor
        pipeline: root.options.pipeline === "input" ? "input" : "output"
    }

    StyledDropShadow {
        target: hero
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    PresetHero {
        id: hero
        anchors.fill: parent
        editor: editor
        landscape: root.landscape

        showTopography: root.options.topography ?? true
        topographyReactive: root.options.topographyReactive ?? true
        topographyPaused: root.covered
        topographyStrength: (root.options.topographyStrength ?? 100) / 100
        art: root.options.art ?? "shape"
        showDevice: root.options.showDevice ?? true
        showState: root.options.showState ?? true
        showDefault: root.options.showDefault ?? true
        showWave: root.options.showWave ?? true
        showCaption: root.options.showCaption ?? true
        showName: root.options.showName ?? true
        showEffects: root.options.showEffects ?? true
        showButtons: root.options.showButtons ?? true

        onEditRequested: {
            if (Config.options.easyEffects?.appEnable ?? true)
                GlobalStates.openEasyEffectsApp("effects");
            else
                EasyEffects.openNativeWindow();
        }
    }
}
