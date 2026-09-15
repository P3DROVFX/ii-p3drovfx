import QtQuick
import QtQuick.Layouts
import Quickshell
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
 * The two tabs live on the toolbar itself, so the bottom band holds nothing
 * and reserves only a margin (edit_mode.js's `bandBottom`); the catalogue
 * opens on the right, into room the geometry has already taken out of the
 * desktop's width.
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
    // The toolbar's second way into the panel: the bar's own quick settings,
    // which are a page of the catalogue rather than a panel of their own.
    signal drawerPageRequested(string section, string page)
    // The drawer's gestures, relayed: the surface owns the geometry and every write.
    signal drawerAddRequested(string widgetId, real dropX, real dropY)
    signal drawerAddWidgetRequested(string widgetId)
    signal drawerBarPlaceRequested(string componentId, string bucket)
    signal drawerBarRemoveRequested(string componentId)
    signal drawerBarDragMoved(string componentId, real x, real y)
    signal drawerBarDropRequested(string componentId, real x, real y)
    signal drawerBarDragCancelled()
    signal drawerDockToggleRequested(string appId)
    signal drawerAddAppRequested(string appId, real dropX, real dropY)
    signal drawerToggleAppRequested(string appId)
    signal drawerAddAppPairRequested(string firstAppId, string secondAppId, string name)
    signal drawerAddFolderRequested(string folderName, var appsList)
    signal drawerClearHomeScreenAppsRequested()
    signal drawerLockLayoutResetRequested()
    // "widgets", "bar", "dock" or "lockIslands": that surface back to the
    // shell's defaults, as one history entry.
    signal drawerResetRequested(string what)

    // The drawer's reveal, from the same geometry the card is: its width is
    // the drawer's on the drawer's scalar, so the panel slides out of the
    // card's right edge exactly as fast as the desktop makes room for it.
    property rect drawer: Qt.rect(root.width, 0, 0, 0)
    readonly property alias drawerItem: drawerReveal
    // Whether the catalogue's search field holds the keyboard: the surface
    // takes focus for it and gives it straight back.
    readonly property bool drawerSearchFocused: drawerLoader.item ? drawerLoader.item.searchFocused : false
    property string drawerScreenName: ""

    // Published for the surface's input mask: the only pixels of a
    // screen-sized layer surface that may take a click.
    readonly property alias toolbarItem: toolbar
    // The guide's card is the other one, while a guided session is on.
    readonly property alias guideItem: guide.cardItem

    // The toolbar's rectangle, for a surface that is not this one. The
    // Welcome's collapsed pill parks beside the toolbar and has no other way
    // to know where it ended up.
    readonly property rect toolbarRect: Qt.rect(toolbar.x, toolbar.y, toolbar.width, toolbar.height)
    // The chrome only exists on the screen the mode is on, so there is never a
    // second one racing this write.
    onToolbarRectChanged: GlobalStates.editToolbarRect = root.toolbarRect

    // ── The toolbar's cascade ────────────────────────────────────────────────
    // The pill rises out of the band as one piece (its `y` is a function of
    // `card`), and its contents used to arrive with it in a single flat frame:
    // eight controls appearing at once, which reads as a screenshot rather than
    // as a toolbar being handed to you.
    //
    // Derived from `editProgress` rather than animated here, and that is the
    // whole trick. That scalar already carries the mode's clock - one Behavior,
    // in GlobalStates - so a piece's own reveal is arithmetic on it: the piece
    // at slot N waits `N * staggerStep` of the entry and then takes
    // `revealSpan` to arrive. Nothing here holds a timer, nothing restarts, and
    // the cascade plays BACKWARDS on the way out for free, because the same
    // scalar runs back down to zero. An animation of its own could do none of
    // that, and a declarative one whose target moves every frame restarts
    // every frame and never ticks at all (b710ef731).
    readonly property real staggerStep: 0.06
    readonly property real revealSpan: 0.5

    function slotReveal(slot) {
        const t = (GlobalStates.editProgress - slot * root.staggerStep) / root.revealSpan;
        return Math.max(0, Math.min(1, t));
    }

    // Scale rather than an offset: a `y` translate would take the control
    // outside the pill it is arriving into, and the pill does not clip.
    function slotScale(slot) {
        return 0.72 + 0.28 * root.slotReveal(slot);
    }

    // The toolbar's own body, claiming the cursor for the whole of it. Without
    // it the gaps between the buttons - the toolbar's padding and the rules -
    // set no cursor at all, so whatever the last surface asked for stays up
    // and the hand the buttons DO ask for reads as intermittent rather than as
    // the pointer answering the button. `Qt.NoButton` keeps it out of the way
    // of every real click, and it sits under the toolbar so each button's own
    // hand still wins over it.
    MouseArea {
        x: toolbar.x
        y: toolbar.y
        width: toolbar.width
        height: toolbar.height
        z: -1
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
    }

    Toolbar {
        id: toolbar
        // Centred on the CARD rather than on the screen: the two are the same
        // point until the drawer translates the desktop, and the chrome
        // belongs to the desktop.
        x: root.card.x + (root.card.width - width) / 2
        y: root.area.y + (root.card.y - root.area.y - height) * root.bandFraction
        spacing: 6

        // Desktop | Lockscreen. Indices are the tab list's own order; the
        // names come back through EditModeLogic so this bar and the state
        // agree on one spelling.
        ToolbarTabBar {
            id: tabBar
            opacity: root.slotReveal(0)
            scale: root.slotScale(0)
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

        // Which screen the mode is on, with more than one: a click moves the
        // mode to the next. Named by the screen's own name - the only name
        // the user has for it in the compositor's config too.
        IconAndTextToolbarButton {
            id: monitorButton
            readonly property var screens: Quickshell.screens
            visible: monitorButton.screens.length > 1
            opacity: root.slotReveal(1)
            scale: (monitorButton.down ? 0.92 : 1) * root.slotScale(1)
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 4
            iconText: "monitor"
            text: GlobalStates.editModeMonitor
            onClicked: {
                const names = Array.from(monitorButton.screens).map(screen => screen.name);
                if (names.length < 2)
                    return;
                const at = names.indexOf(GlobalStates.editModeMonitor);
                GlobalStates.switchEditMonitor(names[(at + 1) % names.length]);
            }

            StyledToolTip {
                requireOverlay: false
                text: Translation.tr("Edit the next screen")
            }
        }

        Rectangle {
            opacity: root.slotReveal(1)
            scale: root.slotScale(1)
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            implicitWidth: 1
            // Short of the toolbar's height on purpose: a full-height rule
            // reads as two containers rather than one.
            implicitHeight: Math.round(Appearance.sizes.toolbarHeight * 0.4)
            color: Appearance.colors.colOutlineVariant
        }

        // The panel's catalogues, as one group of chips: Widgets, Bar, Dock,
        // Style - and on the Lockscreen tab, Widgets, the lock's own switches
        // and Style. The
        // chips mirror the panel's own tabs one for one, so the toolbar and
        // the panel can never disagree about what there is to edit; a chip
        // reads toggled while the panel is open on its catalogue, and a click
        // on that chip closes the panel again. Bar and Dock open on their
        // appearance pages - what the panel is for when you already know
        // which surface you came to change - and the rest on their roots.
        //
        // One group rather than three loose buttons because the three used to
        // read as unrelated actions ("Add widgets", "Bar", "Dock"), and a
        // fourth would have made the toolbar wider than the card on a small
        // screen. Grouped, they are one control with one job: which catalogue.
        Rectangle {
            id: sectionGroup
            opacity: root.slotReveal(2)
            scale: root.slotScale(2)
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: sectionRow.implicitWidth + 6
            implicitHeight: Appearance.sizes.toolbarHeight - 12
            radius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
            color: Appearance.colors.colSurfaceContainerHigh

            component SectionChip: IconAndTextToolbarButton {
                id: chip
                required property string section
                property string page: ""
                property string tooltip: ""
                readonly property bool open: GlobalStates.editDrawerOpen && GlobalStates.editDrawerSection === chip.section

                Layout.fillHeight: false
                implicitHeight: sectionGroup.implicitHeight - 6
                scale: chip.down ? 0.92 : 1
                toggled: chip.open
                onClicked: {
                    if (chip.open) {
                        root.drawerToggleRequested();
                        return;
                    }
                    root.drawerPageRequested(chip.section, chip.page);
                }

                StyledToolTip {
                    requireOverlay: false
                    text: chip.tooltip
                }
            }

            Row {
                id: sectionRow
                anchors.centerIn: parent
                spacing: 2

                SectionChip {
                    visible: PanelFamily.touchFirst && !GlobalStates.editLockPreview
                    section: "apps"
                    iconText: "apps"
                    text: Translation.tr("Apps")
                    tooltip: Translation.tr("Add apps to home screen")
                }
                SectionChip {
                    section: "widgets"
                    iconText: "widgets"
                    text: Translation.tr("Widgets")
                    tooltip: GlobalStates.editLockPreview
                        ? Translation.tr("Widgets on the lock screen")
                        : Translation.tr("Desktop widgets")
                }
                SectionChip {
                    visible: !GlobalStates.editLockPreview
                    section: "bar"
                    page: "appearance"
                    iconText: "dock_to_bottom"
                    text: Translation.tr("Bar")
                    tooltip: Translation.tr("Bar appearance and widgets")
                }
                SectionChip {
                    visible: !GlobalStates.editLockPreview
                    section: "dock"
                    page: "appearance"
                    iconText: PanelFamily.touchFirst ? "dock_to_bottom" : "dock"
                    text: PanelFamily.touchFirst ? Translation.tr("Taskbar") : Translation.tr("Dock")
                    tooltip: PanelFamily.touchFirst
                        ? Translation.tr("Taskbar appearance and apps")
                        : Translation.tr("Dock appearance and apps")
                }
                SectionChip {
                    visible: GlobalStates.editLockPreview
                    section: "lock"
                    iconText: "lock"
                    text: Translation.tr("Lock screen")
                    tooltip: Translation.tr("What the lock screen shows")
                }
                SectionChip {
                    section: "style"
                    iconText: "palette"
                    text: Translation.tr("Style")
                    tooltip: Translation.tr("Wallpaper, theme and colours")
                }
            }
        }

        // Edge snapping, drawn as state. It reads and toggles the key Settings
        // already offers rather than a switch of its own. Icon-only: the
        // toolbar's width is the card's inset and the labels beside it already
        // spend the words.
        IconToolbarButton {
            id: snapButton
            opacity: root.slotReveal(3)
            scale: (snapButton.down ? 0.92 : 1) * root.slotScale(3)
            Layout.alignment: Qt.AlignVCenter
            // The guides ARE the feature - the dot lattice and the alignment
            // lines a dragged widget latches onto. The alignment glyph this
            // used to carry says "align these to the left", which is a
            // different thing and the wrong promise.
            text: Config.options.background.widgets.enableSnap ? "grid_guides" : "grid_off"
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
            opacity: root.slotReveal(4)
            scale: root.slotScale(4)
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
            // RippleButton dims a disabled button through this same property,
            // and an outer binding replaces its rule rather than joining it -
            // so the dimming is multiplied back in by hand.
            opacity: root.slotReveal(5) * (undoButton.enabled ? 1 : 0.4)
            scale: (undoButton.down ? 0.92 : 1) * root.slotScale(5)
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
            opacity: root.slotReveal(6) * (redoButton.enabled ? 1 : 0.4)
            scale: (redoButton.down ? 0.92 : 1) * root.slotScale(6)
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
            opacity: root.slotReveal(7)
            scale: (doneButton.down ? 0.92 : 1) * root.slotScale(7)
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

    // The tour of the toolbar, shown only while a guide is hosting the session.
    // Above the toolbar in declaration order so its card is never behind the
    //control it points at.
    EditModeGuide {
        id: guide
        anchors.fill: parent
        z: 150
        tabsTarget: tabBar
        sectionsTarget: sectionGroup
        historyTarget: undoButton
        doneTarget: doneButton
        drawerTarget: drawerReveal
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
            if (drawerLoader.item && !drawerLoader.item.pointInSearchField(mouse.x, mouse.y))
                drawerLoader.item.releaseSearchFocus();
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

        Loader {
            id: drawerLoader
            anchors.fill: parent
            active: GlobalStates.editDrawerOpen || GlobalStates.editDrawerProgress > 0
            sourceComponent: EditModeDrawer {
                anchors.fill: parent
                ghostParent: root
                screenName: root.drawerScreenName
                onAddRequested: (widgetId, dropX, dropY) => root.drawerAddRequested(widgetId, dropX, dropY)
                onLockLayoutResetRequested: root.drawerLockLayoutResetRequested()
                onResetRequested: what => root.drawerResetRequested(what)
                onAddInstanceRequested: widgetId => root.drawerAddWidgetRequested(widgetId)
                onBarPlaceRequested: (componentId, bucket) => root.drawerBarPlaceRequested(componentId, bucket)
                onBarRemoveRequested: componentId => root.drawerBarRemoveRequested(componentId)
                onBarDragMoved: (componentId, x, y) => root.drawerBarDragMoved(componentId, x, y)
                onBarDropRequested: (componentId, x, y) => root.drawerBarDropRequested(componentId, x, y)
                onBarDragCancelled: root.drawerBarDragCancelled()
                onDockToggleRequested: appId => root.drawerDockToggleRequested(appId)
                onAddAppRequested: (appId, dropX, dropY) => root.drawerAddAppRequested(appId, dropX, dropY)
                onToggleAppOnHomeScreenRequested: appId => root.drawerToggleAppRequested(appId)
                onAddAppPairRequested: (firstAppId, secondAppId, name) => root.drawerAddAppPairRequested(firstAppId, secondAppId, name)
                onAddFolderRequested: (folderName, appsList) => root.drawerAddFolderRequested(folderName, appsList)
                onClearHomeScreenAppsRequested: root.drawerClearHomeScreenAppsRequested()
            }
        }
    }
}
