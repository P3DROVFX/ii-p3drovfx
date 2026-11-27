pragma ComponentBehavior: Bound
import QtQuick

/**
 * URL-based delegate loader for AndroidQuickPanel.
 *
 * Instead of declaring 110 inline DelegateChoice components (which forces Qt to compile
 * every toggle and dashboard widget type + its service singletons on panel load), a single
 * Loader resolves only the QML files actually present in the user's grid.
 */
Loader {
    id: root
    required property int index
    required property var modelData
    property bool editMode: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    property int pageIndex: 0
    property int gridColumns: 4
    property bool isUnused: false
    property var panel: null
    property var gridRef: null
    property int entranceTrigger: -1
    signal openAudioOutputDialog
    signal openAudioInputDialog
    signal openBluetoothDialog
    signal openNightLightDialog
    signal openWifiDialog
    signal openDarkModeDialog
    signal openLocalSendDialog
    signal openVpnDialog
    signal openTailscaleDialog
    signal openKdeConnectDialog
    signal openDnsOverTlsDialog
    signal openIdleInhibitorDialog
    signal openScreenShaderDialog
    signal openModesDialog
    signal openEasyEffectsDialog
    signal openSmartDevicesDialog

    readonly property string resolvedType: root.modelData?.type ?? ""
    readonly property var spec: root.toggleRegistry[root.resolvedType] ?? null

    z: item ? item.z : 0
    asynchronous: false

    function syncSource() {
        const s = root.spec;
        if (!s) {
            root.setSource("");
            return;
        }
        root.setSource(Qt.resolvedUrl(s.file), {
            buttonIndex: root.index,
            buttonData: root.modelData,
            baseCellWidth: root.baseCellWidth,
            baseCellHeight: root.baseCellHeight,
            cellSpacing: root.spacing,
            cellSize: root.modelData?.sizeW ?? 1,
            isUnused: root.isUnused,
            editMode: root.editMode,
            pageIndex: root.pageIndex,
            gridColumns: root.gridColumns,
            panel: root.panel,
            gridRef: root.gridRef,
            entranceTrigger: root.entranceTrigger
        });
    }

    onResolvedTypeChanged: root.syncSource()
    Component.onCompleted: root.syncSource()

    readonly property var toggleRegistry: ({
        "screenShader": { file: "AndroidScreenShaderToggle.qml", menu: "openScreenShaderDialog" },
        "antiFlashbang": { file: "AndroidAntiFlashbangToggle.qml", menu: "openNightLightDialog" },
        "audio": { file: "AndroidAudioToggle.qml", menu: "openAudioOutputDialog" },
        "bluetooth": { file: "AndroidBluetoothToggle.qml", menu: "openBluetoothDialog" },
        "cloudflareWarp": { file: "AndroidCloudflareWarpToggle.qml" },
        "colorPicker": { file: "AndroidColorPickerToggle.qml" },
        "videoEditor": { file: "AndroidVideoEditorToggle.qml" },
        "darkMode": { file: "AndroidDarkModeToggle.qml", menu: "openDarkModeDialog" },
        "easyEffects": { file: "AndroidEasyEffectsToggle.qml", menu: "openEasyEffectsDialog" },
        "gameMode": { file: "AndroidGameModeToggle.qml" },
        "modes": { file: "AndroidModesToggle.qml", menu: "openModesDialog" },
        "notes": { file: "AndroidNotesToggle.qml" },
        "idleInhibitor": { file: "AndroidIdleInhibitorToggle.qml", menu: "openIdleInhibitorDialog" },
        "mic": { file: "AndroidMicToggle.qml", menu: "openAudioInputDialog" },
        "discordVoice": { file: "AndroidDiscordVoiceToggle.qml" },
        "phoneCamera": { file: "AndroidPhoneCameraToggle.qml" },
        "phoneMic": { file: "AndroidPhoneMicToggle.qml" },
        "phoneMirror": { file: "AndroidPhoneMirrorToggle.qml" },
        "speedTest": { file: "AndroidSpeedTestToggle.qml" },
        "musicRecognition": { file: "AndroidMusicRecognition.qml" },
        "network": { file: "AndroidNetworkToggle.qml", menu: "openWifiDialog" },
        "nightLight": { file: "AndroidNightLightToggle.qml", menu: "openNightLightDialog" },
        "smartDevices": { file: "AndroidSmartDevicesToggle.qml", menu: "openSmartDevicesDialog" },
        "notifications": { file: "AndroidNotificationToggle.qml" },
        "autoDnd": { file: "AndroidAutoDndToggle.qml" },
        "onScreenKeyboard": { file: "AndroidOnScreenKeyboardToggle.qml" },
        "keypressDisplay": { file: "AndroidKeypressDisplayToggle.qml" },
        "powerProfile": { file: "AndroidPowerProfileToggle.qml" },
        "screenRecord": { file: "AndroidScreenRecordToggle.qml" },
        "liveDraw": { file: "AndroidLiveDrawToggle.qml" },
        "screenSnip": { file: "AndroidScreenSnipToggle.qml" },
        "systemSounds": { file: "AndroidSystemSoundsToggle.qml" },
        "soundcoreAnc": { file: "AndroidSoundcoreAncToggle.qml" },
        "localSend": { file: "AndroidLocalSendToggle.qml", menu: "openLocalSendDialog" },
        "mediaWidget": { file: "AndroidMediaWidgetToggle.qml" },
        "mediaCircleWidget": { file: "media/AndroidMediaCircleToggle.qml" },
        "expressiveMediaWidget": { file: "media/AndroidExpressiveMediaToggle.qml" },
        "cdMediaWidget": { file: "media/AndroidCdMediaToggle.qml" },
        "compactMediaWidget": { file: "media/AndroidCompactMediaToggle.qml" },
        "nothingRingMediaWidget": { file: "media/AndroidNothingRingMediaToggle.qml" },
        "bluetoothBatteryWidget": { file: "battery/AndroidBluetoothBatteryToggle.qml" },
        "mobileBatteryWidget": { file: "battery/AndroidMobileBatteryToggle.qml" },
        "bluetoothHeadphoneCookieWidget": { file: "battery/AndroidBluetoothHeadphoneCookieToggle.qml" },
        "pcBatteryBarsWidget": { file: "battery/AndroidPcBatteryBarsToggle.qml" },
        "pcBatteryCableWidget": { file: "battery/AndroidPcBatteryCableToggle.qml" },
        "devicesBatteryListWidget": { file: "battery/AndroidDevicesBatteryListToggle.qml" },
        "bluetoothEarbudsStemWidget": { file: "battery/AndroidBluetoothEarbudsStemToggle.qml" },
        "laptopBatteryWidget": { file: "battery/AndroidLaptopBatteryToggle.qml" },
        "systemResourcesWidget": { file: "resources/AndroidSystemResourcesToggle.qml" },
        "cpuResourceWidget": { file: "resources/AndroidCpuResourceToggle.qml" },
        "ramResourceWidget": { file: "resources/AndroidRamResourceToggle.qml" },
        "diskResourceWidget": { file: "resources/AndroidDiskResourceToggle.qml" },
        "gpuResourceWidget": { file: "resources/AndroidGpuResourceToggle.qml" },
        "weatherIconShape": { file: "weather/AndroidWeatherIconShapeToggle.qml" },
        "weatherCard": { file: "weather/AndroidWeatherCardToggle.qml" },
        "weatherWidget": { file: "weather/AndroidWeatherWidgetToggle.qml" },
        "weatherCircle": { file: "weather/AndroidWeatherCircleToggle.qml" },
        "weatherTypography": { file: "weather/AndroidWeatherTypographyToggle.qml" },
        "weatherForecast": { file: "weather/AndroidWeatherForecastToggle.qml" },
        "dashboardToolbar": { file: "AndroidDashboardToolbarToggle.qml" },
        "toolbar": { file: "AndroidDashboardToolbarToggle.qml" },
        "clockWidget": { file: "AndroidClockToggle.qml" },
        "flexClock": { file: "AndroidClockToggle.qml" },
        "horiClock": { file: "AndroidClockToggle.qml" },
        "iosClockWidget": { file: "AndroidIosClockToggle.qml" },
        "iosClock": { file: "AndroidIosClockToggle.qml" },
        "clockIos": { file: "AndroidIosClockToggle.qml" },
        "digitalClockWidget": { file: "AndroidDigitalClockToggle.qml" },
        "clock_ios": { file: "AndroidIosClockToggle.qml" },
        "notificationListWidget": { file: "AndroidNotificationListToggle.qml" },
        "notificationWidget": { file: "AndroidNotificationListToggle.qml" },
        "notificationsWidget": { file: "AndroidNotificationListToggle.qml" },
        "notificationList": { file: "AndroidNotificationListToggle.qml" },
        "notificationsList": { file: "AndroidNotificationListToggle.qml" },
        "calendarWidget": { file: "AndroidDashboardWidgetToggle.qml" },
        "tasksWidget": { file: "AndroidDashboardWidgetToggle.qml" },
        "timerWidget": { file: "AndroidDashboardWidgetToggle.qml" },
        "countdownWidget": { file: "AndroidDashboardWidgetToggle.qml" },
        "pomodoroWidget": { file: "AndroidDashboardWidgetToggle.qml" },
        "fullCalendarWidget": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "calendarMinimalWidget": { file: "calendar/AndroidCalendarMinimalToggle.qml" },
        "calendarMonthGridWidget": { file: "calendar/AndroidCalendarMonthGridToggle.qml" },
        "calendarMonthAgendaWidget": { file: "calendar/AndroidCalendarMonthAgendaToggle.qml" },
        "calendarUpcomingWidget": { file: "calendar/AndroidCalendarUpcomingToggle.qml" },
        "fullTasksWidget": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "fullTimerWidget": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "fullCountdownWidget": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "fullPomodoroWidget": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "fullRemindersWidget": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "fullNotesWidget": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "calendar": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "todo": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "timer": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "countdown": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "pomodoro": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "notesWidget": { file: "AndroidFullDashboardWidgetToggle.qml" },
        "volumeSlider": { file: "AndroidVolumeSliderToggle.qml", menu: "openAudioOutputDialog" },
        "micSlider": { file: "AndroidMicSliderToggle.qml", menu: "openAudioInputDialog" },
        "brightnessSlider": { file: "AndroidBrightnessSliderToggle.qml" },
        "gammaSlider": { file: "AndroidGammaSliderToggle.qml" },
        "keyboardBacklight": { file: "AndroidKeyboardBacklightToggle.qml" },
        "laptopKeyboard": { file: "AndroidLaptopKeyboardToggle.qml" },
        "vpn": { file: "AndroidVpnToggle.qml", menu: "openVpnDialog" },
        "tailscale": { file: "AndroidTailscaleToggle.qml", menu: "openTailscaleDialog" },
        "kdeConnect": { file: "AndroidKdeConnectToggle.qml", menu: "openKdeConnectDialog" },
        "dnsOverTls": { file: "AndroidDnsOverTlsToggle.qml", menu: "openDnsOverTlsDialog" },
        "sportsWidget": { file: "sports/AndroidSportsToggle.qml" },
        "sportsCard": { file: "sports/AndroidSportsCardToggle.qml" },
        "vitalsWidget": { file: "AndroidVitalsToggle.qml" },
        "photoWidget": { file: "AndroidPhotoWidgetToggle.qml" },
        "trayWidget": { file: "AndroidTrayToggle.qml" },
    })

    function dispatchMenu(menuName) {
        switch (menuName) {
        case "openAudioOutputDialog": root.openAudioOutputDialog(); break;
        case "openAudioInputDialog": root.openAudioInputDialog(); break;
        case "openBluetoothDialog": root.openBluetoothDialog(); break;
        case "openNightLightDialog": root.openNightLightDialog(); break;
        case "openWifiDialog": root.openWifiDialog(); break;
        case "openDarkModeDialog": root.openDarkModeDialog(); break;
        case "openLocalSendDialog": root.openLocalSendDialog(); break;
        case "openVpnDialog": root.openVpnDialog(); break;
        case "openTailscaleDialog": root.openTailscaleDialog(); break;
        case "openKdeConnectDialog": root.openKdeConnectDialog(); break;
        case "openDnsOverTlsDialog": root.openDnsOverTlsDialog(); break;
        case "openIdleInhibitorDialog": root.openIdleInhibitorDialog(); break;
        case "openScreenShaderDialog": root.openScreenShaderDialog(); break;
        case "openModesDialog": root.openModesDialog(); break;
        case "openEasyEffectsDialog": root.openEasyEffectsDialog(); break;
        case "openSmartDevicesDialog": root.openSmartDevicesDialog(); break;
        }
    }

    Binding { target: root.item; property: "buttonIndex"; value: root.index; when: root.item !== null }
    Binding { target: root.item; property: "isUnused"; value: root.isUnused; when: root.item !== null }
    Binding { target: root.item; property: "buttonData"; value: root.modelData; when: root.item !== null }
    Binding { target: root.item; property: "editMode"; value: root.editMode; when: root.item !== null }
    Binding { target: root.item; property: "baseCellWidth"; value: root.baseCellWidth; when: root.item !== null }
    Binding { target: root.item; property: "baseCellHeight"; value: root.baseCellHeight; when: root.item !== null }
    Binding { target: root.item; property: "cellSpacing"; value: root.spacing; when: root.item !== null }
    Binding { target: root.item; property: "cellSize"; value: root.modelData?.sizeW ?? 1; when: root.item !== null }
    Binding { target: root.item; property: "pageIndex"; value: root.pageIndex; when: root.item !== null }
    Binding { target: root.item; property: "gridColumns"; value: root.gridColumns; when: root.item !== null }
    Binding { target: root.item; property: "panel"; value: root.panel; when: root.item !== null }
    Binding { target: root.item; property: "gridRef"; value: root.gridRef; when: root.item !== null }
    Binding { target: root.item; property: "entranceTrigger"; value: root.entranceTrigger; when: root.item !== null }

    Connections {
        target: root.item
        ignoreUnknownSignals: true
        function onOpenMenu() {
            if (root.spec && root.spec.menu)
                root.dispatchMenu(root.spec.menu);
        }
    }
}
