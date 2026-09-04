# osk_autoshow

Raises the on-screen keyboard when a text field is focused by finger or pen.

**Binary:** `~/.config/quickshell/ii/scripts/osk/osk_autoshow`
**Source:** `~/.config/quickshell/ii/scripts/osk/osk_autoshow_src/`

## Why a helper is needed

Wayland tells an *input method* when a client focuses a text field, via
`zwp_input_method_v2`. Quickshell exposes no QML binding for that protocol and
Hyprland's IPC has no equivalent event, so the shell has no way to know a text
field was focused.

The helper binds `zwp_input_method_v2` purely as an observer — it never grabs the
keyboard and never commits text, so key events reach applications unchanged. Typing
is still done by the shell through ydotool.

It also watches `/dev/input` directly, because the protocol reports *that* a text
field was focused but not which device did it. `OskAutoShow.qml` correlates the two
so that mouse clicks and Tab navigation never raise the keyboard.

## Building

**Settings → On-screen keyboard → Automatic keyboard → "Build it now"** runs exactly the
command below and picks up the result without a restart. That button is the supported
path: this helper is what stands between a device with no keyboard and a text field, so
unblocking it cannot itself require a terminal to type in.

By hand:

```bash
cd ~/.config/quickshell/ii/scripts/osk/osk_autoshow_src
cargo build --release
cp target/release/osk_autoshow ../osk_autoshow.new
mv -f ../osk_autoshow.new ../osk_autoshow
```

The rename matters on a rebuild: writing over the running helper is `ETXTBSY`, so a
plain `cp` fails and throws away a compile that worked.

## Output protocol

One event per line on stdout:

| Line | Meaning |
| --- | --- |
| `activate` | a text field gained focus |
| `deactivate` | the focused text field went away |
| `touch <x> <y>` | finger contact, coordinates normalized to 0..1 |
| `pen <x> <y>` | pen contact, coordinates normalized to 0..1 |
| `mouse -1 -1` | left click on a relative pointer; ignored unless `osk.autoShow.allowMouse` |
| `devices <t> <p> <m>` | how many touch, pen and pointer devices could be opened, once at startup |
| `denied` | at least one input device could not be opened for permissions |
| `key` | a press on a physical keyboard (throttled to 5 Hz) |
| `unavailable` | another input method holds the seat; the helper exits |

## Requirements

- Membership of the `input` group, to read `/dev/input/event*`. Devices whose names
  look virtual (`ydotool`, `uinput`) are skipped so the keyboard cannot close itself
  by typing.
- No other input method bound to the seat. fcitx5, ibus and this helper are mutually
  exclusive — only one client may hold `zwp_input_method_v2`.
- Applications must implement `text-input-v3`. Most GTK and Qt apps do; some Electron
  builds do not, and the keyboard simply won't auto-show there.

## Configuration

Everything lives under `osk.autoShow` in `~/.config/illogical-impulse/config.json`,
and is exposed in Settings → Overlays → On-screen Keyboard. While `enable` is off the
helper is never launched.

`allowMouse` is off, and should stay off on any device with a touchscreen — someone
using a mouse has a keyboard. It exists so the pipeline can be demonstrated on a
machine with no touch panel, where the daemon reports `devices 0 0 N` and nothing else
on the page can possibly fire.

## Pen mode

The same daemon reports the stylus's barrel buttons, because it is already watching the
pen device and nothing else in the shell is:

| Line | Meaning |
| --- | --- |
| `penbutton <n> <0\|1> <x> <y>` | barrel button `n` released/pressed, with the pen's position |
| `penmove <x> <y>` | pen motion, **only while a barrel button is held** |

Both states of a button are reported because the shell binds press and hold separately:
holding one and moving the pen is how a window gets dragged, and a press-only report
cannot express the end of a hold. Motion is gated on a held button for the same reason
the rest of this file is careful: a pen reports position continuously whenever it is
anywhere near the tablet, and forwarding all of it would be thousands of lines a minute
for something only a drag cares about.

### Why not OpenTabletDriver's own bindings

OTD can bind a barrel button to a key combination, and the shell could then bind that
combination in Hyprland. That is three files that have to agree — OTD's `settings.json`,
Hyprland's config, and the shell's — and opening OTD's own UI rewrites the first one.
OTD passes the buttons through as ordinary `BTN_STYLUS` / `BTN_STYLUS2` on the tablet
device regardless, so reading them here needs nothing configured anywhere else.
