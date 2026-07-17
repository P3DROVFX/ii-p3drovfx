# ii Desktop Widget Extensions

Third-party desktop widgets for the ii Quickshell/Hyprland shell. Install any widget by pasting a GitHub repository URL directly in **Settings → Desktop Widgets → Extensions**.

> [!WARNING]
> By creating or publishing a widget for ii, you grant the shell developer the right to use, modify, redistribute, and showcase the widget, in whole or in part, for any purpose without restriction.

---

## Quick Start

Create a directory with a `widget.json` and your QML file:

```
my-widget/
├── widget.json
└── MyWidget.qml
```

**Minimal `widget.json`:**

```json
{
  "name": "My Widget",
  "component": "MyWidget.qml"
}
```

**Minimal `MyWidget.qml`:**

```qml
import QtQuick
import qs.modules.common
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    implicitWidth: 200
    implicitHeight: 200

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainerHigh
        radius: Appearance.rounding.normal

        Text {
            anchors.centerIn: parent
            text: "Hello!"
            color: root.colText
        }
    }
}
```

**Test locally:** Open Settings → Desktop Widgets → Extensions → paste the absolute path to your widget directory → click Install.

---

## widget.json Schema

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | **Yes** | Display name shown in the widget gallery. |
| `component` | string | **Yes** | Relative path to the main QML file. |
| `description` | string | No | Short description shown in the widget card. |
| `version` | string | No | Semantic version (e.g. `"1.0.0"`). Used for update checking. |
| `author` | string | No | Author display name. |
| `icon` | string | No | [Material Symbols](https://fonts.google.com/icons) icon name. Default: `"extension"`. |
| `category` | string | No | Gallery category. See [Categories](#categories). Default: `"Utility"`. |
| `preview` | string | No | Relative path to a preview image (PNG/JPG). Shown in gallery instead of live render. |
| `defaultWidth` | number | No | Default widget width in pixels. Default: `200`. |
| `defaultHeight` | number | No | Default widget height in pixels. Default: `200`. |
| `defaultX` | number | No | Default x position on desktop. Default: `200`. |
| `defaultY` | number | No | Default y position on desktop. Default: `200`. |
| `configDefaults` | object | No | Default key-value config applied on install. |
| `configSchema` | object | No | Typed settings schema. Auto-renders a settings UI. See [Config Schema](#config-schema). |

### Full Example

```json
{
  "name": "System Monitor",
  "description": "Shows CPU, RAM and network usage in a compact widget.",
  "version": "1.2.0",
  "author": "yourhandle",
  "icon": "monitor_heart",
  "category": "System",
  "component": "SystemMonitor.qml",
  "preview": "assets/preview.png",
  "defaultWidth": 280,
  "defaultHeight": 160,

  "configDefaults": {
    "refreshInterval": 2,
    "showNetwork": true,
    "unit": "percent"
  },

  "configSchema": {
    "refreshInterval": {
      "type": "slider",
      "label": "Refresh Interval (seconds)",
      "default": 2,
      "min": 1,
      "max": 10
    },
    "showNetwork": {
      "type": "bool",
      "label": "Show Network Speed",
      "default": true
    },
    "unit": {
      "type": "enum",
      "label": "Usage Unit",
      "default": "percent",
      "values": ["percent", "absolute"]
    }
  }
}
```

---

## Categories

Use one of the standard categories to ensure your widget appears in the right section of the gallery:

| Category | Description | Icon |
|---|---|---|
| `Clock` | Clocks and timers | `schedule` |
| `Media` | Music/video players | `play_circle` |
| `Weather` | Weather and forecasts | `cloud` |
| `Photo` | Photos and images | `image` |
| `Date` | Calendars and dates | `calendar_today` |
| `System` | CPU, RAM, disk, network | `monitor_heart` |
| `Social` | Feeds and social media | `forum` |
| `Productivity` | Notes, tasks, reminders | `task_alt` |
| `Fun` | Decorative and fun | `toys` |
| `Utility` | Everything else (default) | `build` |

---

## QML Contract

### Root Element

Your root element **must** extend `AbstractBackgroundWidget`. Do **not** set `x` or `y` yourself — the system handles positioning.

```qml
import QtQuick
import qs.modules.common
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    // Injected automatically by the system:
    // property string widgetExtensionId  — your widget's ID (directory name)
    // property var    widgetConfig        — your config values as a JS object

    implicitWidth: 200    // your default size
    implicitHeight: 200

    // ... your content here
}
```

### Injected Properties

| Property | Type | Description |
|---|---|---|
| `widgetExtensionId` | string | The widget's ID (derived from the repository/directory name). |
| `widgetConfig` | var (object) | Current config values. Read-only. Use the settings schema to let users change them. |

### Inherited from `AbstractBackgroundWidget`

You get these for free without any extra code:

| Property | Type | Description |
|---|---|---|
| `colText` | color | Adaptive text color based on wallpaper region. |
| `colTextSecondary` | color | Secondary adaptive text color. |
| `colTextTertiary` | color | Tertiary adaptive text color. |
| `screenWidth` | real | Full screen width in pixels. |
| `screenHeight` | real | Full screen height in pixels. |
| `wallpaperScale` | real | Current wallpaper scale factor. |

### Reading Config Values

Access config through the injected `widgetConfig` property:

```qml
AbstractBackgroundWidget {
    id: root

    Text {
        text: root.widgetConfig?.myValue ?? "default"
    }
}
```

---

## Config Schema

Define `configSchema` in `widget.json` to get a settings UI automatically generated for your widget. Users access it via the gear icon on your widget card in settings.

### Supported Types

| Type | Control | Extra Properties |
|---|---|---|
| `bool` | Toggle switch | — |
| `int` | Spin box | `min`, `max` |
| `float` | Decimal spin box | `min`, `max` |
| `slider` | Slider (float) | `min`, `max` |
| `enum` | Dropdown | `values` (string array) |
| `string` | Text field | `placeholder` (optional) |

### Example Schema

```json
{
  "configSchema": {
    "refreshInterval": {
      "type": "int",
      "label": "Refresh every N seconds",
      "default": 30,
      "min": 5,
      "max": 300
    },
    "showTitle": {
      "type": "bool",
      "label": "Show title bar",
      "default": true
    },
    "style": {
      "type": "enum",
      "label": "Visual style",
      "default": "compact",
      "values": ["compact", "expanded", "minimal"]
    },
    "apiKey": {
      "type": "string",
      "label": "API Key",
      "default": "",
      "placeholder": "Enter your API key..."
    }
  }
}
```

Config values are stored in `widget_extensions.json` under `~/.config/illogical-impulse/` and persist across sessions and presets.

---

## Importing QML Files

Reference other QML files in the same directory without any special import:

```qml
// MyWidget.qml
AbstractBackgroundWidget {
    MySubComponent {}   // loads MySubComponent.qml from the same folder
}
```

For subdirectories, use a relative import:

```qml
import "./components"

AbstractBackgroundWidget {
    MyCard {}   // loads components/MyCard.qml
}
```

---

## Accessing ii Design Tokens

Use `Appearance` and `Quickshell.modules.common` to match the shell's Material You theme:

```qml
import qs.modules.common

AbstractBackgroundWidget {
    Rectangle {
        color: Appearance.colors.colSurfaceContainerHigh
        radius: Appearance.rounding.normal

        Text {
            color: root.colText
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
        }
    }
}
```

### Common Color Tokens

| Token | Description |
|---|---|
| `Appearance.colors.colSurfaceContainerHigh` | Card/surface background |
| `Appearance.colors.colSurfaceContainerLow` | Subtle surface |
| `Appearance.colors.colPrimary` | Primary accent color |
| `Appearance.colors.colOnLayer0` | Text on background |
| `root.colText` | Adaptive text (adapts to wallpaper) |
| `root.colTextSecondary` | Secondary adaptive text |

### Common Size Tokens

| Token | Description |
|---|---|
| `Appearance.rounding.normal` | Standard corner radius |
| `Appearance.rounding.large` | Large corner radius |
| `Appearance.font.pixelSize.normal` | Normal font size |
| `Appearance.font.pixelSize.small` | Small font size |

---

## Testing Locally

1. Create your widget directory anywhere on your filesystem.
2. Open **Settings → Desktop Widgets → Extensions**.
3. Paste the **absolute path** to your directory in the install field.
4. Click **Install**. Your widget appears instantly in the gallery.
5. Toggle it on to see it on the desktop.

> [!TIP]
> Local widgets support **live reload** via the Reload button. After changing your QML, click Reload to pick up changes without reinstalling.

---

## Publishing

To make your widget discoverable in the community browser (coming soon):

1. Push your repository to GitHub.
2. Add the topic `ii-desktop-widget` to your repository.
3. Make sure `widget.json` is at the **repository root**.
4. The community browser will automatically find your widget via the GitHub API.

### Repository Structure Best Practices

- Use kebab-case for your repo name (e.g. `my-cool-widget`, `system-monitor-widget`).
- The repo/directory name becomes the widget ID — keep it unique and descriptive.
- Place `widget.json` at the root.
- Include a `preview.png` (600×400 recommended) so users see a screenshot before installing.
- Add a `README.md` with screenshots and usage instructions.

---

## Best Practices

### Do

- Keep your widget lightweight — it runs alongside the entire shell.
- Use `root.colText` instead of hardcoded colors so your widget adapts to the user's theme.
- Declare sensible `defaultWidth`/`defaultHeight` that fit most common screen sizes.
- Use `configDefaults` for every configurable value — users shouldn't have to configure from scratch.
- Test at multiple scales (`Config.options.background.widgets.widgetsScale`).
- Add a `preview.png` so users know what they're installing.

### Don't

- Don't `import` internal ii modules beyond `qs.modules.common` and `qs.modules.ii.background.widgets`. These APIs are not stable.
- Don't set `x`, `y`, `width`, or `height` directly on the root `AbstractBackgroundWidget` — use `implicitWidth`/`implicitHeight` instead.
- Don't block the QML engine with heavy synchronous computation — use `Process` for shell commands and timers for polling.
- Don't hardcode paths or assume any specific directory structure on the user's machine.

---

## Example Widgets

Coming soon. In the meantime, study the built-in widgets in the ii source:

- **Clock widget**: `modules/ii/background/widgets/clock/ClockWidget.qml`
- **Media widget**: `modules/ii/background/widgets/media/MediaWidget.qml`
- **Photo widget**: `modules/ii/background/widgets/photo/PhotoWidget.qml`

These show patterns for using `AbstractBackgroundWidget`, reading from `Config`, running processes, and adapting to the wallpaper's dominant color.

---

Report issues or questions about the widget extension system [here](https://github.com/P3DROVFX/ii-p3drovfx/issues).
