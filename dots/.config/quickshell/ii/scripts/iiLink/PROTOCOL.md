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
  frames carry JSON objects; frames up to 1 MiB, messages up to 8 MiB. The phone stays
  connected in the background (unless the user turns that off) and pings every 60 s; a
  socket silent for 200 s is dropped.
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
| shell → phone | `{"t":"hello","v":1,"name":"…","caps":["remote"],"actions":[{id,name,icon,toggle}],"wake":[{iface,mac,broadcast,wifi}]}` | Sent on connect and whenever an integration is switched on or off. `icon` is a Material Symbol name; `toggle` actions have an on/off state. `wake` (Settings → ii tools → Wake from the phone) is kept by the phone for Wake-on-LAN: a magic packet to each MAC, at its subnet broadcast and 255.255.255.255, ports 9 and 7. |
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
| phone → shell | `{"t":"caps","caps":["calls"]}` | What this phone does for the PC. Sent on connect and when it changes. |
| phone → shell | `{"t":"call","state":"idle"\|"ringing"\|"talking","name":"…"}` | The phone's call state; `name` is the caller as the dialer's notification shows it. The app opens the link itself when a call rings, even in the background, and keeps it until 10 s after the call. |
| shell → phone | `{"t":"phone","a":"answer"\|"end"\|"silence"\|"dial","arg":"<number>"}` | cap `calls` on both sides. No reply: the next `call` is the answer. |
| shell → phone | `{"t":"clip","text":"…"}` / `{"t":"clip","mime":"image/png","data":"<base64>"}` | cap `clip` on both sides. What was just copied on the PC (images up to 5 MiB), and the latest copy when a phone connects. |
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
| `clip` | `{text}`: onto the PC's clipboard (an image comes as a file, purpose `clip`) | clipboard |
| `share` | `{to: "browser"\|"ai"\|"note"\|"reminder"\|"task", text}`. `browser` takes only an `http(s)` link. | share |
| `deck` | a deck id: `g:<gesture action>`, `c:<command id>`, `app:<desktop id>`, `discordMute`, `discordDeafen` (`locked`, `unavailable`, `not_found`) | deck |

## Notifications

Needs `notifs` in the shell's `caps` (Settings → ii tools → Notifications) and in the
phone's. The app opens the link for a burst of notifications and keeps it until 2 min
after the last one; a PC it cannot reach is not retried for 5 min.

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `{"t":"notifs","list":[n]}` | The whole current list, on every connect (once `hello` shows `notifs`). |
| phone → shell | `{"t":"notif","n":n}` | Posted or updated. A new text pops up on the desktop. |
| phone → shell | `{"t":"notifGone","key"}` | Removed on the phone. |
| shell → phone | `{"t":"notifAct","key","a":"dismiss"\|"action"\|"reply","i":N,"text":"…"}` | `i` indexes `n.actions`; `reply` fills the action's free-form RemoteInput. |
| phone → shell | `{"t":"live","p":{…}}` / `{"t":"liveGone","id"}` | A live update while the link is up: the same payload as an `iilive1:` relay, which the app then does not post. |

