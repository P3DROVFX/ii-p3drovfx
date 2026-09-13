pragma Singleton

import QtQuick
import Quickshell

import qs.modules.common

/**
 * One place for every measurement in the notes app.
 *
 * The alignments went wrong the first time in exactly the way they always do: each file
 * chose its own margin, two of them differed by two pixels, and the result reads as
 * sloppy without anyone being able to point at which number is wrong. So the numbers live
 * here, they are few, and every pane uses them.
 *
 * The scale is 4, which is what the Material spacing scale is built on. Everything below
 * is a multiple of it.
 */
Singleton {
    /// Between the window edge and a pane, and between two panes.
    ///
    /// This gap *is* the separation between sections. The Cheatsheet's pages — timetable,
    /// mail, keybinds — are all built this way: opaque rounded slabs with air between
    /// them, never a rule drawn down the middle. A line says "these are two things"; a gap
    /// and a corner radius show it.
    readonly property int paneGap: 12

    /// Distance from the edge of a pane to its content.
    readonly property int panePadding: 10

    /// Distance from the edge of a card to its text. Larger than the pane padding, so the
    /// text inside a card is never closer to the card edge than the card is to the pane.
    readonly property int cardPadding: 16

    /// Vertical padding inside a list row.
    ///
    /// Smaller than the horizontal padding on purpose. An unfilled row has no edge of its
    /// own, so its padding *is* the space between it and the next one — count it twice,
    /// add the spacing, and generous padding turns a list into a ladder.
    readonly property int rowPaddingVertical: 12

    /// Between two rows. They are filled again, so they carry their own edge and a small
    /// gap is enough to keep them from reading as one block.
    readonly property int cardSpacing: 4

    /// Between the lines inside one card.
    readonly property int cardLineSpacing: 4

    /// The reading pane breathes more than the list: it holds prose, and prose needs a
    /// margin the eye can return to.
    readonly property int readingPadding: 32

    /// A comfortable measure. Text running the whole width of a maximised window is text
    /// nobody finishes a paragraph of.
    readonly property int readingWidth: 720

    /// Rail rows, list rows and icon buttons all sit on this, so a row in one pane lines
    /// up with a row in the next.
    readonly property int rowHeight: 56
    readonly property int iconButtonSize: 44

    /// Vertical rhythm of notebook lines. Single-line blocks, line heights and ruled paper
    /// align on this unit (28px) so ruled backgrounds match text lines across all blocks.
    readonly property int paperLineHeight: 28

    /// The floating button, and the space a list keeps free underneath itself so the last
    /// card can be read rather than sat on.
    readonly property int fabMargin: 16
    readonly property int fabClearance: 88

    // ── Shape ───────────────────────────────────────────────────────────
    /**
     * The pill radius for an element of this height, capped.
     *
     * `height / 2` alone is the classic pill formula and it breaks on anything tall: the
     * curve eats the corners of the content, and a stack of tall pills leaves crescent
     * gaps between them. The project's answer, from the Settings design system, is to cap
     * it at the `large` token — a one-line row still reads as a pill, and a 90px card
     * rounds to 24 instead of 45.
     */
    function pillRadius(itemHeight) {
        if (Appearance.rounding.scale === 0)
            return 0;
        return Math.min(itemHeight / 2, Appearance.rounding.large);
    }

    /// The outer corners of a group, and the corners where two rows meet.
    readonly property int groupEndRadius: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.large
    readonly property int groupJoinRadius: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.verysmall

    /**
     * How much room a hovered element needs beside it.
     *
     * Buttons here grow by two percent under the pointer, and the panes clip — so without
     * an inset the edges of the widest ones are shaved off at the very moment they are
     * meant to lift. Four pixels covers a 400px row.
     */
    readonly property int hoverGrowth: 4

    readonly property int railExpandedWidth: 300
    readonly property int railCollapsedWidth: 88
    readonly property int topBarHeight: 64

    /// How far the rail and the list may be dragged.
    readonly property int railMinimumWidth: 220
    readonly property int railMaximumWidth: 460
    readonly property int listMinimumWidth: 260
    /// The note column is a sidebar, not a second reading pane. Keep its width compact so
    /// previews wrap consistently and the editor keeps the visual weight of the app.
    readonly property int listMaximumWidth: 360
}
