# app_stats

Per-app usage and energy sampler: foreground/background screen time, watt-hours,
CPU and GPU time, memory, launches and sessions — plus the battery's own level and
charge history where there is one — the data behind the usage overlay.

**Binary:** `~/.config/quickshell/ii/scripts/appStats/app_stats`
**Source:** `~/.config/quickshell/ii/scripts/appStats/app_stats_src/`

## Why a helper is needed

Nothing the shell can reach in QML can answer "which app used that battery". The
numbers come from four places at once, three of which need a tight polling loop that
would stall the UI thread if it ran in QML:

- **Hyprland's event socket** for window transitions, so a workspace switch is
  recorded at the instant it happens rather than rounded to the next sample.
- **`/proc/*/stat`** for CPU and RSS across ~450 processes, folded onto apps by
  walking the parent chain — a browser's forty helper processes report as one app.
- **`/proc/*/fdinfo/*`** for per-client GPU engine cycles from the `xe` driver.
- **`/sys/class/powercap/intel-rapl:0*`** for real energy counters.

The daemon knows only pids, window classes and counters. It resolves no desktop
entries, icons or themes — that happens in QML, which already has `AppSearch`. That
split is what keeps it at ~3.5 MB RSS.

## Installation

The QML side ships with the config. Two things do not: the **binary**, which is built
rather than tracked, and the **udev rule**, which lives outside `$HOME` and needs root.
Both are below — paste the block, then press **Super + U**.

```bash
# 1. Build the sampler. rust is the only build requirement; the first build fetches
#    libc and serde_json, so it needs network. Result is ~530 KB.
yay -S --needed rust
~/.config/quickshell/ii/scripts/rust-helpers.sh build app_stats

# 2. Let your own user read the RAPL energy counters. Skip on AMD or in a VM —
#    there is no intel-rapl there — and set energySource to "battery" instead.
sudo tee /etc/udev/rules.d/99-rapl-readable.rules >/dev/null <<'EOF'
# energy_uj is root-only as the mitigation for CVE-2020-8694 (PLATYPUS), a power
# side-channel attack. wheel can already read it through sudo, so widening to wheel
# grants that group no new capability -- it only removes the need to run the sampler
# as root. Only energy_uj is touched; the other attributes are already world-readable.
SUBSYSTEM=="powercap", KERNEL=="intel-rapl:*", TEST=="/sys$devpath/energy_uj", \
  RUN+="/usr/bin/chgrp wheel /sys$devpath/energy_uj", \
  RUN+="/usr/bin/chmod g+r /sys$devpath/energy_uj"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=powercap

# 3. Restart the shell, then check all three.
qs kill; qs &
cat /sys/class/powercap/intel-rapl:0/energy_uj   # a number, not "Permission denied"
pgrep -af app_stats                              # exactly one process
ls ~/.local/state/quickshell/user/app_stats/     # YYYY-MM-DD.json within a minute
```

An empty first minute is normal — the day file is only written every
`flushIntervalMs`. If the RAPL read fails, energy silently falls back to whole-battery
drain, which reads zero on AC.

A few things that bite:

- You must be in `wheel` for step 2 (`groups | grep wheel`); adding yourself needs a
  re-login.
- The binary must end up at `scripts/appStats/app_stats` and be executable. That exact
  path is what `AppStats.qml` launches, with no fallback.
- Nothing rebuilds it automatically — repeat step 1 after any change to `app_stats_src/`.
- The binary, `target/` and `Cargo.lock` are gitignored on purpose; mirror the source
  and build on the target machine. `setup-ii-p3drovfx.sh` protects the built binary so
  a config update carries it across instead of deleting it.

<details>
<summary>Hand-assembled configs: what else has to be present</summary>

Both ship with this config, so this is only for a tree assembled by hand or one that
predates the feature.

The **Super + U** keybind and the layer rules are in `dots/.config/hypr/hyprland/`;
`hyprctl reload` picks them up. Without them the overlay still opens — `qs ipc call
usage toggle` — but it renders unblurred and pops in instead of sliding.

```lua
-- keybinds.lua
hl.bind("SUPER + U", hl.dsp.global("quickshell:usageToggle"), { description = "Shell: Toggle app usage stats" })

-- rules.lua
hl.layer_rule({ match = { namespace = "quickshell:usage" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:usage" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "quickshell:usage" }, animation = "slide bottom"})
```

On the shell side: `services/AppStats.qml`, the `modules/ii/usage/` overlay, the
`appStats` group in `modules/common/Config.qml`, `UsageStatsConfig.qml` registered in
`SettingsPageRegistry` under System, `Directories.appStats`, `usageOpen` in
`GlobalStates.qml`, and a `PanelLoader` for `Usage` in both panel families.

