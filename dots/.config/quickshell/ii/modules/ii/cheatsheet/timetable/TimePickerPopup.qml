import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import "TimetableHelpers.js" as H

/**
 * Material 3 time picker: typed fields on top, clock dial underneath.
 *
 * The dial is the primary input and the fields are the secondary one, which is
 * why the two are kept in sync through explicit writes rather than a binding —
 * typing into a TextInput replaces any binding on `text`, and a dial drag has
 * to be able to write the field back afterwards.
 *
 * In 24-hour locales the dial carries two rings (1–12 outside, 13–00 inside),
 * picked by how far from the centre the press landed.
 */
Item {
    id: root

    property bool opened: false
    property string title: Translation.tr("Select time")
    property int hour: 9
    property int minute: 0

    /** 0 = choosing the hour, 1 = choosing the minute. */
    property int stage: 0
    property bool pm: false
    property bool suppressInputSync: false

    signal accepted(int pickedHour, int pickedMinute)
    signal dismissed

    readonly property bool use12Hour: DateUtils.is12HourTimeFormat(Config.options.time.format)
    readonly property real dialSize: 250
    readonly property real outerRadius: root.dialSize / 2 - 22
    readonly property real innerRadius: root.dialSize / 2 - 62
    readonly property real ringSplit: (root.outerRadius + root.innerRadius) / 2

    visible: root.opened || progress.value > 0.001
    z: 300

    function open(startHour, startMinute, titleText) {
        root.title = titleText && titleText.length > 0 ? titleText : Translation.tr("Select time");
        root.hour = Math.max(0, Math.min(23, startHour));
        root.minute = Math.max(0, Math.min(59, startMinute));
        root.pm = root.hour >= 12;
        root.stage = 0;
        root.syncInputs();
        root.opened = true;
    }

    function close() {
        root.opened = false;
    }

    function dismiss() {
        root.close();
        root.dismissed();
    }

    function confirm() {
        root.accepted(root.hour, root.minute);
        root.close();
    }

    readonly property int displayHour: {
        if (!root.use12Hour)
            return root.hour;
        const value = root.hour % 12;
        return value === 0 ? 12 : value;
    }

    function syncInputs() {
        root.suppressInputSync = true;
        hourInput.text = H.pad2(root.displayHour);
        minuteInput.text = H.pad2(root.minute);
        root.suppressInputSync = false;
    }

    function setHourFromDisplay(value) {
        if (!root.use12Hour) {
            root.hour = Math.max(0, Math.min(23, value));
            return;
        }
        const base = Math.max(1, Math.min(12, value)) % 12;
        root.hour = root.pm ? base + 12 : base;
    }

    function setMeridiem(afternoon) {
        if (!root.use12Hour || root.pm === afternoon)
            return;
        root.pm = afternoon;
        const base = root.hour % 12;
        root.hour = afternoon ? base + 12 : base;
        root.syncInputs();
    }

    // ─── Dial geometry ───
    /** Ring slot (0 at twelve o'clock) the hand points at. */
    readonly property int handPosition: {
        if (root.stage === 1)
            return root.minute;
        if (root.use12Hour)
            return root.hour % 12;
        if (root.hour === 0 || root.hour === 12)
            return 0;
        return root.hour > 12 ? root.hour - 12 : root.hour;
    }
    readonly property bool handOnInnerRing: !root.use12Hour && root.stage === 0 && (root.hour === 0 || root.hour > 12)
    readonly property real handAngle: root.stage === 1 ? root.minute * 6 : root.handPosition * 30
    readonly property real handLength: root.handOnInnerRing ? root.innerRadius : root.outerRadius

    function applyDialPoint(x, y, commit) {
        const centre = root.dialSize / 2;
        const dx = x - centre;
        const dy = y - centre;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const degrees = (Math.atan2(dy, dx) * 180 / Math.PI + 90 + 360) % 360;

        if (root.stage === 1) {
            root.minute = Math.round(degrees / 6) % 60;
        } else {
            const slot = Math.round(degrees / 30) % 12;
            if (root.use12Hour) {
                root.setHourFromDisplay(slot === 0 ? 12 : slot);
            } else if (distance < root.ringSplit) {
                root.hour = slot === 0 ? 0 : slot + 12;
            } else {
                root.hour = slot === 0 ? 12 : slot;
            }
        }
        root.syncInputs();

        // Picking the hour hands over to the minute, like the platform picker.
        if (commit && root.stage === 0)
            stageHandoffTimer.restart();
    }

    Timer {
        id: stageHandoffTimer
        interval: 180
        repeat: false
        onTriggered: root.stage = 1
    }

    QtObject {
        id: progress
        property real value: 0
    }

    onOpenedChanged: {
        openAnim.stop();
        closeAnim.stop();
        if (root.opened)
            openAnim.start();
        else
            closeAnim.start();
    }

    NumberAnimation {
        id: openAnim
        target: progress
        property: "value"
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    NumberAnimation {
        id: closeAnim
        target: progress
        property: "value"
        to: 0
        duration: Appearance.animation.elementMoveExit.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: progress.value

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: root.dismiss()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: cardColumn.width + 44
        height: Math.min(cardColumn.implicitHeight + 44, root.height - 24)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true

        opacity: progress.value
        scale: 0.9 + 0.1 * progress.value
        transform: Translate {
            y: (1 - progress.value) * 20
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onPressed: mouse => {
                mouse.accepted = true;
            }
        }

        Column {
            id: cardColumn
            anchors.centerIn: parent
            width: Math.max(root.dialSize, timeFields.implicitWidth)
            spacing: 14

            StyledText {
                text: root.title.toUpperCase()
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurfaceVariant
            }

            // ─── Typed value ───
            Item {
                width: cardColumn.width
                height: timeFields.implicitHeight

                Row {
                    id: timeFields
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                Rectangle {
                    id: hourBox
                    width: 96
                    height: 74
                    radius: Appearance.rounding.small
                    color: root.stage === 0 ? Appearance.colors.colPrimaryContainer : Appearance.m3colors.m3surfaceContainerHighest

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(hourBox)
                    }

                    StyledTextInput {
                        id: hourInput
                        anchors.fill: parent
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: 38
                        font.weight: Font.Bold
                        color: root.stage === 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        maximumLength: 2
                        validator: IntValidator {
                            bottom: 0
                            top: 23
                        }
                        onActiveFocusChanged: {
                            if (hourInput.activeFocus)
                                root.stage = 0;
                        }
                        onTextChanged: {
                            if (root.suppressInputSync)
                                return;
                            const value = parseInt(hourInput.text);
                            if (isNaN(value))
                                return;
                            root.setHourFromDisplay(value);
                        }
                        Keys.onEscapePressed: root.dismiss()
                    }

                    TapHandler {
                        onTapped: {
                            root.stage = 0;
                            hourInput.forceActiveFocus();
                        }
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ":"
                    font.pixelSize: 32
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Rectangle {
                    id: minuteBox
                    width: 96
                    height: 74
                    radius: Appearance.rounding.small
                    color: root.stage === 1 ? Appearance.colors.colPrimaryContainer : Appearance.m3colors.m3surfaceContainerHighest

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(minuteBox)
                    }

                    StyledTextInput {
                        id: minuteInput
                        anchors.fill: parent
                        horizontalAlignment: TextInput.AlignHCenter
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: 38
                        font.weight: Font.Bold
                        color: root.stage === 1 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        maximumLength: 2
                        validator: IntValidator {
                            bottom: 0
                            top: 59
                        }
                        onActiveFocusChanged: {
                            if (minuteInput.activeFocus)
                                root.stage = 1;
                        }
                        onTextChanged: {
                            if (root.suppressInputSync)
                                return;
                            const value = parseInt(minuteInput.text);
                            if (isNaN(value))
                                return;
                            root.minute = Math.max(0, Math.min(59, value));
                        }
                        Keys.onEscapePressed: root.dismiss()
                    }

                    TapHandler {
                        onTapped: {
                            root.stage = 1;
                            minuteInput.forceActiveFocus();
                        }
                    }
                }

                // ─── AM / PM ───
                Column {
                    visible: root.use12Hour
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    MeridiemButton {
                        label: "AM"
                        selected: !root.pm
                        onPicked: root.setMeridiem(false)
                    }

                    MeridiemButton {
                        label: "PM"
                        selected: root.pm
                        onPicked: root.setMeridiem(true)
                    }
                }
                }
            }

            // ─── Dial ───
            Item {
                width: cardColumn.width
                height: root.dialSize

                Item {
                    id: dial
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.dialSize
                    height: root.dialSize

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.m3colors.m3surfaceContainerHighest
                }

                Item {
                    id: hand
                    anchors.centerIn: parent
                    width: 2
                    height: root.handLength * 2
                    rotation: root.handAngle

                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(dial)
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        width: 2
                        height: root.handLength
                        color: Appearance.colors.colPrimary
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: -20
                        width: 40
                        height: 40
                        radius: 20
                        color: Appearance.colors.colPrimary
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: Appearance.colors.colPrimary
                }

                // Outer ring
                Repeater {
                    model: 12

                    delegate: StyledText {
                        required property int index

                        readonly property real slotAngle: (index * 30 - 90) * Math.PI / 180
                        readonly property int slotValue: root.stage === 1 ? (index * 5) % 60 : (index === 0 ? 12 : index)
                        readonly property bool current: root.stage === 1 ? (Math.round(root.minute / 5) % 12 === index) : (!root.handOnInnerRing && root.handPosition === index)

                        x: dial.width / 2 + Math.cos(slotAngle) * root.outerRadius - width / 2
                        y: dial.height / 2 + Math.sin(slotAngle) * root.outerRadius - height / 2
                        text: root.stage === 1 ? H.pad2(slotValue) : String(slotValue)
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: current ? Font.Bold : Font.Medium
                        color: current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                    }
                }

                // Inner ring: 24-hour locales only
                Repeater {
                    model: root.use12Hour || root.stage === 1 ? 0 : 12

                    delegate: StyledText {
                        required property int index

                        readonly property real slotAngle: (index * 30 - 90) * Math.PI / 180
                        readonly property int slotValue: index === 0 ? 0 : index + 12
                        readonly property bool current: root.handOnInnerRing && root.handPosition === index

                        x: dial.width / 2 + Math.cos(slotAngle) * root.innerRadius - width / 2
                        y: dial.height / 2 + Math.sin(slotAngle) * root.innerRadius - height / 2
                        text: H.pad2(slotValue)
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: current ? Font.Bold : Font.Medium
                        color: current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    onPressed: mouse => root.applyDialPoint(mouse.x, mouse.y, false)
                    onPositionChanged: mouse => {
                        if (pressed)
                            root.applyDialPoint(mouse.x, mouse.y, false);
                    }
                    onReleased: mouse => root.applyDialPoint(mouse.x, mouse.y, true)
                }
                }
            }

            // ─── Actions ───
            Item {
                width: cardColumn.width
                height: 46

                RippleButtonWithIcon {
                    id: cancelButton
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 116
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.full
                    centerContent: true
                    materialIcon: "close"
                    materialIconFill: false
                    mainText: Translation.tr("Cancel")
                    iconPixelSize: Appearance.font.pixelSize.large
                    textPixelSize: Appearance.font.pixelSize.small
                    mainTextWeight: Font.DemiBold
                    colText: Appearance.colors.colPrimary
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12)
                    onClicked: root.dismiss()

                    DashedBorder {
                        anchors.fill: parent
                        color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.75)
                        borderWidth: 1
                        dashLength: 5
                        gapLength: 4
                        radius: Appearance.rounding.full
                    }
                }

                RippleButtonWithIcon {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 126
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.full
                    centerContent: true
                    materialIcon: "check"
                    materialIconFill: false
                    mainText: Translation.tr("Set time")
                    iconPixelSize: Appearance.font.pixelSize.large
                    textPixelSize: Appearance.font.pixelSize.small
                    mainTextWeight: Font.Bold
                    colText: Appearance.colors.colOnPrimary
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    onClicked: root.confirm()
                }
            }
        }
    }

    component MeridiemButton: Rectangle {
        id: meridiem
        property string label: ""
        property bool selected: false

        signal picked

        implicitWidth: 56
        implicitHeight: 37
        width: implicitWidth
        height: implicitHeight
        radius: Appearance.rounding.verysmall
        color: meridiem.selected ? Appearance.colors.colTertiaryContainer : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(meridiem)
        }

        DashedBorder {
            anchors.fill: parent
            visible: !meridiem.selected
            color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
            borderWidth: 1
            dashLength: 4
            gapLength: 3
            radius: Appearance.rounding.verysmall
        }

        StyledText {
            anchors.centerIn: parent
            text: meridiem.label
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.Bold
            color: meridiem.selected ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurfaceVariant
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: meridiem.picked()
        }
    }
}
