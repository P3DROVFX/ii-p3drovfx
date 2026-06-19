# [ Quickshell/II ]

A premium Material 3 / Material You dotfiles for Hyprland, powered by Quickshell.

# System Preview

<img width="1947" height="3536" alt="Frame 145(1)" src="https://github.com/user-attachments/assets/33e9cc10-d09f-446d-b83c-f6f335f89988" />


## Overview

This repository is a heavily customized fork of **[ii-vynx](https://github.com/vaguesyntax/ii-vynx)**, which itself is based on **[illogical-impulse](https://github.com/end-4/dots-hyprland)**. **This is my personal customization, it's not focused on performance or stability, if you are using it, expect a lot of bugs**, if you find one, please create an issue or report to me in my discord: p3drovfx. 

It aims to provide a state-of-the-art Linux desktop experience by strictly adhering to **Material 3 (Material You)** design principles, featuring dynamic theming via Matugen and a highly modular architecture built on **Quickshell**.

> [!NOTE]
> This repository is a work in progress. Some modules, like the Gmail client, require manual setup of API keys.

## Features

- **📧 Gmail Client Integration**: A premium, material-designed Gmail client integrated directly into the cheatsheet with threaded view, smart unread counting, and quick actions.
  *For a full setup guide, backend env parameters, and API configuration, check out the [Gmail Client Setup & Implementation Guide](.github/guides/gmail_client.md).*

- **🎨 Intelligent Color Picker**: Capture colors from your screen and instantly generate Material You palettes. Real-time visual feedback across different M3 layers.
  *For state configuration, bar integration, and persistent backend script bindings, check out the [Advanced Color Picker Setup & Implementation Guide](.github/guides/color_picker.md).*

- **🔋 Redesigned System Dialogs**: Brand new, premium M3-style dialogs for Battery, Bluetooth, and Wi-Fi with smooth transitions and detailed info.
- **⌨️ Keyboard Management**: Completely redesigned keyboard layout widget for the bar with instant switching and dedicated M3-styled popup.
- **🔵 Bluetooth Management**: Integrated device management within the shell. Easily connect, disconnect, and monitor battery levels of peripherals.
  *For the reactive state watcher, scanner background resource cleanup, C++ sync reactivity, and Soundcore audio controls, check out the [Bluetooth Panel Upgrades & Implementation Guide](.github/guides/overview_features.md).*
- **📅 Cheatsheet & Timetable**: Create events directly from the timetable and sync with local calendars (via `khal`) for a full agenda view.
- **📜 Cheatsheet Commands**: Manage your personal command library with dynamic tags, search, and JSON import/export support.
  *For UI card structure, commands tag filtering, and JSON import/export setup, check out the [Cheatsheet Commands Setup & Implementation Guide](.github/guides/cheatsheet_commands.md).*
- **📱 Paged Android Quick Toggles**: Multi-page horizontally swipeable quick toggles mirroring the Android experience.
  *For horizontal paging structures, adaptive height calculations, and custom edit layouts, check out the [Paged Android Quick Toggles Implementation Guide](.github/guides/quick_toggles.md).*
- **🔍 Revamped Search Launcher (Power-User)**: This repository includes a completely revamped search launcher widget (`Super + D` or `Super + Space`) designed for power-users.
  *For a full setup guide, code diffs, and detailed configuration parameters, check out the [Search Upgrades & Implementation Guide](.github/guides/overview_features.md).*

- **🎥 OBS Integration**: Start/stop recordings directly from the bar with real-time status.
- **✅ TickTick Sync**: Full cloud integration for task management synced across devices.
- **✨ Micro-animations**: Refined transitions across the entire system.

## Installation

1. Clone this repository with submodules:
```bash
git clone --recurse-submodules https://github.com/P3DROVFX/ii-vynx.git
```

2. Run the setup script and follow the instructions:
```bash
./setup-ii-vynx.sh
```

## Documentation

Please refer to the **[wiki](https://github.com/vaguesyntax/ii-vynx/wiki)** for detailed component descriptions.

## Credits

- **[end-4](https://github.com/end-4):** Creator of illogical-impulse.
- **[vaguesyntax](https://github.com/vaguesyntax):** Creator of ii-vynx.
- **[pc-trade](https://github.com/pctrade):** Some design and features inspo.
- **[so-do-i-look-like-him](https://github.com/so-do-i-look-like-him):** Instalation bug fixes.
- **[asteriau](https://github.com/asteriau):** Cheatsheet keybinds animations.
- **[gowall](https://github.com/Achno/gowall):** Dyanmic icons theme system.
- **[hyprmon](https://github.com/erans/hyprmon):** Monitor managment in settings.
- **[Quickshell](https://quickshell.org/):** Widget system.
- **[Hyprland](https://hypr.land/):** Compositor.

---

<div align="center">
    <p><b>If you like this project, consider giving it a star! ⭐</b></p>
</div>
