pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * ii Vitals' tokens. Surfaces, radii, motion, type and spacing come from ClockStyle, since
 * the app is a member of the clock family; what is added here is only what Vitals has
 * that the clock does not: its destinations, its tiles, sleep stages, and how old data
 * loses emphasis.
 */
Singleton {
    id: root

    // ── Destinations ────────────────────────────────────────────────────
    /// Rail icon and title per page (VitalsTypes.pages plus "settings").
    readonly property var pageInfo: ({
        today: { icon: "today", label: Translation.tr("Today") },
        activity: { icon: "directions_walk", label: Translation.tr("Activity") },
        sleep: { icon: "bedtime", label: Translation.tr("Sleep") },
        heart: { icon: "favorite", label: Translation.tr("Heart") },
        workouts: { icon: "exercise", label: Translation.tr("Workouts") },
        body: { icon: "monitor_weight", label: Translation.tr("Body") },
        more: { icon: "category", label: Translation.tr("More") }
    })

    // ── Tiles ───────────────────────────────────────────────────────────
    // A tile is a slab one step above the window; the hero is the one primary container
    // on a page, and the controls on it follow its family.
    readonly property color colTile: ClockStyle.colIdleCard
    readonly property color colTileHover: ClockStyle.colIdleCardHover
    readonly property color colTileActive: Appearance.colors.colLayer1Active
    readonly property color colOnTile: ClockStyle.colOnSurface
    readonly property color colOnTileVariant: ClockStyle.colOnSurfaceVariant
    readonly property color colHero: ClockStyle.colPrimaryContainer
    readonly property color colHeroHover: ClockStyle.colPrimaryContainerHover
    readonly property color colHeroActive: ClockStyle.colPrimaryContainerActive
    readonly property color colOnHero: ClockStyle.colOnPrimaryContainer

    readonly property int tileMinWidth: 260
    readonly property int tileHeightMin: 200
    readonly property int tileHeightMax: 248
    /// Tile height = settled tile width × this, clamped to the two above.
    readonly property real tileRatio: 0.8
    readonly property int tilePadding: ClockStyle.cardPadding
    readonly property int heroSpan: 2
    readonly property real radiusTile: ClockStyle.radiusCard

    // ── Sleep stages ────────────────────────────────────────────────────
    // Each stage takes its own colour role (the plan's stage chart); drawn on a tile.
    // Awake is the neutral outline tone: surface-highest vanished on the tile and matched
    // the sheet's fields, and the accent roles are taken by the sleeping stages.
    function colStage(stage: string): color {
        switch (stage) {
        // A light scheme's container is nearly the tile's own tone; its fixed-dim sibling
        // keeps the contrast the container has in a dark scheme.
        case "deep": return Appearance.m3colors.darkmode ? ClockStyle.colPrimaryContainer : Appearance.m3colors.m3primaryFixedDim;
        case "light": return ClockStyle.colPrimary;
        case "rem": return ClockStyle.colTertiary;
        case "awake": return Appearance.colors.colOutline;
        default: return ClockStyle.colSecondaryContainer;
        }
    }

    readonly property int stageStripHeight: 28

    // ── Emphasis ────────────────────────────────────────────────────────
    /// Data older than this many days stays on screen with less weight instead of hiding.
    readonly property int staleDays: 14
    readonly property real staleOpacity: 0.6

    /// 1 for data from the last `staleDays`, `staleOpacity` for older (or unknown) dates.
    function emphasis(date: string, today: string): real {
        const age = VitalsFormat.daysBetween(date, today);
        return age >= 0 && age <= root.staleDays ? 1 : root.staleOpacity;
    }
}
