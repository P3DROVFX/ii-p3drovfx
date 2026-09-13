# Inventário por módulo — auditoria de 8 de setembro de 2026

Leitura estática do fork e checkout local do end-4. As contagens são declarações encontradas no texto (inclusive componentes condicionais e eventuais comentários); não são objetos vivos, CPU ou RAM. N/I = consumo QML exclusivo não isolado. Helpers medidos separadamente estão no relatório principal.

| Árvore do fork | Arquivos QML | KiB de fonte | Timers declarados | Processos declarados | Layers declaradas | QML exclusivo |
|---|---:|---:|---:|---:|---:|---|
| `GlobalStates.qml` | 1 | 95.4 | 6 | 0 | 0 | N/I |
| `ReloadPopup.qml` | 1 | 3.8 | 0 | 0 | 0 | N/I |
| `SettingsWindow.qml` | 1 | 36.8 | 4 | 0 | 0 | N/I |
| `killDialog.qml` | 1 | 6.4 | 0 | 1 | 0 | N/I |
| `modules` | 66 | 884.6 | 18 | 1 | 9 | N/I |
| `modules/common/animations` | 2 | 2.8 | 0 | 0 | 0 | N/I |
| `modules/common/dashboardWidgets` | 14 | 136.3 | 1 | 0 | 0 | N/I |
| `modules/common/dock` | 1 | 4.9 | 0 | 0 | 1 | N/I |
| `modules/common/draw` | 4 | 27.2 | 0 | 0 | 0 | N/I |
| `modules/common/functions` | 19 | 61.5 | 0 | 0 | 0 | N/I |
| `modules/common/media` | 1 | 27.3 | 1 | 1 | 3 | N/I |
| `modules/common/models` | 45 | 57.7 | 7 | 13 | 0 | N/I |
| `modules/common/notifications` | 1 | 8.4 | 1 | 0 | 0 | N/I |
| `modules/common/onScreenKeyboard` | 6 | 29.8 | 1 | 0 | 0 | N/I |
| `modules/common/panels` | 6 | 50.8 | 7 | 1 | 0 | N/I |
| `modules/common/quickToggleDialogs` | 23 | 289.9 | 0 | 2 | 13 | N/I |
| `modules/common/quickToggles` | 65 | 262.7 | 3 | 6 | 12 | N/I |
| `modules/common/tray` | 2 | 13.0 | 0 | 0 | 0 | N/I |
| `modules/common/utils` | 7 | 35.5 | 1 | 6 | 0 | N/I |
| `modules/common/widgets` | 201 | 935.3 | 26 | 11 | 36 | N/I |
| `modules/ii/alarmRingingPopup` | 1 | 4.8 | 0 | 0 | 0 | N/I |
| `modules/ii/background` | 151 | 1404.1 | 36 | 16 | 123 | N/I |
| `modules/ii/bar` | 172 | 1709.2 | 34 | 10 | 51 | N/I |
| `modules/ii/bluetoothConnectionPopup` | 2 | 23.6 | 1 | 0 | 0 | N/I |
| `modules/ii/bluetoothPairing` | 2 | 8.5 | 1 | 0 | 0 | N/I |
| `modules/ii/cheatsheet` | 60 | 1309.7 | 51 | 3 | 3 | N/I |
| `modules/ii/colorPickerPopup` | 2 | 41.0 | 9 | 2 | 0 | N/I |
| `modules/ii/dock` | 32 | 367.1 | 22 | 2 | 16 | N/I |
| `modules/ii/dynamicIsland` | 20 | 335.3 | 17 | 1 | 20 | N/I |
| `modules/ii/editMode` | 28 | 317.0 | 2 | 1 | 1 | N/I |
| `modules/ii/keyboardLayoutTransitionPopup` | 2 | 16.0 | 2 | 0 | 0 | N/I |
| `modules/ii/keypressDisplay` | 1 | 17.2 | 1 | 0 | 0 | N/I |
| `modules/ii/localSendPopup` | 2 | 17.2 | 1 | 0 | 0 | N/I |
| `modules/ii/lock` | 5 | 96.7 | 3 | 1 | 2 | N/I |
| `modules/ii/mediaControls` | 2 | 28.5 | 2 | 1 | 3 | N/I |
| `modules/ii/modeFlashPopup` | 2 | 8.2 | 0 | 0 | 0 | N/I |
| `modules/ii/modes` | 76 | 321.3 | 5 | 0 | 0 | N/I |
| `modules/ii/notes` | 46 | 458.4 | 8 | 6 | 1 | N/I |
| `modules/ii/notificationPopup` | 1 | 4.9 | 1 | 0 | 0 | N/I |
| `modules/ii/oledSaver` | 1 | 5.6 | 3 | 0 | 0 | N/I |
| `modules/ii/onScreenDisplay` | 17 | 153.1 | 6 | 0 | 1 | N/I |
| `modules/ii/overlay` | 26 | 130.2 | 5 | 4 | 4 | N/I |
| `modules/ii/overview` | 56 | 1325.3 | 49 | 8 | 17 | N/I |
| `modules/ii/polkit` | 2 | 17.1 | 1 | 0 | 0 | N/I |
| `modules/ii/regionSelector` | 18 | 154.3 | 2 | 4 | 1 | N/I |
| `modules/ii/scratchpadOverlay` | 1 | 6.0 | 1 | 0 | 0 | N/I |
| `modules/ii/screenCorners` | 1 | 10.6 | 1 | 0 | 0 | N/I |
| `modules/ii/screenTranslator` | 3 | 20.9 | 0 | 0 | 1 | N/I |
| `modules/ii/screenshotOverlay` | 2 | 17.3 | 1 | 0 | 1 | N/I |
| `modules/ii/sessionScreen` | 2 | 19.0 | 2 | 0 | 0 | N/I |
| `modules/ii/sidebarDashboard` | 6 | 90.5 | 2 | 0 | 3 | N/I |
| `modules/ii/sidebarPolicies` | 45 | 954.1 | 22 | 5 | 15 | N/I |
| `modules/ii/tilingAssistant` | 4 | 18.8 | 3 | 0 | 0 | N/I |
| `modules/ii/topLayer` | 15 | 129.3 | 4 | 0 | 3 | N/I |
| `modules/ii/touchGestures` | 3 | 16.0 | 2 | 0 | 0 | N/I |
| `modules/ii/usage` | 10 | 156.6 | 7 | 0 | 2 | N/I |
| `modules/ii/verticalBar` | 13 | 111.2 | 4 | 2 | 8 | N/I |
| `modules/ii/videoEditor` | 3 | 54.0 | 2 | 5 | 0 | N/I |
| `modules/ii/wallpaperSelector` | 8 | 112.0 | 6 | 5 | 4 | N/I |
| `modules/ii/wrappedFrame` | 2 | 23.5 | 0 | 0 | 1 | N/I |
| `modules/settings/configs` | 360 | 3323.1 | 30 | 32 | 14 | N/I |
| `modules/tablet/appDrawer` | 6 | 97.5 | 2 | 0 | 3 | N/I |
| `modules/tablet/appWindow` | 3 | 14.8 | 0 | 0 | 0 | N/I |
| `modules/tablet/dock` | 8 | 66.5 | 0 | 0 | 0 | N/I |
| `modules/tablet/floatingBubble` | 3 | 21.9 | 2 | 0 | 0 | N/I |
| `modules/tablet/homeScreen` | 5 | 44.4 | 3 | 0 | 0 | N/I |
| `modules/tablet/hubMode` | 1 | 14.0 | 2 | 0 | 0 | N/I |
| `modules/tablet/liveDraw` | 3 | 33.2 | 3 | 1 | 0 | N/I |
| `modules/tablet/menu` | 2 | 13.0 | 0 | 0 | 0 | N/I |
| `modules/tablet/navigation` | 4 | 25.1 | 1 | 0 | 0 | N/I |
| `modules/tablet/recents` | 6 | 58.3 | 1 | 0 | 2 | N/I |
| `modules/tablet/setup` | 3 | 21.7 | 1 | 0 | 0 | N/I |
| `modules/tablet/sidebarDashboard` | 9 | 61.6 | 0 | 0 | 3 | N/I |
| `modules/tablet/windows` | 4 | 47.5 | 5 | 0 | 0 | N/I |
| `modules/waffle/actionCenter` | 24 | 63.4 | 0 | 1 | 1 | N/I |
| `modules/waffle/background` | 1 | 1.1 | 0 | 0 | 0 | N/I |
| `modules/waffle/bar` | 22 | 47.8 | 2 | 0 | 2 | N/I |
| `modules/waffle/lock` | 1 | 12.5 | 0 | 0 | 1 | N/I |
| `modules/waffle/looks` | 48 | 72.0 | 1 | 0 | 3 | N/I |
| `modules/waffle/notificationCenter` | 14 | 38.6 | 2 | 0 | 0 | N/I |
| `modules/waffle/notificationPopup` | 1 | 4.9 | 0 | 0 | 0 | N/I |
| `modules/waffle/onScreenDisplay` | 4 | 8.7 | 1 | 0 | 0 | N/I |
| `modules/waffle/polkit` | 2 | 7.7 | 0 | 0 | 0 | N/I |
| `modules/waffle/screenSnip` | 3 | 18.6 | 0 | 1 | 0 | N/I |
| `modules/waffle/sessionScreen` | 4 | 10.5 | 0 | 0 | 0 | N/I |
| `modules/waffle/startMenu` | 17 | 59.0 | 0 | 0 | 0 | N/I |
| `modules/waffle/taskView` | 4 | 24.0 | 0 | 0 | 2 | N/I |
| `modules/welcome/tutorials` | 7 | 61.6 | 0 | 3 | 0 | N/I |
| `panelFamilies` | 4 | 33.3 | 0 | 0 | 0 | N/I |
| `services` | 276 | 3643.9 | 277 | 376 | 2 | N/I |
| `shell.qml` | 1 | 13.6 | 2 | 1 | 0 | N/I |
| `tests` | 28 | 172.0 | 0 | 0 | 0 | N/I |
| `welcome.qml` | 1 | 0.5 | 0 | 0 | 0 | N/I |

