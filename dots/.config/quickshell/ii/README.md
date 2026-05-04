<div align="center">
    <h1> [ Quickshell/II ] </h1>
    <p>A premium Material 3 / Material You dotfiles for Hyprland, powered by Quickshell.</p>
</div>

<div align="center">
    <h2>• overview •</h2>
</div>

This repository is a heavily customized fork of **[ii-vynx](https://github.com/vaguesyntax/ii-vynx)**, which itself is based on the legendary **[illogical-impulse](https://github.com/end-4/dots-hyprland)**. 

It aims to provide a state-of-the-art Linux desktop experience by strictly adhering to **Material 3 (Material You)** design principles, featuring dynamic theming via Matugen and a highly modular architecture built on **Quickshell**.

> [!NOTE]
> This repository is a work in progress. Some modules, like the Gmail client, require manual setup of API keys.

<div align="center">
    <h2>• features & differences •</h2>
</div>

This fork introduces several new features and improvements over the original `ii-vynx` dots. Below is a highlight of the main changes:

<table width="100%">
  <tr>
    <td width="50%" valign="top">
      <h3>📧 Gmail Client Integration</h3>
      <p>A premium, material-designed Gmail client integrated directly into the cheatsheet with threaded view, smart unread counting, and quick actions.</p>
      <video src="https://github.com/user-attachments/assets/5f251196-9fab-4faa-b674-60235f1f729e" width="100%" autoplay loop muted playsinline></video>
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
1. **Env**: `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REDIRECT_URI=http://localhost:8080`.
2. **Deps**: `pip install google-auth google-auth-oauthlib google-api-python-client python-dotenv`.
3. **Auth**: Run shell -> Email Tab -> "Connect Account".

      </details>
    </td>
    <td width="50%" valign="top">
      <h3>🎨 Intelligent Color Picker</h3>
      <p>Capture colors from your screen and instantly generate Material You palettes. Real-time visual feedback across different M3 layers.</p>
      <img src="https://github.com/user-attachments/assets/89e2d851-fda4-4105-a66f-ebbf26d10949" alt="Color Picker" />
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

### 6. Module Definition (`modules/ii/colorPickerPopup/qmldir`)
```text
module qs.modules.ii.colorPickerPopup
ColorPickerPopup 1.0 ColorPickerPopup.qml
ColorPickerPopupContent 1.0 ColorPickerPopupContent.qml
```

      </details>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>🔋 Redesigned System Dialogs</h3>
      <p>Brand new, premium M3-style dialogs for <b>Battery</b>, <b>Bluetooth</b>, and <b>Wi-Fi</b> with smooth transitions and detailed info.</p>
      <img src="https://github.com/user-attachments/assets/126a5660-9bf6-4e57-a910-2c57127c39a7" alt="System Dialogs" />
    </td>
    <td width="50%" valign="top">
      <h3>⌨️ Keyboard Management</h3>
      <p>Completely redesigned keyboard layout widget for the bar with instant switching and dedicated M3-styled popup.</p>
      <img src="https://github.com/user-attachments/assets/8a6225d9-1d40-43a4-b73c-29bcb7badd80" alt="Keyboard Layout" />
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>🔵 New Bluetooth Management</h3>
      <p>Integrated device management within the shell. Easily connect, disconnect, and monitor battery levels of peripherals.</p>
      <img src="https://github.com/user-attachments/assets/9473e473-b5f5-4cd5-b634-d0f7c98334a6" alt="Bluetooth" />
    </td>
    <td width="50%" valign="top">
      <h3>⚙️ Native System Settings</h3>
      <p>Centralized control module to manage all shell options, UI tweaks, and system preferences without editing files manually.</p>
      <img src="https://github.com/user-attachments/assets/0368bf0f-bc5b-482b-ae06-1d291c47e3e2" alt="Settings" />
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>📅 Cheatsheet & Timetable</h3>
      <p>Create events directly from the timetable and sync with local calendars (via <code>khal</code>) for a full agenda view.</p>
      <img src="https://github.com/user-attachments/assets/608bbf11-9819-4fe0-880c-014fe3845000" alt="Timetable" />
    </td>
    <td width="50%" valign="top">
      <h3>📜 Cheatsheet Commands</h3>
      <p>Manage your personal command library with dynamic tags, search, and JSON import/export support.</p>
      <img src="REPLACE_WITH_COMMANDS_PREVIEW_IMAGE" alt="Commands" />
      <br><br>
      <details>
        <summary><b>🛠️ Implementation Guide</b></summary>
        <p>Follow these steps to integrate the commands module:</p>
        <ol>
          <li>Add <code>enableCommands</code> and <code>commandsTagsSidebar</code> to <code>Config.qml</code>.</li>
          <li>Register <code>CommandsService.qml</code> as a singleton.</li>
          <li>Add toggles to <code>InterfaceConfig.qml</code> for user control.</li>
          <li>Check <a href="modules/ii/cheatsheet/commands/commands.md">commands.md</a> for the full documentation.</li>
        </ol>
      </details>
    </td>
  </tr>
</table>

### 🚀 Other Highlights
- **🎥 OBS Integration**: Start/stop recordings directly from the bar with real-time status.
- **✅ TickTick Sync**: Full cloud integration for task management synced across devices.
- **✨ Micro-animations**: Refined transitions across the entire system.

<div align="center">
    <h2>• warning •</h2>
</div>

These dots are based on **illogical-impulse**. You can access original **illogical-impulse** dots from [here](https://github.com/end-4/dots-hyprland).

While this repository is my daily driver, please be aware that it contains many custom tweaks and features that may still be in active development. Bugs and stability issues might occur. Join the conversation and report issues to help improve the project!

<div align="center">
    <h2>• installation •</h2>
</div>

1. Clone this repository with submodules:

```bash
git clone --recurse-submodules https://github.com/P3DROVFX/ii-vynx.git
```

2. Run the setup script and follow the instructions:

```bash
./setup-ii-vynx.sh
```

<div align="center">
    <h2>• documentation •</h2>
</div>

Please refer to the **[wiki](https://github.com/vaguesyntax/ii-vynx/wiki)** for detailed component descriptions.

<div align="center">
    <h2>• credits •</h2>
</div>

- **[end-4](https://github.com/end-4):** Creator of illogical-impulse.
- **[vaguesyntax](https://github.com/vaguesyntax):** Creator of ii-vynx.
- **[Quickshell](https://quickshell.org/):** Widget system.
- **[Hyprland](https://hypr.land/):** Compositor.

<div align="center">
    <br>
    <p><b>If you like this project, consider giving it a star! ⭐</b></p>
</div>