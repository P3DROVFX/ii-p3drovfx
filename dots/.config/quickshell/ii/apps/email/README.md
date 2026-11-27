# Email — Standalone Shell App

Standalone Gmail client ported from the shell's Cheatsheet Email tab to the isolated `apps/` runtime. It keeps the exact same Material 3 Expressive design, animations, and feature set, while running in its own `qs -p` process so closing the window returns **100% of its memory** to the OS.

## How it runs

```bash
# Start directly (or reuse via IPC)
qs -p ~/.config/quickshell/ii/apps/email.qml
qs -p ~/.config/quickshell/ii/apps/email.qml ipc call email open inbox
qs -p ~/.config/quickshell/ii/apps/email.qml ipc call email open compose
qs -p ~/.config/quickshell/ii/apps/email.qml ipc call email compose "dest@example.com" "Subject"
qs -p ~/.config/quickshell/ii/apps/email.qml ipc call email quit

# Or via the running shell's IPC (respects Floating/Tiling setting and reuses an open window)
qs -c ii ipc call email open
qs -c ii ipc call email openTab compose
qs -c ii ipc call email quit
```

When launched from the shell (`GlobalStates.openEmailApp()`), it first attempts to focus/navigate an already-running `apps/email.qml` instance via IPC. If none is running, it spawns a detached `qs -p` process:
- **Floating (default):** launched via `hyprctl dispatch 'hl.dsp.exec_cmd("[float; center] ...")'` (with classic `hyprctl dispatch exec` fallback) at the Cheatsheet's screen-relative size (`~90% × 80%`, capped at `1820×960`).
- **Tiling:** launched directly as a normal tiled window.

## Architecture & isolation

Because Quickshell treats `apps/` as the `qs` root for `qs -p apps/email.qml`, the app never loads the shell's full singletons or background daemons:

| File | Role |
|---|---|
| `apps/email.qml` | Entrypoint `ApplicationWindow`, IPC handler (`email`), layout host and loaders. |
| `apps/email/*.qml`, `EmailIconRules.js` | Full UI: `EmailSidebar`, `EmailInbox`, `EmailContent`, `EmailStackedContent`, `EmailCompose`, `EmailSettings`, `EmailAuth`, `EmailIcon`, `EmailNavButton`, `SelectableEmailText`. |
| `apps/services/EmailService.qml` | Slim `EmailService` for the standalone process (no `GlobalStates`/`Network` shell bindings; live refresh runs only while the window is open). |
| `apps/services/KeyringStorage.qml` | Slim `secret-tool` wrapper using the same `illogical-impulse` keyring schema as the shell. |
| `apps/services/CalendarService.qml` | IPC bridge forwarding `.ics` attachment imports to the shell's `CalendarService` (`qs -c ii ipc call calendar importIcs ...`) without booting `khal`/`vdirsyncer` in the app. |

### Shared state with the shell

The shell keeps its own `services/EmailService.qml` active **only** for shell integrations that run independently of the app window (desktop widgets `EmailWidget` / `EmailWidget2x1`, `AtAGlance`, `GmailPanel`, `AiGmailIntegration`, `GmailCalendarImport`):

- **Accounts & OAuth tokens:** stored in the same `secret-tool` keyring entry (`gmail_accounts`). After browser sign-in, `scripts/email/oauth_server.py` sends `gmail onAuthComplete` over IPC to **both** `apps/email.qml` and the main shell (`qs -c ii`).
- **App & inbox preferences:** stored in the same `QtCore.Settings` file (`~/.local/state/quickshell/user/email-settings.ini`, category `EmailService`), including drafts, enabled tabs/labels, compact mode, thread stacking, and refresh interval.
- **Live theme & shell config:** `apps/modules/common/Appearance.qml` watches `colors.json` (matugen) and `apps/modules/common/Config.qml` reads a minimal read-only slice of `config.json`.

## Shell integration (no `.desktop` file)

Email is registered as a first-class shell app without generating any `.desktop` entry:

- **Search / Launcher:** registered in `modules/common/ShellActionRegistry.qml` (`id: "email"`, included in `appIds`), appearing in the **Apps** section when searching for `email`, `gmail`, `mail`, or `inbox`.
- **Settings → Apps & Overlays:** has its own `AppCard` (`modules/settings/configs/OverlaysConfig.qml`) with enable switch (`Config.options.emailApp.enable`), **Floating / Tiling** chip (`Config.options.emailApp.openFloating`), live shortcut display, and **Open** button.
- **Settings → Hyprland → Shortcuts:** includes a 1-click toggle to bind/unbind `Super + Alt + M` to the shell's `GlobalShortcut` (`quickshell:emailOpen`), staged into `~/.config/hypr/custom/keybinds.lua` via `HyprlandBinds`.
- **Desktop widgets & Overview:** clicking a message or the compose button in `EmailWidget` / `EmailWidget2x1` or `GmailPanel` opens the standalone Email app directly on the relevant tab.

## Known limitations

- **Wayland `app_id` / Hyprland `class`:** Quickshell sets `class = org.quickshell` for all `qs -p` windows (`title = "Email"`). Without a `.desktop` file, the dock/taskbar cannot assign a custom system icon or pin it via `pinnedApps`. Any custom Hyprland rules should match `class:^(org\.quickshell)$, title:^(Email)$`.
- **DesktopEntries-only grids:** views that strictly enumerate `DesktopEntries.applications` (such as `AppGridWidget`) do not list shell apps.
- **Memory footprint:** while open, PSS is ~155 MB (~93 MB anon), split between the Quickshell/Qt6 baseline (~80–93 MB) and the inbox list's `Repeater` + per-card `layer.enabled` / `layer.samples: 8` `OpacityMask` buffers. Closing the window releases 100% of it back to the OS.