`n` is `{key, pkg, app, title, text, time, image?, actions?: [{i, label, reply, hint}]}`;
`image` is a base64 JPEG of at most 480 px (a big picture or the sender's photo). App
icons go once per app per PC as files (`purpose: "appIcon"`, name `<package>.png`), kept
in `<state>/icons/`.

## Phone data

Needs `phoneData` in the shell's caps (Settings → ii tools → Phone data); the phone
announces `status` and, with the contacts permission, `contacts`.

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `{"t":"status","battery":{level,charging,plug,temp,health}\|null,"net":{type,signal},"alarm":{at,pkg}\|null}` | On connect, when the next alarm changes (it brings the link up for that) and on battery news while connected (at most every 30 s unless plugging changed). `alarm` goes to PhoneAlarmService, which then stops polling ADB. |
| shell → phone | `{"t":"get","what":"contacts","have":"<hash>"}` | On connect, with the version the PC keeps in `<state>/contacts.json`. |
| phone → shell | `{"t":"contacts","hash","list":[contact]}` | Only when `hash` differs. `contact` is the shape the shell's vCard reader gives (`id, displayName, givenName, familyName, organization, phones[{value,normalized,type}], emails[{value,type}], birthday{year,month,day}`) plus `photo`, the photo's hash or `""`. |
| shell → phone | `{"t":"get","what":"photos","keys":["<photo>",…]}` | The photos the PC lacks; each comes as a file, purpose `contactPhoto`, name `<photo>.jpg`, kept in `<state>/contacts/`. |

## Do Not Disturb and the PC's live activity

| Direction | Message | |
| --- | --- | --- |
| both | `{"t":"dnd","on":bool}` | caps `dnd`. The phone reports its own changes (not those the PC asked for) and its state on connect; the shell tells the phone only when what it should be changes (the shell's DND, or a mode chosen in Settings), never again, so turning the phone's off by hand sticks. |
| shell → phone | `{"t":"pcLive","items":[item]}` | caps `pcLive`. Pushed whole on change, at most twice a second. `item` is `{id, kind: "record"\|"timer"\|"stopwatch"\|"alarm"\|"progress", title, text?, start?, end?, paused?, remaining?, total?, progress?, actions?: [{id, label}]}`; times are epoch ms, so the phone counts by itself. |
| phone → shell | `cmd` `live` with `{id, action}` | A button: `rec` `stop`, `pomodoro` `pause`/`resume`, a countdown's id `pause`/`resume`, `alarm` `snooze`/`stop`. |

## Performance panel

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `{"t":"sub","what":"perf","on":bool}` | caps `perf`. On while the phone's panel is on screen (sent again after a reconnect); a sampler runs only then. |
| shell → phone | `{"t":"perf","cpu":{name,usage,temp,clock,…},"gpu":{name,usage,temp,power,state,vramUsed,vramTotal,…},"ram":{used,total,…},"fps":{active,fps,frametime,…},"gamemode":bool}` | Once a second: the performance HUD's sampler (`perf_monitor.py`), frame rate from MangoHud. |

## The Phone tab's actions

KdeConnectService lists the paired phone as a device, `iitools:<id>`, and sends its
actions here instead of to KDE Connect:

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `{"t":"act","a":"ring"}` | Find my phone: rings at alarm volume (put back after) until "Found it", for at most a minute. |
| shell → phone | `{"t":"act","a":"ping","text"?}` | A notification. |
| shell → phone | `{"t":"act","a":"url","url"}` | `http(s)` only; offered as a notification (a background app may not open screens). |
| shell → phone | `{"t":"act","a":"text","text"}` | Onto the phone's clipboard, with a notification. |
| shell → phone | `sendFile` purpose `share` | Into the phone's Downloads, with a notification that opens it. |

## Media

Needs `media` in the shell's caps (Settings → ii tools → Phone media); the helper is told
with `{"op":"config","media":bool}` and handles these itself: each phone app playing
becomes an MPRIS player, `org.mpris.MediaPlayer2.iitools_<package>`, for as long as its
phone stays connected. The shell never sees these messages.

| Direction | Message | |
| --- | --- | --- |
| phone → helper | `{"t":"media","source":"<package>","app","title","artist","album","playing","position":ms,"length":ms,"rate","volume":0–100,"canPlay","canPause","canNext","canPrevious","canSeek","art"?:"<base64 JPEG>"}` | On every metadata or playback change, and all of them on connect. `art` only with a new track; kept as `<state>/media/<hash>.jpg` for `mpris:artUrl`. |
| phone → helper | `{"t":"mediaGone","source"}` | The session ended: the player goes. |
| helper → phone | `{"t":"mediaCmd","source","a":"play"\|"pause"\|"next"\|"previous"\|"seek"\|"volume","value"?}` | From the MPRIS methods (`seek` in ms, `volume` 0–100). |

## Files

A file is a header, then its bytes as binary frames (the app sends 256 KiB each):

```
{"t":"file","id":N,"name":"photo.jpg","size":S,"purpose":"wallpaper","target":"desktop"|"lock"|"both"}
```

The helper writes the bytes to `<state>/incoming/<dev>-<id>.part` (0600) and, once `size`
bytes arrived, renames it and emits `{"ev":"file","dev","id","path","name","purpose","target"}`.
The shell moves or deletes it and answers `ok` / `err` with the same `id`. The helper
itself refuses with `err`: `bad_arg` (no size), `too_large` (over 64 MiB), `write` (more
bytes than announced, disk error). A new header drops an unfinished file, and so does
the connection closing. One file at a time per phone.

| `purpose` | Needs | The shell |
| --- | --- | --- |
| `share` | `iiTools.share.enable` | moves it to `~/Downloads` under its own name (`name (1).ext` when taken, mode 0644), then `target` `downloads` says so in a notification (Open / Show in folder), `shelf` adds it to the FileShelf, `ai` (images only) attaches it to the AI chat and opens it. |
| `clip` | `iiTools.clipboard.enable` | `wl-copy --type <image mime>` from the file, then deletes it. |
| `contactPhoto` | `iiTools.phoneData.enable` | moves `<photo>.jpg` to `<state>/contacts/`. |
| `appIcon` | — | moves `<package>.png` to `<state>/icons/`, for the notifications. |
| `screenshot` | `iiTools.screenshots.enable` | a phone screenshot: to `~/Pictures/Screenshots/Phone/<name>`, onto the clipboard, and into the screenshot preview. The other way the phone (cap `shots`) saves it to its gallery (Pictures/ii tools) with a notification. |
| `wallpaper` | `iiTools.wallpaper.enable` | moves it to the wallpapers folder as `phone-<date>-<name>`, then `Wallpapers.select` / `selectLockscreen`. `bad_arg` unless the name is an image, `busy` while one is being filed. |

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
| `{"ev":"ready","port","fp","name","addrs":[…],"wake":[{iface,mac,broadcast,wifi}],"discovery":bool}` | Listening. `wake`: the LAN adapters, wired first. |
| `{"ev":"peers","list":[{id,name,model,pairedAt,lastSeen}]}` | At start and on every change. |
| `{"ev":"pairing","url","qr":["0101…",…],"expires":ms}` | A pairing window opened. |
| `{"ev":"paired","dev":{id,name,model}}` | Sent after `peers`, before `pairingEnd`. |
| `{"ev":"pairingEnd","reason":"paired"\|"cancel"\|"timeout"}` | |
| `{"ev":"connected","dev","addr","name","model"}` / `{"ev":"disconnected","dev"}` | |
| `{"ev":"msg","dev","m":{…}}` | A message from an authenticated phone. |
| `{"ev":"fileStart","dev","id","name","size","purpose","target"}` | A file header was accepted; bytes follow. |
| `{"ev":"fileProgress","dev","id","received"}` | At most every 1 % and 150 ms. |
| `{"ev":"fileAbort","dev","id"}` | A file dropped before its end (bad chunk, new header, socket closed). |
| `{"ev":"file","dev","id","path","name","purpose","target"}` | A file arrived whole (see *Files*). |
| `{"ev":"error","code"?,"msg"}` | E.g. `code: "port"` when the port is taken. |

| Shell → helper | |
| --- | --- |
| `{"op":"pair"}`, `{"op":"pairCancel"}` | |
| `{"op":"unpair","id"}` | Also tells the phone `unpaired` and closes it. |
| `{"op":"send","dev":"<id>"\|"*","m":{…}}` | |
| `{"op":"kick","dev"}` | Close a connection. |
| `{"op":"sendFile","dev","id","path","name"?,"purpose","delete"?}` | A file to a phone: the same `file` header and binary frames, the other way. `fileSent` / `fileSendFailed` with the id once queued; `delete` removes the file then. |

`peers` always comes before `pairingEnd`: the shell keeps the helper alive only while a
phone is paired or a pairing is open, and must never see neither.

The shell also exposes `qs -c ii ipc call iiLink pair|cancelPairing|unpair <id>|status`.
