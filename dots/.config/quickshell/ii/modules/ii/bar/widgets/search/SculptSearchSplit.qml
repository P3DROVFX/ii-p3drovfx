pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * `split` variant of Sculpt search — the M3 Expressive split button.
 *
 * Two halves two pixels apart, outer corners round, inner corners nearly
 * square. The leading half opens search (icon, plus the label in the balanced
 * and extended sizes); the trailing half, on the soft tone, opens the app
 * overview. The half under the pointer rounds its inner corners; the trailing
 * half becomes a full circle and offers to close while its overview is open,
 * as the spec's menu half does while its menu is.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property int contentRotation: 0
    property string sizeMode: "balanced"
    property bool hasShortcut: false
    property bool activated: false
    property bool overviewOpen: false
    property BarWidgetPalette tones

    signal activate()
    signal openOverview()

    readonly property bool compact: root.sizeMode === "compact"
    readonly property bool sharp: Appearance.rounding.scale === 0
    readonly property real outer: root.sharp ? 0 : root.thickness / 2
    readonly property real seam: root.sharp ? 0 : 4
    readonly property real gap: 2

    readonly property real leadLength: root.compact ? root.thickness : leadRow.implicitWidth + 24
    readonly property real trailLength: Math.round(root.thickness * 0.95)
    readonly property real length: root.leadLength + root.gap + root.trailLength

    implicitWidth: root.vertical ? root.thickness : root.length
    implicitHeight: root.vertical ? root.length : root.thickness

    // ── Leading half: search ────────────────────────────────────────────────
    Rectangle {
        id: lead
        readonly property bool hovered: leadHover.hovered
        property real inner: (lead.hovered || root.activated) ? root.outer : root.seam
        Behavior on inner {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(lead)
        }

        width: root.vertical ? root.thickness : root.leadLength
        height: root.vertical ? root.leadLength : root.thickness
        topLeftRadius: root.outer
        topRightRadius: root.vertical ? root.outer : lead.inner
        bottomLeftRadius: root.vertical ? lead.inner : root.outer
        bottomRightRadius: lead.inner
        color: lead.hovered ? root.tones.colBackgroundHover : root.tones.colBackground
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(lead)
        }

        HoverHandler {
            id: leadHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: root.activate()
        }

        Row {
            id: leadRow
            anchors.centerIn: parent
            rotation: root.contentRotation
            spacing: 6

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: root.activated ? "close" : "search"
                iconSize: Math.round(root.thickness * 0.56)
                color: root.tones.colOnBackground
            }

            StyledText {
                visible: !root.compact
                anchors.verticalCenter: parent.verticalCenter
                text: root.sizeMode === "extended" ? Translation.tr("Search everything") : Translation.tr("Search")
                color: root.tones.colOnBackground
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            SearchShortcutBadge {
                visible: root.hasShortcut && !root.compact
                anchors.verticalCenter: parent.verticalCenter
                badgeColor: root.tones.colBackgroundVariant
                glyphColor: root.tones.colOnBackgroundVariant
            }
        }

        StyledToolTip {
            text: Translation.tr("Open launcher")
            alternativeVisibleCondition: lead.hovered
            extraVisibleCondition: false
            requireOverlay: false
        }
    }

    // ── Trailing half: the overview ─────────────────────────────────────────
    Rectangle {
        id: trail
        readonly property bool hovered: trailHover.hovered
        property real inner: (trail.hovered || root.overviewOpen) ? root.outer : root.seam
        Behavior on inner {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(trail)
        }

        x: root.vertical ? 0 : root.leadLength + root.gap
        y: root.vertical ? root.leadLength + root.gap : 0
        width: root.vertical ? root.thickness : root.trailLength
        height: root.vertical ? root.trailLength : root.thickness
        topLeftRadius: trail.inner
        topRightRadius: root.vertical ? trail.inner : root.outer
        bottomLeftRadius: root.vertical ? root.outer : trail.inner
        bottomRightRadius: root.outer
        color: root.overviewOpen
            ? (trail.hovered ? root.tones.colBackgroundHover : root.tones.colBackground)
            : (trail.hovered ? root.tones.colBackgroundVariantHover : root.tones.colBackgroundVariant)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(trail)
        }

        HoverHandler {
            id: trailHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: root.openOverview()
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.overviewOpen ? "close" : "apps"
            fill: 1
            iconSize: Math.round(root.thickness * 0.5)
            color: root.overviewOpen ? root.tones.colOnBackground : root.tones.colOnBackgroundVariant
        }

        StyledToolTip {
            text: Translation.tr("Overview")
            alternativeVisibleCondition: trail.hovered
            extraVisibleCondition: false
            requireOverlay: false
        }
    }
}
