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

    readonly property bool sidebarOpen: !GlobalStates || GlobalStates.sidebarRightOpen || GlobalStates.sidebarLeftOpen || GlobalStates.settingsOpen || GlobalStates.osdVolumeOpen || GlobalStates.wallpaperSelectorOpen || GlobalStates.cheatsheetOpen || GlobalStates.notesAppOpen || GlobalStates.clockAppOpen || GlobalStates.sessionOpen || GlobalStates.usageOpen || GlobalStates.overviewOpen || GlobalStates.modesOpen || GlobalStates.editMode || GlobalStates.islandDashboardOpen
    readonly property bool internalVisibleCondition: Config.options.bar.tooltips.enableTooltips
        // Both reads have to be guarded. `parent?.hovered` was, `parent.hovered` was not,
        // so a tooltip evaluated while it has no parent — during the frame a delegate is
        // being rebuilt, for instance — threw instead of simply staying hidden.
        && ((extraVisibleCondition && (parent?.hovered === undefined || parent?.hovered)) || alternativeVisibleCondition)
        // A popup is drawn in the window's overlay whatever its parent's
        // visibility, so a tip whose control is hidden - a collapsed list, a
        // section of a page that is not shown, a button folded away while
        // still hovered - would float on its own.
        && parent?.visible !== false
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
    // `lingering` mirrors the bubble's `isVisible` imperatively: read in the `active`
    // binding, it re-evaluated `active` while the Loader was creating or destroying
    // the bubble - a binding loop on every show and hide.
    contentItem: Loader {
        id: contentLoader
        property bool revealed: false
        property bool lingering: false
        active: root.visible || lingering
        onActiveChanged: if (!active) {
            revealed = false;
            lingering = false;
        }
        onLoaded: Qt.callLater(() => contentLoader.revealed = contentLoader.active)
        Connections {
            target: contentLoader.item
            function onIsVisibleChanged() {
                contentLoader.lingering = contentLoader.item?.isVisible ?? false;
            }
        }
        sourceComponent: StyledToolTipContent {
            font: root.font
            text: root.text
            shown: root.visible && contentLoader.revealed
            horizontalPadding: root.horizontalPadding
            verticalPadding: root.verticalPadding
        }
    }
}
