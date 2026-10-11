# ii-p3drovfx SDDM theme

An optional SDDM login screen that mirrors the shell's lock screen: the same
wallpaper and lock effects (blur, dim, desaturate, colour wash, vignette), the
same islands and colours, the Material-shape password characters, and the
lock's centred clock when one is configured. It also gives the greeter the
shell's cursor theme and size, and matches each monitor's scale so everything
comes out the same size as on the lock.

## Install / remove

```sh
ii-p3drovfx sddm          # install or refresh (asks for sudo)
ii-p3drovfx sddm remove   # uninstall; SDDM goes back to its previous theme
```

`ii-p3drovfx apply --sddm` installs it as part of an apply. Once installed, an
apply or update offers to refresh it whenever its files changed (`--no-sddm`
skips that). It needs SDDM 0.21+ with the Qt 6 greeter and `qt6-5compat`.

## How it stays in sync

```
shell (SddmSync.qml) ──runs──▶ scripts/sddm/stage_sddm.py
        writes ~/.local/state/quickshell/user/generated/sddm/state.json
                                     │ (ii-sddm-sync@<user>.path watches it)
                                     ▼
root: /usr/local/lib/ii-sddm/ii-sddm-sync <user>
        /var/lib/ii-sddm/{wallpaper.*, fonts/, avatars/, theme.conf.user}
        /etc/sddm.conf.d/zz-ii-p3drovfx-cursor.conf
        /var/lib/sddm/.config/kwinoutputconfig.json (output scales)
```

The greeter runs as the `sddm` user and cannot read your home, so the files it
needs are copied out. The root service opens every file you name with your own
uid and groups, so it cannot copy anything you could not already read, and it
checks every value against a fixed format before writing it. There is no sudoers
rule: the path unit replaces it. Lock settings → "Login screen" turns the sync
off; the login screen then keeps its last synced look.

## Notes

- The battery chip reads sysfs, which needs `QML_XHR_ALLOW_FILE_READ=1` in
  SDDM's `GreeterEnvironment`. The installer sets it unless another file in
  `/etc/sddm.conf.d` already sets `GreeterEnvironment`, in which case it says so
  and leaves that file alone.
- A video wallpaper is shown as its first frame (needs `ffmpeg`).
- There is no on-screen keyboard. Remove `QT_IM_MODULE=qtvirtualkeyboard` (or
  `InputMethod=qtvirtualkeyboard`) from SDDM's config if another theme set it:
  Qt's keyboard then opens in its own window and pops up in a loop. The
  installer warns when it finds one.
- A cursor theme that exists only in your home is copied to
  `/usr/local/share/icons`; system-wide themes are used in place.
- Islands that depend on your session (alarm, weather, modes, keep awake) are
  not shown. The login screen adds the current user above the password field,
  which unfolds into a strip of every user, and a session pill before the power
  island, which opens upward into its list. Either opens only when there is
  more than one to choose from.
