# [ Quickshell/II ]

A premium Material 3 / Material You dotfiles for Hyprland, powered by Quickshell.

# System Preview

<img width="1947" height="3231" alt="Frame 145" src="https://github.com/user-attachments/assets/61327556-d985-44b2-b31b-2dad51849984" />

## Overview

This repository is a heavily customized fork of **[ii-vynx](https://github.com/vaguesyntax/ii-vynx)**, which itself is based on the legendary **[illogical-impulse](https://github.com/end-4/dots-hyprland)**. 

It aims to provide a state-of-the-art Linux desktop experience by strictly adhering to **Material 3 (Material You)** design principles, featuring dynamic theming via Matugen and a highly modular architecture built on **Quickshell**.

> [!NOTE]
> This repository is a work in progress. Some modules, like the Gmail client, require manual setup of API keys.

## Features

- **📧 Gmail Client Integration**: A premium, material-designed Gmail client integrated directly into the cheatsheet with threaded view, smart unread counting, and quick actions.
  <details>
    <summary><b>📧 Gmail Client Full Setup & Implementation</b></summary>

    ### ✨ Features
    - **Threaded Conversations**: Automatically groups related emails into threads.
    - **Smart Unread Counting**: Displays unread badges on thread stacks and individual messages.
    - **Semantic Timestamps**: Human-readable date formatting (e.g., "Just now", "2h ago").
    - **Rich Content Viewer**: Supports HTML rendering, quoted text collapsing, and link actions.
    - **Smart Data Extraction**: Automatically detects meeting links (Meet, Zoom, Teams) and OTP codes.

    ### 📂 Installation Guide
    1. **Service Layer**: Copy `EmailService.qml` to `services/`.
    2. **Backend Scripts**: Copy the `email/` folder to `scripts/`.
    3. **UI Components**: Copy the `email/` folder to `modules/ii/cheatsheet/`.
    4. **Main View**: Ensure `CheatsheetEmail.qml` is in `modules/ii/cheatsheet/`.
    5. **Environment**: Create a `.env` file in the root.

    ### 🔧 Core Integration Changes
    #### 1. `modules/common/Config.qml`
    ```qml
    // inside options.cheatsheet
    property bool enableGmail: false
    ```
    #### 2. `modules/ii/cheatsheet/Cheatsheet.qml`
    ```qml
    if (Config.options.cheatsheet.enableGmail) {
        list.push({ "icon": "mail", "name": Translation.tr("Email") });
    }
    ```
    #### 3. `modules/settings/InterfaceConfig.qml`
    ```qml
    SettingToggle {
        text: "Enable Gmail Client"
        checked: Config.options.cheatsheet.enableGmail
        onCheckedChanged: Config.options.cheatsheet.enableGmail = checked
    }
    ```

    ### 🔑 How to get Google Cloud Credentials
    1. Create a project in [Google Cloud Console](https://console.cloud.google.com/).
    2. Enable **Gmail API**.
    3. Configure **OAuth Consent Screen** (External, add scope `.../auth/gmail.modify`, add your email as Test User).
    4. Create **OAuth 2.0 Client ID** (Desktop App).
    5. Copy Client ID and Secret to `.env`.

    ### 🚀 Setup Instructions
    1. **Env**: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` in `.env` (shared across Gmail, Google Tasks, and Google Drive).
    2. **Deps**: `pip install google-auth google-auth-oauthlib google-api-python-client python-dotenv`.
    3. **Auth**: Run shell -> Email Tab / Settings -> "Connect Google Tasks" / "Connect Account".
  </details>

- **🔍 Revamped Search Launcher (Power-User)**: This repository includes a completely revamped search launcher widget (`Super + D` or `Super + Space`) designed for power-users.
  <details>
    <summary><b>🔍 Search Launcher Features & Setup Guide</b></summary>

    ### ✨ Features
    - **Prefix-less Math & Unit Converter**: Real-time evaluation of mathematical expressions (including functions like `sqrt`, `sin`, `cos`) and units/currency conversions (e.g. `120 usd to eur` or `50c to f`) right inside the preview results block without needing a prefix.
    - **Secure System Controls**: Instantly lock the screen (`lock`), suspend the PC (`suspend`), reboot (`reboot`), shutdown (`poweroff`), or restart the Quickshell shell (`restart`) directly from the search bar.
    - **Two-Step Confirmation Safeguard**: Clicking or hitting Enter on critical system commands dynamically prompts for confirmation inside the launcher (e.g., `Reboot PC (Are you sure?)`), keeping the launcher open and requiring a second Enter/click to execute, while cancelling automatically if you type or move away.

    ### 📖 Setup Guide
    For a full setup guide, code diffs, and detailed configuration parameters, check out the [Search Upgrades & Implementation Guide](modules/ii/overview/IMPLEMENTATION_GUIDE.md).
  </details>

- **🎨 Intelligent Color Picker**: Capture colors from your screen and instantly generate Material You palettes. Real-time visual feedback across different M3 layers.
  <details>
    <summary><b>🎨 Advanced Color Picker Implementation</b></summary>

    ### 1. Global State Management (`modules/common/GlobalStates.qml`)
    ```qml
    property bool colorPickerPopupOpen: false
    property string colorPickerPopupColor: ""

    function pickColor(hex) {
        if (hex && hex.startsWith("#")) {
            root.colorPickerPopupColor = hex;
            root.colorPickerPopupOpen = false;
            Qt.callLater(() => { root.colorPickerPopupOpen = true; });
        }
    }

    function launchColorPicker() {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "colorPickerLaunch", "trigger"]);
    }

    IpcHandler {
        target: "pickColor"
        function handle(hex: string): void { root.pickColor(hex); }
    }
    ```

    ### 2. Bar Integration (`modules/ii/bar/UtilButtons.qml`)
    ```qml
    Loader {
        active: Config.options.bar.utilButtons.showColorPicker
        sourceComponent: CircleUtilButton {
            onClicked: GlobalStates.launchColorPicker()
            MaterialSymbol { 
                text: "colorize"
                iconSize: Appearance.font.pixelSize.large 
                color: Appearance.colors.colOnLayer2
            }
        }
    }
    ```

    ### 3. Hyprland Keybind (`hyprland/keybinds.conf`)
    ```ini
    bindd = Super+Shift, C, Color picker, global, quickshell:colorPickerLaunch
    ```

    ### 4. Shell Registration (`panelFamilies/IllogicalImpulseFamily.qml`)
    ```qml
    import qs.modules.ii.colorPickerPopup
    // ... inside Scope
    PanelLoader { component: ColorPickerPopup {} }
    ```

    ### 5. Backend Persistence (`scripts/colors/switchwall.sh`)
    ```bash
    --color) set_accent_color "$2"; shift 2 ;;

    current_wallpaper=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE")
    if [[ -n "$imgpath" && "$imgpath" != "$current_wallpaper" ]]; then
        set_accent_color "" 
    fi
    ```
  </details>

- **🔋 Redesigned System Dialogs**: Brand new, premium M3-style dialogs for Battery, Bluetooth, and Wi-Fi with smooth transitions and detailed info.
- **⌨️ Keyboard Management**: Completely redesigned keyboard layout widget for the bar with instant switching and dedicated M3-styled popup.
- **🔵 Bluetooth Management**: Integrated device management within the shell. Easily connect, disconnect, and monitor battery levels of peripherals.
- **📅 Cheatsheet & Timetable**: Create events directly from the timetable and sync with local calendars (via `khal`) for a full agenda view.
- **📜 Cheatsheet Commands**: Manage your personal command library with dynamic tags, search, and JSON import/export support.
  <details>
    <summary><b>🛠️ Full Implementation Guide</b></summary>

    ### 1. File Structure
    - `modules/ii/cheatsheet/commands/CheatsheetCommands.qml`
    - `modules/ii/cheatsheet/commands/CommandCard.qml`
    - `modules/ii/cheatsheet/commands/CommandForm.qml`
    - `services/CommandsService.qml`

    ### 2. Configuration Setup
    #### Update `Config.qml`
    ```qml
    property bool enableCommands: true
    property bool commandsTagsSidebar: false
    ```

    #### Update `InterfaceConfig.qml`
    ```qml
    ConfigSwitch {
        buttonIcon: "terminal"
        text: Translation.tr("Enable Commands")
        checked: Config.options.cheatsheet.enableCommands
        onCheckedChanged: { Config.options.cheatsheet.enableCommands = checked; }
    }
    ```

    ### 3. Module Integration
    - **Service Registration**: Ensure `CommandsService.qml` is registered as a singleton.
    - **Cheatsheet Entry**: Add the tab conditionally in `Cheatsheet.qml`.
  </details>

- **📱 Paged Android Quick Toggles**: Multi-page horizontally swipeable quick toggles mirroring the Android experience.
  <details>
    <summary><b>🛠️ Implementation Details</b></summary>
    
    - **Horizontal Paging**: Smooth flicking and snapping between multiple toggle pages.
    - **Intelligent Height**: The panel height adapts to the current page's toggle count.
    - **Enhanced Edit Mode**: New UI for adding/deleting pages and reordering toggles with full visual feedback.
    - **Layout Sync**: Bottom widgets automatically contract when editing to maximize space.
  </details>

- **🏝️ Dynamic Island Bar**: An adaptive, floating bar style that morphs and scales based on active widgets.
  <details>
    <summary><b>🛠️ Implementation Details</b></summary>
    
    - **Adaptive Morphing**: The bar background automatically scales its dimensions based on the active content's implicit size.
    - **Activation**: Enabled by setting `Config.options.bar.cornerStyle` to `3`.
    - **Full Git Diff**: [View full changes here](https://github.com/P3DROVFX/ii-vynx-fork/commit/8486eb4b4373ffbba5feceaf9cc2dc037f4b69f7)

    #### 1. Configuration Setup (`Config.qml`)
    ```qml
    // modules/common/Config.qml
    property int cornerStyle: 3 // 0: Hug | 1: Float | 2: Plain | 3: Dynamic Island
    ```

    #### 2. Settings UI (`QuickConfig.qml` & `BarConfig.qml`)
    To enable the option in the settings menu, a new entry was added to the `ConfigSelectionArray`:
    ```qml
    // modules/settings/QuickConfig.qml & BarConfig.qml
    options: [
        // ... other options
        {
            displayName: Translation.tr("Dynamic Island"),
            icon: "water_drop",
            value: 3
        }
    ]
    ```

    #### 3. Logic & Adaptive Background (`BarContent.qml`)
    [View BarContent.qml Diff](https://github.com/P3DROVFX/ii-vynx-fork/commit/8486eb4b4373ffbba5feceaf9cc2dc037f4b69f7#diff-19f0d37be19b8e033e30c9ffc925acd0f814df621836d9411bfa00d0458a71aa)
    ```qml
    readonly property bool isDynamicIsland: Config.options.bar.cornerStyle === 3

    Rectangle {
        id: barBackground
        anchors {
            fill: root.isDynamicIsland ? undefined : parent
            centerIn: root.isDynamicIsland ? parent : undefined
        }
        
        // Width scales based on the implicit size of the active sections
        width: root.isDynamicIsland ? (Math.max(islandSections.implicitWidth + 24, 200)) : parent.width

        Behavior on width {
            NumberAnimation { duration: 450; easing.type: Easing.OutExpo }
        }
    }
    ```

    #### 4. Concave Corner System (`RoundCorner.qml`)
    Used to achieve the seamless "island" look at intersections:
    ```qml
    RoundCorner {
        anchors.top: barBackground.top
        anchors.right: barBackground.left
        implicitSize: barBackground.baseRadius
        corner: RoundCorner.CornerEnum.TopRight
        visible: root.isDynamicIsland && root.showBarBackground && !Config.options.bar.bottom
    }
    ```

    #### 5. Vertical Support (`VerticalBarContent.qml`)
    [View VerticalBarContent.qml Diff](https://github.com/P3DROVFX/ii-vynx-fork/commit/8486eb4b4373ffbba5feceaf9cc2dc037f4b69f7#diff-79b59a8a73d9fe4e13613cf5e7ee4ea70c474d6796587e2e46734f36ac0e595b)
  </details>

- **🧠 AI Assistant**: A built-in chat assistant with local (Ollama) or cloud models, tool calling (settings, files, web search, tasks, Gmail read-only, ESPN, RAG over local folders), and per-tool approval controls.
  <details>
    <summary><b>🧠 AI Assistant Setup & Troubleshooting</b></summary>

    Full setup instructions (local Ollama models, cloud providers, policy levels, RAG local retrieval) and troubleshooting are in the [AI Assistant Guide](AI_ASSISTANT_GUIDE.md).
  </details>

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
- **[Quickshell](https://quickshell.org/):** Widget system.
- **[Hyprland](https://hypr.land/):** Compositor.

---

<div align="center">
    <p><b>If you like this project, consider giving it a star! ⭐</b></p>
</div>
