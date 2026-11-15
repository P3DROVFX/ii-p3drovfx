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
| phone → shell | `{"t":"get","what":"appIcons","icons":["…"]}` → `{"t":"appIcon","name":"…","png":"<base64>"}` | cap `appIcons` (with `deck`). Up to 32 icon theme names or file paths per request; rendered to 96×96 PNG in the active icon theme, cached in `~/.cache/quickshell/iilink/appicons/` and sent one message per resolved icon (unknown names are skipped). |
| phone → helper | `{"t":"icons","names":["…"]}` → `{"t":"icons","paths":{name:"<svg path>"}}` | Answered by the helper itself, from the Material Symbols Rounded font (fontconfig). Path data in the 0–960 box, y down, like the official SVGs. Up to 64 names; unknown names are left out. |
| phone → shell | `{"t":"sub","what":"focus","on":true}` → `{"t":"focus","class":"firefox","open":["firefox","kitty"]}` | cap `deckFocus` (with `deck`). Deck profiles: the phone subscribes only while its deck is on screen and has a folder bound to apps (or one is being edited). `class` is the focused window's Wayland app id (`""` when none), `open` the classes of every window; pushed on change, held 120 ms so a focus move does not bounce the deck. The phone matches the class (case-insensitive) against the folders' `match` lists, which live on the phone. |
| shell → phone | `{"t":"handoff","url":"https://…","title","artist","app","position":ms}` | cap `handoff` (phone) with `pcMedia`. The PC locked while a web page played (`xesam:url`, http/https only); the phone posts a notification that opens the page at `position` (YouTube `t=`, Twitch `t=`, Vimeo `#t=`) and pauses the PC's player with `cmd pcMedia {a:"pause"}`. `pcMedia` also carries `url`, so the phone's media card has a "Continue on phone" button any time. Off with `iiTools.handoff.onLock`. |
| shell → phone | file, purpose `wallSync` (name = hash of the wallpaper path) | Cap `wallSync` (phone, off by default: "Use the PC's wallpaper"). The desktop wallpaper as a JPEG of at most 3840 px (a video's first frame), made once per image (`<state>/wallsync/`), sent when the wallpaper changes and when such a phone connects. The phone centre-crops it to its screen and sets it as home and lock wallpaper (`SET_WALLPAPER`), skipping a name it already applied. `iiTools.wallSync.enable` turns the sending off. |
| phone → shell | `media` gains `"url":"https://…"` | Only when the phone's app gives the track a web page (an http(s) `METADATA_KEY_MEDIA_URI`/`MEDIA_ID`, or a Spotify track/episode URI turned into its open.spotify.com page). The helper publishes it as `xesam:url` on the phone's MPRIS player; the phone tab's media card then shows *Continue on PC*, which opens the page at the playing position (`IiLinkService.continueOnPc`) and pauses the phone. |
| phone → shell | `{"t":"get","what":"wallpaper"}` → file, purpose `wallSave` | Cap `wallSave` (shell, with `iiTools.wallSync.enable`). The app's *Save the PC's wallpaper* button: the same 3840 px JPEG as `wallSync`, uncropped, filed by the phone in Pictures/ii tools so the user can crop or move it. `{"t":"err","code":"unavailable"}` when it cannot be made. |
| shell → phone | `{"t":"display","monitor","brightness":0–1\|-1,"floor","night":bool,"temp":K,"auto":bool}` | cap `display` (with `remote`). The focused monitor's brightness (`Brightness`: backlight or DDC/CI; -1 when it cannot be read; `floor` is the lowest the shell allows) and the night light. Pushed whole on change (≤ 16/s) only after `sub display`, which the phone sends while the remote screen is open. Commands: `cmd brightness` (arg 0–1), `cmd night` (arg bool, a manual toggle like the quick toggle), `cmd nightTemp` (arg 1200–6500 K, writes `light.night.colorTemperature`). |
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
| `clipPull` | `"<cliphist id>"`: decodes that entry and sends it in `clip` to the phone, without copying to the PC (`locked`, `too_large`, `not_found`) | clipHistory |
| `clipCopyPc` | `"<cliphist id>"`: copies that entry to the PC's current clipboard (`locked`, `not_found`) | clipHistory |
| `share` | `{to: "browser"\|"ai"\|"note"\|"reminder"\|"task", text}`. `browser` takes only an `http(s)` link. | share |
| `deck` | a deck id: `g:<gesture action>`, `c:<command id>`, `app:<desktop id>`, `discordMute`, `discordDeafen` (`locked`, `unavailable`, `not_found`) | deck |

## Clipboard history

Needs `clipHistory` in the shell's `caps` (`iiTools.clipboard.enable` and `iiTools.clipboard.history` both on). Refuses any entry or action with `err` (`locked`) while the lock screen is active.

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `{"t":"get","what":"clipHistory","offset":0,"limit":50}` | Answer: `{"t":"clipHistory","offset":0,"total":N,"list":[{"id":"<cliphist id>","text":"<preview, max 200 chars>","image":bool,"pinned":bool}]}` — pinned first in the shell's pinned order, then newest first. |
| phone → shell | `{"t":"get","what":"clipThumbs","ids":[…]}` | Up to 24 ids per request. Answer: one `{"t":"clipThumb","id","png":"<base64 ≤160px>"}` per image entry, rendered in one batch and cached in `~/.cache/quickshell/iilink/clipthumbs/<id>.png` (pruned when the id leaves history). |
| phone → shell | `{"t":"sub","what":"clipHistory","on":bool}` | Subscribe (`on: true`) while the history screen is visible; unsubscribe (`on: false` or `unsub`) when leaving. |
| shell → phone | `{"t":"clipHistoryChanged"}` | Pushed (debounced 1 s) when entries or pins change, only while subscribed and unlocked. |
| phone → shell | `cmd` `clipPull` / `clipCopyPc` | `clipPull` decodes the entry and sends `{"t":"clip",…}` to the phone with no echo back to the PC; `clipCopyPc` makes it the PC's current clipboard (`Cliphist.copy`). |

## Notifications

Needs `notifs` in the shell's `caps` (Settings → ii tools → Notifications) and in the
phone's. Announcing `notifFilter` alongside `notifs` opts into the per-app filter list.
The app opens the link for a burst of notifications and keeps it until 2 min
after the last one; a PC it cannot reach is not retried for 5 min.

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `{"t":"notifs","list":[n]}` | The whole current list, on every connect (once `hello` shows `notifs`), when the phone's notification access comes up after the link, and when asked. |
| shell → phone | `{"t":"get","what":"notifs"}` | Whenever a phone starts mirroring (its `caps` gain `notifs`, or the shell reloaded). |
| phone → shell | `{"t":"notif","n":n}` | Posted or updated. A new text pops up on the desktop. |
| phone → shell | `{"t":"notifGone","key"}` | Removed on the phone, or dropped when its app is blocked. |
| shell → phone | `{"t":"notifAct","key","a":"dismiss"\|"action"\|"reply","i":N,"text":"…"}` | `i` indexes `n.actions`; `reply` fills the action's free-form RemoteInput. |
| phone → shell | `{"t":"notifApps","list":[{"pkg":"…","name":"…","blocked":false}]}` | Seen apps (newest first) plus anything blocked, on connect when `hello` includes `notifFilter` and debounced (≤1/s) on changes. Any unsent `appIcon` is queued too. |
| shell → phone | `{"t":"notifFilter","pkg":"…","blocked":true}` | Block or unblock one package on the phone (persisted on the phone; blocking drops its mirrored notifications via `notifGone`). |
| phone → shell | `{"t":"live","p":{…}}` / `{"t":"liveGone","id"}` | A live update while the link is up: the same payload as an `iilive1:` relay, which the app then does not post. |

`n` is `{key, pkg, app, title, text, time, image?, avatar?, actions?: [{i, label, reply, hint}]}`;
`image` is content, a base64 JPEG of at most 480 px (a big picture, or a large icon that
is not square: a video thumbnail); `avatar` is a person, at most 128 px (a square large
icon, or the last message's sender in a chat), shown as the group's icon. App
icons go once per app per PC as files (`purpose: "appIcon"`, name `<package>.png`), kept
in `<state>/icons/`.

## Phone data

Needs `phoneData` in the shell's caps (Settings → ii tools → Phone data); the phone
announces `status` and, with the contacts permission, `contacts`.

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `{"t":"status","battery":{level,charging,plug,temp,health}\|null,"net":{type,signal},"ringer":"normal"\|"vibrate"\|"silent","alarm":{at,pkg}\|null}` | On connect, when the next alarm changes (it brings the link up for that), on battery news while connected (at most every 30 s unless plugging changed), and when the ringer mode or the network type changes while connected. The Modes `phone` trigger reads `battery`, `net` and `ringer` from it. `alarm` goes to PhoneAlarmService, which then stops polling ADB. |
| shell → phone | `{"t":"get","what":"contacts","have":"<hash>"}` | On connect, with the version the PC keeps in `<state>/contacts.json`. |
| phone → shell | `{"t":"contacts","hash","list":[contact]}` | Only when `hash` differs. `contact` is the shape the shell's vCard reader gives (`id, displayName, givenName, familyName, organization, phones[{value,normalized,type}], emails[{value,type}], birthday{year,month,day}`) plus `photo`, the photo's hash or `""`. |
| shell → phone | `{"t":"get","what":"photos","keys":["<photo>",…]}` | The photos the PC lacks; each comes as a file, purpose `contactPhoto`, name `<photo>.jpg`, kept in `<state>/contacts/`. |

## Phone usage (screen time)

Needs `usage` in the shell's `caps` (`iiTools.usage.enable`, off by default) and `usage` in the phone's `caps` (enabled in the app with `PACKAGE_USAGE_STATS` granted).

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `{"t":"get","what":"phoneUsage","since":"YYYY-MM-DD"}` | Sent on connect (once `caps` include `usage`), when the usage app opens, and when the clock app's Bedtime tab opens. `since` is the newest day the PC already has (re-sends that day), or empty/oldest if none. |
| phone → shell | `{"t":"phoneUsage","days":[{"date":"YYYY-MM-DD","apps":[{"pkg":"…","name":"…","h":[24 ints]}],"sessions":[[startMs,endMs],…]}]}` | Daily foreground seconds per hour (`h` = 24 ints, 0–3600 per hour) per package (launchers, SystemUI, and ii tools itself omitted) and screen-interactive `[startMs, endMs]` intervals of that day. Max 30 days back. Sent on connect when the shell's `hello.caps` includes `usage`, on `get phoneUsage`, and for today on `ACTION_SCREEN_OFF` (runtime receiver while enabled, debounced at most once per 10 minutes). |

The shell stores each day in `<state>/phone_usage/<date>.json`, keeps 60 days, and reads days on demand. Launcher icons for phone apps use the existing `launcherIcons` capability (`get` `launcherIcons`).

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

## The PC's media

The other way: the shell's active player as a media player on the phone (its lock screen
and Quick Settings). Needs `pcMedia` in both caps (Settings → ii tools → PC media on the
phone; the app's own switch). The phone's own players (`iitools_` buses) are never sent.

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `{"t":"pcMedia","on":true,"id":"<bus>","app","title","artist","album","playing","position":ms,"length":ms,"rate","canPlay","canPause","canNext","canPrevious","canSeek","art":"<md5>","track":"<md5>"}` | On change (coalesced 150 ms) and on connect; `{"t":"pcMedia","on":false}` when nothing plays. The position is only re-sent when it jumps (a seek): the phone runs the clock from `position`, `playing` and `rate`. |
| shell → phone | `sendFile` purpose `pcMediaArt`, name `<md5>` | The cover, once per image per connection; `art` names it. |
| phone → shell | `cmd` `pcMedia`, arg `{"a":"play"\|"pause"\|"toggle"\|"next"\|"previous"\|"seek","value"?:ms}` | The phone's buttons. `unsupported` for a seek the player cannot do. |

### The PC's lyrics

The phone's Media Mode shows the lyrics the shell already fetched for the PC's player
(`LyricsService`). Needs `pcLyrics` in the phone's caps, which the shell offers together with
`pcMedia`. The shell sends them only while the phone watches, and holds `LyricsService` open
for as long as a phone does.

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `cmd` `pcLyrics`, arg `{"a":"watch","on":true\|false}` | Media Mode opened or closed. The phone asks again after a reconnect. |
| shell → phone | `{"t":"pcLyrics","track":"<md5>","state":"synced"\|"plain"\|"instrumental"\|"searching"\|"none","source","offset":ms,"lines":[{"ms","end"?,"text","words"?:[{"ms","end","text"}]}],"plain"?}` | `track` is the same id as in `pcMedia` (`track`), so the phone drops lyrics that belong to another song. `lines` comes with `synced` (word timing when the source has it, each word keeping its trailing space), `plain` with `plain`. `offset` is the shell's own sync nudge (`background.mediaMode.lyricsOffsetMs`). Resent on any change. |

## The shell's look

The desktop wallpaper behind the phone's PC card. Needs `look` in the phone's caps and
*Settings → ii tools → Wallpaper on phone* (`iiTools.look.enable`).

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `sendFile` purpose `look`, name `<md5>` | A JPEG of the wallpaper at most 1080 px wide (a video's first frame), made once per wallpaper (`<stateDir>/look`), sent once per image per connection, before the topic. |
| shell → phone | `{"t":"look","wall":"<md5>"}` | After the file, and again when the wallpaper changes. The phone keeps the last image for when the PC is away. |

## Drawing pad

The phone as a drawing pad for live draw (cap `draw` in the shell's hello, while live
draw is on; Settings → ii tools → Drawing pad). The pad stands for the focused screen and
takes its shape (`aspect`). Strokes go through live draw's own surface
(`LiveDraw.remoteStroke`), so smoothing, tools, the eraser and undo are the PC's.

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `{"t":"draw","a":"start"}` / `{"t":"draw","a":"stop"}` | The pad opened (live draw opens, pen down) / closed (live draw closes, the ink stays; also when the phone disconnects). |
| shell → phone | `{"t":"draw","open","tool","eraser","color","width","palette":[…],"aspect","canUndo","canRedo"}` | The pen as the PC uses it, on start and on every change while the pad is open. `{"t":"draw","err":"disabled"}` when off. |
| phone → shell | `{"t":"draw","s":"down"\|"move"\|"up","p":[[x,y,pressure],…]}` | A stroke, x and y in 0–1 of the focused screen; `move` carries every sample since the last (the touch history). Pressure is the stylus's, 1 for a finger. With the eraser on, the points rub out instead. |
| phone → shell | `{"t":"draw","a":"tool","tool":"pen"\|"highlighter"\|"laser"\|"eraser"}`, `{"a":"color","color"}`, `{"a":"width","width"}`, `{"a":"undo"\|"redo"\|"clear"\|"close"}` | The pad's toolbar. |

## Presenter

The phone as a slide clicker (cap `present` in the shell's hello; Settings → ii tools →
Presenter, told to the helper with `{"op":"config","present":bool}`). Its keys are typed
by the helper's virtual keyboard into whatever has focus, so any presentation app follows;
the laser is a dot the shell draws over the focused screen (`PresenterLaser.qml`, an
Overlay surface with no input, mapped only while the dot shows).

| Direction | Message | |
| --- | --- | --- |
| phone → helper, shell | `{"t":"present","a":"start"}` / `{"t":"present","a":"stop"}` | The screen opened (the helper makes the virtual keyboard, no touchpad) / closed (also when the phone disconnects). |
| shell → phone | `{"t":"present","aspect":w/h}` | The focused screen's shape, for the laser pad. |
| phone → helper | `{"t":"present","key":"Left"\|"Right"\|"Page_Up"\|"Page_Down"\|"Home"\|"End"\|"F5"\|"Escape"\|"b"\|"w"}` | One key; anything else is dropped. The volume keys send Left and Right. |
| phone → shell | `{"t":"present","laser":[x,y]}` / `{"t":"present","laser":null}` | The laser at x, y (0–1 of the screen focused when it went down) on every touch event / off. |
| helper → phone | `{"t":"present","err":"disabled"\|"keyboard"}` | Off in Settings / the compositor has no virtual keyboard. |

## Second screen

The phone as a monitor (cap `screen` in the shell's hello; Settings → ii tools → Phone as a
monitor, `iiTools.screen`). **USB only for now:** the video does not ride the link but a
plain socket the helper binds on 127.0.0.1, which `adb reverse` brings to the phone. The
shell (`PhoneScreenService`) finds the phone in `adb devices -l` (a USB entry, by model),
makes the output (extend: `hyprctl output create headless II-PHONE` at the phone's size
times `res`, `fps` and `scale`, placed against the screen that had focus on the chosen
`side`, centred, or the next free side; mirror: the focused screen) and maps the
helper's touchscreen (`ii-tools-screen`) onto it with `hl.device`, again after a config
reload. Whatever it made goes when the session ends.

| Direction | Message | |
| --- | --- | --- |
| phone → shell | `{"t":"screen","a":"start","mode":"extend"\|"mirror","w":px,"h":px,"res":1\|0.75\|0.5,"fps":30\|60\|90\|120,"scale":1\|1.25\|1.5\|2,"side":"left"\|"right"\|"above"\|"below","bitrate":Mbps}` | `w`×`h`: the phone's whole display, held sideways. The phone's settings; mirror uses only the bitrate. |
| phone → shell | `{"t":"screen","a":"monitors"}` → `{"t":"screen","monitors":[{"name","label","w","h","focused"}]}` | The PC's screens, for mirror's choice (`"output"` in `start`, `""` for the focused one). |
| phone → shell | `{"t":"screen","a":"switch","output":name\|"next"}` | Mirror another screen without stopping: the capture starts again there (`{"op":"screen","a":"output","output"}` to the helper) and the phone gets `state: "size"` with `w`, `h`, `output`. |
| phone → shell | `{"t":"screen","a":"draw"}` | The floating toolbar: focus the phone's output and toggle live draw there. |
| shell → phone | `{"t":"screen","state":"starting"\|"ready"\|"live"\|"stopped","port"?,"token"?,"w"?,"h"?,"mode"?,"encoder"?,"reason"?}` | `ready` carries the port to connect to on 127.0.0.1 and the one-time token; `w`×`h` is the picture. |
| shell → phone | `{"t":"screen","err":"disabled"\|"adb"\|"usb"\|"unauthorized"\|"busy"\|"encoder"\|"timeout"\|"output"\|"bind"\|"encoder_exit"}` | `adb`: no adb on the PC; `usb`: the phone is not on USB with debugging; `unauthorized`: debugging not allowed for this PC. |
| phone → shell | `{"t":"screen","a":"stop"}` | Leaving the picture ends it. |

Helper ops: `{"op":"screen","a":"start","dev","sid","output","token","w","h","bitrate"}` /
`{"op":"screen","a":"stop"}`; events `{"ev":"screen","dev","sid","port"}`,
`{"ev":"screenLive","dev","sid","encoder"}` (`nvenc`, `vaapi` or `x264`) and
`{"ev":"screenEnd","dev","sid","reason"}`.

On the socket (screen.rs): the phone sends the token and `\n`, then touch frames `[1][n]`
and n × `[u8 id][u16 x][u16 y]` (every finger down, 0–65535 of the picture), typed text
`[2][u16 n][utf-8]` and named keys `[3][u8 n][name][u8 mods]` (1 shift, 2 ctrl, 4 alt,
8 super) for a keyboard of its own the helper makes on the first key. The PC sends
`[u32 length][u8 kind][u64 pts µs][Annex-B H.264]`, kind 0 the SPS/PPS, 1 a frame, 2 a key
frame. wf-recorder captures and encodes (FLV out, one tag per frame); a still screen
sends nothing. The phone has 60 s to connect; the session ends when the socket closes.

## Touchpad and keyboard

The phone as this PC's touchpad and keyboard (cap `touchpad` in the shell's hello;
Settings → ii tools → Touchpad and keyboard, told to the helper with
`{"op":"config","touchpad":bool}`). The helper handles these itself, on an input thread:
the shell never sees them.

| Direction | Message | |
| --- | --- | --- |
| phone → helper | `{"t":"pad","a":"start","w":mm,"h":mm}` | The touchpad screen opened: a uinput multitouch touchpad of that size (40 units/mm, 5 slots, BTN_LEFT/RIGHT/MIDDLE) and a Wayland virtual keyboard. libinput then gives it the user's touchpad settings and gestures. Again on a resize. |
| phone → helper | `{"t":"pad","f":[[id,x,y],…]}` | Every finger down, x and y in 0–1; `[]` when all are lifted. Sent on every touch event. |
| phone → helper | `{"t":"pad","btn":"left"\|"right"\|"middle","down":bool}` | The on-screen buttons. |
| phone → helper | `{"t":"kbd","text":"…"}` | Typed as is, any character: each gets a keycode in the virtual keyboard's own keymap (as wtype does), so the PC's layout does not matter. |
| phone → helper | `{"t":"kbd","key":"Return"\|"BackSpace"\|"Left"\|…\|"a","mods":["ctrl","alt","super","shift"]}` | A named key (XKB names from a fixed list) or one character, with modifiers. |
| phone → helper | `{"t":"pad","a":"stop"}` | The screen closed; both devices go. Also when the phone disconnects. |
| helper → phone | `{"t":"pad","err":"uinput"\|"keyboard"\|"disabled","msg"?}` | `uinput`: no write access to /dev/uinput (the `input` group); the keyboard still works. |

## Files on the phone

The phone's storage in the PC's file manager, as with KDE Connect (cap `files` on both
sides; Settings → ii tools → Phone files). The phone runs an SFTP server (Apache SSHD)
only while asked; the link carries what sshfs needs, so nothing is guessed or trusted
on the LAN.

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `{"t":"files","a":"start"}` | Start (or keep) the server and issue a new password. |
| phone → shell | `{"t":"files","port","user":"iitools","password","hostKey":"ecdsa-sha2-nistp256 AAAA…","paths":["/storage/emulated/0",…],"names":[…]}` | The shell writes `[addr]:port hostKey` to `<state>/files_known_hosts` and mounts `sshfs -o password_stdin,StrictHostKeyChecking=yes,UserKnownHostsFile=…` at `$XDG_RUNTIME_DIR/ii-tools/<phone name>`, then `gio open`s the first path. |
| phone → shell | `{"t":"files","err":"permission"\|"disabled"\|"no_storage"\|"failed"}` | `permission`: the phone also shows a notification that opens *All files access*. |
| shell → phone | `{"t":"files","a":"stop"}` | The PC let go. The server also stops when the link drops; the shell unmounts (`fusermount3 -uz`) when the phone disconnects. |

The host key is the phone's own (EC P-256, made once, in the app's private files); the
password is 168 random bits, new on every start, checked by hash in constant time. The
server listens on the first free port of 1739–1764 and serves `/` with only the storage
volumes reachable (KDE Connect's `NativeStorageFileSystemFactory`).

## Gallery

The phone's photos and videos on the PC, read only (nothing is ever deleted or changed
from the PC; cap `gallery` on both sides: the shell puts it in `hello.caps` while
`iiTools.gallery.enable` is on, and the phone puts it in `caps` while its Gallery switch
is on and it holds `READ_MEDIA_IMAGES` or `READ_MEDIA_VISUAL_USER_SELECTED`; without
`READ_MEDIA_VIDEO` it lists no videos).

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `{"t":"gallery","a":"albums"}` | Answer: `{"t":"gallery","a":"albums","list":[{"id":"<bucket id>","name","count","cover":<item id>}]}` — one per `BUCKET_ID` with images and videos, newest first (by its newest item). |
| shell → phone | `{"t":"gallery","a":"list","req":N,"album":""\|"<bucket id>","before":{"taken":ms,"id":id}\|null,"n":200}` | Answer: `{"t":"gallery","a":"list","req":N,"album","items":[item],"more":bool}`. Newest first (`ORDER BY taken DESC, id DESC`); `before` is an exclusive keyset cursor. `n` at most 500 (default 200); `req` is echoed so stale answers are dropped. |
| shell → phone | `{"t":"gallery","a":"thumbs","ids":[…]}` | Up to 128 ids. Replaces the phone's pending thumbnail queue (any upload in flight finishes). Each thumbnail arrives as a file (`purpose: "galleryThumb"`, `<id>.jpg`, 256×256 JPEG quality 80). Missing ids answer `{"t":"gallery","a":"gone","ids":[…]}`. |
| shell → phone | `{"t":"gallery","a":"get","id":N}` | Full image as a file (`purpose: "galleryFull"`, `<id>.<ext>`): JPEG/PNG/WebP/GIF as stored; anything else (HEIC/HEIF/AVIF/DNG…) decoded honoring orientation to JPEG quality 92 (`<id>.jpg`). Queued ahead of thumbnails. Refusals: `{"t":"gallery","a":"get","id":N,"err":"video"\|"too_large"\|"not_found"\|"read"}` (`video`: opened over SFTP instead; `too_large`: over 64 MiB). |
| phone → shell | `{"t":"gallery","a":"new","items":[item]}` / `{"t":"gallery","a":"gone","ids":[…]}` / `{"t":"gallery","a":"changed"}` | Live `ContentObserver` updates on images and videos, debounced 1.5 s. `changed` covers bulk changes without URIs (the shell re-reads the first page). |
| phone → shell | `{"t":"gallery","err":"disabled"\|"permission"}` | Reply to any gallery request when the phone's switch is off or media permission is missing. |

`item` is `{id, kind: "image"|"video", name, mime, w, h, size, taken, dur, album, path}`:
`id` is MediaStore `_ID` (unique across images and videos); `taken` is ms (`DATE_TAKEN` if
`> 0`, else `DATE_MODIFIED * 1000`); `dur` is ms (`0` for images); `w`/`h` are display
dimensions (swapped when `ORIENTATION` is 90 or 270); `album` is `<bucket id>`; `path` is
the phone's absolute path (`DATA`), used to open videos through the SFTP mount.

## Webcam

The phone's camera as a PC webcam: a v4l2loopback device (`/dev/videoN`, every app lists it) or, with no loopback module, a PipeWire camera node (`iiTools.camera.output`: `auto`, `v4l2`, `pipewire`; cap `camera` on both sides: the shell puts it in `hello.caps` while `iiTools.camera.enable` is on, and the phone puts it in `caps` while it has a camera). Live camera controls reuse `lens`, `aspect`, `quality`, `torch`, `zoom`, and `stabilize` as reported by the phone.

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `{"t":"camera","a":"request"}` | Ask the phone to start the webcam stream (starts immediately if foregrounded/running, else posts a notification). |
| shell → phone | `{"t":"camera","a":"stop"}` | Stop asking or stop the active stream. |
| shell → phone | `{"t":"camera","a":"set",…}` | Change any subset of `lens` (`"front"`\|`"wide"`\|`"main"`\|`"tele"`), `aspect` (`"4:3"`\|`"16:9"`), `quality` (`"720p"`\|`"1080p"`), `torch` (bool), `zoom` (float), `stabilize` (bool), `mirror` (bool). Phone applies it and pushes `status`. |
| shell → phone | `{"t":"camera","state":"ready","token":"<hex 32>","sid":N,"usb":bool}` | Answer to `start`: helper is armed and waiting for the camera socket. `usb`: the phone is on a USB cable and the shell ran `adb reverse` of the link's port, so the phone connects to 127.0.0.1 first (Wi-Fi jitters by tens of ms), then the link's own host. |
| shell → phone | `{"t":"camera","state":"live","device":"/dev/videoN","sid":N}` | `ffmpeg` is writing decoded frames into `/dev/videoN`. |
| shell → phone | `{"t":"camera","state":"stopped","reason":"…","sid":N}` | PC side ended (`stopped`, `closed`, `timeout`, `decoder`, `device`). |
| shell → phone | `{"t":"camera","err":"disabled"\|"deps"\|"device"\|"busy"}` | `start` refused on the PC side. |
| phone → shell | `{"t":"camera","a":"start","w":1440,"h":1080,"fps":30}` | Phone is about to stream (`w`×`h` encoded landscape size). |
| phone → shell | `{"t":"camera","a":"stop"}` | Phone stopped streaming. |
| phone → shell | `{"t":"camera","status":{…}}` | Phone camera capabilities and state (`state`, `error`, `lens`, `lenses`, `aspect`, `quality`, `w`, `h`, `fps`, `zoom`, `zoomMin`, `zoomMax`, `torch`, `hasTorch`, `stabilize`, `mirror`, `rotation`), pushed after `hello` and on every change. |
| phone → shell | `{"t":"camera","asking":bool,"reason"?}` | Whether the phone is waiting for the user to confirm the PC's `request` (a notification; it expires after a minute). `asking:false` with `reason:"notifications"`: the app's notifications are off, so the user has to open the webcam on the phone. |

The H.264 stream travels over a second WebSocket to `/iilink/1/camera` on the helper port (same pinned TLS certificate): the phone authenticates with `{"t":"hello","token":"<token>"}`, sends metadata `{"t":"meta","w":1440,"h":1080,"rot":0\|90\|180\|270,"fps":30,"mirror":bool}` (`mirror`: the phone's own switch; with ii tools the PC adds none, its sidebar switch sets the phone's), and streams binary frames `[u8 kind][u64 pts µs BE][Annex-B bytes]` (`kind` 0 = codec config, 1 = frame, 2 = key frame; helper requests key frames with `{"t":"key"}`), which the helper pipes into `ffmpeg` toward `/dev/videoN`.

## Wireless mirroring radio keep-awake

Needs `mirrorRadio` in both caps (always announced by the shell; enabled by default on the phone, controllable in Settings → Connection and PC link).

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `{"t":"mirror","on":bool}` | `true` when any wireless scrcpy session starts (mirror, embed, record, or app window), `false` when the last one ends. Resent if `on` when the link reconnects and `caps` arrive. |

While `on` is `true`, the phone holds `WIFI_MODE_FULL_LOW_LATENCY` (plus a `WIFI_MODE_FULL_HIGH_PERF` fallback lock) and sends a tiny UDP keep-awake datagram (`iim\n`, 4 bytes) every 50 ms to the PC link host on its UDP discovery port (`helper.port`) until `on:false`, link loss, or a 3 h safety timeout. Because the datagram does not start with `iilink?`, the helper's discovery listener silently ignores it without logging or replying.

## Files

A file is a header, then its bytes as binary frames (the app sends 256 KiB each):

```
{"t":"file","id":N,"name":"photo.jpg","size":S,"purpose":"wallpaper","target":"desktop"|"lock"|"both"}
```

The helper writes the bytes to `<state>/incoming/<dev>-<id>.part` (0600) and, once `size`
bytes arrived, renames it and emits `{"ev":"file","dev","id","path","name","purpose","target"}`.
The shell moves or deletes it and answers `ok` / `err` with the same `id`. The helper
itself refuses with `err`: `bad_arg` (no size, or an invalid gallery name), `too_large`
(over 64 MiB), `write` (more bytes than announced, disk error). A new header drops an
unfinished file, and so does the connection closing. One file at a time per phone (the
phone serializes uploads).

| `purpose` | Needs | The shell |
| --- | --- | --- |
| `share` | `iiTools.share.enable` | moves it to `~/Downloads` under its own name (`name (1).ext` when taken, mode 0644), then `target` `downloads` says so in a notification (Open / Show in folder), `shelf` adds it to the FileShelf, `ai` (images only) attaches it to the AI chat and opens it. |
| `clip` | `iiTools.clipboard.enable` | converts to `image/png` if needed, runs `wl-copy --type image/png`, then deletes it. |
| `contactPhoto` | `iiTools.phoneData.enable` | moves `<photo>.jpg` to `<state>/contacts/`. |
| `appIcon` | — | moves `<package>.png` to `<state>/icons/`, for the notifications. |
| `launcherIcon` | — | moves `<package>.png` (192 px, full bleed: an adaptive icon's safe zone fills it, unmasked) to `~/.cache/quickshell/phone_app_icons/iitools_<dev>/`, the Android Apps page's cache, which masks it to the chosen shape. Asked with `{"t":"get","what":"launcherIcons","pkgs":[…]}` (up to 64 per message; cap `launcherIcons`) for the listed apps that have none. |
| `screenshot` | `iiTools.screenshots.enable` | a phone screenshot: to `~/Pictures/Screenshots/Phone/<name>`, onto the clipboard, and into the screenshot preview. The other way the phone (cap `shots`) saves it to its gallery (Pictures/ii tools) with a notification. |
| `wallpaper` | `iiTools.wallpaper.enable` | moves it to the wallpapers folder as `phone-<date>-<name>`, then `Wallpapers.select` / `selectLockscreen`. `bad_arg` unless the name is an image, `busy` while one is being filed. |
| `galleryThumb` | `iiTools.gallery.enable` | handled by the helper itself (never emitted as `fileStart`/`file`): validates `^[0-9]{1,19}\.jpg$`, writes to `$XDG_CACHE_HOME/quickshell/phone_gallery/<dev>/thumbs/<name>` (default `~/.cache`, dirs 0700, files 0600, via `.part` + rename), replies `{"t":"ok","id"}`, and coalesces ids into `galleryThumbs` (at most every 100 ms per phone, flushed on disconnect). |
| `galleryFull` | `iiTools.gallery.enable` | handled by the helper itself (never emitted as `fileStart`/`file`): validates `^[0-9]{1,19}\.(jpg\|jpeg\|png\|webp\|gif)$`, writes to `$XDG_CACHE_HOME/quickshell/phone_gallery/<dev>/full/<name>` (dirs 0700, files 0600, via `.part` + rename), replies `{"t":"ok","id"}`, and emits `galleryProgress`, `galleryFile`, or `galleryAbort`. |

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
| `{"ev":"galleryThumbs","dev","ids":[…]}` | Coalesced `galleryThumb` item ids (numbers), at most every 100 ms per phone and flushed on disconnect. |
| `{"ev":"galleryProgress","dev","id","received","size"}` | `galleryFull` progress (`id` is the item id), at most every 1 % and 150 ms. |
| `{"ev":"galleryFile","dev","id","path"}` | A `galleryFull` file landed in the gallery cache (`id` is the item id). |
| `{"ev":"galleryAbort","dev","id"}` | A `galleryFull` transfer dropped before its end (`id` is the item id). |
| `{"ev":"camera","dev","sid","token"}` | Helper armed a camera session and generated a one-time socket token. |
| `{"ev":"cameraLive","dev","sid","w","h","sink"}` | The camera is up: the writer started on the first key frame (`w`×`h` the session's size after rotation; `sink` `v4l2` or `pipewire`). Once per session. |
| `{"ev":"cameraEnd","dev","sid","reason"}` | Camera helper session ended once per armed session (`stopped`\|`closed`\|`timeout`\|`decoder`\|`device`). |
| `{"ev":"error","code"?,"msg"}` | E.g. `code: "port"` when the port is taken. |

| Shell → helper | |
| --- | --- |
| `{"op":"pair"}`, `{"op":"pairCancel"}` | |
| `{"op":"unpair","id"}` | Also tells the phone `unpaired`, closes it, and removes `<cache>/quickshell/phone_gallery/<id>/`. |
| `{"op":"send","dev":"<id>"\|"*","m":{…}}` | |
| `{"op":"kick","dev"}` | Close a connection. |
| `{"op":"sendFile","dev","id","path","name"?,"purpose","delete"?}` | A file to a phone: the same `file` header and binary frames, the other way. `fileSent` / `fileSendFailed` with the id once queued; `delete` removes the file then. |
| `{"op":"camera","a":"arm","dev","sid","device":"/dev/videoN","mirror":bool,"rotate":0\|90\|180\|270}` or `{…,"sink":"pipewire"}` | Arm a session (one at a time; a new one ends the old with `stopped`). v4l2: `ffmpeg -f h264 -i pipe:0 … -f v4l2 <device>`; a size the device refuses (an app holds it) is scaled and padded into the old one. PipeWire: `gst-launch-1.0 fdsrc ! rawvideoparse ! videoconvert ! pipewiresink mode=provide` with `media.class=Video/Source`, `media.role=Camera`, node `ii-tools-camera`. `rotate` adds to the phone's `rot`. Two stages: the decoder (`ffmpeg`, H.264 → raw I420 at the session's size, turned, mirrored, fitted) restarts on any picture change; the writer (the device or the node) stays open the whole session and repeats the last picture every 200 ms while none comes, so the camera never vanishes. The first picture fixes the size; a later aspect or turn is fitted into it. A dropped socket has 20 s to reconnect with the same token (the phone retries by itself); `{"t":"bye"}` on the socket ends at once. |
| `{"op":"camera","a":"config","mirror":bool,"rotate":0\|90\|180\|270}` | Update `ffmpeg` mirror/rotation live (restarts `ffmpeg`). |
| `{"op":"camera","a":"stop"}` | Stop the armed/running camera helper session. |
| `{"op":"mic","a":"arm","dev","sid"}` / `{"op":"mic","a":"stop"}` | The phone's microphone session (see Microphone). |

`peers` always comes before `pairingEnd`: the shell keeps the helper alive only while a
phone is paired or a pairing is open, and must never see neither.

The shell also exposes `qs -c ii ipc call iiLink pair|cancelPairing|unpair <id>|status`.

## Microphone

The phone as a PC microphone: a PipeWire source `ii-tools-mic` ("ii tools microphone", `media.class=Audio/Source`) that every app lists and `PhoneMicService` / EasyEffects take as an input. Cap `mic` on both sides: the shell puts it in `hello.caps` while `iiTools.mic.enable` is on, the phone puts it in `caps` while it has a microphone. `iiTools.mic.useDroidcam` keeps the old scrcpy / DroidCam backends instead.

The audio is raw PCM, not a codec: 48 kHz mono `s16le` is 768 kbit/s, nothing for Wi-Fi or a cable, and no encoder or decoder adds a frame of delay. It travels like the webcam's video: a second WebSocket on the link's port at `/iilink/1/mic`, authenticated by a one-time token from a shell `arm`. The first text message is `{"t":"hello","token":"…"}`, then `{"t":"meta","rate":48000}` (8000–48000), then binary messages of whole 16-bit samples (the phone sends 20 ms each). `{"t":"bye"}` ends the session at once. A dropped socket has 20 s to reconnect with the same token; the source stays up, silent, meanwhile. The helper queues about 240 ms for `pw-cat` and drops the rest, so a stalled reader costs a click and never a growing delay. The source appears with the first chunk and goes away with the session.

| Direction | Message | |
| --- | --- | --- |
| shell → phone | `{"t":"mic","a":"request"}` | Ask the phone to start (starts at once with its Mic screen open, else posts a notification). |
| shell → phone | `{"t":"mic","a":"stop"}` | Stop asking or stop the stream. |
| shell → phone | `{"t":"mic","state":"ready","token":"<hex 32>","sid":N}` | Answer to `start`: the helper is armed and waits for the socket. |
| shell → phone | `{"t":"mic","state":"live","sid":N}` | The source exists and audio is flowing into it. |
| shell → phone | `{"t":"mic","state":"stopped","reason":"…","sid":N}` | PC side ended (`stopped`, `closed`, `timeout`, `device`). |
| shell → phone | `{"t":"mic","err":"disabled"\|"busy"}` | `start` refused on the PC side. |
| phone → shell | `{"t":"mic","a":"start"}` | The phone is about to stream. |
| phone → shell | `{"t":"mic","a":"stop"}` | The phone stopped. |
| phone → shell | `{"t":"mic","err":"permission"\|"mic"\|"network"\|"offline"\|"timeout"}` | The phone could not start or lost the stream; the shell shows it and ends the session. |
| phone → shell | `{"t":"mic","status":{"state","error","muted","rate"}}` | Pushed after `hello` and on every change. |
| phone → shell | `{"t":"mic","asking":bool,"reason"?}` | As the webcam's: the phone waits for the user to confirm the PC's `request`; `reason:"notifications"` when it cannot ask. |

Helper op: `{"op":"mic","a":"arm","dev","sid"}` arms a session (one at a time; a new one ends the old with `stopped`) and answers `{"ev":"mic","dev","sid","token"}`; `{"op":"mic","a":"stop"}` ends it. Events: `micLive` (`rate`) at the first chunk, `micEnd` (`reason`) exactly once. The source is `pw-cat --playback --raw` into a node, so there is no kernel module, no null sink and nothing for the shell to route.

## Routines: the shell's actions for the phone, and the phone's for the shell

Needs `remote` in the shell's caps; the shell announces `modeActions`, the phone `ctl`.

| Direction | Message | Meaning |
|---|---|---|
| phone → shell | `{"t":"get","what":"modeActions"}` | Asks for the catalog of Modes & Routines actions (the app asks on every `hello`, and keeps the last answer so rules can be edited with the PC off). |
| shell → phone | `{"t":"modeActions","list":[{id,label,icon,category,categoryLabel,form,choices?}]}` | The registry of the shell's own Modes actions, minus those that would hand the phone a shell (`shell`, `launch`, `closeApps`, `hyprland`, `file`, `wallpaper`, `suspend`, EasyEffects…) and those not available on this machine. `form` says how the value is entered: `none`, `switch` (bool), `choice` (`choices: [{v,l}]`), `percent` (0–100), `kelvin`, `volume` (`{level,muted}`), `workspace` (`{action:"go",target,back}`), `text`. `mode` and `routine` are `choice` with the ids (a bare id; `""` stops the active mode). |
| phone → shell | `{"t":"cmd","id":n,"a":"modeAction","arg":{"type":"brightness","value":40}}` | Runs one action exactly as a mode would (`Modes.applyActions`); `{type, value}` is a mode's action verbatim. Replies `ok`, or `err` with `unavailable` / `failed` / `unknown_action`. |
| shell → phone | `{"t":"act","a":"ctl","kind":"dnd"\|"ringer"\|"volume"\|"torch"\|"brightness"\|"rotate"\|"media"\|"notify"\|"speak"\|"vibrate"\|"ring",…}` | What the PC's routines do on the phone (the Modes "Phone control" action). Fields by kind: `dnd{on}`, `ringer{mode}`, `volume{stream:"media"\|"ring"\|"alarm"\|"call",level}`, `torch{on}`, `brightness{level}`/`{auto:true}`, `rotate{auto}`, `media{cmd}`, `notify{title,text}`, `speak{text}`, `vibrate{ms}`. Skipped when the phone lacks the permission (brightness and rotation need "change system settings", silent needs Do Not Disturb access) or the user turned the feature off (cap `ctl` is then not announced). |

