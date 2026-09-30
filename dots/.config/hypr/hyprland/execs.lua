-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function()

    -- Tray watcher: holds org.kde.StatusNotifierWatcher across shell restarts, so
    -- tray icons survive one. Started before the shell, which then uses it
    -- instead of registering a watcher of its own. See
    -- ~/.config/quickshell/ii/scripts/tray/README.md; a no-op until the helper
    -- is built (scripts/rust-helpers.sh build sni_watcher).
    hl.exec_cmd("$HOME/.config/quickshell/$qsConfig/scripts/tray/sni_watcher")

    -- Bar, wallpaper
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
    -- jemalloc defaults to 4 arenas per CPU, and the shell's ~50 threads each leave
    -- half-filled pages in their own: one arena measured ~100 MB less RAM with no
    -- change in startup time. It is read before main(), so it has to be in the
    -- environment here (and at every other place that starts the shell) - a
    -- `//@ pragma Env` in shell.qml is applied too late to reach the allocator.
    hl.exec_cmd("MALLOC_CONF=narenas:1 qs -c $qsConfig")
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")

    -- Core components (authentication, lock screen, notification daemon)
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target")


    -- Audio (wait for Quickshell's tray watcher so EasyEffects registers its tray icon successfully)
    hl.exec_cmd(
        "until busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1; do sleep 0.2; done; easyeffects --hide-window --service-mode")

    -- Clipboard: history
    -- Kill existing instances
    hl.exec_cmd("killall wl-paste wl-clip-persist 2>/dev/null")
    -- Start wl-clip-persist to retain clipboard contents after apps exit (with delay for Wayland display readiness)
    hl.exec_cmd("sleep 1.5 && wl-clip-persist --clipboard both")
    -- Start cliphist watchers with quickshell integration
    hl.exec_cmd(
        "sleep 1.5 && wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
    hl.exec_cmd(
        "sleep 1.5 && wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
    hl.exec_cmd(
        "sleep 1.5 && wl-paste --type text/uri-list --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")

    -- Cursor: reapply the theme and size env.lua exported, so a size saved in Settings survives a relogin
    hl.exec_cmd(
        'hyprctl setcursor "${HYPRCURSOR_THEME:-${XCURSOR_THEME:-Bibata-Modern-Classic}}" "${HYPRCURSOR_SIZE:-${XCURSOR_SIZE:-24}}"')
end)

hl.on("hyprland.shutdown", function()
    os.execute("systemctl --user stop hyprland-session.target && sleep 0.1")
end)
