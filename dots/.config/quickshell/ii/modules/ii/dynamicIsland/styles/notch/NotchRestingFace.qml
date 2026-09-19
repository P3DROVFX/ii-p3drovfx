pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.dynamicIsland.bubble

/**
 * The island at rest: the time, and the ongoing activities that sit beside it.
 *
 * Apple's collapsed island shares its width between a few things instead of giving it
 * to one: the clock holds the middle, media's cover sits at the left end and an agent
 * at work at the right. Side widgets are only the long-running, glanceable activities
 * (media and AI for now); anything passing through - a notification, a workspace
 * change - still takes the whole island for its moment and hands the resting face back.
 *
 * The clock is only numbers, in SF Pro Display: no shape, no container, the way the
 * time reads on Apple's hardware. The glances are the auxiliary bubbles' own, cut to
 * their circle, so the two presentations of an activity are the same object.
 *
 * The width is declared, not measured from the surface: the island animates toward
 * `targetWidth`, and the clock stays centred because the two ends are reserved
 * symmetrically - one side widget still keeps the time in the middle.
 */
Item {
    id: face

    /** The side widgets present, as activity ids ("media", "ai"). */
    property var sideIds: []

    readonly property bool hasMedia: face.sideIds.indexOf("media") !== -1
    readonly property bool hasAi: face.sideIds.indexOf("ai") !== -1
    readonly property bool hasSides: face.hasMedia || face.hasAi

    // A fixed size, from the island's resting height rather than its live one: the
    // width is derived from it, and a width chasing the animated height would chase
    // its own morph.
    readonly property real glanceSize: Math.round(IslandMotion.pillHeight * 0.68)
    readonly property real endPadding: 10
    readonly property real sideGap: 14

    readonly property real targetWidth: face.hasSides
        ? 2 * (face.endPadding + face.glanceSize + face.sideGap) + clockMetrics.advanceWidth
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

    component SideGlance: AuxiliaryBubbleContent {
        id: glance
        required property bool present
        required property string sideId
        // Built only while it is on show, or on its way out.
        activityId: glance.present || glance.opacity > 0.01 ? glance.sideId : ""
        width: face.glanceSize
        diameter: face.glanceSize
        glanceOnly: true
        anchors.verticalCenter: parent.verticalCenter
        // Arrives and leaves in place while the island widens or narrows around it.
        opacity: glance.present ? 1 : 0
        scale: glance.present ? 1 : 0.6
        visible: glance.opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(glance)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(glance)
        }
    }

    SideGlance {
        anchors.left: parent.left
        anchors.leftMargin: face.endPadding
        sideId: "media"
        present: face.hasMedia
    }

    SideGlance {
        anchors.right: parent.right
        anchors.rightMargin: face.endPadding
        sideId: "ai"
        present: face.hasAi
    }
}
