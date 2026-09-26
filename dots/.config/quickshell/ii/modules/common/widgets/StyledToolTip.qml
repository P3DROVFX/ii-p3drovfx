import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ToolTip {
    id: root
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false
    // Tooltips started out as a sidebar-only thing, so they stay hidden unless
    // some overlay is open. Bar widgets, which are hovered with nothing else on
    // screen, opt out of that gate.
    property bool requireOverlay: true

    readonly property bool sidebarOpen: !GlobalStates || GlobalStates.sidebarRightOpen || GlobalStates.sidebarLeftOpen || GlobalStates.settingsOpen || GlobalStates.osdVolumeOpen || GlobalStates.wallpaperSelectorOpen || GlobalStates.cheatsheetOpen || GlobalStates.notesAppOpen || GlobalStates.sessionOpen || GlobalStates.usageOpen || GlobalStates.overviewOpen || GlobalStates.modesOpen || GlobalStates.editMode
    readonly property bool internalVisibleCondition: Config.options.bar.tooltips.enableTooltips
        // Both reads have to be guarded. `parent?.hovered` was, `parent.hovered` was not,
        // so a tooltip evaluated while it has no parent — during the frame a delegate is
        // being rebuilt, for instance — threw instead of simply staying hidden.
        && ((extraVisibleCondition && (parent?.hovered === undefined || parent?.hovered)) || alternativeVisibleCondition)
        && (!requireOverlay || sidebarOpen)
    verticalPadding: 5
    horizontalPadding: 10
    background: null
    font {
        family: Appearance.font.family.main
        variableAxes: Appearance.font.variableAxes.main
        pixelSize: Appearance?.font.pixelSize.smaller ?? 14
        hintingPreference: Font.PreferNoHinting // Prevent shaky text
    }
    

    delay: 0
    enabled: Config.options.bar.tooltips.enableTooltips
    visible: internalVisibleCondition
    
    // Hundreds of tooltips exist per shell and almost none are ever on screen, so the
    // bubble (text layout, three animated Behaviors) is built on show and dropped once
    // its exit animation has settled. It is created hidden and revealed a turn later,
    // so the grow-in animation still plays on every show.
    contentItem: Loader {
        id: contentLoader
        property bool revealed: false
        active: root.visible || (item?.isVisible ?? false)
        onActiveChanged: if (!active) revealed = false
        onLoaded: Qt.callLater(() => contentLoader.revealed = contentLoader.active)
        sourceComponent: StyledToolTipContent {
            font: root.font
            text: root.text
            shown: root.visible && contentLoader.revealed
            horizontalPadding: root.horizontalPadding
            verticalPadding: root.verticalPadding
        }
    }
}
