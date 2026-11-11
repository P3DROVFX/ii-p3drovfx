# ii link protocol (`iilink/1`)

`ii_link` is the network half of the link between the ii shell and the **ii tools**
Android app (`~/Projects/ii-tools`, package `dev.ii.tools`). It owns TLS, the
WebSocket, pairing, the paired devices and LAN discovery, and relays everything an
authenticated phone says to the shell. It executes nothing: `services/IiLinkService.qml`
decides what a message does, against its list of allowed actions.

```
ii_link --state-dir DIR [--port N] [--name NAME]     run (NDJSON on stdin/stdout)
ii_link unpair --state-dir DIR --id ID                forget a device while not running
```

The shell starts it only while a phone is paired or a pairing is open, so users without
the app never run it. It idles on its sockets and stdin: zero wakeups when nothing
happens (`~/Projects/ii-tools/tools/measure.sh` checks this).

## State directory

`~/.local/state/quickshell/user/iilink/` (mode 0700, files 0600):

| File | Contents |
| --- | --- |
| `cert.der`, `key.der` | Self-signed ECDSA P-256 identity, generated on first run. The phone pins the SHA-256 of `cert.der`. |
| `peers.json` | `[{id, name, model, tokenHash, pairedAt, lastSeen}]`. The shell watches this file to know whether a phone is paired without running the helper. |

## Network

- **TCP `port`** (default 47210): TLS 1.3, then a WebSocket on path `/iilink/1`. Text
  frames carry JSON objects; frames up to 1 MiB, messages up to 8 MiB. The phone pings
  every 30 s; a socket silent for 95 s is dropped.
- **UDP `port`**: discovery. A datagram starting with `iilink?` gets
  `{"iilink":1,"port":N,"fp":"<sha256>","name":"<host>"}` back. mDNS is not used:
  Fedora's default firewall zone keeps 5353 closed, while high ports are open (as
  KDE Connect relies on).

## Pairing

1. The shell sends `{"op":"pair"}`. The helper opens a 5-minute window with a one-time
   secret and emits `pairing` with the link and its QR matrix:

   ```
   iilink://pair?v=1&h=<ip,ip…>&p=<port>&fp=<sha256 hex>&s=<secret>&n=<host name>
   ```

2. The app scans the QR code (or opens the link, e.g. sent over KDE Connect), connects
   to each host in turn, checks the certificate fingerprint and sends
   `{"t":"pair","secret":"…","name":"<device name>","model":"<model>"}`.
3. The helper answers `{"t":"paired","id":"<12 hex>","token":"<64 hex>","name":"<host>"}`
   and stores only the token's SHA-256. The window closes; the secret is single-use.

## Authenticated session

The first frame of every later connection is `{"t":"auth","id":"…","token":"…"}`,
answered by `{"t":"authOk","name":"<host>"}` or `{"t":"authErr","code":"…"}` and a close
(`unknown_device`, `bad_token`, `bad_secret`, `not_pairing`, `expected_auth`).

After `authOk` every frame is a JSON object with a `t` field:

| Direction | Message | Meaning |
| --- | --- | --- |
| shell → phone | `{"t":"hello","v":1,"name":"…","caps":["remote"],"actions":[{id,name,icon,toggle}]}` | Sent on connect and whenever an integration is switched on or off. `icon` is a Material Symbol name; `toggle` actions have an on/off state. |
| shell → phone | `{"t":"state","on":["lock","mediaMode"]}` | The toggle actions that are on. Sent after `hello` and on every change, whatever caused it (the phone, a keybind, the lock timing out). |
| phone → shell | `{"t":"cmd","id":N,"a":"<action id>"}` | Run an action from `actions`. |
| phone → shell | `{"t":"cmd","id":N,"a":"<command>","arg":…}` | A command with an argument (table below). |
| shell → phone | `{"t":"workspaces","active":N,"list":[{id,windows}]}` | cap `workspaces`. Normal workspaces that exist. |
| shell → phone | `{"t":"modes","active":"<id>"\|"","list":[{id,name,icon}]}` | cap `modes`. Empty list when Modes is off. |
| shell → phone | `{"t":"presets","active":"<name>"\|"","list":["<name>",…]}` | cap `presets`. |
| shell → phone | `{"t":"audio","out":id,"in":id,"outputs":[dev],"inputs":[dev],"apps":[dev],"ee":{on,preset,presets}\|null}` | cap `audio`. `dev` is `{id,name,vol,mute}`, `vol` 0–1; ids are PipeWire node ids. |
| shell → phone | `{"t":"ok","id":N}` / `{"t":"err","id":N,"code":"…"}` | `disabled`, `unknown_action`, `locked` (unlocking, or the desktop AOD, while the PC is locked). |
| phone → shell | `{"t":"ping","id":N}` → `{"t":"pong","id":N}` | Round-trip check. |
| shell → phone | `{"t":"deck","list":[{id,name,icon,group,toggle}]}` | cap `deck`. The deck catalog; toggle keys are on while their id is in `state.on`. |
| phone → shell | `{"t":"get","what":"apps"}` → `{"t":"apps","list":[{id,name,icon}]}` | Installed apps, only while the deck picker asks. |
| phone → helper | `{"t":"icons","names":["…"]}` → `{"t":"icons","paths":{name:"<svg path>"}}` | Answered by the helper itself, from the Material Symbols Rounded font (fontconfig). Path data in the 0–960 box, y down, like the official SVGs. Up to 64 names; unknown names are left out. |
| phone → helper | `{"t":"unpair"}` | "Forget this PC": the helper drops the device and closes. |
| shell → phone | `{"t":"unpaired"}` | The PC forgot this phone; the app forgets the PC. |

