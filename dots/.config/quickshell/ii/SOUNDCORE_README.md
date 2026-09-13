# Soundcore Life Q30 Integration for Quickshell/II

This integration allows native control of ANC modes (Normal, Transparency, Noise Canceling) for Anker Soundcore Life Q30 headphones directly from the Quickshell UI.

## How it Works

The integration follows a multi-layer architecture:
1.  **CLI Layer**: Uses `openscq30_cli` (via Python) to communicate with the headphones over Bluetooth.
2.  **Bash Wrapper**: `scripts/soundcore/soundcore_anc.sh` simplifies CLI calls and parses JSON output into plain strings for QML.
3.  **Service Layer**: `SoundcoreService.qml` (Singleton) tracks Bluetooth connection via `BluetoothStatus` and manages the current ANC mode.
4.  **UI Layer**: 
    -   A custom Quick Toggle in the sidebar dashboard.
    -   An status indicator in the Bluetooth connection popup.

## File Map

| File Path | Description |
| :--- | :--- |
| `scripts/soundcore/soundcore_anc.sh` | Bash wrapper for the `openscq30_cli`. |
| `modules/common/SoundcoreService.qml` | Singleton service that handles logic and process execution. |
| `modules/common/models/quickToggles/SoundcoreAncToggle.qml` | The model defining the toggle behavior, icons, and labels. |
| `modules/common/quickToggles/androidStyle/AndroidSoundcoreAncToggle.qml` | The visual Android-style toggle component. |
| `modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml` | Registered the toggle so it appears in the dashboard menu. |
| `modules/common/quickToggles/AndroidQuickPanel.qml` | Whitelisted the toggle type for the sidebar. |
| `modules/ii/bluetoothConnectionPopup/BluetoothConnectionPopupContent.qml` | Added the ANC status label to the connection overlay. |

## How to Modify

### Changing the Device
If you change headphones or have a different MAC address, update these properties in `modules/common/SoundcoreService.qml`:
-   `targetDeviceName`: The name as it appears in `bluetoothctl`.
-   `macAddress`: The Bluetooth MAC address of your device.

### Adding New Modes
If the CLI supports more modes in the future:
1.  Update the `get` case in `scripts/soundcore/soundcore_anc.sh` if the JSON structure changes.
2.  Update the `mainAction` cycle logic in `modules/common/models/quickToggles/SoundcoreAncToggle.qml`.
3.  Add corresponding icons to the `icon` property in the same file.

## Troubleshooting
-   **Toggle doesn't work**: Ensure `openscq30_cli` is installed and reachable at `~/.local/bin/openscq30_cli`.
-   **No connection detection**: Verify that the `targetDeviceName` in `SoundcoreService.qml` exactly matches your device's name in the Bluetooth settings.
-   **Manual Test**: Run `/path/to/shell/scripts/soundcore/soundcore_anc.sh get <MAC>` to verify the CLI is responding correctly.
