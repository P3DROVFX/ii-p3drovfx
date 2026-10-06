pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import "../../../ii/dock/widgets"
import "../../../ii/dock/utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * The dock, live, at the edge of the wallpaper it sits on.
 *
 * What is on it comes from the running dock (`GlobalStates.dockContents`): the
 * same items in the same order, drawn by the dock's own buttons and widgets over
 * an inert `DockPreviewContext`. The tray around them follows Dock.qml's rules for
 * each style (radius, edge gap, hug corners, notch, full width), so a style can be
 * tried on (`styleOverride`) before it is chosen. Nothing on the stage takes input.
 */
Item {
    id: root

    /** A style to show instead of the saved one ("" for the saved one). */
    property string styleOverride: ""
    property bool dockOn: Config.options.dock.enable

    readonly property var live: GlobalStates.dockContents.length > 0 ? GlobalStates.dockContents[0] : null
    /** Item types to leave off the stage (e.g. the apps, on the widgets page). */
    property var hiddenTypes: []
    readonly property var items: {
        const all = root.dockOn && root.live ? (root.live.modelItems ?? []) : [];
        return root.hiddenTypes.length === 0 ? all : all.filter(item => root.hiddenTypes.indexOf(item?.type) < 0);
    }
    readonly property int count: root.items.length

    /** An edge to show instead of the saved one ("" for the saved one). */
    property string positionOverride: ""
    readonly property string pos: {
        const p = root.positionOverride.length > 0 ? root.positionOverride : (Config.options.dock.position ?? "bottom");
        if (p !== "auto")
            return p;
        return (Config.options.bar.bottom && !Config.options.bar.vertical) ? "top" : "bottom";
    }
    readonly property bool vertical: root.pos === "left" || root.pos === "right"
    readonly property string savedStyle: {
        const st = Config.options.dock.dockStyle ?? "";
        if (["islands", "dynamic_island", "hug", "floating", "transparent", "full_width", "full_width_concave"].indexOf(st) >= 0)
            return st;
        return (Config.options.dock.islandsStyle ?? false) ? "islands" : "floating";
    }
    readonly property string dockStyle: root.styleOverride.length > 0 ? root.styleOverride : root.savedStyle

    readonly property bool isIslands: root.dockStyle === "islands"
    readonly property bool isDynamic: root.dockStyle === "dynamic_island"
    readonly property bool isHug: root.dockStyle === "hug"
    readonly property bool isTransparent: root.dockStyle === "transparent"
    readonly property bool isFullWidthConcave: root.dockStyle === "full_width_concave"
    readonly property bool isFullWidth: root.dockStyle === "full_width" || root.isFullWidthConcave
    readonly property bool isAttached: root.isDynamic || root.isHug || root.isFullWidth

    /** Where the page's pills go: the edge away from the dock. */
    readonly property string pillEdge: root.pos === "bottom" ? "top" : "bottom"
    /** Height the page gives the stage: a strip for a horizontal dock, a band for a side one. */
    readonly property real preferredHeight: root.vertical
        ? Math.max(300, Math.min(560, root.trayLength * 0.4 + root.shadowPad * 2 + 40))
        : Math.max(176, Math.min(232, root.width / 4.4))

    /** Plays "launch" or "notification" on the apps on the stage. */
    function playAttention(kind) {
        ctx.attentionRequested(kind);
    }

    // ── The dock's own geometry ───────────────────────────────────────────
    DockPreviewContext {
        id: ctx
        live: root.live
        dockPos: root.pos
        dockWidgetsActive: root.visible && root.dockOn
    }

    readonly property real slot: ctx.buttonSlotSize
    readonly property real cross: root.vertical ? ctx.buttonSlotSize : ctx.buttonSlotHeight
    readonly property real spacing: Config.options.dock.iconSpacing ?? 0
    readonly property real shadowPad: Math.round(Appearance.sizes.elevationMargin * 1.2)
    readonly property real edgeGap: root.isAttached ? 0 : root.shadowPad
    readonly property real sepThickness: Math.max(3, Math.round(Appearance.sizes.dockButtonSize * 0.06))
    readonly property real sepSlot: Math.max(ctx.dotMargin, root.sepThickness * 2)
    readonly property bool showDividers: (Config.options.dock.showDividers ?? true) && !root.isIslands
    readonly property real islandExtraGap: root.isIslands
        ? Math.max(0, (Config.options.dock.islandSpacing ?? 8) - root.spacing) : 0
    readonly property real cornerRadius: (Config.options.dock.dockRadius ?? -1) >= 0
        ? Config.options.dock.dockRadius
        : (root.isAttached ? Appearance.rounding.windowRounding : Appearance.rounding.windowRounding + 12)
    readonly property real concaveRadius: Math.min((Config.options.dock.dockRadius ?? -1) >= 0
        ? Config.options.dock.dockRadius : Appearance.rounding.large, root.cross * 0.8)
    readonly property int livePreviewSlots: Math.max(2, Math.min(6, Config.options.dock.livePreviewSlots ?? 2))

    function extentFor(item) {
        if (root.vertical || !item)
            return root.slot;
        switch (item.type) {
        case "media":
        case "weather":
        case "tasks":
            return root.slot * 3;
        case "sports":
            return root.slot * ctx.sportsWidgetSlots;
        case "livePreview":
            return root.slot * root.livePreviewSlots;
        case "widgetStack":
            return root.live ? root.live.widgetStackExtent : root.slot * 3;
        case "utility":
            return root.slot * DockUtilityCatalog.slotsFor(item, false);
        default:
            return root.slot;
        }
    }

    // DockContent._separatorBeforeSpaceFor / _separatorAfterSpaceFor.
    function sepBefore(index) {
        if (!root.showDividers || index <= 0 || !root.live)
            return 0;
        const item = root.items[index];
        if (Config.options.dock.smartGrouping)
            return root.live.getItemCategory(item) !== root.live.getItemCategory(root.items[index - 1]) ? root.sepSlot : 0;
        return root.live.isSpecialItem(item) ? root.sepSlot : 0;
    }
    function sepAfter(index) {
        if (!root.showDividers || index >= root.items.length - 1 || !root.live || Config.options.dock.smartGrouping)
            return 0;
        return root.live.isSpecialItem(root.items[index]) && !root.live.isSpecialItem(root.items[index + 1]) ? root.sepSlot : 0;
    }

    /** Main-axis placement of every item, and the islands they form. */
    readonly property var layout: {
        const list = root.items;
        const out = [];
        const segments = root.isIslands && root.live ? root.live._buildIslandSegments(list) : [];
        const starts = {};
        for (const segment of segments)
            starts[segment.startIndex] = true;
        let cursor = 0;
        for (let i = 0; i < list.length; i++) {
            const gap = i > 0 && starts[i] ? root.islandExtraGap : 0;
            const before = root.sepBefore(i);
            const after = root.sepAfter(i);
            const extent = root.extentFor(list[i]);
            out.push({
                "start": cursor,
                "body": cursor + gap + before,
                "extent": extent,
                "before": before,
                "after": after
            });
            cursor += gap + before + extent + after + (i < list.length - 1 ? root.spacing : 0);
        }
        return { "items": out, "length": cursor, "segments": segments };
    }
    readonly property real contentLength: Math.max(root.slot, root.layout.length)
    readonly property real trayLength: root.contentLength + (root.isDynamic ? root.concaveRadius * 2 : 0)

    /**
     * Down only: the dock keeps its own pixel size while it fits. Never below half
     * size (a side dock, whose band is shorter than a page is wide: a third) — past
     * that the icons stop reading, so a long dock runs off both ends instead.
     */
    readonly property real fitScale: {
        const room = (root.vertical ? root.height : root.width) - 40;
        const needs = root.trayLength + root.shadowPad * 2;
        return Math.max(root.vertical ? 0.35 : 0.5, Math.min(1, room / Math.max(1, needs)));
    }
    property real liveScale: root.fitScale
    Behavior on liveScale {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // ── Backdrop: the edge of the desktop the dock sits on ───────────────
    ClippingRectangle {
        id: backdrop
        anchors.fill: parent
        // The screen's own corners: a larger radius cut the ends of attached docks.
        radius: Appearance.rounding.windowRounding
        color: Appearance.colors.colLayer2

        Item {
            // The wallpaper at the screen's proportions, of which the stage sees the dock's edge.
            width: parent.width
            height: Math.max(parent.height, parent.width * 9 / 16)
            y: root.pos === "bottom" ? parent.height - height
                : root.pos === "top" ? 0 : (parent.height - height) / 2
            ColorsWallpaperImage {
                anchors.fill: parent
                targetMode: "desktop"
                visible: root.visible
            }
        }
        // Keeps a light wallpaper from swallowing a light dock, and the other way round.
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            opacity: root.dockOn ? 0.16 : 0.42
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        // ── The scene, at the dock's own pixel size ──────────────────────
        Item {
            id: scene
            width: root.width / root.liveScale
            height: root.height / root.liveScale
            scale: root.liveScale
            transformOrigin: Item.TopLeft
            visible: root.items.length > 0

            readonly property real mainLength: root.vertical ? scene.height : scene.width
            readonly property real trayMain: root.isFullWidth ? scene.mainLength : root.trayLength
            readonly property real trayMainStart: (scene.mainLength - scene.trayMain) / 2
            readonly property real contentMainStart: (scene.mainLength - root.contentLength) / 2
            // Cross position of the tray's near edge to the screen edge.
            readonly property real trayCross: root.pos === "bottom" ? scene.height - root.edgeGap - root.cross
                : root.pos === "right" ? scene.width - root.edgeGap - root.cross
                : root.edgeGap

            StyledRectangularShadow {
                target: tray
                cached: true
                blur: Appearance.sizes.elevationMargin
                spread: 0
                color: Qt.rgba(0, 0, 0, 0.35)
                offset: root.pos === "left" ? Qt.vector2d(2, 0) : root.pos === "right" ? Qt.vector2d(-2, 0)
                    : root.pos === "top" ? Qt.vector2d(0, 2) : Qt.vector2d(0, -2)
                visible: !root.isIslands && !root.isDynamic && !root.isTransparent
                    && !Config.options.appearance.transparency.popups
                    && !Config.options.appearance.transparency.enable
            }

            // The tray (Dock.qml › dockVisualBackground).
            Rectangle {
                id: tray
                x: root.vertical ? scene.trayCross : scene.trayMainStart
                y: root.vertical ? scene.trayMainStart : scene.trayCross
                width: root.vertical ? root.cross : scene.trayMain
                height: root.vertical ? scene.trayMain : root.cross
                readonly property real trayRadius: root.isAttached ? 0 : root.cornerRadius
                readonly property real hugRadius: root.cornerRadius
                color: root.isTransparent || (root.isDynamic && !root.vertical) ? "transparent" : Appearance.colors.colLayer0
                opacity: root.isIslands || root.isTransparent ? 0 : 1
                topLeftRadius: root.isHug ? ((root.pos === "bottom" || root.pos === "right") ? tray.hugRadius : 0)
                    : root.isDynamic && root.vertical ? (root.pos === "right" ? tray.hugRadius : 0) : tray.trayRadius
                topRightRadius: root.isHug ? ((root.pos === "bottom" || root.pos === "left") ? tray.hugRadius : 0)
                    : root.isDynamic && root.vertical ? (root.pos === "left" ? tray.hugRadius : 0) : tray.trayRadius
                bottomLeftRadius: root.isHug ? ((root.pos === "top" || root.pos === "right") ? tray.hugRadius : 0)
                    : root.isDynamic && root.vertical ? (root.pos === "right" ? tray.hugRadius : 0) : tray.trayRadius
                bottomRightRadius: root.isHug ? ((root.pos === "top" || root.pos === "left") ? tray.hugRadius : 0)
                    : root.isDynamic && root.vertical ? (root.pos === "left" ? tray.hugRadius : 0) : tray.trayRadius
                Behavior on width {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Notch {
                    id: notch
                    visible: root.isDynamic && !root.vertical
                    anchors.fill: parent
                    bodyWidth: parent.width
                    bodyHeight: parent.height
                    disableBehaviors: true
                    topRadius: root.concaveRadius
                    bottomRadius: Math.min(root.cornerRadius, parent.height)
                    fillColor: Appearance.colors.colLayer0
                    transform: Scale {
                        xScale: 1
                        yScale: root.pos === "bottom" ? -1 : 1
                        origin.y: notch.height / 2
                    }
                }

                // Full width · rounded, and a side dynamic island: the tray curves
                // into the screen at both ends of its inner edge.
                Repeater {
                    model: (root.isFullWidthConcave || (root.isDynamic && root.vertical)) && !root.isIslands ? 2 : 0
                    delegate: RoundCorner {
                        required property int index
                        readonly property bool startEnd: index === 0
                        readonly property bool alongEdge: root.isDynamic
                        implicitSize: Math.max(1, root.concaveRadius)
                        color: Appearance.colors.colLayer0
                        corner: root.isDynamic
                            ? (root.pos === "left" ? (startEnd ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.TopLeft)
                                : (startEnd ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.TopRight))
                            : root.pos === "top" ? (startEnd ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.TopRight)
                            : root.pos === "left" ? (startEnd ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.BottomLeft)
                            : root.pos === "right" ? (startEnd ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.BottomRight)
                            : (startEnd ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight)
                        // The side island's corners sit past its two ends, on the edge;
                        // full width's sit on its inner side, at the screen's two sides.
                        x: alongEdge ? (root.pos === "left" ? 0 : parent.width - width)
                            : root.pos === "left" ? parent.width - 1
                            : root.pos === "right" ? -width + 1
                            : (startEnd ? 0 : parent.width - width)
                        y: alongEdge ? (startEnd ? -height + 1 : parent.height - 1)
                            : root.pos === "bottom" ? -height + 1
                            : root.pos === "top" ? parent.height - 1
                            : (startEnd ? 0 : parent.height - height)
                    }
                }
            }

            // Islands: one surface per run of items, as the dock draws them.
            Repeater {
                model: root.isIslands ? root.layout.segments : []
                delegate: DockIslandSurface {
                    required property var modelData
                    readonly property var first: root.layout.items[modelData.startIndex]
                    readonly property var last: root.layout.items[modelData.endIndex]
                    readonly property real mainStart: scene.contentMainStart + (first ? first.body : 0)
                    readonly property real mainLength: last && first ? (last.body + last.extent) - first.body : 0
                    active: true
                    islandKind: modelData.kind
                    dockPosition: root.pos
                    cornerRadius: root.cornerRadius
                    x: root.vertical ? scene.trayCross : mainStart
                    y: root.vertical ? mainStart : scene.trayCross
                    width: root.vertical ? root.cross : mainLength
                    height: root.vertical ? mainLength : root.cross
                }
            }

            // The items, each by the dock's own component.
            Repeater {
                model: root.items
                delegate: Item {
                    id: slotItem
                    required property var modelData
                    required property int index
                    readonly property var place: root.layout.items[slotItem.index] ?? null
                    readonly property real mainPos: scene.contentMainStart + (slotItem.place ? slotItem.place.body : 0)
                    readonly property real extent: slotItem.place ? slotItem.place.extent : root.slot

                    x: root.vertical ? scene.trayCross : slotItem.mainPos
                    y: root.vertical ? slotItem.mainPos : scene.trayCross
                    width: root.vertical ? root.cross : slotItem.extent
                    height: root.vertical ? slotItem.extent : root.cross

                    // Dividers sit in their own slots on either side (DockContent's wrapper).
                    Rectangle {
                        visible: (slotItem.place?.before ?? 0) > 0
                        readonly property real offset: -(slotItem.place?.before ?? 0) + ((slotItem.place?.before ?? 0) - root.sepThickness) / 2
                        x: root.vertical ? ctx.dotMargin : offset
                        y: root.vertical ? offset : ctx.dotMarginV
                        width: root.vertical ? parent.width - ctx.dotMargin * 2 : root.sepThickness
                        height: root.vertical ? root.sepThickness : parent.height - ctx.dotMarginV * 2
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colOutlineVariant
                    }
                    Rectangle {
                        visible: (slotItem.place?.after ?? 0) > 0
                        readonly property real offset: slotItem.extent + ((slotItem.place?.after ?? 0) - root.sepThickness) / 2
                        x: root.vertical ? ctx.dotMargin : offset
                        y: root.vertical ? offset : ctx.dotMarginV
                        width: root.vertical ? parent.width - ctx.dotMargin * 2 : root.sepThickness
                        height: root.vertical ? root.sepThickness : parent.height - ctx.dotMarginV * 2
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colOutlineVariant
                    }

                    DockItemView {
                        anchors.fill: parent
                        itemData: slotItem.modelData
                        itemIndex: slotItem.index
                        context: ctx
                    }
                }
            }
        }

        // Takes every press and hover on the stage — the dock stays a picture — and
        // hands the wheel on to the page.
        DockInputShield {}
    }
}