Topics (`workspaces`, `modes`, `presets`, `audio`) are pushed whole: once when a phone
connects or the integration is switched on, then on every change. Audio is coalesced to
at most one push per 60 ms while a volume is being dragged.

Commands with an argument, answered with `ok` or `err` (`bad_arg`, `not_found`, `disabled`):

| Command | `arg` | Needs |
| --- | --- | --- |
| `workspace` | workspace number, 1–100 | remote |
| `mode` | mode id: toggles it; `""` ends the active mode | remote |
| `preset` | preset name from `presets` (applying one reloads the shell; the phone reconnects) | remote |
| `volume` | `{id, vol}` (0–1) for a device or an app stream | audio |
| `mute` | `{id, mute}` | audio |
| `default` | device id: becomes the default output or input | audio |
| `eePreset` | EasyEffects output preset name | audio |
| `eeBypass` | `true` / `false` | audio |
| `deck` | a deck id: `g:<gesture action>`, `c:<command id>`, `app:<desktop id>`, `discordMute`, `discordDeafen` (`locked`, `unavailable`, `not_found`) | deck |

Actions in `iilink/1`, all toggles:

| Action | On while | Running it while on |
| --- | --- | --- |
| `lock` | the PC is locked | refused (`locked`): unlocking stays with the PC's own authentication |
| `lockAod` | locked with the AOD up | leaves the AOD for the lock screen, still locked |
| `oledSaver` | the desktop AOD is up (not locked) | leaves it; refused while locked |
| `mediaMode` | media mode is open | closes it |
| `scratchpad` | the scratchpad is shown | hides it |

Adding a message never needs a version bump: unknown `t` values are ignored on both
sides. Changing the meaning of an existing one does: that is `iilink/2`, on a new path.

## Helper ↔ shell (stdin/stdout NDJSON)

| Helper → shell | |
| --- | --- |
| `{"ev":"ready","port","fp","name","addrs":[…],"discovery":bool}` | Listening. |
| `{"ev":"peers","list":[{id,name,model,pairedAt,lastSeen}]}` | At start and on every change. |
| `{"ev":"pairing","url","qr":["0101…",…],"expires":ms}` | A pairing window opened. |
| `{"ev":"paired","dev":{id,name,model}}` | Sent after `peers`, before `pairingEnd`. |
| `{"ev":"pairingEnd","reason":"paired"\|"cancel"\|"timeout"}` | |
| `{"ev":"connected","dev","addr","name","model"}` / `{"ev":"disconnected","dev"}` | |
| `{"ev":"msg","dev","m":{…}}` | A message from an authenticated phone. |
| `{"ev":"error","code"?,"msg"}` | E.g. `code: "port"` when the port is taken. |

| Shell → helper | |
| --- | --- |
| `{"op":"pair"}`, `{"op":"pairCancel"}` | |
| `{"op":"unpair","id"}` | Also tells the phone `unpaired` and closes it. |
| `{"op":"send","dev":"<id>"\|"*","m":{…}}` | |
| `{"op":"kick","dev"}` | Close a connection. |

`peers` always comes before `pairingEnd`: the shell keeps the helper alive only while a
phone is paired or a pairing is open, and must never see neither.

The shell also exposes `qs -c ii ipc call iiLink pair|cancelPairing|unpair <id>|status`.