## Serviços individualmente

Um arquivo nesta lista não implica que o singleton foi instanciado. Serviços e widgets dividem os heaps nativo e JavaScript; custo exclusivo exige instrumentação e isolamento.

| Serviço QML | Singleton | KiB de fonte | Timers | Processos | RAM / CPU exclusivos |
|---|---|---:|---:|---:|---|
| `services/Ai.qml` | sim | 339.0 | 7 | 14 | N/I |
| `services/AiAttentionService.qml` | sim | 3.8 | 0 | 0 | N/I |
| `services/AiPlanUsage.qml` | sim | 16.4 | 2 | 1 | N/I |
| `services/AiStatusService.qml` | sim | 3.4 | 1 | 1 | N/I |
| `services/AiUsage.qml` | sim | 17.7 | 3 | 0 | N/I |
| `services/AlarmService.qml` | sim | 6.7 | 2 | 0 | N/I |
| `services/AppSearch.qml` | sim | 13.1 | 0 | 0 | N/I |
| `services/AppStats.qml` | sim | 31.8 | 4 | 3 | N/I |
| `services/AppUsage.qml` | sim | 5.7 | 3 | 0 | N/I |
| `services/AtAGlanceService.qml` | sim | 13.8 | 0 | 0 | N/I |
| `services/Audio.qml` | sim | 5.2 | 0 | 0 | N/I |
| `services/Battery.qml` | sim | 8.1 | 0 | 0 | N/I |
| `services/BirthdaysService.qml` | sim | 2.6 | 0 | 0 | N/I |
| `services/BluetoothAgent.qml` | sim | 6.1 | 1 | 1 | N/I |
| `services/BluetoothStatus.qml` | sim | 8.0 | 2 | 3 | N/I |
| `services/Booru.qml` | sim | 19.5 | 0 | 0 | N/I |
| `services/BooruResponseData.qml` | não | 0.2 | 0 | 0 | N/I |
| `services/Brightness.qml` | sim | 9.8 | 2 | 4 | N/I |
| `services/BrowserSites.qml` | sim | 22.2 | 4 | 3 | N/I |
| `services/BudsLinkService.qml` | sim | 22.6 | 6 | 1 | N/I |
| `services/BudsService.qml` | sim | 5.5 | 0 | 1 | N/I |
| `services/CalendarIcsFileImport.qml` | sim | 4.5 | 0 | 1 | N/I |
| `services/CalendarNotifier.qml` | sim | 12.7 | 1 | 0 | N/I |
| `services/CalendarService.qml` | sim | 32.0 | 2 | 5 | N/I |
| `services/CalendarSubscriptions.qml` | sim | 6.6 | 0 | 2 | N/I |
| `services/CavaService.qml` | sim | 0.9 | 0 | 1 | N/I |
| `services/ChangelogService.qml` | sim | 5.9 | 0 | 1 | N/I |
| `services/Cliphist.qml` | sim | 14.9 | 2 | 3 | N/I |
| `services/CommandsService.qml` | sim | 6.6 | 1 | 0 | N/I |
| `services/ConflictKiller.qml` | sim | 1.5 | 0 | 1 | N/I |
| `services/CustomLyricsStore.qml` | sim | 3.1 | 2 | 0 | N/I |
| `services/DarkModeService.qml` | sim | 3.2 | 0 | 0 | N/I |
| `services/DashboardIconCues.qml` | sim | 6.4 | 0 | 0 | N/I |
| `services/DateTime.qml` | sim | 5.3 | 1 | 0 | N/I |
| `services/DefaultApps.qml` | sim | 9.2 | 1 | 2 | N/I |
| `services/DictationService.qml` | sim | 32.7 | 6 | 11 | N/I |
| `services/DiscordVoice.qml` | sim | 7.0 | 3 | 1 | N/I |
| `services/DisplayCalibration.qml` | sim | 12.8 | 1 | 3 | N/I |
| `services/DisplayColorFilter.qml` | sim | 7.5 | 2 | 1 | N/I |
| `services/DnsOverTls.qml` | sim | 11.5 | 2 | 4 | N/I |
| `services/DockLivePreviewService.qml` | sim | 6.8 | 0 | 0 | N/I |
| `services/DockerService.qml` | sim | 15.5 | 4 | 6 | N/I |
| `services/EarbudsControlService.qml` | sim | 16.2 | 0 | 0 | N/I |
| `services/EasyEffects.qml` | sim | 3.6 | 2 | 4 | N/I |
| `services/EmailService.qml` | sim | 47.7 | 4 | 17 | N/I |
| `services/Emojis.qml` | sim | 10.5 | 2 | 0 | N/I |
| `services/Fingerprint.qml` | sim | 23.3 | 2 | 6 | N/I |
| `services/GameDetector.qml` | sim | 10.1 | 4 | 0 | N/I |
| `services/GlobalFocusGrab.qml` | sim | 2.0 | 0 | 0 | N/I |
| `services/GmailCalendarImport.qml` | sim | 7.0 | 2 | 1 | N/I |
| `services/GoogleCalendarService.qml` | sim | 25.8 | 0 | 10 | N/I |
| `services/GoogleCloud.qml` | sim | 3.3 | 0 | 0 | N/I |
| `services/GoogleDriveService.qml` | sim | 27.3 | 3 | 6 | N/I |
| `services/GoogleTasksService.qml` | sim | 21.4 | 0 | 6 | N/I |
| `services/Holidays.qml` | sim | 10.9 | 2 | 0 | N/I |
| `services/Hotspot.qml` | sim | 10.2 | 1 | 0 | N/I |
| `services/HyprlandAntiFlashbangShader.qml` | sim | 0.7 | 0 | 0 | N/I |
| `services/HyprlandBinds.qml` | sim | 47.5 | 1 | 5 | N/I |
| `services/HyprlandCatalog.qml` | sim | 34.0 | 0 | 0 | N/I |
| `services/HyprlandConfig.qml` | sim | 5.5 | 0 | 1 | N/I |
| `services/HyprlandData.qml` | sim | 11.3 | 1 | 6 | N/I |
| `services/HyprlandDevices.qml` | sim | 6.5 | 1 | 1 | N/I |
| `services/HyprlandEnv.qml` | sim | 33.2 | 0 | 5 | N/I |
| `services/HyprlandGui.qml` | sim | 51.5 | 3 | 6 | N/I |
| `services/HyprlandKeybinds.qml` | sim | 3.0 | 0 | 2 | N/I |
| `services/HyprlandRules.qml` | sim | 27.9 | 0 | 0 | N/I |
| `services/HyprlandSettings.qml` | sim | 5.6 | 1 | 1 | N/I |
| `services/HyprlandXkb.qml` | sim | 5.6 | 0 | 2 | N/I |
| `services/Hyprsunset.qml` | sim | 12.8 | 2 | 1 | N/I |
| `services/IconThemes.qml` | sim | 13.4 | 2 | 5 | N/I |
| `services/Idle.qml` | sim | 11.5 | 3 | 0 | N/I |
| `services/KdeConnectService.qml` | sim | 83.4 | 11 | 14 | N/I |
| `services/KeybindsService.qml` | sim | 47.6 | 5 | 5 | N/I |
| `services/KeyboardBacklight.qml` | sim | 7.8 | 3 | 3 | N/I |
| `services/KeypressService.qml` | sim | 14.2 | 2 | 1 | N/I |
| `services/KeyringStorage.qml` | sim | 5.2 | 1 | 2 | N/I |
| `services/LaptopKeyboardService.qml` | sim | 2.0 | 0 | 0 | N/I |
| `services/LatexRenderer.qml` | sim | 3.5 | 0 | 1 | N/I |
| `services/LauncherApps.qml` | sim | 1.5 | 0 | 0 | N/I |
| `services/LauncherSearch.qml` | sim | 126.0 | 2 | 2 | N/I |
| `services/LocalLyrics.qml` | sim | 1.1 | 0 | 0 | N/I |
| `services/LocalMediaSelection.qml` | sim | 7.5 | 1 | 2 | N/I |
| `services/LocalMediaService.qml` | sim | 23.4 | 1 | 4 | N/I |
| `services/LocalSend.qml` | sim | 23.9 | 3 | 8 | N/I |
| `services/LyricsService.qml` | sim | 14.3 | 3 | 0 | N/I |
| `services/MaterialThemeLoader.qml` | sim | 7.7 | 1 | 0 | N/I |
| `services/MediaDownloaderService.qml` | sim | 22.1 | 1 | 5 | N/I |
| `services/Modes.qml` | sim | 54.4 | 6 | 0 | N/I |
| `services/MonoAudioService.qml` | sim | 2.5 | 1 | 2 | N/I |
| `services/MprisController.qml` | sim | 10.8 | 1 | 1 | N/I |
| `services/MusicVideoService.qml` | sim | 15.8 | 1 | 3 | N/I |
| `services/Network.qml` | sim | 20.8 | 5 | 2 | N/I |
| `services/NetworkCommands.qml` | sim | 28.4 | 0 | 1 | N/I |
| `services/NetworkFallback.qml` | sim | 5.9 | 3 | 0 | N/I |
| `services/NetworkProfiles.qml` | sim | 5.0 | 1 | 0 | N/I |
| `services/NetworkSpeed.qml` | sim | 2.9 | 1 | 1 | N/I |
| `services/NetworkState.qml` | sim | 11.4 | 0 | 0 | N/I |
| `services/NotesService.qml` | sim | 32.8 | 2 | 1 | N/I |
| `services/Notifications.qml` | sim | 28.5 | 4 | 0 | N/I |
| `services/OskAutoShow.qml` | sim | 14.5 | 2 | 2 | N/I |
| `services/OutlookCalendarImport.qml` | sim | 6.3 | 2 | 1 | N/I |
| `services/OutlookIcsImport.qml` | sim | 7.2 | 2 | 1 | N/I |
| `services/OutlookService.qml` | sim | 10.6 | 1 | 3 | N/I |
| `services/PenMode.qml` | sim | 12.3 | 0 | 1 | N/I |
| `services/PhoneAppIconService.qml` | sim | 6.0 | 0 | 1 | N/I |
| `services/PhoneCameraService.qml` | sim | 34.4 | 7 | 8 | N/I |
| `services/PhoneContactsService.qml` | sim | 10.6 | 3 | 2 | N/I |
| `services/PhoneMicService.qml` | sim | 61.3 | 12 | 21 | N/I |
| `services/PhoneScrcpyService.qml` | sim | 14.3 | 2 | 2 | N/I |
| `services/PolkitService.qml` | sim | 1.4 | 0 | 0 | N/I |
| `services/PortWatcher.qml` | sim | 11.3 | 3 | 2 | N/I |
| `services/PresetStore.qml` | sim | 27.1 | 3 | 2 | N/I |
| `services/Privacy.qml` | sim | 6.4 | 1 | 1 | N/I |
| `services/ProgressService.qml` | sim | 7.0 | 1 | 1 | N/I |
| `services/QuickToggleRegistry.qml` | sim | 4.8 | 0 | 0 | N/I |
| `services/ResourceUsage.qml` | sim | 25.3 | 4 | 8 | N/I |
| `services/RustHelperBuild.qml` | não | 8.3 | 1 | 2 | N/I |
| `services/ScreenShader.qml` | sim | 14.0 | 0 | 4 | N/I |
| `services/SearchRegistry.qml` | sim | 22.0 | 0 | 1 | N/I |
| `services/SessionWarnings.qml` | sim | 1.1 | 0 | 2 | N/I |
| `services/ShellBackup.qml` | sim | 11.0 | 2 | 1 | N/I |
| `services/ShellUpdates.qml` | sim | 9.0 | 4 | 3 | N/I |
| `services/SongRec.qml` | sim | 4.5 | 0 | 2 | N/I |
| `services/SoundService.qml` | sim | 15.9 | 0 | 3 | N/I |
| `services/SoundcoreService.qml` | sim | 3.3 | 0 | 1 | N/I |
| `services/SportsService.qml` | sim | 59.6 | 5 | 0 | N/I |
| `services/SystemInfo.qml` | sim | 4.3 | 1 | 2 | N/I |
| `services/TailscaleService.qml` | sim | 15.1 | 1 | 2 | N/I |
| `services/TaskbarApps.qml` | sim | 11.6 | 0 | 0 | N/I |
| `services/ThemePreviewCache.qml` | sim | 4.3 | 1 | 0 | N/I |
| `services/TickTickService.qml` | sim | 16.1 | 1 | 6 | N/I |
| `services/TilingAssistant.qml` | sim | 50.2 | 3 | 2 | N/I |
| `services/TimerService.qml` | sim | 13.3 | 3 | 0 | N/I |
| `services/Todo.qml` | sim | 17.9 | 2 | 0 | N/I |
| `services/TouchGestureService.qml` | sim | 40.6 | 2 | 3 | N/I |
| `services/Translation.qml` | sim | 5.4 | 0 | 1 | N/I |
| `services/TrayService.qml` | sim | 4.8 | 0 | 0 | N/I |
| `services/TypeToSearch.qml` | sim | 17.0 | 2 | 1 | N/I |
| `services/TypingLanguages.qml` | sim | 5.2 | 0 | 0 | N/I |
| `services/TypingSoundPacks.qml` | sim | 2.2 | 0 | 0 | N/I |
| `services/Updates.qml` | sim | 1.6 | 1 | 2 | N/I |
| `services/VialKeyboard.qml` | sim | 4.3 | 0 | 1 | N/I |
| `services/VideoColorSampler.qml` | sim | 2.4 | 2 | 1 | N/I |
| `services/VpnService.qml` | sim | 18.5 | 1 | 2 | N/I |
| `services/WallpaperBrowser.qml` | sim | 17.5 | 0 | 0 | N/I |
| `services/WallpaperPreviewCache.qml` | sim | 4.6 | 2 | 1 | N/I |
| `services/WallpaperResponseData.qml` | não | 0.2 | 0 | 0 | N/I |
| `services/Wallpapers.qml` | sim | 25.1 | 1 | 6 | N/I |
| `services/WaterReminderService.qml` | sim | 4.1 | 1 | 0 | N/I |
| `services/Weather.qml` | sim | 18.7 | 4 | 0 | N/I |
| `services/WidgetColorScheme.qml` | sim | 35.1 | 0 | 0 | N/I |
| `services/WidgetExtensionManager.qml` | sim | 18.6 | 2 | 5 | N/I |
| `services/WorkspaceCompactor.qml` | sim | 4.6 | 1 | 1 | N/I |
| `services/WorkspaceProfileService.qml` | sim | 18.2 | 0 | 14 | N/I |
| `services/XdgDesktopPortal.qml` | sim | 11.1 | 1 | 3 | N/I |
| `services/XkbCatalog.qml` | sim | 5.5 | 0 | 1 | N/I |
| `services/Ydotool.qml` | sim | 4.3 | 0 | 0 | N/I |
| `services/ai/AiAccessibilityAnnouncer.qml` | sim | 0.8 | 0 | 0 | N/I |
| `services/ai/AiActionRegistry.qml` | sim | 5.0 | 0 | 0 | N/I |
| `services/ai/AiConversationRepository.qml` | não | 4.5 | 0 | 0 | N/I |
| `services/ai/AiDiagnosticsService.qml` | sim | 23.7 | 0 | 4 | N/I |
| `services/ai/AiDraftStore.qml` | não | 6.5 | 2 | 1 | N/I |
| `services/ai/AiMemory.qml` | sim | 4.0 | 0 | 0 | N/I |
| `services/ai/AiMessageData.qml` | não | 5.3 | 0 | 0 | N/I |
| `services/ai/AiModel.qml` | não | 3.4 | 0 | 0 | N/I |
| `services/ai/AiOutputController.qml` | sim | 2.2 | 0 | 1 | N/I |
| `services/ai/AiPersonas.qml` | não | 6.7 | 0 | 0 | N/I |
| `services/ai/AiProvider.qml` | não | 1.3 | 0 | 0 | N/I |
| `services/ai/AiRagService.qml` | sim | 11.1 | 0 | 4 | N/I |
| `services/ai/AiRequest.qml` | não | 16.0 | 2 | 1 | N/I |
| `services/ai/AiResponseProfiles.qml` | sim | 4.0 | 0 | 0 | N/I |
| `services/ai/AiRunCoordinator.qml` | não | 9.1 | 0 | 0 | N/I |
| `services/ai/AiSearchNavigator.qml` | não | 6.1 | 0 | 0 | N/I |
| `services/ai/AiSearchPage.qml` | não | 20.7 | 0 | 0 | N/I |
| `services/ai/AiSearchSurface.qml` | não | 4.2 | 0 | 0 | N/I |
| `services/ai/AiSessions.qml` | não | 19.7 | 2 | 2 | N/I |
| `services/ai/AiSurfaceRouter.qml` | não | 4.6 | 0 | 0 | N/I |
| `services/ai/AiTextTask.qml` | não | 7.0 | 0 | 0 | N/I |
| `services/ai/AiToolBroker.qml` | não | 21.1 | 1 | 0 | N/I |
| `services/ai/AiToolRegistry.qml` | sim | 97.7 | 0 | 0 | N/I |
| `services/ai/AiTools.qml` | não | 11.1 | 0 | 0 | N/I |
| `services/ai/AiTranscriptRegistry.qml` | sim | 8.8 | 0 | 0 | N/I |
| `services/ai/AiVoiceService.qml` | não | 14.2 | 3 | 4 | N/I |
| `services/ai/AnthropicApiStrategy.qml` | não | 11.8 | 0 | 0 | N/I |
| `services/ai/ApiStrategy.qml` | não | 7.1 | 0 | 0 | N/I |
| `services/ai/GeminiApiStrategy.qml` | não | 13.1 | 0 | 0 | N/I |
| `services/ai/ModelCatalog.qml` | não | 24.4 | 0 | 0 | N/I |
| `services/ai/OllamaCatalog.qml` | sim | 20.5 | 2 | 2 | N/I |
| `services/ai/OpenAiCompatStrategy.qml` | não | 19.2 | 0 | 0 | N/I |
| `services/ai/OpenRouterModels.qml` | sim | 8.3 | 1 | 0 | N/I |
| `services/ai/blocks/AiAnnotationSourceButton.qml` | não | 1.3 | 0 | 0 | N/I |
| `services/ai/blocks/AiApiKeyManager.qml` | não | 15.3 | 0 | 0 | N/I |
| `services/ai/blocks/AiAttachmentTray.qml` | não | 15.0 | 0 | 0 | N/I |
| `services/ai/blocks/AiConfigDiffCard.qml` | não | 9.1 | 0 | 0 | N/I |
| `services/ai/blocks/AiFileAttachCard.qml` | não | 3.9 | 0 | 0 | N/I |
| `services/ai/blocks/AiFileResultCard.qml` | não | 4.3 | 0 | 0 | N/I |
| `services/ai/blocks/AiGmailResultCard.qml` | não | 3.0 | 0 | 0 | N/I |
| `services/ai/blocks/AiImagePreview.qml` | não | 2.0 | 0 | 0 | N/I |
| `services/ai/blocks/AiMediaControlCard.qml` | não | 3.7 | 0 | 0 | N/I |
| `services/ai/blocks/AiMessageCodeBlock.qml` | não | 12.3 | 2 | 0 | N/I |
| `services/ai/blocks/AiMessageControlButton.qml` | não | 0.8 | 0 | 0 | N/I |
| `services/ai/blocks/AiMessageTableBlock.qml` | não | 10.1 | 1 | 0 | N/I |
| `services/ai/blocks/AiMessageTextBlock.qml` | não | 8.3 | 1 | 0 | N/I |
| `services/ai/blocks/AiMessageThinkBlock.qml` | não | 8.6 | 2 | 0 | N/I |
| `services/ai/blocks/AiModelPickerPopover.qml` | não | 33.0 | 0 | 0 | N/I |
| `services/ai/blocks/AiNotesCard.qml` | não | 4.2 | 0 | 0 | N/I |
| `services/ai/blocks/AiOllamaModelsPage.qml` | não | 16.2 | 1 | 0 | N/I |
| `services/ai/blocks/AiOpenRouterModelsPage.qml` | não | 21.9 | 0 | 0 | N/I |
| `services/ai/blocks/AiRagResultCard.qml` | não | 2.6 | 0 | 0 | N/I |
| `services/ai/blocks/AiReminderCard.qml` | não | 4.4 | 0 | 0 | N/I |
| `services/ai/blocks/AiSearchQueryButton.qml` | não | 1.5 | 0 | 0 | N/I |
| `services/ai/blocks/AiSettingResultCard.qml` | não | 24.8 | 0 | 0 | N/I |
| `services/ai/blocks/AiSongIdentifyCard.qml` | não | 5.7 | 0 | 0 | N/I |
| `services/ai/blocks/AiSportsGameCard.qml` | não | 3.6 | 0 | 0 | N/I |
| `services/ai/blocks/AiSystemControlCard.qml` | não | 4.1 | 0 | 0 | N/I |
| `services/ai/blocks/AiTaskCard.qml` | não | 5.0 | 0 | 0 | N/I |
| `services/ai/blocks/AiTaskMutationCard.qml` | não | 7.0 | 0 | 0 | N/I |
| `services/ai/blocks/AiTaskResultCard.qml` | não | 2.6 | 0 | 0 | N/I |
| `services/ai/blocks/AiTimerCard.qml` | não | 3.9 | 0 | 0 | N/I |
| `services/ai/blocks/AiToolPermissionList.qml` | não | 9.3 | 0 | 0 | N/I |
| `services/ai/blocks/AiToolsPopover.qml` | não | 12.6 | 0 | 0 | N/I |
| `services/ai/blocks/AiTypingIndicator.qml` | não | 6.5 | 1 | 0 | N/I |
| `services/ai/blocks/AiWallpaperCard.qml` | não | 4.3 | 0 | 0 | N/I |
| `services/ai/blocks/AiWindowMoveCard.qml` | não | 3.7 | 0 | 0 | N/I |
| `services/ai/integrations/AiFilesIntegration.qml` | não | 5.0 | 0 | 0 | N/I |
| `services/ai/integrations/AiGmailIntegration.qml` | não | 6.4 | 0 | 1 | N/I |
| `services/ai/integrations/AiMediaIntegration.qml` | não | 4.5 | 0 | 0 | N/I |
| `services/ai/integrations/AiNotesIntegration.qml` | não | 3.9 | 0 | 0 | N/I |
| `services/ai/integrations/AiRagIntegration.qml` | não | 3.0 | 0 | 0 | N/I |
| `services/ai/integrations/AiSettingsIntegration.qml` | não | 23.1 | 0 | 2 | N/I |
| `services/ai/integrations/AiShellContextIntegration.qml` | não | 5.3 | 0 | 0 | N/I |
| `services/ai/integrations/AiSportsIntegration.qml` | não | 15.8 | 0 | 0 | N/I |
| `services/ai/integrations/AiSystemControlsIntegration.qml` | não | 5.4 | 0 | 0 | N/I |
| `services/ai/integrations/AiSystemIntegration.qml` | não | 6.2 | 0 | 0 | N/I |
| `services/ai/integrations/AiTasksIntegration.qml` | não | 14.7 | 0 | 0 | N/I |
| `services/ai/integrations/AiThemeIntegration.qml` | não | 2.9 | 0 | 0 | N/I |
| `services/ai/integrations/AiTimeIntegration.qml` | não | 29.6 | 0 | 0 | N/I |
| `services/ai/integrations/AiWindowsIntegration.qml` | não | 2.8 | 0 | 0 | N/I |
| `services/modes/ModeActions.qml` | não | 57.4 | 0 | 0 | N/I |
| `services/modes/ModeCondition.qml` | não | 1.3 | 1 | 0 | N/I |
| `services/modes/ModeWatcher.qml` | não | 7.3 | 2 | 0 | N/I |
| `services/modes/conditions/AlarmCondition.qml` | não | 0.3 | 0 | 0 | N/I |
| `services/modes/conditions/AppCondition.qml` | não | 1.5 | 0 | 0 | N/I |
| `services/modes/conditions/AudioDeviceCondition.qml` | não | 1.1 | 0 | 0 | N/I |
| `services/modes/conditions/BatteryCondition.qml` | não | 1.5 | 0 | 0 | N/I |
| `services/modes/conditions/BluetoothCondition.qml` | não | 0.8 | 0 | 0 | N/I |
| `services/modes/conditions/CalendarCondition.qml` | não | 1.1 | 0 | 0 | N/I |
| `services/modes/conditions/DeviceInUseCondition.qml` | não | 1.5 | 0 | 0 | N/I |
| `services/modes/conditions/DiscordVoiceCondition.qml` | não | 0.3 | 0 | 0 | N/I |
| `services/modes/conditions/FullscreenCondition.qml` | não | 0.4 | 0 | 0 | N/I |
| `services/modes/conditions/GameCondition.qml` | não | 1.0 | 0 | 0 | N/I |
| `services/modes/conditions/IdleCondition.qml` | não | 0.7 | 0 | 0 | N/I |
| `services/modes/conditions/KeyboardLayoutCondition.qml` | não | 0.4 | 0 | 0 | N/I |
| `services/modes/conditions/LidCondition.qml` | não | 1.1 | 1 | 1 | N/I |
| `services/modes/conditions/LockedCondition.qml` | não | 0.3 | 0 | 0 | N/I |
| `services/modes/conditions/MediaCondition.qml` | não | 1.6 | 0 | 0 | N/I |
| `services/modes/conditions/ModeActiveCondition.qml` | não | 0.4 | 0 | 0 | N/I |
| `services/modes/conditions/MonitorsCondition.qml` | não | 1.0 | 0 | 0 | N/I |
| `services/modes/conditions/NotificationCondition.qml` | não | 1.2 | 0 | 0 | N/I |
| `services/modes/conditions/PhoneCondition.qml` | não | 1.2 | 0 | 0 | N/I |
| `services/modes/conditions/PomodoroCondition.qml` | não | 0.6 | 0 | 0 | N/I |
| `services/modes/conditions/PomodoroLapCondition.qml` | não | 0.7 | 0 | 0 | N/I |
| `services/modes/conditions/ResourceCondition.qml` | não | 1.9 | 0 | 0 | N/I |
| `services/modes/conditions/ScheduleCondition.qml` | não | 1.1 | 0 | 0 | N/I |
| `services/modes/conditions/ShortcutCondition.qml` | não | 0.7 | 0 | 0 | N/I |
| `services/modes/conditions/UpdatesCondition.qml` | não | 0.5 | 0 | 0 | N/I |
| `services/modes/conditions/VpnCondition.qml` | não | 0.8 | 0 | 0 | N/I |
| `services/modes/conditions/WeatherCondition.qml` | não | 1.4 | 0 | 0 | N/I |
| `services/modes/conditions/WifiCondition.qml` | não | 1.1 | 0 | 0 | N/I |
| `services/modes/conditions/WorkspaceCondition.qml` | não | 1.3 | 0 | 0 | N/I |
| `services/network/WifiAccessPoint.qml` | não | 2.8 | 0 | 0 | N/I |
| `services/notes/NotesDocumentFile.qml` | não | 7.0 | 3 | 0 | N/I |
| `services/notes/NotesLinkPreview.qml` | sim | 5.3 | 1 | 1 | N/I |
| `services/notes/NotesRevisions.qml` | sim | 7.7 | 0 | 3 | N/I |
| `services/notes/NotesStore.qml` | não | 16.4 | 1 | 1 | N/I |
| `services/notes/NotesSync.qml` | sim | 5.2 | 0 | 2 | N/I |
