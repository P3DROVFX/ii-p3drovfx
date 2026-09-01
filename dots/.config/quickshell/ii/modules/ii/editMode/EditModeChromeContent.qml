import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Edit Mode's chrome: the toolbar above the shrunk desktop.
 *
 * Everything is placed off `card`, the rectangle the desktop is drawn at -
 * the same arithmetic the desktop's own transform is built out of - so the
 * chrome cannot be a pixel off the thing it frames. That also gives the motion
 * for free and gives it the right shape: `card` is a function of the mode's
 * progress, so the toolbar rises out of the top band exactly as fast as the
 * desktop shrinks away from it. Nothing here carries a Behavior of its own, and
 * must not: a Behavior whose target moves every frame restarts every frame
 * and never ticks.
 *
 * The Lockscreen tab bar (stage 7b) will mirror the toolbar in the bottom
 * band; the widget drawer (stage 5) opens on the right. Both bands are already
 * reserved by the geometry so their arrival changes nothing about the desktop.
 */
Item {
    id: root

    // The desktop's rectangle on screen. Defaults to the whole item, so an
    // unconnected instance parks its chrome off the edge rather than somewhere
    // arbitrary.
    property rect card: Qt.rect(0, 0, root.width, root.height)
    // The screen minus what the bar and the dock occupy, interpolated on the
    // same progress as `card`: the band the toolbar sits in is the gap between
    // the two rectangles, so a bar of any height pushes the chrome rather than
    // being drawn over by it.
    property rect area: Qt.rect(0, 0, root.width, root.height)
    // Where in its band the toolbar sits, as a fraction of the band's slack
    // (edit_mode.js's chromeBandFraction): the tight gap on the outside, the
    // generous one between it and the desktop. A fraction rather than a pixel
    // offset because the band has no height at progress 0 and the piece has to
    // be parked off the edge there.
    property real bandFraction: 0.5

    signal doneRequested()
    signal undoRequested()
    signal redoRequested()
    signal tabRequested(string tab)
    signal snapToggleRequested()
    signal drawerToggleRequested()
    // The drawer's gestures, relayed: the surface owns the geometry and every write.
    signal drawerAddRequested(string widgetId, real dropX, real dropY)
    signal drawerToggleWidgetRequested(string widgetId)
    signal drawerBarAddRequested(string componentId, string bucket)
    signal drawerBarRemoveRequested(string componentId)
    signal drawerBarDragMoved(string componentId, real x, real y)
    signal drawerBarDropRequested(string componentId, real x, real y)
    signal drawerBarDragCancelled()
    signal drawerDockToggleRequested(string appId)
    signal drawerLockLayoutResetRequested()

    // The drawer's reveal, from the same geometry the card is: its width is
    // the drawer's on the drawer's scalar, so the panel slides out of the
    // card's right edge exactly as fast as the desktop makes room for it.
    property rect drawer: Qt.rect(root.width, 0, 0, 0)
    readonly property alias drawerItem: drawerReveal
    // Whether the catalogue's search field holds the keyboard: the surface
    // takes focus for it and gives it straight back.
    readonly property alias drawerSearchFocused: drawerPanel.searchFocused
    property alias drawerScreenName: drawerPanel.screenName

    // Published for the surface's input mask: the only pixels of a
    // screen-sized layer surface that may take a click.
    readonly property alias toolbarItem: toolbar

    Toolbar {
        id: toolbar
        // Centred on the CARD rather than on the screen: the two are the same
        // point until the drawer translates the desktop, and the chrome
        // belongs to the desktop.
        x: root.card.x + (root.card.width - width) / 2
        y: root.area.y + (root.card.y - root.area.y - height) * root.bandFraction
        spacing: 6

        // The title, and every part of this is about it NOT reading as a
        // control: no icon (an icon beside a word is the button shape here),
        // the label tier in the variant role, and a rule between it and the
        // buttons.
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 10
            text: Translation.tr("Edit layout")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colOnSurfaceVariant
        }

        // Desktop | Lockscreen. Indices are the tab list's own order; the
        // names come back through EditModeLogic so this bar and the state
        // agree on one spelling.
        ToolbarTabBar {
            id: tabBar
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 4
            implicitHeight: Appearance.sizes.toolbarHeight - 12
            tabButtonList: [
                { "name": Translation.tr("Desktop"), "icon": "desktop_windows" },
                { "name": Translation.tr("Lock screen"), "icon": "lock" }
            ]
            requestOnly: true
            currentIndex: EditModeLogic.tabIndex(GlobalStates.editTab)
            onIndexSelected: index => root.tabRequested(EditModeLogic.tabAt(index))
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            implicitWidth: 1
            // Short of the toolbar's height on purpose: a full-height rule
            // reads as two containers rather than one with a title on it.
            implicitHeight: Math.round(Appearance.sizes.toolbarHeight * 0.4)
            color: Appearance.colors.colOutlineVariant
        }

        // The drawer's toggle. Inert until stage 5 brings the drawer; shown
        // already so the toolbar's shape does not change under the user then.
        IconAndTextToolbarButton {
            id: drawerButton
            Layout.alignment: Qt.AlignVCenter
            iconText: "widgets"
            text: Translation.tr("Add widgets")
            toggled: GlobalStates.editDrawerOpen
            onClicked: root.drawerToggleRequested()
        }

        // Edge snapping, drawn as state. It reads and toggles the key Settings
        // already offers rather than a switch of its own. Icon-only: the
        // toolbar's width is the card's inset and the two labels beside it
        // already spend the words.
        IconToolbarButton {
            id: snapButton
            Layout.alignment: Qt.AlignVCenter
            text: "align_horizontal_left"
            toggled: Config.options.background.widgets.enableSnap
            onClicked: root.snapToggleRequested()

            StyledToolTip {
                requireOverlay: false
                text: Config.options.background.widgets.enableSnap
                    ? Translation.tr("Edge snapping on")
                    : Translation.tr("Edge snapping off")
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            implicitWidth: 1
            implicitHeight: Math.round(Appearance.sizes.toolbarHeight * 0.4)
            color: Appearance.colors.colOutlineVariant
        }

        // The two the keyboard already offers, for a pointer that never
        // reaches for it. Disabled rather than hidden when their stack is
        // empty: a button that comes and goes moves every other button on the
        // toolbar with it, and the toolbar is centred on the card, so the whole
        // row would slide under the pointer on the first edit.
        IconToolbarButton {
            id: undoButton
            Layout.alignment: Qt.AlignVCenter
            text: "undo"
            enabled: GlobalStates.editCanUndo
            onClicked: root.undoRequested()

            StyledToolTip {
                requireOverlay: false
                text: Translation.tr("Undo (Ctrl+Z)")
            }
        }

        IconToolbarButton {
            id: redoButton
            Layout.alignment: Qt.AlignVCenter
            text: "redo"
            enabled: GlobalStates.editCanRedo
            onClicked: root.redoRequested()

            StyledToolTip {
                requireOverlay: false
                text: Translation.tr("Redo (Ctrl+Shift+Z)")
            }
        }

        // The mode's real way out. It carries its label - a mode the user
        // cannot see how to leave costs them the whole session, and a checkmark
        // is not a word - and it is FILLED on the primary role, because
        // rendered flat beside the title it read as a second label.
        IconAndTextToolbarButton {
            id: doneButton
            Layout.alignment: Qt.AlignVCenter
            iconText: "done"
            text: Translation.tr("Done")
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            colText: Appearance.colors.colOnPrimary
            onClicked: root.doneRequested()
        }
    }

    // Clicking anywhere but the field lets the keyboard go. Only this surface
    // needs the catcher: a click on the desktop lands on another surface, which
    // takes the keyboard with it and deactivates this window on its own. The
    // press is declined rather than consumed, so whatever was actually clicked
    // still gets it.
    MouseArea {
        anchors.fill: parent
        z: 200
        enabled: root.drawerSearchFocused
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            if (!drawerPanel.pointInSearchField(mouse.x, mouse.y))
                drawerPanel.releaseSearchFocus();
            mouse.accepted = false;
        }
    }

    // The reveal: a clip the width of the drawer's animated scalar, with the
    // full-width panel anchored to its left edge, so the panel slides in from
    // the card's right edge and its contents never reflow.
    Item {
        id: drawerReveal
        x: root.drawer.x
        y: root.drawer.y
        width: root.drawer.width
        height: root.drawer.height
        clip: true
        visible: width > 0

        EditModeDrawer {
            id: drawerPanel
            anchors.fill: parent
            ghostParent: root
            onAddRequested: (widgetId, dropX, dropY) => root.drawerAddRequested(widgetId, dropX, dropY)
            onLockLayoutResetRequested: root.drawerLockLayoutResetRequested()
            onToggleRequested: widgetId => root.drawerToggleWidgetRequested(widgetId)
            onBarAddRequested: (componentId, bucket) => root.drawerBarAddRequested(componentId, bucket)
            onBarRemoveRequested: componentId => root.drawerBarRemoveRequested(componentId)
            onBarDragMoved: (componentId, x, y) => root.drawerBarDragMoved(componentId, x, y)
            onBarDropRequested: (componentId, x, y) => root.drawerBarDropRequested(componentId, x, y)
            onBarDragCancelled: root.drawerBarDragCancelled()
            onDockToggleRequested: appId => root.drawerDockToggleRequested(appId)
        }
    }
}
