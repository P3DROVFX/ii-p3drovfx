# Calendar — Standalone Shell App

Standalone Calendar app ported from the shell's Cheatsheet Timetable tab to the isolated `apps/` runtime. It preserves the exact Material 3 Expressive design, views (Day, 3-day, Week, Month), event sidebar, pickers, animations, keyboard shortcuts, and in-app settings, while running in its own `qs -p` process so closing the window returns **100% of its memory** to the OS.

## How it runs

```bash
# Start directly (or reuse via IPC)
qs -p ~/.config/quickshell/ii/apps/calendar.qml
qs -p ~/.config/quickshell/ii/apps/calendar.qml ipc call calendar open week
qs -p ~/.config/quickshell/ii/apps/calendar.qml ipc call calendar open month
qs -p ~/.config/quickshell/ii/apps/calendar.qml ipc call calendar openDate 2026-12-25
qs -p ~/.config/quickshell/ii/apps/calendar.qml ipc call calendar quit

# Or via the running shell's IPC (respects Floating/Tiling setting and reuses an open window)
qs -c ii ipc call calendar open
qs -c ii ipc call calendar openMode week
qs -c ii ipc call calendar openDate 2026-12-25
qs -c ii ipc call calendar quit
```

When launched from the shell (`GlobalStates.openCalendarApp(dateStr, mode)`), it first attempts to focus/navigate an already-running `apps/calendar.qml` instance via IPC. If none is running, it spawns a detached `qs -p` process:
- **Floating (default):** launched via `hyprctl dispatch 'hl.dsp.exec_cmd("[float; center] ...")'` (with classic `hyprctl dispatch exec` fallback) at the Cheatsheet's screen-relative size (`~90% × 80%`, capped at `1820×960`).
- **Tiling:** launched directly as a normal tiled window.

## Architecture & isolation

Because Quickshell treats `apps/` as the `qs` root for `qs -p apps/calendar.qml`, the app never loads the shell's full singletons or background daemons:

| File | Role |
|---|---|
| `apps/calendar.qml` | Entrypoint `ApplicationWindow`, IPC handler (`calendar`), top bar (`TimetableViewSwitch` + `AppSettingsButton`), `AppSettingsHost`, Google reauth banner, and depth-animated view switcher. |
| `apps/calendar/*.qml`, `*.js` | Full Calendar UI ported verbatim from `modules/ii/cheatsheet/timetable/`: `WeekView`, `MonthView`, `EventSidebar`, `MonthDayCell`, `MonthUpcomingPanel`, `DatePickerPopup`, `TimePickerPopup`, `TimetableViewSwitch`, `TimetableHeader`, `TimetableGesture*`, `EventBlock`, `DayBriefingCard`, `EventNotesStore`, etc. |
| `apps/calendar/settings/TimetableSettings.qml`, `TimetableStatusCard.qml` | In-app settings sheet (display, notifications, Google colors, ICS/Outlook sources, `khal` setup guide). Mutations persist through the shell via `Config.setShellOption(...)` → `qs -c ii ipc call calendar setConfig`. |
| `apps/services/CalendarService.qml` | Lazy standalone `CalendarService` (`khal` + `ics.py` + `vdirsyncer`). Stays completely dormant until `activate()` is called by `apps/calendar.qml` so other apps in `apps/` (such as `email.qml`) pay **0 RAM / 0 processes**; notifies `qs -c ii ipc call calendar reload` after edits. |
| `apps/modules/common/Persistent.qml` | Slim persistence stand-in storing Calendar UI state (`timetableView`, `timetableShowUpcoming`, `timetableMonthDensity`, `timetableCollapseRecurring`, `timetableSlotHeight`, etc.) in `~/.local/state/quickshell/user/apps/calendar.json` without touching the shell's `states.json`. |
| `apps/services/{DateTime,Todo,RemindersService,Holidays,GoogleCalendarService,AtAGlanceService,BirthdaysService,PhoneContactsService,Weather,AlarmService,TimerService,NotesService,Ai,SportsService,CalendarIcsFileImport,CalendarSubscriptions,Outlook*}.qml` | Slim file-backed or IPC-bridged stand-ins with zero background daemons or shell-service fan-out. |

