import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The app chip of a window card, the overview's take on Android's recents:
 * icon, app name and a chevron that opens the window's menu.
 *
 * Geometry is computed, not laid out, so the chip never grows past
 * `maxWidth`; a name that does not fit is dropped before it elides to a stub.
 */
Item {
    id: root

    property string appName
    property string iconSource
    property real maxWidth: 0
    property bool compact: false
    property bool focusedWindow: false
    property bool engaged: false
    property bool menuOpen: false
    property bool animationsEnabled: true

    signal clicked()

    readonly property bool active: root.engaged || root.menuOpen
    readonly property color colChip: root.focusedWindow ? OverviewStyle.colChipFocused
        : root.active ? OverviewStyle.colChipHovered : OverviewStyle.colChip
    readonly property color colContent: root.focusedWindow ? OverviewStyle.colOnChipFocused
        : root.active ? OverviewStyle.colOnChipHovered : OverviewStyle.colOnChip

    readonly property real chipHeight: root.compact ? OverviewStyle.chipHeightCompact : OverviewStyle.chipHeight
    readonly property real badgeSize: root.compact ? OverviewStyle.chipIconBadgeCompact : OverviewStyle.chipIconBadge
    readonly property real startPad: (root.chipHeight - root.badgeSize) / 2
    readonly property real chevronSize: root.compact ? OverviewStyle.chipChevronSizeCompact : OverviewStyle.chipChevronSize
    readonly property real fixedWidth: root.startPad + root.badgeSize + OverviewStyle.chipSpacing + root.chevronSize + OverviewStyle.chipPaddingEnd
    readonly property real nameWidth: {
        const wanted = Math.min(nameText.implicitWidth, OverviewStyle.chipMaxNameWidth);
        const width = Math.max(0, Math.min(wanted, root.maxWidth - root.fixedWidth - OverviewStyle.chipSpacing));
        return width >= wanted || width >= OverviewStyle.chipMinNameWidth ? width : 0;
    }
    readonly property real nameGap: root.nameWidth > 0 ? OverviewStyle.chipSpacing : 0

    implicitHeight: root.chipHeight
    implicitWidth: Math.min(root.maxWidth, root.fixedWidth + root.nameGap + root.nameWidth)

    // ── Done feedback: the chevron turns into the action's glyph for a moment ──
    property string doneSymbol: ""
    function markDone(symbol) {
        root.doneSymbol = symbol;
        doneTimer.restart();
    }
    Timer {
        id: doneTimer
        interval: OverviewStyle.actionDoneDuration
        onTriggered: root.doneSymbol = ""
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: OverviewStyle.radiusFor(height)
        color: chipMouse.pressed ? ColorUtils.mix(root.colChip, root.colContent, 1 - OverviewStyle.actionTintPressed) : root.colChip
        clip: true
        Behavior on color {
            enabled: root.animationsEnabled
            animation: OverviewStyle.motionFast.colorAnimation.createObject(this)
        }

        Rectangle {
            id: badge
            x: root.startPad
            anchors.verticalCenter: parent.verticalCenter
            width: root.badgeSize
            height: root.badgeSize
            radius: OverviewStyle.radiusFor(height)
            color: root.focusedWindow ? root.colContent : ColorUtils.applyAlpha(root.colContent, OverviewStyle.chipBadgeTint)
            Behavior on color {
                enabled: root.animationsEnabled
                animation: OverviewStyle.motionFast.colorAnimation.createObject(this)
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: root.compact ? OverviewStyle.chipIconSizeCompact : OverviewStyle.chipIconSize
                source: root.iconSource
            }
        }

        StyledText {
            id: nameText
            x: badge.x + badge.width + root.nameGap
            anchors.verticalCenter: parent.verticalCenter
            width: root.nameWidth
            visible: width > 0
            text: root.appName
            elide: Text.ElideRight
            color: root.colContent
            font.family: Appearance.font.family.main
            font.pixelSize: OverviewStyle.chipNameSize
            font.variableAxes: OverviewStyle.chipNameAxes
            Behavior on color {
                enabled: root.animationsEnabled
                animation: OverviewStyle.motionFast.colorAnimation.createObject(this)
            }
        }

        MaterialSymbol {
            id: chevron
            x: root.width - OverviewStyle.chipPaddingEnd - root.chevronSize
            anchors.verticalCenter: parent.verticalCenter
            width: root.chevronSize
            horizontalAlignment: Text.AlignHCenter
            text: root.doneSymbol.length > 0 ? root.doneSymbol : "expand_more"
            fill: root.doneSymbol.length > 0 ? 1 : 0
            iconSize: root.chevronSize
            color: root.colContent
            rotation: root.menuOpen && root.doneSymbol.length === 0 ? 180 : 0
            Behavior on rotation {
                enabled: root.animationsEnabled
                animation: OverviewStyle.motionMove.numberAnimation.createObject(this)
            }
            Behavior on color {
                enabled: root.animationsEnabled
                animation: OverviewStyle.motionFast.colorAnimation.createObject(this)
            }
        }
    }

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
