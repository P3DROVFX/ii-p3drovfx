pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * `field` variant of Sculpt search — an assistant's prompt bar.
 *
 * A soft field holding the placeholder, ended by a vivid action circle. The
 * compact size keeps only the circle. Under the pointer the circle's corners
 * pull into a rounded square; while the launcher is open it stays one and
 * offers to close it.
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
    readonly property real actionSize: root.compact ? root.thickness : root.thickness - 6
    readonly property bool sharp: Appearance.rounding.scale === 0

    readonly property real labelLength: root.compact ? 0 : placeholder.implicitWidth + (root.hasShortcut ? badge.implicitWidth + 8 : 0)
    readonly property real length: root.compact ? root.thickness : 14 + root.labelLength + 8 + root.actionSize + 3

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
        anchors.fill: parent
        visible: !root.compact
        radius: root.sharp ? 0 : root.thickness / 2
        color: root.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
        }
    }

    // ── The placeholder ─────────────────────────────────────────────────────
    Item {
        visible: !root.compact
        width: root.vertical ? root.thickness : root.length - root.actionSize - 3
        height: root.vertical ? root.length - root.actionSize - 3 : root.thickness

        Row {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.vertical ? 0 : 2
            rotation: root.contentRotation
            spacing: 8

            StyledText {
                id: placeholder
                anchors.verticalCenter: parent.verticalCenter
                text: root.sizeMode === "extended"
                    ? Translation.tr("Search apps, files & more")
                    : Translation.tr("Search")
                color: root.tones.colOnBackgroundVariant
                opacity: 0.82
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            SearchShortcutBadge {
                id: badge
                visible: root.hasShortcut
                anchors.verticalCenter: parent.verticalCenter
                badgeColor: root.tones.colBackground
                glyphColor: root.tones.colOnBackground
            }
        }
    }

    // ── The action ──────────────────────────────────────────────────────────
    Rectangle {
        id: action
        x: root.vertical ? Math.round((root.width - width) / 2) : root.width - width - (root.compact ? 0 : 3)
        y: root.vertical ? root.height - height - (root.compact ? 0 : 3) : Math.round((root.height - height) / 2)
        width: root.actionSize
        height: root.actionSize
        property real corner: root.sharp ? 0 : (root.activated || root.hovered) ? root.actionSize * 0.3 : root.actionSize / 2
        Behavior on corner {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(action)
        }
        radius: action.corner
        color: root.hovered ? root.tones.colBackgroundHover : root.tones.colBackground
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(action)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.activated ? "close" : "search"
            iconSize: Math.round(root.actionSize * 0.56)
            color: root.tones.colOnBackground
        }
    }

    StyledToolTip {
        text: Translation.tr("Open launcher")
        alternativeVisibleCondition: root.hovered
        extraVisibleCondition: false
        requireOverlay: false
    }
}
