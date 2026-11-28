# Gallery — Standalone Shell App

Standalone Material 3 Expressive photo & video gallery integrated into the `ii` shell. Runs in its own `qs -p` process so closing the window returns **100% of its memory** to the OS (`0 MB` retained in the shell).

## Features

- **Home Timeline:** Chronological vertical day-grouped timeline (`ListView` virtualized) with editorial M3E header, live item/photo/video stats, filter chips (`All`, `Photos`, `Videos`, `Favorites`), instant search (`/`), and customizable grid size (`P` = 7, `M` = 5, `G` = 3) and source folders (defaults to `~/Pictures` and `~/Downloads`, including subfolders).
- **Albums:** Bento-style M3E folder overview (hero 3-photo mosaic card, tall secondary card with photo strip, subfolder cards, dashed add-folder card) + Album detail view with breadcrumbs, subfolder chips, and virtualized grid.
- **Phone Gallery (`ii tools`):** Live integration with the shell's `PhoneGalleryService` over IPC (`qs -c ii ipc call phoneGallery ...`) without booting `IiLinkService` inside the Gallery process. Browse phone albums, view full-resolution photos, play mounted videos, and save items directly to `~/Pictures/Phone`.
- **Unified Media Viewer (lazy-loaded):**
  - **Images:** Wheel zoom (100%–400%), double-click zoom, drag pan, 90° rotation, favorite, copy path, details side sheet, move to trash.
  - **Videos:** `QtMultimedia` `MediaPlayer` + `AudioOutput` with autoplay, M3E wavy progress bar (`WavyLine`) with click/drag seek, ±10s skip, volume slider & mute, playback speed (`0.5×`–`2×`), loop, and fullscreen.
  - **Shell & Phone Actions:** 1-click **Set as desktop wallpaper**, **Set as lockscreen wallpaper** (in Details sheet), **Set as profile avatar**, **Send to phone** (PC → Phone via `ii tools`), and **Save to PC** (Phone → PC).
