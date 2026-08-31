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

    readonly property bool sidebarOpen: !GlobalStates || GlobalStates.sidebarRightOpen || GlobalStates.sidebarLeftOpen || GlobalStates.settingsOpen || GlobalStates.osdVolumeOpen || GlobalStates.wallpaperSelectorOpen || GlobalStates.cheatsheetOpen || GlobalStates.sessionOpen || GlobalStates.usageOpen || GlobalStates.overviewOpen || GlobalStates.modesOpen
    readonly property bool internalVisibleCondition: Config.options.bar.tooltips.enableTooltips
        && ((extraVisibleCondition && (parent.hovered === undefined || parent?.hovered)) || alternativeVisibleCondition)
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
    
    contentItem: StyledToolTipContent {
        id: contentItem
        font: root.font
        text: root.text
        shown: root.visible
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
    }
}