### Shared state with the shell

The shell keeps its own `services/CalendarService.qml` active **only** for shell integrations that run independently of the app window (desktop widgets, `AtAGlanceService`, `CalendarNotifier`, `CalendarEventRows`, `Clock`, AI integrations):

- **Events & sync:** both read/write the same `khal` calendars and `vdirsyncer` config. After mutations in the standalone app, `apps/services/CalendarService.qml` calls `qs -c ii ipc call calendar reload` so the shell refreshes immediately.
- **Google reauthorization:** `scripts/calendar/vdirsyncer_reauth.py` sends `calendar onGoogleAuthComplete` over IPC to **both** the main shell (`qs -c ii`) and `apps/calendar.qml`.
- **UI state:** stored in `~/.local/state/quickshell/user/apps/calendar.json`.
- **Live theme & shell config:** `apps/modules/common/Appearance.qml` watches `colors.json` (matugen) and `apps/modules/common/Config.qml` reads a minimal read-only slice of `config.json`.

## Shell integration (no `.desktop` file)

Calendar is registered as a first-class shell app without generating any `.desktop` entry:

- **Search / Launcher:** registered in `modules/common/ShellActionRegistry.qml` (`id: "calendar"`, included in `appIds`), appearing in the **Apps** section when searching for `calendar`, `calendário`, `timetable`, `agenda`, or `events`.
- **Settings → Apps & Overlays:** has its own `AppCard` (`modules/settings/configs/OverlaysConfig.qml`) with enable switch (`Config.options.calendarApp.enable`), **Floating / Tiling** chip (`Config.options.calendarApp.openFloating`), live shortcut display, **Set shortcut** link to Hyprland Shortcuts, and **Open** button.
- **Settings → Hyprland → Shortcuts:** includes a 1-click toggle to bind/unbind `Super + Alt + C` to the shell's `GlobalShortcut` (`quickshell:calendarOpen`), staged into `~/.config/hypr/custom/keybinds.lua` via `HyprlandBinds`.
- **Widgets & notifications:** `GlobalStates.openTimetableAt(...)`, `GlobalStates.openCheatsheet("timetable")`, `CalendarEventRows`, `CalendarNotifier`, `AtAGlanceService`, and Clock strips now open the standalone Calendar app directly.

## Memory measurements (2026-11-27)

Measured via `/proc/<pid>/smaps_rollup` and `pgrep -P <pid>` in a floating `1728×864` window:

| State | PSS | Pss_Anon | RSS | Child processes |
|---|---|---|---|---|
| Initial (Month view) | 168.1 MB | 115.7 MB | 306.5 MB | 0 steady (1 transient `khal`/`vdirsyncer` during sync) |
| After IPC `open week` | 208.6 MB | 155.7 MB | 349.0 MB | 0 |
| After IPC `open day` | 209.4 MB | 156.4 MB | 349.7 MB | 0 |
| After IPC `openDate 2026-12-25` | 223.8 MB | 168.1 MB | 375.5 MB | 0 steady (1 transient during range fetch) |
| After closing / IPC `quit` | **0 MB in shell** | **0 MB** | — | **0** |

## Known limitations

- **Wayland `app_id` / Hyprland `class`:** Quickshell sets `class = org.quickshell` for all `qs -p` windows (`title = "Calendar"`). Without a `.desktop` file, the dock/taskbar cannot assign a custom system icon or pin it via `pinnedApps`. Custom Hyprland rules should match `class:^(org\.quickshell)$, title:^(Calendar)$`.
- **Phone calendars (`ii tools` / `IiLinkService`) & live ESPN sports:** intentionally excluded from the standalone app process so it never boots `IiLinkService` (`avahi-browse`) or background ESPN polling. Phone calendars and sports remain active in the shell's own services.
- **Weather forecast badges in header:** `apps/services/Weather.qml` is a lightweight no-polling stand-in, so live weather icons in `TimetableHeader` are not fetched inside the standalone Calendar process.
- **Cross-app actions (Alarms, Timers, Notes, AI):** creating an alarm, countdown, note, or AI prompt from the EventSidebar forwards via IPC to open the corresponding shell panel (`clock`, `notes`, `sidebarLeft`).
