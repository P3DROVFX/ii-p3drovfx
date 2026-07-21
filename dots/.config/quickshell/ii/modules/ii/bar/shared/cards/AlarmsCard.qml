import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    implicitHeight: columnLayout.implicitHeight + 32
    radius: Appearance.rounding.large
    color: Appearance.colors.colSurfaceContainerHighest
    clip: true

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    // Internal animation control
    property bool startAnim: false

    onStartAnimChanged: {
        if (startAnim) {
            // Reset header elements
            alarmIcon.scale = 0.8;
            alarmIconRotation.angle = -10;
            alarmsTitle.opacity = 0.0;
            alarmsCount.opacity = 0.0;
            deleteButton.scale = 0.8;
            deleteButton.opacity = 0.0;
            addButton.scale = 0.8;
            addButton.opacity = 0.0;
            
            // Reset alarm cards
            for (var i = 0; i < listView.count; i++) {
                var item = listView.itemAtIndex(i);
                if (item) {
                    item.cardOpacity = 0.0;
                    item.cardTranslateX = 80;
                }
            }
            
            // Start animations
            Qt.callLater(function() {
                alarmIconAnim.start();
                alarmsTitleAnim.start();
                alarmsCountAnim.start();
                deleteBtnAnim.start();
                addBtnAnim.start();
                
                for (var j = 0; j < listView.count; j++) {
                    var cardItem = listView.itemAtIndex(j);
                    if (cardItem) {
                        cardItem.cardAnimDelay = 100 + (j * 80);
                        cardItem.startCardAnim();
                    }
                }
            });
        }
    }

    Connections {
        target: root
        function onPopupOpenProgressChanged() {
            if (root && root.popupOpenProgress === 0.0) {
                alarmIconAnim.stop();
                alarmsTitleAnim.stop();
                alarmsCountAnim.stop();
                deleteBtnAnim.stop();
                addBtnAnim.stop();

                alarmIcon.scale = 0.8;
                alarmIconRotation.angle = -10;
                alarmsTitle.opacity = 0.0;
                alarmsCount.opacity = 0.0;
                deleteButton.scale = 0.8;
                deleteButton.opacity = 0.0;
                addButton.scale = 0.8;
                addButton.opacity = 0.0;
                
                for (var k = 0; k < listView.count; k++) {
                    var resetItem = listView.itemAtIndex(k);
                    if (resetItem) {
                        resetItem.stopCardAnim();
                        resetItem.cardOpacity = 0.0;
                        resetItem.cardTranslateX = 80;
                    }
                }
            }
        }
    }

    property string mode: "list" // "list", "add", "edit"
    property int editingIndex: -1
    property bool deleteMode: false

    // Edit form states
    property string editTimeHour: "08"
    property string editTimeMinute: "00"
    property string editLabel: ""
    property var editDays: [false, false, false, false, false, false, false]

    function openEdit(index, alarm) {
        root.editingIndex = index;
        root.editTimeHour = alarm.time.split(":")[0] || "08";
        root.editTimeMinute = alarm.time.split(":")[1] || "00";
        root.editLabel = alarm.label || "";
        root.editDays = [...alarm.days];
        root.deleteMode = false;
        root.mode = "edit";
    }

    function openAdd() {
        let now = new Date();
        root.editingIndex = -1;
        root.editTimeHour = now.getHours().toString().padStart(2, '0');
        root.editTimeMinute = now.getMinutes().toString().padStart(2, '0');
        root.editLabel = "";
        root.editDays = [false, false, false, false, false, false, false];
        root.deleteMode = false;
        root.mode = "add";
    }

    function getRemainingTimeText(alarm, now) {
        if (!alarm || !alarm.enabled) {
            return Translation.tr("Alarm");
        }

        let currentDay = now.getDay();
        let currentHour = now.getHours();
        let currentMinute = now.getMinutes();

        let parts = alarm.time.split(":");
        let alarmHour = parseInt(parts[0]);
        let alarmMin = parseInt(parts[1]);

        let minDiff = alarmMin - currentMinute;
        let hourDiff = alarmHour - currentHour;
        if (minDiff < 0) {
            minDiff += 60;
            hourDiff--;
        }
        if (hourDiff < 0) {
            hourDiff += 24;
        }

        let hasRepeat = alarm.days && alarm.days.includes(true);
        let daysUntil = 0;

        if (hasRepeat) {
            let targetDay = -1;
            for (let i = 0; i < 7; i++) {
                let checkedDay = (currentDay + i) % 7;
                if (alarm.days[checkedDay]) {
                    if (i === 0) {
                        if (alarmHour > currentHour || (alarmHour === currentHour && alarmMin > currentMinute)) {
                            targetDay = checkedDay;
                            daysUntil = 0;
                            break;
                        }
                    } else {
                        targetDay = checkedDay;
                        daysUntil = i;
                        break;
                    }
                }
            }
            if (targetDay === -1) {
                daysUntil = 7;
            }
        } else {
            if (alarmHour < currentHour || (alarmHour === currentHour && alarmMin <= currentMinute)) {
                daysUntil = 1;
            } else {
                daysUntil = 0;
            }
        }

        let totalMinutes = daysUntil * 24 * 60 + hourDiff * 60 + minDiff;
        if (totalMinutes <= 0) {
            return Translation.tr("Ringing");
        }

        let d = Math.floor(totalMinutes / (24 * 60));
        let h = Math.floor((totalMinutes % (24 * 60)) / 60);
        let m = totalMinutes % 60;

        let res = "";
        if (d > 0) {
            res += d + "d ";
        }
        if (h > 0) {
            res += h + "h ";
        }
        if (m > 0 || (d === 0 && h === 0)) {
            res += m + "m";
        }
        return Translation.tr("In") + " " + res.trim();
    }

    function formatAlarmTime(timeStr) {
        if (!timeStr) return "";
        let parts = timeStr.split(":");
        let h = parseInt(parts[0]);
        let m = parts[1] || "00";

        let is12Hour = false;
        let timeFormat = "";
        if (Config.options && Config.options.time && Config.options.time.format) {
            timeFormat = Config.options.time.format;
            is12Hour = timeFormat.toLowerCase().indexOf("ap") !== -1;
        }
        if (is12Hour) {
            let suffix = h >= 12 ? "PM" : "AM";
            let displayHour = h % 12;
            if (displayHour === 0) displayHour = 12;
            let pad = timeFormat.indexOf("hh") !== -1;
            let displayHourStr = pad ? displayHour.toString().padStart(2, '0') : displayHour.toString();
            return displayHourStr + ":" + m + " " + suffix;
        }
        return timeStr;
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 16
        }
        spacing: 16

        // LIST MODE
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: root.mode === "list"

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    id: alarmIcon
                    text: "alarm"
                    iconSize: 24
                    fill: 1
                    color: AlarmService.ringingAlarmIndex !== -1 ? Appearance.colors.colError : Appearance.colors.colPrimary
                    scale: 1.0
                    
                    transform: Rotation {
                        id: alarmIconRotation
                        origin.x: alarmIcon.width / 2
                        origin.y: alarmIcon.height / 2
                        angle: 0
                    }
                    
                    SequentialAnimation {
                        id: alarmIconAnim
                        PauseAnimation { duration: 80 }
                        ParallelAnimation {
                            NumberAnimation { target: alarmIcon; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                            NumberAnimation { target: alarmIconRotation; property: "angle"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 1
                    StyledText {
                        id: alarmsTitle
                        text: Translation.tr("Alarms")
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurface
                        opacity: 1.0
                        
                        SequentialAnimation {
                            id: alarmsTitleAnim
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: alarmsTitle; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                        }
                    }

                    StyledText {
                        id: alarmsCount
                        text: AlarmService.alarms ? AlarmService.alarms.length + " " + Translation.tr("Alarms") : "0 " + Translation.tr("Alarms")
                        font.weight: Font.Light
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        opacity: 1.0
                        
                        SequentialAnimation {
                            id: alarmsCountAnim
                            PauseAnimation { duration: 160 }
                            NumberAnimation { target: alarmsCount; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Delete (red/toggle) button
                RippleButton {
                    id: deleteButton
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    buttonRadius: 16
                    colBackground: root.deleteMode ? Appearance.colors.colError : Appearance.colors.colErrorContainer
                    colBackgroundHover: root.deleteMode ? Appearance.colors.colErrorHover : Appearance.colors.colErrorContainerHover
                    scale: 1.0
                    opacity: 1.0
                    
                    SequentialAnimation {
                        id: deleteBtnAnim
                        PauseAnimation { duration: 200 }
                        ParallelAnimation {
                            NumberAnimation { target: deleteButton; property: "scale"; from: 0.8; to: 1.0; duration: 320; easing.type: Easing.OutBack }
                            NumberAnimation { target: deleteButton; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete"
                        iconSize: 16
                        color: root.deleteMode ? Appearance.colors.colOnError : Appearance.colors.colOnErrorContainer
                    }

                    onClicked: {
                        root.deleteMode = !root.deleteMode;
                    }
                }

                // Add (blue) button
                RippleButton {
                    id: addButton
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    buttonRadius: 16
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    scale: 1.0
                    opacity: 1.0
                    
                    SequentialAnimation {
                        id: addBtnAnim
                        PauseAnimation { duration: 240 }
                        ParallelAnimation {
                            NumberAnimation { target: addButton; property: "scale"; from: 0.8; to: 1.0; duration: 320; easing.type: Easing.OutBack }
                            NumberAnimation { target: addButton; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    onClicked: {
                        root.openAdd();
                    }
                }
            }

            // Horizontal list of alarm cards
            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: count > 0 ? 96 : 0
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                model: AlarmService.alarms

                add: Transition {
                    NumberAnimation { properties: "scale,opacity"; from: 0; to: 1.0; duration: 250; easing.type: Easing.OutQuad }
                }
                remove: Transition {
                    NumberAnimation { properties: "scale,opacity"; to: 0; duration: 200; easing.type: Easing.OutQuad }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutQuad }
                }

                delegate: Rectangle {
                    id: alarmCard
                    width: listView.count >= 2 ? (listView.width > 0 ? listView.width * 0.85 : 320) : (listView.width > 0 ? listView.width : 380)
                    height: 96
                    radius: Appearance.rounding.large
                    color: AlarmService.ringingAlarmIndex === index ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerLow
                    clip: true

                    opacity: alarmCard.cardOpacity
                    transform: Translate {
                        x: alarmCard.cardTranslateX
                    }

                    // Animation properties
                    property real cardOpacity: 1.0
                    property real cardTranslateX: 0
                    property int cardAnimDelay: 0
                    
                    function startCardAnim() {
                        cardAnim.start();
                    }

                    SequentialAnimation {
                        id: cardAnim
                        PauseAnimation { duration: alarmCard.cardAnimDelay }
                        ParallelAnimation {
                            NumberAnimation { target: alarmCard; property: "cardOpacity"; from: 0.0; to: 1.0; duration: 350 }
                            NumberAnimation { target: alarmCard; property: "cardTranslateX"; from: 80; to: 0; duration: 450; easing.type: Easing.OutCubic }
                        }
                    }

                    Behavior on opacity {
                        id: opacityBehavior
                        enabled: AlarmService.ringingAlarmIndex !== index
                        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                    }

                    required property var modelData
                    required property int index

                    // Clickable area for editing (on label & time side)
                    MouseArea {
                        anchors {
                            left: parent.left
                            right: controlsColumn.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        onClicked: {
                            if (!root.deleteMode && AlarmService.ringingAlarmIndex === -1) {
                                root.openEdit(alarmCard.index, alarmCard.modelData);
                            }
                        }
                    }

                    ColumnLayout {
                        anchors {
                            left: parent.left
                            leftMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 4

                        StyledText {
                            text: {
                                let label = alarmCard.modelData.label;
                                let isDefault = !label || label === "Alarm" || label === Translation.tr("Alarm");
                                return isDefault ? root.getRemainingTimeText(alarmCard.modelData, DateTime.clock.date) : label;
                            }
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: AlarmService.ringingAlarmIndex === index ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: root.formatAlarmTime(alarmCard.modelData.time)
                            font.pixelSize: Math.min(36, alarmCard.width * 0.1)
                            font.family: Appearance.font.family.title
                            font.weight: Font.Bold
                            color: AlarmService.ringingAlarmIndex === index ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurface
                        }
                    }

                    // Switch, Delete, or STOP button column
                    ColumnLayout {
                        id: controlsColumn
                        anchors {
                            right: parent.right
                            rightMargin: 20
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 12
                        Layout.alignment: Qt.AlignRight

                        Loader {
                            id: controlLoader
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: item ? (item.width > 0 ? item.width : item.implicitWidth) : 0
                            Layout.preferredHeight: item ? (item.height > 0 ? item.height : item.implicitHeight) : 0
                            sourceComponent: {
                                if (AlarmService.ringingAlarmIndex === alarmCard.index) {
                                    return stopButtonComponent;
                                }
                                if (root.deleteMode) {
                                    return deleteItemButtonComponent;
                                }
                                return switchComponent;
                            }
                        }

                        // 7 Weekday dots (hidden when ringing or deleting to keep tidy)
                        RowLayout {
                            spacing: 4
                            Layout.alignment: Qt.AlignRight
                            visible: AlarmService.ringingAlarmIndex !== alarmCard.index && !root.deleteMode

                            Repeater {
                                model: 7
                                delegate: Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: alarmCard.modelData.days[index] ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    opacity: alarmCard.modelData.days[index] ? 1.0 : 0.2
                                }
                            }
                        }
                    }

                    // Pulse animation for ringing card
                    SequentialAnimation {
                        running: AlarmService.ringingAlarmIndex === alarmCard.index
                        loops: Animation.Infinite

                        NumberAnimation {
                            target: alarmCard
                            property: "opacity"
                            from: 1.0
                            to: 0.5
                            duration: 500
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            target: alarmCard
                            property: "opacity"
                            from: 0.5
                            to: 1.0
                            duration: 500
                            easing.type: Easing.InOutQuad
                        }
                        onStopped: {
                            alarmCard.opacity = 1.0;
                        }
                    }

                    Component {
                        id: stopButtonComponent
                        RippleButton {
                            width: 64
                            height: 32
                            buttonRadius: 16
                            colBackground: Appearance.colors.colError
                            colBackgroundHover: Appearance.colors.colErrorHover

                            contentItem: StyledText {
                                text: Translation.tr("STOP")
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnError
                            }

                            onClicked: {
                                AlarmService.stopRinging();
                            }
                        }
                    }

                    Component {
                        id: deleteItemButtonComponent
                        RippleButton {
                            width: 32
                            height: 32
                            buttonRadius: 16
                            colBackground: Appearance.colors.colErrorContainer
                            colBackgroundHover: Appearance.colors.colErrorContainerHover

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: 16
                                color: Appearance.colors.colOnErrorContainer
                            }

                            onClicked: {
                                AlarmService.deleteAlarm(alarmCard.index);
                            }
                        }
                    }

                    Component {
                        id: switchComponent
                        StyledSwitch {
                            checked: alarmCard.modelData.enabled
                            sizeScale: 0.75
                            onCheckedChanged: {
                                if (alarmCard.modelData.enabled !== checked) {
                                    AlarmService.toggleAlarm(alarmCard.index);
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: listView.count === 0
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No alarms set")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        // ADD / EDIT INLINE MODE
        ColumnLayout {
            id: editLayout
            Layout.fillWidth: true
            spacing: 12
            visible: root.mode !== "list"

            StyledText {
                text: root.mode === "add" ? Translation.tr("Add Alarm") : Translation.tr("Edit Alarm")
                font.weight: Font.Bold
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSurface
            }

            // Input Row: Hour : Minute | Label
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Hour Field
                MaterialTextField {
                    id: hourInput
                    Layout.preferredWidth: 64
                    placeholderText: "HH"
                    text: root.editTimeHour
                    inputMethodHints: Qt.ImhDigitsOnly
                }

                StyledText {
                    text: ":"
                    font.weight: Font.Bold
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSurface
                }

                // Minute Field
                MaterialTextField {
                    id: minuteInput
                    Layout.preferredWidth: 64
                    placeholderText: "MM"
                    text: root.editTimeMinute
                    inputMethodHints: Qt.ImhDigitsOnly
                }

                // Label Field
                MaterialTextField {
                    id: labelInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Alarm Label")
                    text: root.editLabel
                }
            }

            // Weekday dot selector buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Layout.alignment: Qt.AlignHCenter

                Repeater {
                    model: 7
                    delegate: RippleButton {
                        id: dayButton
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        buttonRadius: 16

                        property bool selected: root.editDays[index]
                        property string dayText: {
                            const letters = [
                                Translation.tr("S"),
                                Translation.tr("M"),
                                Translation.tr("T"),
                                Translation.tr("W"),
                                Translation.tr("T"),
                                Translation.tr("F"),
                                Translation.tr("S")
                            ];
                            return letters[index];
                        }

                        colBackground: selected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                        colBackgroundHover: selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover

                        contentItem: StyledText {
                            text: dayButton.dayText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: dayButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }

                        onClicked: {
                            let temp = [...root.editDays];
                            temp[index] = !temp[index];
                            root.editDays = temp;
                        }
                    }
                }
            }

            // Save / Cancel / Delete controls
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Layout.topMargin: 4

                // Delete button in edit form
                RippleButton {
                    visible: root.mode === "edit"
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    buttonRadius: 18
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete"
                        iconSize: 18
                        color: Appearance.colors.colOnErrorContainer
                    }

                    onClicked: {
                        AlarmService.deleteAlarm(root.editingIndex);
                        root.mode = "list";
                    }
                }

                Item {
                    visible: root.mode === "edit"
                    Layout.fillWidth: true
                }

                 RippleButton {
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    Layout.preferredWidth: 110
                    Layout.preferredHeight: 40
                    buttonRadius: 20

                    contentItem: RowLayout {
                        spacing: 6
                        RowLayout {
                            Layout.alignment: Qt.AlignCenter
                            spacing: 6
                            MaterialSymbol {
                                text: "close"
                                iconSize: 18
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                text: Translation.tr("Cancel")
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }

                    onClicked: {
                        root.mode = "list";
                    }
                }

                RippleButton {
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    Layout.fillWidth: root.mode === "add"
                    Layout.preferredWidth: root.mode === "edit" ? 110 : -1
                    Layout.preferredHeight: 40
                    buttonRadius: 20

                    contentItem: RowLayout {
                        spacing: 6
                        RowLayout {
                            Layout.alignment: Qt.AlignCenter
                            spacing: 6
                            MaterialSymbol {
                                text: "check"
                                iconSize: 18
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            StyledText {
                                text: Translation.tr("Save")
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    onClicked: {
                        // JS Validation
                        let h = parseInt(hourInput.text);
                        let m = parseInt(minuteInput.text);

                        if (isNaN(h) || h < 0 || h > 23 || isNaN(m) || m < 0 || m > 59) {
                            console.log("Invalid alarm time input:", hourInput.text, ":", minuteInput.text);
                            return;
                        }

                        let timeStr = h.toString().padStart(2, '0') + ":" + m.toString().padStart(2, '0');
                        let labelStr = labelInput.text.trim();

                        if (root.mode === "add") {
                            AlarmService.addAlarm(timeStr, labelStr, root.editDays);
                        } else {
                            AlarmService.editAlarm(root.editingIndex, timeStr, labelStr, root.editDays);
                        }
                        root.mode = "list";
                    }
                }
            }
        }
    }
}
