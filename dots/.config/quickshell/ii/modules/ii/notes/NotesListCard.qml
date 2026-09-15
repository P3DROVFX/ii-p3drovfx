import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.notes
import "../../../services/notes/NotesSearchIndex.js" as SearchIndex

/**
 * One note in the list.
 *
 * Everything drawn here comes from the index — title, preview, date, whether there is ink
 * in it. Not one card opens a document to render itself, which is the whole reason the
 * store keeps an index at all.
 */
RippleButton {
    id: root

    required property var note
    property var searchTerms: []
    property bool current: false
    /// Where this card sits in the list, and whether its neighbours are the selected one.
    property bool isFirst: false
    property bool isLast: false
    property bool prevIsCurrent: false
    property bool nextIsCurrent: false
    property bool compact: Persistent.ready && Persistent.states.notes?.viewMode === "compact"

    signal triggered()

    // The control's own padding, rather than a margin per row plus a hand-computed
    // height. Those disagreed with each other by a couple of pixels — enough to look like
    // a mistake, not enough to look deliberate — and `Button` was quietly adding its
    // default padding to the height on top of that.
    leftPadding: NotesMetrics.cardPadding
    rightPadding: NotesMetrics.cardPadding
    topPadding: root.compact ? 8 : NotesMetrics.rowPaddingVertical
    bottomPadding: root.compact ? 8 : NotesMetrics.rowPaddingVertical
    toggled: root.current

    // Cards must remain aligned to the ListView viewport. RippleButton's generic hover
    // scale grows around the center and changes the apparent side margins of a full-width
    // delegate, which is especially visible in this narrow column.
    scale: 1.0

    /**
     * The Settings sidebar's smart radius, and the reason it is not a full pill.
     *
     * A card here is around 90px tall. `height / 2` would round it by 45, which swallows
     * the first line of text and leaves crescent-shaped gaps against the cards above and
     * below. Capping at the `large` token keeps the corner generous and the row rectangular
     * enough to read. The neighbours facing the selected card round too, so the selection
     * presses into the stack instead of floating in a hole cut out of it.
     */
    readonly property real pillRadius: NotesMetrics.pillRadius(root.implicitHeight)
    readonly property bool topIsPill: root.current || root.down || root.prevIsCurrent
    readonly property bool bottomIsPill: root.current || root.down || root.nextIsCurrent

    topLeftRadius: root.topIsPill ? root.pillRadius : (root.isFirst ? NotesMetrics.groupEndRadius : NotesMetrics.groupJoinRadius)
    topRightRadius: root.topLeftRadius
    bottomLeftRadius: root.bottomIsPill ? root.pillRadius : (root.isLast ? NotesMetrics.groupEndRadius : NotesMetrics.groupJoinRadius)
    bottomRightRadius: root.bottomLeftRadius

    Behavior on topLeftRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on bottomLeftRadius {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    // Filled, on the opaque surface of the pane behind it.
    //
    // The first attempt used the theme's layered colours, which are transparency-adjusted:
    // measured on a real screenshot, a card sat ten channel-steps from its own pane, which
    // is not an edge anybody can see. These two surfaces are opaque and are the pair the
    // Cheatsheet's own lists use.
    colBackground: Appearance.m3colors.m3surfaceContainerHighest
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggled: Appearance.colors.colSecondaryContainer

    onClicked: root.triggered()

    readonly property color colText: root.current
        ? Appearance.m3colors.m3onSecondaryContainer
        : Appearance.colors.colOnSurfaceVariant

    /// Today shows a time, this year a day and month, anything older the year as well.
    /// A list where every row says the same date is a list with no dates in it.
    readonly property string whenText: {
        const stamp = Number(root.note.modified) || Number(root.note.created) || 0;
        if (stamp <= 0)
            return "";
        const when = new Date(stamp);
        const now = new Date();
        if (when.toDateString() === now.toDateString())
            return Qt.formatDateTime(when, "HH:mm");
        if (when.getFullYear() === now.getFullYear())
            return Qt.formatDateTime(when, "d MMM");
        return Qt.formatDateTime(when, "MMM yyyy");
    }

    contentItem: ColumnLayout {
        id: layout
        spacing: NotesMetrics.cardLineSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: root.note.icon.length > 0 ? root.note.icon : "article"
                iconSize: 18
                color: root.colText
                opacity: 0.8
            }

            StyledText {
                Layout.fillWidth: true
                text: root.note.title.length > 0 ? root.note.title : Translation.tr("Untitled note")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.colText
                elide: Text.ElideRight
            }

            MaterialSymbol {
                text: "keep"
                iconSize: 15
                fill: 1
                color: root.colText
                visible: root.note.pinned === true
            }

            MaterialSymbol {
                text: "star"
                iconSize: 15
                fill: 1
                color: root.colText
                visible: root.note.favorite === true
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.compact
            text: root.searchTerms && root.searchTerms.length > 0
                ? SearchIndex.highlightSnippet(root.note.preview, root.searchTerms, 120)
                : (root.note.preview.length > 0 ? root.note.preview : Translation.tr("Empty"))
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.current
                ? Appearance.m3colors.m3onSecondaryContainer
                : Appearance.colors.colSubtext
            opacity: root.note.preview.length > 0 ? 0.9 : 0.55
            id: preview
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            /**
             * Two lines, always, measured from the font rather than from the text.
             *
             * A `Text` reports the implicit height of one *unwrapped* line, so a layout
             * asking for its natural size built a card one line too short and the preview
             * spilled onto the card below. Asking the text how tall it turned out is
             * circular — with `maximumLineCount` and eliding, its height is whatever it
             * was given — so the height comes from the font, and the card is the same
             * height whether the preview needs one line or two.
             */
            Layout.preferredHeight: Math.max(previewLine.height, 1) * 2

            /// One line of this very text, unwrapped — a ruler, not a label.
            TextMetrics {
                id: previewLine
                font: preview.font
                text: preview.text
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            StyledText {
                text: root.whenText
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.current
                    ? Appearance.m3colors.m3onSecondaryContainer
                    : Appearance.colors.colSubtext
                opacity: 0.85
            }

            MaterialSymbol {
                text: "draw"
                iconSize: 13
                color: Appearance.colors.colSubtext
                visible: root.note.hasInk === true
            }

            MaterialSymbol {
                text: "image"
                iconSize: 13
                color: Appearance.colors.colSubtext
                visible: root.note.hasImages === true
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
