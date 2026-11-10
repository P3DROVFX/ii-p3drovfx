import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import "."
import "TimetableHelpers.js" as H

RippleButton {
    id: nextEventIndicator
    
    property var nextEventData
    property real headerHeight
    property int timeColumnWidth
    property real dayColumnWidth
    property real itemSpacing
    property real contentY
    property real flickableHeight
    property real flickableContentHeight
    property real pixelsPerMinute
    property int startHour
    property int startMinute
    property bool showShortcutHints: false

    signal scrollRequested(real targetY)

    readonly property real nextEventY: nextEventData ? H.minutesToY(nextEventData.startMinutes, startHour, startMinute, pixelsPerMinute) : -1
    readonly property bool isAbove: nextEventData && (nextEventY + 20 < contentY)
    readonly property bool isBelow: nextEventData && (nextEventY > contentY + flickableHeight - 40)
    
    visible: nextEventData !== null && (isAbove || isBelow)
    
    width: 40
    height: 40
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colPrimary
    colBackgroundHover: Appearance.colors.colPrimaryHover
    colBackgroundActive: Appearance.colors.colPrimaryActive
    colRipple: Appearance.colors.colOnPrimary
    z: 100
    antialiasing: true
    
    x: {
        if (!nextEventData) return 0;
        return timeColumnWidth + itemSpacing + (nextEventData.dayIndex * (dayColumnWidth + itemSpacing)) + (dayColumnWidth / 2) - (width / 2);
    }
    
    y: isAbove ? headerHeight + 20 : parent.height - height - 20
    
    contentItem: TaskShortcutContent {
        anchors.centerIn: parent
        symbol: nextEventIndicator.isAbove ? "arrow_upward" : "arrow_downward"
        shortcut: "Ctrl\nJ"
        showHint: nextEventIndicator.showShortcutHints
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnPrimary
    }

    StyledToolTip {
        extraVisibleCondition: nextEventIndicator.hovered
        text: Translation.tr("Jump to event") + " (Ctrl+J)"
    }

    onClicked: {
        if (nextEventData) {
            let targetY = nextEventIndicator.nextEventY - flickableHeight / 3;
            targetY = Math.max(0, targetY);
            scrollRequested(targetY);
        }
    }
}
