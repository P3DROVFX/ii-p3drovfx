import qs.services
import qs.modules.common
import "layouts.js" as Layouts
import QtQuick

/**
 * The deck keyboard: six rows on a unit grid, sized to whatever box it is given.
 *
 * OskContent still draws the classic keyboard; this is its counterpart for the deck data in
 * layouts.js. Every row is deckUnits wide, so one unit is simply width / deckUnits and each key
 * claims its own share of it - that is what keeps the columns lined up from the F-row down to the
 * space bar. Gaps live inside the cells rather than between them, because a layout spacing would
 * cost each row a different total and stagger the right edge.
 */
Item {
    id: root

    property real gap: 4
    property real preferredUnit: 40 // Only used when nothing sizes the deck from outside
    property bool pinned: false // Lights up the Pin key; the dock owns the actual state

    signal actionTriggered(string action)

    // The layout the user pinned in settings, if it names a deck we have. Anything else - the
    // stale "qwerty_full", the "auto" phase 6 introduces - defers to whatever Hyprland reports.
    readonly property string configuredLayout: Config.options?.osk.layout ?? ""
    readonly property string liveLayoutCode: HyprlandXkb.currentLayoutCode
    readonly property string layoutCode: {
        const configured = Layouts.deckCodeFor(root.configuredLayout);
        return configured ?? Layouts.deckCodeFor(root.liveLayoutCode) ?? "";
    }
    readonly property var deck: Layouts.deckFor(root.layoutCode)

    /**
     * Thumb typing: the two halves pushed apart, with the middle left empty.
     *
     * A full-width keyboard on an 11" tablet held in two hands puts the middle columns out
     * of reach of either thumb — you have to let go of the device to type. Android and One UI
     * both offer a split for exactly this, and this family is landscape-only, which is the
     * posture that needs it.
     *
     * Implemented as an offset rather than as a second layout. Every key already knows its
     * own column on a unit grid, so "which half" is a question about that column and the
     * split is one term added to x. A separate split layout per language would be a second
     * copy of layouts.js to keep in step with the first.
     */
    property bool split: false
    /// Width of the empty middle, in grid units. Wide enough to be a gap rather than a seam.
    readonly property real splitUnits: root.split ? root.deck.units * 0.16 : 0
    /// Keys whose centre falls past this column belong to the right hand.
    readonly property real splitColumn: root.deck.units / 2

    readonly property real rowUnits: root.deck.rows.length - 1 + root.deck.fnRowScale
    // The gap is part of the width the keys have to share, or splitting would push the right
    // half off the end of the dock.
    readonly property real unitWidth: root.width / (root.deck.units + root.splitUnits)
    readonly property real unitHeight: root.height / root.rowUnits
    readonly property real splitGap: root.splitUnits * root.unitWidth

    /// How far right a key sits because of the split. Measured from the key's centre, so a
    /// wide key straddling the middle stays with the hand that most of it is under — the
    /// space bar therefore bridges the gap rather than being cut in two. Splitting it would
    /// mean editing every layout in layouts.js, which is the second copy this whole approach
    /// exists to avoid.
    function splitOffsetFor(key) {
        if (!root.split)
            return 0;
        return (key.at + key.u / 2) >= root.splitColumn ? root.splitGap : 0;
    }

    // Glyphs scale with the smaller side, or a wide dock would print letters too tall for their key.
    readonly property real glyphUnit: Math.min(root.unitWidth, root.unitHeight)

    readonly property real fnRowHeight: root.unitHeight * root.deck.fnRowScale
    // The cluster lives on the right, so it travels with the right hand.
    readonly property real clusterLeft: (root.deck.units - root.deck.clusterUnits) * root.unitWidth
        + root.splitGap

    implicitWidth: (root.deck.units + root.splitUnits) * root.preferredUnit
    implicitHeight: root.rowUnits * root.preferredUnit

    // The F-row is the only short one, so every row below it starts a whole unit further down.
    function rowTop(index) {
        return index === 0 ? 0 : root.fnRowHeight + (index - 1) * root.unitHeight;
    }

    onLayoutCodeChanged: {
        if (root.layoutCode !== "" || root.liveLayoutCode === "")
            return;
        console.log("[DeckContent] No deck for " + root.liveLayoutCode + ", using " + root.deck.short);
    }

    // One slot of the grid. The key floats inside it with half a gap on every side, so neighbours
    // end up a full gap apart and the outer edge keeps a half-gap margin.
    component KeyCell: Item {
        id: cell

        required property var modelData

        x: cell.modelData.at * root.unitWidth + root.splitOffsetFor(cell.modelData)
        width: cell.modelData.u * root.unitWidth
        height: parent ? parent.height : 0

        DeckKey {
            anchors.fill: parent
            anchors.margins: root.gap / 2
            keyData: cell.modelData
            unitWidth: root.glyphUnit
            active: cell.modelData.action === "pin" && root.pinned
            onActionTriggered: action => root.actionTriggered(action)
        }
    }

    // A row is a bare strip its keys place themselves in - no positioner. Qt's positioners quietly
    // refuse to lay out a child they once saw at zero size, which a row rebuilt on a layout swap
    // can be, and the whole grid is known in advance anyway.
    component KeyRow: Item {
        id: row

        property var keys: []
        property real heightScale: 1
        readonly property var lastKey: row.keys.length > 0 ? row.keys[row.keys.length - 1] : null

        height: root.unitHeight * row.heightScale
        width: row.lastKey ? (row.lastKey.at + row.lastKey.u) * root.unitWidth : 0

        Repeater {
            model: row.keys
            delegate: KeyCell {}
        }
    }

    Repeater {
        model: root.deck.rows

        delegate: KeyRow {
            required property var modelData
            required property int index

            y: root.rowTop(index)
            keys: modelData
            heightScale: index === 0 ? root.deck.fnRowScale : 1
        }
    }

    // The last two rows stop short by the cluster's width, which spans both of them: the arrows in
    // an inverted T, with Pin and Hide filling the two corners it leaves empty.
    KeyRow {
        x: root.clusterLeft
        y: root.rowTop(4)
        keys: root.deck.cluster.top
    }

    KeyRow {
        x: root.clusterLeft
        y: root.rowTop(5)
        keys: root.deck.cluster.bottom
    }
}
