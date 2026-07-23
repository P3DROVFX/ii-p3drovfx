# end4-pC Discord Voice Vencord companion

Vesktop's built-in arRPC socket supports Rich Presence but not Discord's
authenticated voice RPC commands. This Vencord user plugin publishes the same
voice state locally so the Quickshell plugin can support Vesktop without
removing the regular Discord RPC backend.

Install this directory as `src/userplugins/end4DiscordVoice` in a Vencord source
checkout, run `pnpm build`, copy the checkout's `package.json` into `dist/`,
select that `dist` directory under Vesktop Settings → Vencord Location, then
fully restart Vesktop. **End4DiscordVoice** is enabled by default and remains
available in Vencord's Plugins page.

For the locally validated build, select:
`~/.local/share/end4-pC/Vencord/dist`.

The companion uses a user-only Unix socket at
`$XDG_RUNTIME_DIR/end4-discord-voice-vencord.sock`. Vencord Flux events push
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
