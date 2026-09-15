pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Where you are, and everything that is about the whole app rather than one note.
 *
 * New note at the top, where the mail sidebar puts Compose. The places and the notebooks
 * in the middle, each a group shaped at its ends. And at the bottom the two things that
 * are not places at all — finding a note, and changing how the app behaves — because a
 * rail that mixes "which notes am I looking at" with "find something" and "change
 * something" in one column makes all three harder to find.
 *
 * Two, and no more. A third full-width button here reads as a third place, which is
 * exactly the confusion the split was meant to end: anything else that is about the whole
 * app — the statistics, for one — belongs in the bar across the top instead.
 */
Item {
    id: root

    property bool expanded: true
    property string scope: "all"
    /// Held down while the settings page is the one open, the way a place is while you are
    /// in it: the button opens somewhere, so it has to be able to say you are there.
    property bool settingsOpen: false
    readonly property string query: searchBox.text

    signal scopePicked(string scope)
    signal createRequested()
    signal templatesRequested()
    signal settingsRequested()

    // Clipped at the pane's own bounds.
    //
    // The slab below is a *sibling* of the content, so its own `clip` contains nothing —
    // a list long enough to scroll had cards drawn outside the rounded rectangle they are
    // supposed to live in. Clipping belongs to whatever owns the bounds, which is this.
    clip: true

    function clearSearch(): void {
        searchBox.text = "";
    }

    function focusSearch(): void {
        searchBox.forceActiveFocus();
    }

    readonly property var places: [
        { id: "all", icon: "description", name: Translation.tr("All notes") },
        { id: "recent", icon: "history", name: Translation.tr("Recent") },
        { id: "favorites", icon: "star", name: Translation.tr("Favourites") },
        { id: "trash", icon: "delete", name: Translation.tr("Trash") }
    ]

    readonly property var notebooks: Array.from(NotesService.notebooks ?? [])

    function countFor(scopeId) {
        const live = Array.from(NotesService.index.notes ?? []).filter(note => note.trashedAt === 0);
        if (scopeId === "all")
            return live.length;
        if (scopeId === "favorites")
            return live.filter(note => note.favorite).length;
        if (scopeId === "recent")
            return Math.min(20, live.length);
        if (scopeId === "trash")
            return Array.from(NotesService.index.notes ?? []).filter(note => note.trashedAt > 0).length;
        return live.filter(note => note.notebookId === scopeId || note.sectionId === scopeId).length;
    }

    // A slab. Opaque on purpose: the theme's layered colours are transparency-adjusted and
    // collapse into each other over a wallpaper, so a boundary drawn with them is not one
    // anybody can see. Every Cheatsheet page uses this surface for the same reason.
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: NotesMetrics.panePadding
        spacing: 0

        /**
         * Compose, and the one other way to start a note.
         *
         * The templates were reachable from exactly one place: the button in the middle of
         * the empty-notes placeholder, which anybody with a single note in the store never
         * sees again. They belong beside the button that makes notes, on the same row, so
         * the rail's bottom stays at two things.
         */
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 24
            spacing: 8

        RippleButton {
            id: composeButton
            Layout.fillWidth: true
            implicitHeight: 64
            buttonRadius: NotesMetrics.pillRadius(composeButton.implicitHeight)
            colBackgroundToggled: Appearance.colors.colPrimary
            // The soft container, not primary. Primary belongs to whichever place you are
            // in; two bright blocks stacked made "make a note" and "where I am" shout at
            // each other. It is also exactly how Compose sits in the mail sidebar.
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colBackgroundActive: Appearance.colors.colSecondaryContainerActive

            onClicked: root.createRequested()

            scale: composeButton.down ? 0.95 : (composeButton.hovered ? 1.02 : 1.0)
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Icon and label centred as one group, which is how the mail sidebar's own
            // Compose button is built. The previous arrangement pinned the icon to the
            // left and let the label stretch, so the pair sat against the left edge of a
            // 186px pill with forty pixels of nothing after it.
            contentItem: Item {
                anchors.fill: parent

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "edit"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("New note")
                        visible: root.expanded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSecondaryContainer
                        elide: Text.ElideRight
                    }
                }
            }

            StyledToolTip {
                text: Translation.tr("New note")
                extraVisibleCondition: !root.expanded
            }
        }

        RippleButton {
            id: templatesButton
            Layout.preferredWidth: 64
            implicitHeight: 64
            visible: root.expanded
            buttonRadius: NotesMetrics.pillRadius(templatesButton.implicitHeight)
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colBackgroundActive: Appearance.colors.colSecondaryContainerActive

            onClicked: root.templatesRequested()

            scale: templatesButton.down ? 0.95 : (templatesButton.hovered ? 1.02 : 1.0)
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Aligned, not merely anchored: a `Control` positions its `contentItem` in the
            // content rect and stretches it to that width, so a `Text` inside draws its
            // glyph at the left edge unless it is told to centre. Ten pixels off, which is
            // exactly what it looked like beside the pill.
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "dashboard_customize"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.m3colors.m3onSecondaryContainer
            }

            StyledToolTip {
                text: Translation.tr("Start from a template")
            }
        }

        }

        Flickable {
            id: railScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: railColumn.implicitHeight
            // Clipped, because a scrolled row must not paint over the pane's corner — so
            // the rows are inset instead, leaving the two-percent hover scale somewhere to
            // grow rather than a slice taken off both ends of it.
            clip: true

            ColumnLayout {
                id: railColumn
                x: NotesMetrics.hoverGrowth
                width: railScroll.width - NotesMetrics.hoverGrowth * 2
                spacing: 2

                Repeater {
                    model: root.places
                    delegate: NotesRailItem {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        isFirst: index === 0
                        isLast: index === root.places.length - 1
                        prevIsCurrent: index > 0 && root.scope === root.places[index - 1].id
                        nextIsCurrent: index < root.places.length - 1 && root.scope === root.places[index + 1].id
                        expanded: root.expanded
                        symbol: modelData.icon
                        label: modelData.name
                        count: root.countFor(modelData.id)
                        current: root.scope === modelData.id
                        onTriggered: root.scopePicked(modelData.id)
                    }
                }

                // The gap that says "these are a different kind of place", without the
                // word: the notebooks carry their own icons and names, and a caption over
                // them was one label more than the rail needed.
                Item {
                    Layout.preferredHeight: 16
                    visible: root.notebooks.length > 0
                }

                Repeater {
                    model: root.notebooks
                    delegate: NotesRailItem {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        isFirst: index === 0
                        isLast: index === root.notebooks.length - 1
                        prevIsCurrent: index > 0 && root.scope === root.notebooks[index - 1].id
                        nextIsCurrent: index < root.notebooks.length - 1 && root.scope === root.notebooks[index + 1].id
                        expanded: root.expanded
                        symbol: modelData.icon.length > 0 ? modelData.icon : "book"
                        label: modelData.title
                        count: root.countFor(modelData.id)
                        current: root.scope === modelData.id
                        onTriggered: root.scopePicked(modelData.id)
                    }
                }
            }
        }

        NotesSearchBox {
            id: searchBox
            Layout.fillWidth: true
            Layout.topMargin: 20
            Layout.bottomMargin: 8
            expanded: root.expanded
            placeholder: Translation.tr("Search notes")
            onCleared: root.clearSearch()
        }

        // Below the search, where the mail sidebar keeps its own Settings.
        RippleButton {
            id: settingsButton
            Layout.fillWidth: true
            implicitHeight: 56
            buttonRadius: NotesMetrics.pillRadius(settingsButton.implicitHeight)
            toggled: root.settingsOpen
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colBackgroundActive: Appearance.colors.colSecondaryContainerActive
            colBackgroundToggled: Appearance.colors.colPrimary
            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive

            scale: settingsButton.down ? 0.95 : (settingsButton.hovered ? 1.02 : 1.0)
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            onClicked: root.settingsRequested()

            contentItem: Item {
                anchors.fill: parent

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "settings"
                        iconSize: Appearance.font.pixelSize.huge
                        color: root.settingsOpen
                            ? Appearance.colors.colOnPrimary
                            : Appearance.m3colors.m3onSecondaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Settings")
                        visible: root.expanded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: root.settingsOpen
                            ? Appearance.colors.colOnPrimary
                            : Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }

            StyledToolTip {
                text: Translation.tr("Notes settings")
                extraVisibleCondition: !root.expanded
            }
        }
    }
}
