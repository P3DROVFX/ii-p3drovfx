pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.dynamicIsland.bubble

/**
 * The island at rest: the time, and the ongoing activities that sit beside it.
 *
 * Apple's collapsed island shares its width between a few things instead of giving it
 * to one: the clock holds the middle and the long-running, glanceable activities
 * (media, an agent at work, a screen recording, a running timer) sit at its ends,
 * balanced between the two. Anything passing through (a notification, a workspace
 * change) still takes the whole island for its moment and hands the resting face back.
 *
 * The clock is only numbers, in SF Pro Display: no shape, no container, the way the
 * time reads on Apple's hardware. Media is its cover alone, a circle a little larger
 * than the other glances - no rim, no progress - so it reads as the artwork. The others
 * are the auxiliary bubbles' own glances without their pill padding, so the two
 * presentations of an activity are the same object.
 *
 * Balance: media takes both edges - its cover at the left, a small audio visualizer at
 * the right - so the time sits centred between them. Every other arrival takes the end
 * with fewer widgets, inside media's pair. A widget keeps its end for as long as it is
 * present - nothing trades sides because a neighbour left.
 *
 * Spacing: one gap between every pair of neighbours, the clock included, and the
 * island hugs what it holds. Mirroring the wider end to keep the time mathematically
 * centred left a narrow widget (the cover) floating far from the clock while text
 * widgets ran into the other end. The ends follow what sits at them: a circle is inset
 * concentrically with the island's rounded end (the same space all round), text keeps
 * a wider inset so it clears the curve.
 *
 * The width is declared, not measured from the surface: the island animates toward
 * `targetWidth`.
 */
