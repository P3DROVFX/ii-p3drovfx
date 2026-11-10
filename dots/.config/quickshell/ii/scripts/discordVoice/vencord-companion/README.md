# Quickshell/II Discord Voice Vencord companion

Vesktop's built-in arRPC socket supports Rich Presence but not Discord's
authenticated voice RPC commands. Standalone Vencord injected into the official
Discord client has the same gap. This Vencord user plugin publishes the same
voice state locally so the Quickshell/II plugin can support these clients
without removing the regular Discord RPC backend.

`install.sh` automates all of this for three setups — run it directly, or use
the "Install Companion" button in the Discord Voice overlay:

- **Vesktop / Equibop**: builds the plugin into a source checkout, then points
  the client at it via the `vencordDir`/`equicordDir` key of its `state.json`.
- **Official Discord with Vencord** (installed via the standalone Vencord
  Installer, not Vesktop): there is no equivalent settings key — the injected
  `patcher.js` hardcodes `~/.config/Vencord/dist` as the load path. The script
  builds the plugin into a separate checkout and replaces that directory
  outright, after backing up the existing build to
  `~/.config/Vencord/dist.bak-<timestamp>`. It also disables Vencord's
  in-client auto-updater (`autoUpdate`/`autoUpdateNotification` in
  `~/.config/Vencord/settings/settings.json`), since it would otherwise
  re-download the official build and silently wipe the custom plugin out. To
  go back to official builds, restore the backup and re-enable auto-update
  from Vencord's settings.

Detection is automatic (checked via installed binaries and Electron profile
markers, not just leftover config directories) but can be forced with
`QS_DISCORD_CLIENT=vesktop|equibop|vencord ./install.sh` if it guesses wrong.

For the locally validated build, the source checkout lives at:
`~/.local/share/quickshell-ii/Vencord/dist`.

The companion uses a user-only Unix socket at
`$XDG_RUNTIME_DIR/ii-discord-voice-vencord.sock`. Vencord Flux events push
voice state immediately, while mute/deafen commands return over the same
connection. The five-second heartbeat is only for crash detection and
reconnection; it does not poll Discord state. No Discord token is read or
exported.

Because the heartbeat is that infrequent, a Flux event arriving while a publish
is already in flight is re-published as soon as that one finishes rather than
dropped — otherwise the shell would show stale mute state for up to five
seconds. If `XDG_RUNTIME_DIR` is unset the companion disables itself; it never
falls back to a shared temporary directory.

Official Discord does not need this companion. The Quickshell bridge continues
to use Discord's native local RPC and authorization flow when it is available.
