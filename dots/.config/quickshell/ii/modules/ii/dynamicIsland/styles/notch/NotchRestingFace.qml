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
 * to one: the clock holds the middle and the long-running, glanceable activities sit
 * at its ends - media's cover and a screen recording at the left, an agent at work and
 * a running timer at the right. Anything passing through (a notification, a workspace
 * change) still takes the whole island for its moment and hands the resting face back.
 *
 * The clock is only numbers, in SF Pro Display: no shape, no container, the way the
 * time reads on Apple's hardware. Media is its cover alone, a circle a little larger
 * than the other glances - no rim, no progress - so it reads as the artwork. The others
 * are the auxiliary bubbles' own glances without their pill padding, so the two
 * presentations of an activity are the same object.
 *
 * The width is declared, not measured from the surface: the island animates toward
 * `targetWidth`. Both ends reserve the wider of the two rows, so the time stays centred
 * whatever sits on either side.
 */
Item {
    id: face

    /** The side widgets present, as activity ids. */
    property var sideIds: []

    readonly property bool hasMedia: face.sideIds.indexOf("media") !== -1
    readonly property bool hasRecording: face.sideIds.indexOf("recording") !== -1
    readonly property bool hasAi: face.sideIds.indexOf("ai") !== -1
    readonly property bool hasTimer: face.sideIds.indexOf("timer") !== -1

    /**
     * The island's resting height, from the island. Sizes come from it rather than from
     * the live height: the width is derived from them, and a width chasing the animated
     * height would chase its own morph.
     */
    property real restHeight: IslandMotion.pillHeight
    readonly property real glanceSize: Math.round(face.restHeight * 0.68)
    // A little larger than the other glances, well clear of the island's edges.
    readonly property real coverSize: Math.round(face.restHeight * 0.72)
    readonly property real endPadding: Math.round((face.restHeight - face.coverSize) / 2)
    /** Between two side widgets, and between the inner one and the clock. */
    readonly property real itemGap: 12

    // What each row asks for, from the target widths (never the animating ones).
    function slotWidth(present, contentWidth) {
        return present ? contentWidth + face.itemGap : 0;
    }
    readonly property real leftWidth: face.slotWidth(face.hasMedia, face.coverSize)
        + face.slotWidth(face.hasRecording, recordingGlance.preferredWidth)
    readonly property real rightWidth: face.slotWidth(face.hasAi, face.glanceSize)
        + face.slotWidth(face.hasTimer, timerGlance.preferredWidth)
    readonly property real sideReserve: Math.max(face.leftWidth, face.rightWidth)

    readonly property real targetWidth: face.sideReserve > 0
        ? 2 * (face.endPadding + face.sideReserve + 2) + clockMetrics.advanceWidth
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
        anchors.centerIn: parent
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
        required property bool present
        required property real contentWidth
        /** Left row: the gap is to the right of the content; right row: to its left. */
        property bool leftSide: true
        default property alias contents: holder.data

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

    // ── Left: media, then a screen recording ─────────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.leftMargin: face.endPadding
        height: parent.height

        SideSlot {
            present: face.hasMedia
            contentWidth: face.coverSize

            // Media: the cover, cut to a circle.
            Item {
                id: cover
                anchors.verticalCenter: parent.verticalCenter
                width: face.coverSize
                height: face.coverSize

                readonly property string artSource: face.hasMedia
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

        SideSlot {
            present: face.hasRecording
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
    }

    // ── Right: an agent, then a running timer ────────────────────────────────
    Row {
        anchors.right: parent.right
        anchors.rightMargin: face.endPadding
        height: parent.height
        layoutDirection: Qt.RightToLeft

        SideSlot {
            present: face.hasAi
            contentWidth: face.glanceSize
            leftSide: false

            AuxiliaryBubbleContent {
                anchors.verticalCenter: parent.verticalCenter
                width: face.glanceSize
                activityId: face.hasAi ? "ai" : ""
                diameter: face.glanceSize
                glanceOnly: true
            }
        }

        SideSlot {
            present: face.hasTimer
            contentWidth: timerGlance.preferredWidth
            leftSide: false

            AuxiliaryBubbleContent {
                id: timerGlance
                anchors.verticalCenter: parent.verticalCenter
                width: timerGlance.preferredWidth
                activityId: "timer"
                diameter: face.glanceSize
                glanceOnly: true
            }
        }
    }
}