Item {
    id: face

    /** The side widgets present, as activity ids. */
    property var sideIds: []


    /**
     * The island's resting height, from the island. Sizes come from it rather than from
     * the live height: the width is derived from them, and a width chasing the animated
     * height would chase its own morph.
     */
    property real restHeight: IslandMotion.pillHeight
    readonly property real glanceSize: Math.round(face.restHeight * 0.68)
    // A little larger than the other glances, well clear of the island's edges.
    readonly property real coverSize: Math.round(face.restHeight * 0.72)
    /** A circle at an end: concentric with the island's rounded end. */
    readonly property real endPadding: Math.round((face.restHeight - face.coverSize) / 2)
    /** Text at an end: clear of the curve. */
    readonly property real textEndPadding: Math.round(face.restHeight * 0.36)
    /** Between any two neighbours, the clock included. */
    readonly property real itemGap: 14

    // ── Balance ──────────────────────────────────────────────────────────────
    /** Who is seated first when several arrive together. */
    readonly property var sideOrder: ["media", "ai", "recording", "timer", "earbuds", "weather"]  // media brings "mediaViz"
    /** Each end's widgets, from the island's edge inwards. */
    property var leftIds: []
    property var rightIds: []

    function isPresent(id) {
        // The visualizer is media's other half, present with it.
        return face.sideIds.indexOf(id === "mediaViz" ? "media" : id) !== -1;
    }

    /**
     * Seat arrivals on the end with fewer widgets. Widgets that left stay in their row
     * until the next arrival, so they fold away in place instead of their neighbours
     * jumping over them; an arrival clears them out first, since by then they are gone.
     */
    function reassign() {
        const arrivals = face.sideOrder.filter(id => face.isPresent(id)
            && face.leftIds.indexOf(id) === -1 && face.rightIds.indexOf(id) === -1);
        if (arrivals.length === 0)
            return;
        const left = face.leftIds.filter(id => face.isPresent(id));
        const right = face.rightIds.filter(id => face.isPresent(id));
        for (let i = 0; i < arrivals.length; i++) {
            // Media takes both ends at once - the cover at the left edge and its
            // visualizer at the right - which keeps the time between them centred.
            if (arrivals[i] === "media") {
                left.unshift("media");
                right.unshift("mediaViz");
                continue;
            }
            (face.countOthers(left) <= face.countOthers(right) ? left : right).push(arrivals[i]);
        }
        face.leftIds = left;
        face.rightIds = right;
    }
    onSideIdsChanged: face.reassign()
    Component.onCompleted: face.reassign()

    /** Widgets on an end, not counting media's pair (which sits on both). */
    function countOthers(ids) {
        return ids.filter(id => id !== "media" && id !== "mediaViz").length;
    }

    /** What a widget asks for, from its target size (never the animating one). */
    function contentWidthOf(id) {
        switch (id) {
        case "media": return face.coverSize;
        case "mediaViz": return face.coverSize;
        case "ai": return face.glanceSize;
        case "recording": return recordingGlance.preferredWidth;
        case "timer": return timerGlance.preferredWidth;
        case "earbuds": return earbudsGlance.implicitWidth;
        case "weather": return weatherGlance.implicitWidth;
        }
        return 0;
    }
    function rowTarget(ids) {
        let total = 0;
        for (let i = 0; i < ids.length; i++) {
            if (face.isPresent(ids[i]))
                total += face.contentWidthOf(ids[i]) + face.itemGap;
        }
        return total;
    }
    readonly property real leftWidth: face.rowTarget(face.leftIds)
    readonly property real rightWidth: face.rowTarget(face.rightIds)

    /** The inset at an end, from what sits outermost there. */
    function edgeFor(ids) {
        for (let i = 0; i < ids.length; i++) {
            if (face.isPresent(ids[i]))
                return (ids[i] === "media" || ids[i] === "mediaViz" || ids[i] === "ai")
                    ? face.endPadding : face.textEndPadding;
        }
        // Nothing at this end: the clock is outermost here, and it is text.
        return face.textEndPadding;
    }
    readonly property real leftEdge: face.edgeFor(face.leftIds)
    readonly property real rightEdge: face.edgeFor(face.rightIds)
    readonly property bool hasSides: face.leftWidth > 0 || face.rightWidth > 0

    // The live row widths, from the slots as they open and fold.
    function rowLive(ids) {
        let total = 0;
        for (let i = 0; i < ids.length; i++)
            total += face.slotOf(ids[i]).width;
        return total;
    }
    property real leftEdgeLive: face.leftEdge
    property real rightEdgeLive: face.rightEdge
    Behavior on leftEdgeLive {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(face)
    }
    Behavior on rightEdgeLive {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(face)
    }

    // Placement, from the slots' *live* widths: a widget opening or folding slides its
    // neighbours along with it.
    function slotOf(id) {
        switch (id) {
        case "media": return mediaSlot;
        case "mediaViz": return vizSlot;
        case "ai": return aiSlot;
        case "recording": return recordingSlot;
        case "timer": return timerSlot;
        case "earbuds": return earbudsSlot;
        case "weather": return weatherSlot;
        }
        return null;
    }
    function slotX(id) {
        let offset = 0;
        let index = face.leftIds.indexOf(id);
        if (index !== -1) {
            for (let i = 0; i < index; i++)
                offset += face.slotOf(face.leftIds[i]).width;
            return face.leftEdgeLive + offset;
        }
        index = face.rightIds.indexOf(id);
        if (index !== -1) {
            for (let i = 0; i <= index; i++)
                offset += face.slotOf(face.rightIds[i]).width;
            return face.width - face.rightEdgeLive - offset;
        }
        return 0;
    }

    readonly property real targetWidth: face.hasSides
        ? face.leftEdge + face.leftWidth + clockMetrics.advanceWidth + face.rightWidth + face.rightEdge
        : Math.max(110, clockMetrics.advanceWidth + 56)

    FontLoader {
        id: clockFont
        source: "file://" + Directories.assetsPath + "/fonts/sf-pro-display/SFPRODISPLAYBOLD.OTF"
    }
    readonly property string clockFamily: clockFont.status === FontLoader.Ready && clockFont.name
        ? clockFont.name : Appearance.font.family.main
    readonly property real clockSize: 16

    TextMetrics {
        id: clockMetrics
        text: DateTime.time
        font.family: face.clockFamily
        font.pixelSize: face.clockSize
        font.weight: Font.Bold
    }

    Text {
        id: clock
        // Between the two rows, centred in whatever the island has between them - which
        // is the whole island when nothing sits beside it.
        readonly property real before: face.leftEdgeLive + face.rowLive(face.leftIds)
        readonly property real after: face.rightEdgeLive + face.rowLive(face.rightIds)
        x: clock.before + (face.width - clock.before - clock.after - clock.width) / 2
        anchors.verticalCenter: parent.verticalCenter
        text: DateTime.time
        color: Appearance.colors.colOnLayer0
        font.family: face.clockFamily
        font.pixelSize: face.clockSize
        font.weight: Font.Bold
        // Figures that do not shift the time as a digit changes.
        font.features: ({ "tnum": 1 })
    }

    /**
     * One side widget's place in its row. It opens and closes its own width, so a
     * widget arriving slides its neighbours along instead of the row jumping, and the
     * gap it keeps sits on its inner side (towards the clock).
     */
    component SideSlot: Item {
        id: slot
        required property string sideId
        required property real contentWidth
        readonly property bool present: face.isPresent(slot.sideId)
        /** Left end: the gap is to the right of the content; right end: to its left. */
        readonly property bool leftSide: face.leftIds.indexOf(slot.sideId) !== -1
        default property alias contents: holder.data

        x: face.slotX(slot.sideId)
        width: slot.present ? slot.contentWidth + face.itemGap : 0
        height: face.height
        opacity: slot.present ? 1 : 0
        visible: slot.width > 0.5
        Behavior on width {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(slot)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(slot)
        }

        Item {
            id: holder
            x: slot.leftSide ? 0 : face.itemGap
            width: slot.contentWidth
            height: parent.height
        }
    }

    // ── The side widgets, each placed on its end by `slotX` ───────────────────
    SideSlot {
        id: mediaSlot
        sideId: "media"
        contentWidth: face.coverSize

        // Media: the cover, cut to a circle.
        Item {
            id: cover
            anchors.verticalCenter: parent.verticalCenter
            width: face.coverSize
            height: face.coverSize

            readonly property string artSource: face.isPresent("media")
                ? (MprisController.activePlayer?.trackArtUrl ?? "") : ""

            // Behind the cover, and all there is for a player that publishes none.
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Appearance.colors.colLayer2
                visible: coverImage.status !== Image.Ready

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "music_note"
                    fill: 1
                    iconSize: Math.round(parent.width * 0.5)
                    color: Appearance.colors.colOnLayer2
                }
            }

            StyledImage {
                id: coverImage
                anchors.fill: parent
                source: cover.artSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: Math.ceil(face.coverSize * 2)
                sourceSize.height: Math.ceil(face.coverSize * 2)
                visible: false
            }

            Rectangle {
                id: coverMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: parent
                source: coverImage
                visible: coverImage.status === Image.Ready
                maskEnabled: true
                maskSource: coverMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
    }

    // Media's other half: a few bars following the audio, the width of the cover.
    SideSlot {
        id: vizSlot
        sideId: "mediaViz"
        contentWidth: face.coverSize

        Row {
            id: visualizer
            anchors.centerIn: parent
            spacing: 3
            readonly property int barCount: 5
            readonly property real barWidth: 3
            readonly property real maxHeight: Math.round(face.coverSize * 0.62)
            /**
             * Read from the shared Cava process, which already runs while anything
             * plays; the island adds no work beyond drawing five bars. Nothing is read
             * while the widget is not on show, and paused music rests as dots.
             */
            readonly property var points: vizSlot.present && (MprisController.activePlayer?.isPlaying ?? false)
                ? CavaService.visualizerPoints : []

            Repeater {
                model: visualizer.barCount
                delegate: Rectangle {
                    required property int index
                    // Spread across the low and middle bands, where music moves most.
                    readonly property int source: Math.round(3 + index * 5)
                    readonly property real level: visualizer.points.length > source
                        ? Math.min(1, visualizer.points[source] / 1000) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: visualizer.barWidth
                    height: Math.max(visualizer.barWidth, level * visualizer.maxHeight)
                    radius: width / 2
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.9
                }
            }
        }
    }

    SideSlot {
        id: aiSlot
        sideId: "ai"
        contentWidth: face.glanceSize

        AuxiliaryBubbleContent {
            anchors.verticalCenter: parent.verticalCenter
            width: face.glanceSize
            activityId: face.isPresent("ai") ? "ai" : ""
            diameter: face.glanceSize
            glanceOnly: true
        }
    }

    SideSlot {
        id: recordingSlot
        sideId: "recording"
        contentWidth: recordingGlance.preferredWidth

        AuxiliaryBubbleContent {
            id: recordingGlance
            anchors.verticalCenter: parent.verticalCenter
            width: recordingGlance.preferredWidth
            activityId: "recording"
            diameter: face.glanceSize
            glanceOnly: true
        }
    }

    SideSlot {
        id: timerSlot
        sideId: "timer"
        contentWidth: timerGlance.preferredWidth

        AuxiliaryBubbleContent {
            id: timerGlance
            anchors.verticalCenter: parent.verticalCenter
            width: timerGlance.preferredWidth
            activityId: "timer"
            diameter: face.glanceSize
            glanceOnly: true
        }
    }

    // Earbuds: the headphones glyph and the case-or-bud battery, iOS-style.
    SideSlot {
        id: earbudsSlot
        sideId: "earbuds"
        contentWidth: earbudsGlance.implicitWidth

        Row {
            id: earbudsGlance
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            readonly property int iconSize: Math.round(face.glanceSize * 0.66)

            // The user's device picture (Settings → Bluetooth device images, then
            // built-in art by MAC/name) when there is one; the headphones glyph
            // otherwise. Row lays out visible children only, so they never stack.
            Image {
                id: earbudImage
                anchors.verticalCenter: parent.verticalCenter
                source: EarbudsControlService.glanceDevice
                    ? BluetoothDeviceImages.sourceFor(EarbudsControlService.glanceDevice) : ""
                sourceSize: Qt.size(earbudsGlance.iconSize, earbudsGlance.iconSize)
                width: earbudsGlance.iconSize
                height: earbudsGlance.iconSize
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "headphones"
                iconSize: earbudsGlance.iconSize
                color: Appearance.colors.colOnLayer0
                visible: earbudImage.status !== Image.Ready
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.max(0, EarbudsControlService.glancePercent) + "%"
                color: Appearance.colors.colOnLayer0
                font.family: face.clockFamily
                font.pixelSize: face.clockSize
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
            }
        }
    }

    // Weather: the same icon the bar widgets draw, with the temperature beside it.
    SideSlot {
        id: weatherSlot
        sideId: "weather"
        contentWidth: weatherGlance.implicitWidth

        Row {
            id: weatherGlance
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            readonly property int iconSize: Math.round(face.glanceSize * 0.66)

            Image {
                anchors.verticalCenter: parent.verticalCenter
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                sourceSize: Qt.size(weatherGlance.iconSize, weatherGlance.iconSize)
                fillMode: Image.PreserveAspectFit
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.data?.temp ?? ""
                color: Appearance.colors.colOnLayer0
                font.family: face.clockFamily
                font.pixelSize: face.clockSize
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
            }
        }
    }
}