One line is not optional: `shell.qml` touches `AppStats.stateDir` on startup. The
singleton is lazy, so without it nothing is collected until the overlay is first opened.

</details>

### Configuration

Settings → System → **App Usage** covers all of it. The same keys live under
`Config.options.appStats` in `~/.config/illogical-impulse/config.json`.

Everything in the first table is a command-line flag the daemon reads once at
startup, so changing one relaunches it.

| Key                | Default           | Effect                                                                                                                                                                    |
| ------------------ | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enable`           | `true`            | run the sampler at all                                                                                                                                                    |
| `sampleIntervalMs` | `10000`           | counter poll period                                                                                                                                                       |
| `flushIntervalMs`  | `60000`           | day-file write period                                                                                                                                                     |
| `retentionDays`    | `31`              | days of history kept — a floor rather than the window itself under `previousMonth`                                                                                        |
| `retentionMode`    | `"previousMonth"` | `previousMonth` never drops a day last month needs, so the window slides between 31 and 62 days and the two months can be compared; `fixed` keeps exactly `retentionDays` |
| `energySource`     | `"auto"`          | `auto`, `rapl`, `battery` or `none`                                                                                                                                       |
| `gpuFullEvery`     | `30`              | samples between full GPU rescans                                                                                                                                          |
| `idleTimeoutSec`   | `300`             | seconds without input before foreground time stops; `0` disables the idle monitor                                                                                         |
| `trackHeadless`    | `true`            | record processes that own no window                                                                                                                                       |

The rest are read live by the overlay.

| Key                  | Default | Effect                                                                                                                         |
| -------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `overlayEnabled`     | `true`  | load the overlay panel                                                                                                         |
| `showHeadless`       | `false` | count headless processes in the list and the totals                                                                            |
| `defaultGranularity` | `"day"` | `day`, `week` or `month`                                                                                                       |
| `defaultMetric`      | `"fg"`  | `fg`, `focus`, `energy`, `cpu` or `gpu`                                                                                        |
| `rememberLastView`   | `true`  | reopen on the last granularity, metric and view instead of the defaults above                                                  |
| `lastView`           | `"apps"`| which half of the overlay reopens: `apps` or `battery`. Ignored on a machine with no battery                                   |
| `weekStartsMonday`   | `true`  | which day a calendar week runs from                                                                                            |
| `keepSelection`      | `false` | keep the picked app across openings                                                                                            |
| `showComparison`     | `false` | percent change against the period before. Off by default: it parses that period as well, doubling the files a month view reads |
| `minDurationSec`     | `0`     | hide apps under this from the list. Duration metrics only, and never from the totals                                           |

Turning `enable` off stops collection but keeps the history; deleting the state
directory, or the button on the settings page, is what discards it.

## Running it by hand

It is a normal program: run it in a terminal and watch the NDJSON.

```bash
./app_stats --state-dir /tmp/stats --interval-ms 3000
```

| Flag               | Default                                     | Effect                                                                                                            |
| ------------------ | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `--interval-ms`    | `10000`                                     | counter poll period (minimum 1000)                                                                                |
| `--flush-ms`       | `60000`                                     | how often the day file is rewritten                                                                               |
| `--retention-days` | `30`                                        | day files older than this are deleted                                                                             |
| `--retention-mode` | `fixed`                                     | `fixed`, or `previous-month` to treat the above as a floor and never drop a day the previous calendar month needs |
| `--state-dir`      | `$XDG_STATE_HOME/quickshell/user/app_stats` | where day files go                                                                                                |
| `--energy`         | `auto`                                      | `rapl`, `battery`, `auto` or `off`                                                                                |
| `--gpu-full-every` | `30`                                        | intervals between full GPU rescans (a new window forces one)                                                      |
| `--no-headless`    | —                                           | skip processes that own no window                                                                                 |
| `--quiet`          | —                                           | write day files, print nothing                                                                                    |

## Protocol

One JSON object per line, in both directions.

**stdin**

| Line                                                    | Meaning                                                                      |
| ------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `{"t":"state","locked":true,"idle":false,"dpms":"off"}` | screen state changed; foreground time stops accruing while any of these hold |
| `{"t":"flush"}`                                         | write the day file now                                                       |
| `{"t":"quit"}`                                          | flush and exit (`SIGTERM` does the same)                                     |

**stdout**

| Line                     | Meaning                                                        |
| ------------------------ | -------------------------------------------------------------- |
| `{"t":"ready",…}`        | startup: energy source in use, interval, state dir             |
| `{"t":"sample",…}`       | one interval's deltas per app, plus the unattributed remainder |
| `{"t":"flush","file":…}` | a day file was written                                         |

## Storage

One sparse file per local day, `YYYY-MM-DD.json`, so today's chart never has to parse
a month of history and retention is an unlink. Each app maps hours to a fixed tuple:

| idx | field    | unit |     | idx | field      | unit  |
| --- | -------- | ---- | --- | --- | ---------- | ----- |
| 0   | `fg`     | s    |     | 6   | `ramPeak`  | MiB   |
| 1   | `bg`     | s    |     | 7   | `mJfg`     | mJ    |
| 2   | `focus`  | s    |     | 8   | `mJbg`     | mJ    |
| 3   | `cpu`    | s    |     | 9   | `launches` | count |
| 4   | `gpu`    | s    |     | 10  | `sessions` | count |
| 5   | `ramAvg` | MiB  |     |     |            |       |

`focus` is a subset of `fg`: on a tiling WM every mapped window on the active
workspace is "foreground", which inflates screen time, so focused time is recorded
separately and the UI can switch which one it reports without recollecting anything.

`launches` counts an app appearing that had no window at all a moment ago; `sessions`
counts any of its windows coming into view, so switching to a workspace holding three
of them adds three. The overlay shows the latter as "Appearances" for that reason.

The `__system` row is the device, not an app. Its `fg` is screen time counted once
however many windows were up, its `bg` the time the machine was awake with nothing
on screen, and `mJbg` the energy no app accounts for.

On a machine with a battery the file carries one more section, `bat`, holding the
pack's full capacity in mWh and its own hour tuple. It sits beside `apps` rather than
among them because a battery is a level as well as an amount, and no row of totals can
say where an hour opened and closed. The section is additive: the app tuples are
unchanged, so a file with it reads on an older shell and a file without it reads here
as a day with no battery history.

| idx | field   | unit        |     | idx | field      | unit |
| --- | ------- | ----------- | --- | --- | ---------- | ---- |
| 0   | `start` | 0.1 %       |     | 5   | `in`       | mWh  |
| 1   | `end`   | 0.1 %       |     | 6   | `offAc`    | s    |
| 2   | `low`   | 0.1 %       |     | 7   | `charging` | s    |
| 3   | `high`  | 0.1 %       |     | 8   | `onAc`     | s    |
| 4   | `out`   | mWh         |     |     |            |      |

The level is `charge_now / charge_full`, not `capacity`, which the kernel rounds to
whole percent — a whole percent is an hour the level never appears to move. `out` and `in` are integrated
from the instantaneous draw rather than differenced from the level, because the firmware
refreshes `charge_now` every few minutes at best: an hour of real work can pass with the
reported charge never moving. `offAc` follows the mains line rather than the battery's
own status, which reads `Discharging` at roughly zero draw whenever a charge limit holds
the pack below full.

Time the sampler did not run through — a suspend, a hibernate, a stall — is credited
to nobody. A gap longer than three sample intervals is skipped rather than filled:
nothing about it was observed, and spreading it over the hours it spans would invent
a night of background activity for every process that happened to be resident.

Written directly rather than through `JsonAdapter`, so the numeric tuples cannot be
silently coerced to another type.

## Energy attribution

RAPL measures the whole package and cannot see processes, so per-app energy is a
model, not a measurement:

```
E(app) = ΔE_core × cpu_share + ΔE_uncore × gpu_share + ΔE_dram × rss_share
```

Whatever is left over — idle draw, kernel threads, display backlight, radios — goes
into an explicit `__system` bucket instead of being normalised away. On this machine
that residual is **50–60 %** at light load, which is the honest measure of how much
weight the per-app numbers can bear.

## Requirements

None of these are checked at startup; each one missing costs a category of data
rather than stopping the daemon.

- **The udev rule** from installation step 2. Without it every RAPL read fails and the
  daemon falls back to whole-battery drain split by a fixed ratio — much cruder, and
  zero while on AC. The daemon never uses `sudo`.
- A **Hyprland** session: it reads `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/`.
  On anything else there are no window events, so every process is headless and
  foreground time is always zero.
- The **`xe`** or **`i915`** driver for GPU accounting. Without per-client
  `drm-cycles-*` in fdinfo, GPU shares are simply zero and the uncore energy all
  lands in `__system`.
- **Write access to `$XDG_STATE_HOME`** for the day files. The directory is created if
  it does not exist.
- A **battery** under `/sys/class/power_supply`, for the `bat` section and the overlay's
  battery view. A desktop writes neither, and the view does not appear.

## Cost

Measured on this machine at the default 10 s interval, ~450 processes, Brave and
Discord running: **6.8 ms of CPU per sample — 0.07 % of one core**, 3.5 MB RSS.

Most of that is the `/proc` sweep. The GPU scan is kept cheap by remembering which
fds of which processes are DRM fds: a full sweep opens every fd of every process,
while the scans in between reopen only the handful that matter. Removing that cache
roughly doubles the cost.