- **Live Theme:** Uses `apps/modules/common/Appearance.qml` (`colors.json` watcher), reacting immediately to matugen wallpaper/theme changes.
- **App Settings:** Stored in `${Directories.appsState}/gallery.json` (never in the shell's `config.json`).

## How it runs

```bash
# Start directly or reuse via IPC
qs -p ~/.config/quickshell/ii/apps/gallery.qml
qs -p ~/.config/quickshell/ii/apps/gallery.qml ipc call gallery open home
qs -p ~/.config/quickshell/ii/apps/gallery.qml ipc call gallery open albums
qs -p ~/.config/quickshell/ii/apps/gallery.qml ipc call gallery open phone
qs -p ~/.config/quickshell/ii/apps/gallery.qml ipc call gallery open settings
qs -p ~/.config/quickshell/ii/apps/gallery.qml ipc call gallery openPath /path/to/photo.jpg
qs -p ~/.config/quickshell/ii/apps/gallery.qml ipc call gallery quit

# Or via the running shell's IPC (respects Floating/Tiling setting and reuses an open window)
qs -c ii ipc call gallery open
qs -c ii ipc call gallery openTab phone
qs -c ii ipc call gallery openPath /path/to/video.mp4
qs -c ii ipc call gallery quit
```

When launched from the shell (`GlobalStates.openGalleryApp()`), it first tries to focus/navigate an already-running `apps/gallery.qml` instance via IPC. Otherwise it spawns a detached `qs -p` process:
- **Floating (default):** `hyprctl dispatch 'hl.dsp.exec_cmd("[float; center; size 1240 780] ...")'` (with classic `hyprctl dispatch exec` fallback).
- **Tiling:** launched directly as a normal tiled window.

## Architecture & isolation

| File | Role |
|---|---|
| `apps/gallery.qml` | Entrypoint `ApplicationWindow`, single-instance `IpcHandler` (`gallery`), lazy `Loader`s for secondary views and viewer. |
| `apps/gallery/GalleryStore.qml` | Central state, `${Directories.appsState}/gallery.json` persistence, one-shot scanner runner, throttled video thumbnail queue, wallpaper/avatar/trash actions. |
| `apps/gallery/PhoneGalleryBridge.qml` | Slim IPC bridge to the shell's `PhoneGalleryService` (`qs -c ii ipc call phoneGallery ...`); polls only while Phone tab or a transfer is active. |
| `apps/gallery/GalleryAppBar.qml` | M3E top bar with morphing brand mark, search field (`/`), phone quick-jump pill, refresh, maximize/close. |
| `apps/gallery/GalleryNavBar.qml` | Floating M3E bottom navigation pill with sliding indicator and clean inline badges. |
| `apps/gallery/GalleryHomePage.qml` | Editorial header + virtualized day-grouped `ListView` timeline. |
| `apps/gallery/GalleryAlbumsPage.qml` | Bento-style albums overview + breadcrumb album detail `GridView`. |
| `apps/gallery/GalleryPhonePage.qml` | `ii tools` Phone Gallery page with offline/setup guide, album strip, and virtualized day-grouped grid. |
| `apps/gallery/GallerySettingsPage.qml` | Grid size (`P`/`M`/`G`), sort order, playback switches, timeline folder toggles, and library breakdown. |
| `apps/gallery/GalleryAddFolderSheet.qml` | Right-hand side sheet with suggested XDG folders, custom path validation, and native folder picker. |
| `apps/gallery/GalleryMediaTile.qml` | Lightweight `ClippingRectangle` tile (`cache: false`, bounded `sourceSize`, zero `layer.enabled`/`OpacityMask`). |
| `apps/gallery/GalleryViewer.qml` | Unified photo & video viewer with `QtMultimedia`, `WavyLine` seek bar, zoom/pan/rotate, details sheet, filmstrip, and shell/phone actions. |
| `scripts/gallery/scan_gallery.py` | Zero-daemon Python helper for fast media scanning (auto-skips `.git`/code repos/icon packs), on-demand `ffmpeg`/`ffprobe` video thumbnails, `gio trash`, and folder picker. |

## Shell integration (no `.desktop` file)

- **Search / Launcher:** Registered in `modules/common/ShellActionRegistry.qml` (`id: "gallery"`, icon `photo_library`, listed in `appIds`).
- **Config:** `Config.options.galleryApp` (`enable: true`, `openFloating: true`) in `modules/common/Config.qml`.
- **Settings → Apps & Overlays:** `AppCard` in `modules/settings/configs/OverlaysConfig.qml` with enable switch, **Floating / Tiling** chip, **Set shortcut** chip, and **Open** button.
- **Settings → Hyprland → Shortcuts:** 1-click toggle in `modules/settings/configs/hyprland/ShortcutsTab.qml` to bind/unbind `Super + Alt + G` → `quickshell:galleryOpen` in `custom/keybinds.lua`.
- **Shell IPC bridges:** `GlobalStates.qml` (`gallery` target: `open`, `openTab`, `openPath`, `quit`, `setAvatar`), `services/PhoneGalleryService.qml` (`phoneGallery` target), and `services/Wallpapers.qml` (`wallpapers` target).

## Benchmark (PSS / Pss_Anon / Children)

Measured on a real library of **2,688 items** (`774` in `~/Pictures`, `1,914` in `~/Downloads`) with `ii tools` connected (`S23 de Pedro`, `8,236` phone items):

| State | PSS | Pss_Anon | Child processes |
|---|---|---|---|
| Idle Home (2,688 items) | 180.3 MB | 124.6 MB | 0 |
| Albums Overview (49 folders) | 243.9 MB | 183.4 MB | 0 |
| Phone Gallery (`ii tools`) | 247.6 MB | 184.6 MB | 0 |
| Settings | 249.0 MB | 185.4 MB | 0 |
| Video Viewer (playing H.264 + audio) | 429.9 MB | 250.4 MB | 0 |
| After `ipc call gallery quit` | **0 MB** | **0 MB** | **0** |

## Known limitations

- **Wayland `app_id` / Hyprland `class`:** Like other `qs -p` apps, Quickshell uses `class = org.quickshell` and `title = "Gallery"`. Custom Hyprland rules should match `class:^(org\.quickshell)$, title:^(Gallery)$`.
- **Repository & icon-pack pruning:** `scan_gallery.py` automatically skips subdirectories containing `.git`, `index.theme`, `package.json`, `Cargo.toml`, `pyproject.toml`, `.nomedia`, etc., and caps scans at 3,000 newest items to prevent developer directories or icon packs in `~/Downloads` from flooding the gallery and JS heap.
- **HEIC / unusual formats:** Decoding depends on installed Qt image format plugins (`qt6-imageformats` / `kimageformats`).
