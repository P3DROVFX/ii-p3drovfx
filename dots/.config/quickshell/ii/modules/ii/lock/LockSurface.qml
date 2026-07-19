import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.widgets.tray
import Quickshell
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    required property LockContext context
    property bool active: false
    property bool showInputField: active || context.currentText.length > 0
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower

    // Force focus on entry
    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        forceFieldFocus();
        layoutDialog.close();
        if (Config.options.lock.rippleEffect ?? true) {
            // Emit via GlobalStates so Background.qml (WlrLayer.Top) renders the ripple
            // — the WlSessionLock surface renders under the background panel when locked.
            GlobalStates.lockScreenRipple(mouse.x, mouse.y);
        }
    }
    onPositionChanged: mouse => {
        forceFieldFocus();
    }

    // Toolbar appearing animation
    property real toolbarScale: 0.9
    property real toolbarOpacity: 0
    Behavior on toolbarScale {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }
    Behavior on toolbarOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Init
    Component.onCompleted: {
        forceFieldFocus();
        toolbarScale = 1;
        toolbarOpacity = 1;
    }

    // Key presses
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_CapsLock) {
            GlobalStates.capsLockActive = !GlobalStates.capsLockActive;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
            layoutDialog.close();
        } 
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        forceFieldFocus();
    }

    // RippleButton {
    //     anchors {
    //         top: parent.top
    //         left: parent.left
    //         leftMargin: 10
    //         topMargin: 10
    //     }
    //     implicitHeight: 40
    //     colBackground: Appearance.colors.colLayer2
    //     onClicked: {
    //         context.unlocked(LockContext.ActionEnum.Unlock);
    //         GlobalStates.screenLocked = false;
    //     }
    //     contentItem: StyledText {
    //         text: "[[ DEBUG BYPASS ]]"
    //     }
    // }

    // Notifications (read-only)
    Loader {
        readonly property bool notifsOnTop: Config.options.lock.notifications.position.startsWith("top")
        readonly property bool notifsOnLeft: Config.options.lock.notifications.position.endsWith("left")
        anchors {
            top: notifsOnTop ? parent.top : undefined
            bottom: notifsOnTop ? undefined : parent.bottom
            left: notifsOnLeft ? parent.left : undefined
            right: notifsOnLeft ? undefined : parent.right
            margins: 20
        }
        active: Config.options.lock.notifications.enable
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        sourceComponent: LockNotifications {}
    }

    // Now Playing island
    Toolbar {
        id: nowPlayingIsland
        anchors {
            top: parent.top
            topMargin: 20
            horizontalCenter: parent.horizontalCenter
        }
        
        readonly property bool showNowPlaying: (Config.options.lock.nowPlaying ?? true) && MprisController.activePlayer !== null
        
        opacity: root.toolbarOpacity * (showNowPlaying ? 1 : 0)
        scale: root.toolbarScale * (showNowPlaying ? 1 : 0.8)
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutBack
            }
        }

        transform: Translate {
            y: nowPlayingIsland.showNowPlaying ? (1.0 - root.toolbarOpacity) * -40 : -40
            Behavior on y {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                }
            }
        }

        spacing: 12

        Item {
            id: textWrapper
            Layout.fillHeight: true
            Layout.leftMargin: 12
            implicitWidth: Math.min(200, Math.max(120, textColumn.implicitWidth))
            clip: true

            Behavior on implicitWidth {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            Column {
                id: textColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                
                StyledText {
                    width: parent.width
                    text: MprisController.activeTrack ? MprisController.activeTrack.title : Translation.tr("Unknown Title")
                    font.weight: Font.Bold
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }
                
                StyledText {
                    width: parent.width
                    text: MprisController.activeTrack ? MprisController.activeTrack.artist : Translation.tr("Unknown Artist")
                    font.weight: Font.Light
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurface
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            implicitWidth: 48
            implicitHeight: 48
            Layout.alignment: Qt.AlignVCenter
            
            Image {
                id: albumArt
                anchors.fill: parent
                source: MprisController.artUrl && MprisController.artUrl !== "" ? MprisController.artUrl : ""
                fillMode: Image.PreserveAspectCrop
                visible: source !== ""
                
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: albumArt.width
                        height: albumArt.height
                        radius: width / 2
                    }
                }
            }

            Rectangle {
                id: placeholderCircle
                anchors.fill: parent
                color: Appearance.colors.colPrimary
                radius: width / 2
                visible: !albumArt.visible
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "music_note"
                    color: Appearance.colors.colOnPrimary
                    iconSize: 22
                }
            }
        }
    }



    // Main toolbar: password box
    Toolbar {
        id: mainIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 20
        }
        Behavior on anchors.bottomMargin {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        // Fingerprint
        Loader {
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.fingerprintsConfigured
            visible: active

            sourceComponent: ColumnLayout {
                id: fingerprintStatus
                spacing: 0

                readonly property int triesLeft: root.context.fingerprintTriesLeft
                readonly property bool exhausted: triesLeft === 0
                property bool failureFlash: false

                Connections {
                    target: root.context
                    function onFingerprintFailed() {
                        fingerprintStatus.failureFlash = true;
                        failureFlashTimer.restart();
                        fingerprintShakeAnim.restart();
                    }
                }
                Timer {
                    id: failureFlashTimer
                    interval: 800
                    onTriggered: fingerprintStatus.failureFlash = false
                }

                MaterialSymbol {
                    id: fingerprintIcon
                    Layout.alignment: Qt.AlignHCenter
                    fill: 1
                    text: "fingerprint"
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: (fingerprintStatus.failureFlash || fingerprintStatus.exhausted)
                        ? Appearance.colors.colError
                        : Appearance.colors.colOnSurfaceVariant
                    opacity: fingerprintStatus.exhausted ? 0.5 : 1
                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                    transform: Translate { id: fingerprintShakeOffset }
                    SequentialAnimation {
                        id: fingerprintShakeAnim
                        NumberAnimation { target: fingerprintShakeOffset; property: "x"; to: -6; duration: 50 }
                        NumberAnimation { target: fingerprintShakeOffset; property: "x"; to: 6; duration: 50 }
                        NumberAnimation { target: fingerprintShakeOffset; property: "x"; to: -3; duration: 40 }
                        NumberAnimation { target: fingerprintShakeOffset; property: "x"; to: 3; duration: 40 }
                        NumberAnimation { target: fingerprintShakeOffset; property: "x"; to: 0; duration: 30 }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4
                    Repeater {
                        model: root.context.fingerprintMaxTries
                        Rectangle {
                            implicitWidth: 5
                            implicitHeight: 5
                            radius: 2.5
                            color: index < fingerprintStatus.triesLeft
                                ? ((fingerprintStatus.failureFlash) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant)
                                : "transparent"
                            border.width: index < fingerprintStatus.triesLeft ? 0 : 1
                            border.color: fingerprintStatus.exhausted
                                ? Appearance.colors.colError
                                : Appearance.colors.colOutline
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                    }
                }
            }
        }

        ToolbarTextField {
            id: passwordBox
            Layout.rightMargin: -Layout.leftMargin
            placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

            // Style
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
            selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

            // Password
            enabled: !root.context.unlockInProgress
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData

            // Synchronizing (across monitors) and unlocking
            onTextChanged: root.context.currentText = this.text
            onAccepted: {
                root.context.tryUnlock(ctrlHeld);
            }
            Connections {
                target: root.context
                function onCurrentTextChanged() {
                    passwordBox.text = root.context.currentText;
                }
            }

            Keys.onPressed: event => {
                root.context.resetClearTimer();
            }
            
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: height / 2
                }
            }

            // Shake when wrong password
            ErrorShakeAnimation {
                id: wrongPasswordShakeAnim
                target: passwordBox
            }
            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                }
            }

            // We're drawing dots manually
            property bool materialShapeChars: Config.options.lock.materialShapeChars
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
            Loader {
                active: passwordBox.materialShapeChars
                anchors {
                    fill: parent
                    leftMargin: passwordBox.padding
                    rightMargin: passwordBox.padding
                }
                sourceComponent: PasswordChars {
                    length: root.context.currentText.length
                    selectionStart: passwordBox.selectionStart
                    selectionEnd: passwordBox.selectionEnd
                    cursorPosition: passwordBox.cursorPosition
                }
            }
        }

        ToolbarButton {
            id: confirmButton
            implicitWidth: height
            toggled: true
            enabled: !root.context.unlockInProgress
            colBackgroundToggled: Appearance.colors.colPrimary

            onClicked: root.context.tryUnlock()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 24
                text: {
                    if (root.context.targetAction === LockContext.ActionEnum.Unlock) {
                        return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                        return "power_settings_new";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                        return "restart_alt";
                    }
                }
                color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }
        }
    }

    // Left toolbar
    Toolbar {
        id: leftIsland
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity
        visible: batteryButton.visible || capsLockPill.visible || nextAlarmButton.visible || weatherButton.visible || layoutSwitcherButton.visible

        ToolbarButton {
            id: batteryButton
            Layout.fillHeight: true
            implicitWidth: height
            visible: Battery.available
            pointingHandCursor: false
            
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            
            contentItem: Item {
                anchors.fill: parent
                
                readonly property real percentage: Battery.percentage
                readonly property bool isCharging: Battery.isCharging
                readonly property bool isPluggedIn: Battery.isPluggedIn
                readonly property bool effectivelyCharging: isCharging || isPluggedIn
                readonly property bool chargeLimitReached: Battery.chargeLimitReached
                readonly property bool showCheck: chargeLimitReached || (Battery.isFull && effectivelyCharging)
                
                readonly property bool isLow: percentage <= Config.options.battery.low / 100
                readonly property bool isCritical: percentage <= Config.options.battery.critical / 100
                
                readonly property color colHighlight: (isCritical || isLow) && !effectivelyCharging 
                    ? Appearance.m3colors.m3error 
                    : Appearance.colors.colOnPrimary
                    
                readonly property color colTrack: ColorUtils.transparentize(colHighlight, 0.7)

                Item {
                    id: android16Battery
                    anchors.centerIn: parent
                    width: 29
                    height: 14

                    Row {
                        anchors.centerIn: parent
                        spacing: 1

                        ClippedProgressBar {
                            id: batteryProgress
                            width: 26
                            height: 14
                            radius: 4.5
                            value: batteryButton.contentItem.percentage
                            highlightColor: batteryButton.contentItem.colHighlight
                            trackColor: batteryButton.contentItem.colTrack

                            textMask: Item {
                                width: 26
                                height: 14
                                StyledText {
                                    anchors.centerIn: parent
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    text: batteryProgress.text
                                    color: (batteryButton.contentItem.isLow || batteryButton.contentItem.isCritical) && !batteryButton.contentItem.effectivelyCharging
                                        ? Appearance.m3colors.m3onError
                                        : Appearance.colors.colPrimary
                                }
                            }
                        }

                        Rectangle {
                            id: batteryTip
                            width: 2
                            height: 6
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 1
                            color: (batteryButton.contentItem.percentage >= 0.98) 
                                ? batteryProgress.highlightColor 
                                : batteryProgress.trackColor
                        }
                    }

                    MaterialSymbol {
                        visible: batteryButton.contentItem.effectivelyCharging || batteryButton.contentItem.showCheck
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.right
                        anchors.horizontalCenterOffset: -1
                        text: batteryButton.contentItem.showCheck ? "check" : "bolt"
                        iconSize: 17
                        fill: 1
                        color: Appearance.colors.colPrimary
                        z: 2
                    }

                    MaterialSymbol {
                        visible: batteryButton.contentItem.effectivelyCharging || batteryButton.contentItem.showCheck
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.right
                        anchors.horizontalCenterOffset: -1
                        text: batteryButton.contentItem.showCheck ? "check" : "bolt"
                        iconSize: 16
                        fill: 1
                        color: batteryProgress.highlightColor
                        z: 3
                    }
                }
            }
        }

        ToolbarButton {
            id: capsLockPill
            Layout.fillHeight: true
            Layout.preferredWidth: GlobalStates.capsLockActive ? 100 : 0
            visible: Layout.preferredWidth > 0
            clip: true
            
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            
            Behavior on Layout.preferredWidth {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
            
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "keyboard_capslock"
                iconSize: 22
                color: Appearance.colors.colOnSecondaryContainer
                fill: 1
            }
        }

        ToolbarButton {
            id: nextAlarmButton
            Layout.fillHeight: true
            
            readonly property var nextAlarm: {
                if (!AlarmService.alarms || AlarmService.alarms.length === 0) return null;
                let enabledAlarms = AlarmService.alarms.filter(a => a.enabled);
                if (enabledAlarms.length === 0) return null;

                let now = DateTime.clock.date;
                let currentDay = now.getDay();
                let currentHour = now.getHours();
                let currentMinute = now.getMinutes();

                let closestAlarm = null;
                let minTimeUntil = Infinity;

                for (let i = 0; i < enabledAlarms.length; i++) {
                    let alarm = enabledAlarms[i];
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
                        for (let j = 0; j < 7; j++) {
                            let checkedDay = (currentDay + j) % 7;
                            if (alarm.days[checkedDay]) {
                                if (j === 0) {
                                    if (alarmHour > currentHour || (alarmHour === currentHour && alarmMin > currentMinute)) {
                                        targetDay = checkedDay;
                                        daysUntil = 0;
                                        break;
                                    }
                                } else {
                                    targetDay = checkedDay;
                                    daysUntil = j;
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
                    if (totalMinutes < minTimeUntil) {
                        minTimeUntil = totalMinutes;
                        closestAlarm = alarm;
                    }
                }
                return closestAlarm;
            }
            
            readonly property bool showNextAlarm: (Config.options.lock.showAlarm ?? true) && nextAlarm !== null
            
            Layout.preferredWidth: showNextAlarm ? (contentRow.implicitWidth + 24) : 0
            visible: Layout.preferredWidth > 0
            clip: true
            pointingHandCursor: false
            
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            
            Behavior on Layout.preferredWidth {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
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

            contentItem: RowLayout {
                id: contentRow
                anchors.centerIn: parent
                spacing: 8
                
                MaterialSymbol {
                    text: "alarm"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                    fill: 1
                }
                
                StyledText {
                    text: nextAlarmButton.formatAlarmTime(nextAlarmButton.nextAlarm ? nextAlarmButton.nextAlarm.time : "")
                    font.weight: Font.Medium
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        ToolbarButton {
            id: weatherButton
            Layout.fillHeight: true
            implicitWidth: height
            
            readonly property bool showWeather: (Config.options.lock.showWeather ?? true) && Weather.data !== null && Weather.data.wCode !== undefined
            
            visible: showWeather
            pointingHandCursor: false
            
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: Icons.getWeatherIcon(Weather.data ? Weather.data.wCode : 113) || "device_thermostat"
                iconSize: 22
                color: Appearance.colors.colOnSecondaryContainer
                fill: 1
            }
        }

        ToolbarButton {
            id: layoutSwitcherButton
            Layout.fillHeight: true
            Layout.preferredWidth: showSwitcher ? (layoutSwitcherRow.implicitWidth + 24) : 0
            readonly property bool showSwitcher: HyprlandXkb.layoutCodes.length > 1
            visible: Layout.preferredWidth > 0
            clip: true
            
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            
            Behavior on Layout.preferredWidth {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
            
            contentItem: RowLayout {
                id: layoutSwitcherRow
                anchors.centerIn: parent
                spacing: 6
                
                MaterialSymbol {
                    text: "keyboard"
                    iconSize: 18
                    color: Appearance.colors.colOnSecondaryContainer
                    fill: 1
                }
                
                StyledText {
                    text: (HyprlandXkb.currentLayoutCode || "").toUpperCase()
                    font.weight: Font.Bold
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            
            onClicked: {
                layoutDialog.toggle();
            }
        }
    }

    // Right toolbar
    Toolbar {
        id: rightIsland
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: 10
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        IconToolbarButton {
            id: sleepButton
            onClicked: Session.suspend()
            text: "dark_mode"
            iconFill: true
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            colText: Appearance.colors.colOnSecondaryContainer

            StyledToolTipContent {
                text: Translation.tr("Sleep")
                shown: parent.hovered
                anchors.bottom: parent.top
                anchors.bottomMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                z: 100
            }
        }

        PasswordGuardedIconToolbarButton {
            id: powerButton
            text: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff

            StyledToolTipContent {
                text: Translation.tr("Shutdown")
                shown: parent.hovered
                anchors.bottom: parent.top
                anchors.bottomMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                z: 100
            }
        }

        PasswordGuardedIconToolbarButton {
            id: rebootButton
            text: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot

            StyledToolTipContent {
                text: Translation.tr("Reboot")
                shown: parent.hovered
                anchors.bottom: parent.top
                anchors.bottomMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                z: 100
            }
        }
    }


    component PasswordGuardedIconToolbarButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        toggled: root.context.targetAction === guardedBtn.targetAction

        iconFill: true
        colBackground: toggled ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colBackgroundHover: toggled ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colRipple: toggled ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
        colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

        onClicked: {
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }

    component IconAndTextPair: Row {
        required property string icon
        required property string text
        property color color: Appearance.colors.colOnSurfaceVariant

        spacing: 4
        Layout.fillHeight: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: parent.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: parent.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.text
            color: parent.color
        }
    }

    Loader {
        active: layoutDialog.visible
        anchors.fill: layoutDialog
        sourceComponent: StyledRectangularShadow {
            target: layoutDialog
            anchors.fill: undefined
        }
    }

    Rectangle {
        id: layoutDialog
        visible: opacity > 0.01
        opacity: 0
        scale: 0.8
        transformOrigin: Item.Bottom
        
        x: leftIsland.x + layoutSwitcherButton.x + (layoutSwitcherButton.width - width) / 2
        y: leftIsland.y - height - 10
        
        width: 140
        height: layoutList.implicitHeight + 16
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer
        
        // Prevent click-through
        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: false
        }
        
        ColumnLayout {
            id: layoutList
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4
            
            Repeater {
                model: HyprlandXkb.layoutCodes
                delegate: RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    buttonRadius: Appearance.rounding.small
                    
                    readonly property string layoutCodeString: modelData.trim()
                    readonly property bool isActive: HyprlandXkb.currentLayoutCode.startsWith(layoutCodeString)
                    
                    colBackground: isActive ? Appearance.colors.colPrimary : "transparent"
                    colBackgroundHover: isActive ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                    colRipple: isActive ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
                    
                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        
                        MaterialSymbol {
                            text: "keyboard"
                            iconSize: 18
                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            fill: 1
                        }
                        
                        StyledText {
                            Layout.fillWidth: true
                            text: layoutCodeString.toUpperCase()
                            font.weight: Font.Bold
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        }
                    }
                    
                    onClicked: {
                        const idx = index;
                        const cmd = "hyprctl switchxkblayout all " + idx;
                        const proc = Qt.createQmlObject('import Quickshell; Process { command: ["bash", "-c", "' + cmd + '"] }', layoutDialog);
                        proc.running = true;
                        layoutDialog.close();
                    }
                }
            }
        }
        
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutBack }
        }
        
        function open() {
            opacity = 1;
            scale = 1;
        }
        
        function close() {
            opacity = 0;
            scale = 0.8;
        }
        
        function toggle() {
            if (opacity === 1) {
                close();
            } else {
                open();
            }
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            layoutDialog.close();
        }
    }
}
