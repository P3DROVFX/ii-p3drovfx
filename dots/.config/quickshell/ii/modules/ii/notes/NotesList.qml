pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/// Which note. A list of cards, and the one button that makes another one.
Item {
    id: root

    property var notes: []
    property var searchTerms: []
    property string selectedId: ""
    property bool searching: false
    property bool trash: false

    signal notePicked(string noteId)
    signal createRequested()
    signal templatesRequested()

    /**
     * Whether the staggered entrance is still owed.
     *
     * `populate` runs on every model *reset*, and this model is a plain array that the
     * service rebuilds whenever anything is saved — so the whole list re-entered, row by
     * row, on every keystroke's autosave. It plays once, when the list first fills, and
     * then the rows just are where they are.
     */
    property bool entranceSpent: false

    Timer {
        id: entranceGuard
        interval: 700
        onTriggered: root.entranceSpent = true
    }

    // Clipped at the pane's own bounds.
    //
    // The slab below is a *sibling* of the content, so its own `clip` contains nothing —
    // a list long enough to scroll had cards drawn outside the rounded rectangle they are
    // supposed to live in. Clipping belongs to whatever owns the bounds, which is this.
    clip: true

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true
    }

    StyledListView {
        id: list
        anchors.fill: parent
        // Symmetric. Zero at the bottom let the last card run to the slab's edge, where a
        // rectangular clip cuts straight across a corner that curves — which is what a
        // card poking out of the pane actually was.
        anchors.margins: NotesMetrics.panePadding
        topMargin: 0
        bottomMargin: NotesMetrics.panePadding
        spacing: NotesMetrics.cardSpacing
        clip: true

        // This is the actual scrolling viewport. Masking the parent pane does not change
        // the rectangular clip applied here, so a card entering at the top or leaving at
        // the bottom could still end in a hard horizontal edge. The mask follows this
        // viewport's bounds and rounds both ends of the visible list content.
        layer.enabled: true
        layer.samples: 8
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: list.width
                height: list.height
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                color: Appearance.colors.colOnSurface
                antialiasing: true
            }
        }

        model: root.notes
        // The cards arrive one after another rather than all at once. It is the app's
        // entrance, and a list that snaps into place reads as a redraw rather than a view.
        // Once.
        staggerStep: root.entranceSpent ? 0 : 18
        animatePopulate: !root.entranceSpent

        onCountChanged: {
            if (list.count > 0 && !root.entranceSpent)
                entranceGuard.restart();
        }

        delegate: NotesListCard {
            required property var modelData
            required property int index
            // ListView owns the delegate's x position. The previous manual inset was
            // ignored by the view while its width reduction remained active, leaving the
            // card with space on the right but none on the left. Fill the masked viewport
            // so both sides use the same pane padding.
            width: list.width
            isFirst: index === 0
            isLast: index === root.notes.length - 1
            // Guarded on both sides. A delegate outlives the array it indexes for a frame
            // whenever the list changes underneath it — a search narrowing, a note being
            // trashed — and reading `.id` off the gap throws once per row, every time.
            prevIsCurrent: index > 0 && index - 1 < root.notes.length
                && root.notes[index - 1]?.id === root.selectedId
            nextIsCurrent: index + 1 < root.notes.length
                && root.notes[index + 1]?.id === root.selectedId
            note: modelData
            searchTerms: root.searchTerms
            current: modelData.id === root.selectedId
            onTriggered: root.notePicked(modelData.id)
        }

        // Air after the last card, so it does not end flush against the pane's corner.
        footer: Item {
            height: NotesMetrics.panePadding
        }
    }

    PagePlaceholder {
        anchors.centerIn: parent
        width: parent.width - 40
        visible: root.notes.length === 0
        icon: root.trash ? "delete" : (root.searching ? "search_off" : "note_stack")
        title: root.trash
            ? Translation.tr("The trash is empty")
            : (root.searching ? Translation.tr("Nothing matches") : Translation.tr("No notes yet"))
        description: root.trash
            ? Translation.tr("Notes you delete wait here before they go for good.")
            : (root.searching
                ? Translation.tr("Try fewer words, or search in another notebook.")
                : Translation.tr("Write the first one. It saves itself."))
    }

    RowLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        anchors.topMargin: 90
        spacing: 10
        visible: root.notes.length === 0 && !root.trash && !root.searching

        RippleButton {
            implicitHeight: 36
            implicitWidth: 110
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            onClicked: root.createRequested()

            contentItem: RowLayout {
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: "add"
                    iconSize: 18
                    color: Appearance.colors.colOnPrimary
                }

                StyledText {
                    text: Translation.tr("New note")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        RippleButton {
            implicitHeight: 36
            implicitWidth: 120
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: root.templatesRequested()

            contentItem: RowLayout {
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: "dashboard_customize"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    text: Translation.tr("Templates")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

}
