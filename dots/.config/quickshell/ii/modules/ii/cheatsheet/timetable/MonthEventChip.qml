import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import "TimetableHelpers.js" as H

/**
 * One event inside a month cell.
 *
 * All-day events are filled with the event colour so they read as a band across
 * the day; timed events use a dot plus time, which keeps a busy cell legible.
 * Read-only sports projections use a tertiary filled pill and a sports icon so
 * they cannot be mistaken for appointments that can be edited or dragged.
 * Dragging is reported to the month view in its coordinate space — the chip
 * never reparents itself, so cell clipping cannot swallow the drag proxy.
 */
Item {
    id: root

    required property var eventData
    property bool allDay: false
    property bool dragEnabled: true
    property bool dragging: false
    property bool compact: false
    /** Item the drag coordinates are reported in. */
    property Item coordinateRoot: null
    property int entranceKey: 0
    property int entranceIndex: 0

    signal activated
    signal dragBegan(var eventData, real x, real y, real w, real h)
    signal dragMoved(real x, real y)
    signal dragEnded
    signal dragCanceled

    implicitHeight: compact ? 20 : 24

    readonly property color accent: H.chipColor(root.eventData, Appearance.colors, GoogleCalendarService.colorForEvent(root.eventData))
    readonly property bool sportEvent: root.eventData?.sportEvent === true
    readonly property bool hasExceptions: (root.eventData?.exdates?.length ?? CalendarService.eventDetailsForUid(root.eventData?.uid)?.exdates?.length ?? 0) > 0
    readonly property string titleText: root.eventData?.content ?? Translation.tr("Event")
    readonly property string timeText: H.eventStartText(root.eventData, Config.options?.time.format)

    opacity: root.dragging ? 0.3 : 1.0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    // ─── Entrance ───
    // Visible on creation, animated only when the month view bumps entranceKey.
    // A chip is recreated whenever its cell rebuilds its entry array — which
    // happens every time SportsService republishes, right after the grid has
    // settled — so replaying the entrance on creation makes the whole month
    // flash. The open case is covered by MonthView.gridOpacity starting at 0:
    // the first entranceKey bump lands while the grid is still invisible.
    property real revealProgress: 1.0
    transform: Translate {
        id: revealTranslate
        x: (1.0 - root.revealProgress) * -10
    }

    onEntranceKeyChanged: root.replayEntrance()

    function replayEntrance() {
        revealAnim.stop();
        root.revealProgress = 0.0;
        revealAnim.start();
    }

    SequentialAnimation {
        id: revealAnim
        PauseAnimation {
            duration: Math.min(140, root.entranceIndex * 26)
        }
        NumberAnimation {
            target: root
            property: "revealProgress"
            from: 0.0
            to: 1.0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.allDay ? Appearance.rounding.verysmall : Math.min(height / 2, Appearance.rounding.small)
        opacity: root.revealProgress
        color: {
            if (root.sportEvent)
                return pointer.containsMouse ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colTertiaryContainer;
            if (root.allDay)
                return pointer.containsMouse ? ColorUtils.mix(root.accent, Appearance.colors.colOnSurface, 0.88) : root.accent;
            if (pointer.containsMouse)
                return ColorUtils.applyAlpha(root.accent, 0.28);
            return "transparent";
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(surface)
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: root.allDay || root.sportEvent ? 7 : 5
            anchors.rightMargin: 6
            spacing: 5

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.allDay && !root.sportEvent
                width: root.compact ? 6 : 7
                height: width
                radius: width / 2
                color: root.accent
            }

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.sportEvent
                text: "sports_score"
                iconSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnTertiaryContainer
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.allDay && !root.compact && root.timeText.length > 0
                text: root.timeText
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: root.sportEvent ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurfaceVariant
            }

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.compact && (root.eventData?.repeatSymbol ?? "").length > 0
                text: "repeat"
                iconSize: Appearance.font.pixelSize.smallest
                color: root.sportEvent ? Appearance.colors.colOnTertiaryContainer : (root.allDay ? ColorUtils.getContrastingTextColor(root.accent) : Appearance.colors.colOnSurfaceVariant)
            }

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.compact && root.hasExceptions
                text: "event_busy"
                iconSize: Appearance.font.pixelSize.smallest
                color: root.sportEvent ? Appearance.colors.colOnTertiaryContainer : (root.allDay ? ColorUtils.getContrastingTextColor(root.accent) : Appearance.colors.colOnSurfaceVariant)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - x)
                text: root.titleText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: root.compact ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                font.strikeout: String(root.eventData?.status ?? "").toUpperCase() === "CANCELLED"
                color: root.sportEvent ? Appearance.colors.colOnTertiaryContainer : (root.allDay ? ColorUtils.getContrastingTextColor(root.accent) : Appearance.colors.colOnSurface)
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: pointer.containsMouse && !root.dragging
        text: {
            const parts = [root.titleText];
            if (root.allDay)
                parts.push(Translation.tr("All day"));
            else
                parts.push(H.eventRangeText(root.eventData, Config.options?.time.format));
            if (root.eventData?.description)
                parts.push(root.eventData.description);
            if (root.eventData?.calendar)
                parts.push(root.eventData.calendar);
            return parts.filter(part => String(part).length > 0).join("\n");
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        readonly property int dragThreshold: 6
        property real pressX: 0
        property real pressY: 0
        property bool started: false

        function scenePoint(mouse) {
            if (!root.coordinateRoot)
                return Qt.point(mouse.x, mouse.y);
            return root.mapToItem(root.coordinateRoot, mouse.x, mouse.y);
        }

        onPressed: mouse => {
            pointer.pressX = mouse.x;
            pointer.pressY = mouse.y;
            pointer.started = false;
        }

        onPositionChanged: mouse => {
            if (!pointer.pressedButtons || !root.dragEnabled)
                return;
            const point = pointer.scenePoint(mouse);
            if (pointer.started) {
                root.dragMoved(point.x, point.y);
                return;
            }
            if (Math.abs(mouse.x - pointer.pressX) + Math.abs(mouse.y - pointer.pressY) < pointer.dragThreshold)
                return;
            pointer.started = true;
            const origin = root.mapToItem(root.coordinateRoot, 0, 0);
            root.dragBegan(root.eventData, origin.x, origin.y, root.width, root.height);
            root.dragMoved(point.x, point.y);
        }

        onReleased: {
            if (pointer.started) {
                pointer.started = false;
                root.dragEnded();
                return;
            }
            root.activated();
        }

        onCanceled: {
            if (!pointer.started)
                return;
            pointer.started = false;
            root.dragCanceled();
        }
    }
}
