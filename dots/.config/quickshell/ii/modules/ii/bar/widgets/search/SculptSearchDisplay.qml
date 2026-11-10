pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * `display` variant of Sculpt search — the word is the button.
 *
 * "SEARCH" set the way an events poster sets a name: black weight, wide, and
 * slanted, on a vivid rounded-square card. Under the pointer the word stands
 * up straight (the slant axis moves in snapped steps, see
 * `variableAxes.blend`). The compact size keeps a single slash — the key most
 * apps open search with — at display size. While the launcher is open the card
 * takes the other half of the pair.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property int contentRotation: 0
    property string sizeMode: "balanced"
    property bool hasShortcut: false
    property bool activated: false
    property BarWidgetPalette tones

    signal activate()

    readonly property bool compact: root.sizeMode === "compact"
    readonly property bool hovered: hover.hovered
    readonly property bool sharp: Appearance.rounding.scale === 0

    property real upright: root.hovered ? 1 : 0
    Behavior on upright {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    readonly property color colCard: root.activated
        ? (root.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant)
        : (root.hovered ? root.tones.colBackgroundHover : root.tones.colBackground)
    readonly property color colInk: root.activated ? root.tones.colOnBackgroundVariant : root.tones.colOnBackground

    readonly property real contentLength: row.implicitWidth
    readonly property real length: root.compact ? root.thickness : root.contentLength + 18

    implicitWidth: root.vertical ? root.thickness : root.length
    implicitHeight: root.vertical ? root.length : root.thickness

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: root.activate()
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: root.sharp ? 0 : Math.round(root.thickness * 0.3)
        color: root.colCard
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.compact ? -1 : 0
        rotation: root.contentRotation
        spacing: 7

        StyledText {
            id: word
            anchors.verticalCenter: parent.verticalCenter
            text: root.compact ? "/" : Translation.tr("Search").toUpperCase()
            color: root.colInk
            font.family: Appearance.font.family.main
            font.pixelSize: Math.round(root.thickness * (root.compact ? 0.78 : 0.56))
            font.letterSpacing: root.compact ? 0 : -0.6
            font.variableAxes: ({
                "wght": 900,
                "wdth": root.compact ? 100 : 125,
                "slnt": Appearance.font.variableAxes.blend(-10, 0, root.upright),
                "ROND": 0
            })
        }

        SearchShortcutBadge {
            visible: root.hasShortcut && !root.compact
            anchors.verticalCenter: parent.verticalCenter
            badgeColor: root.activated ? root.tones.colBackground : root.tones.colBackgroundVariant
            glyphColor: root.activated ? root.tones.colOnBackground : root.tones.colOnBackgroundVariant
        }
    }

    StyledToolTip {
        text: Translation.tr("Open launcher")
        alternativeVisibleCondition: root.hovered
        extraVisibleCondition: false
        requireOverlay: false
    }
}
