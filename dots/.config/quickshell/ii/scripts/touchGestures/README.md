# Touchscreen Gestures Helper (`touch_gestures`)

Helper passivo para observação e reconhecimento de gestos em telas touchscreen no `ii-p3drovfx`.

## Visão Geral

- **Backend:** `evdev` (Linux input subsystem)
- **Modo:** Observador passivo (não realiza `grab` do dispositivo, permitindo que as aplicações continuem recebendo eventos de touch normalmente)
- **Dispositivos suportados:** Telas touchscreen físicas (`INPUT_PROP_DIRECT` + `BTN_TOUCH`)
- **Dispositivos ignorados:** Touchpads, mouses, teclados e emuladores virtuais (`ydotool`, `uinput`, etc.)
- **Protocolo:** JSON Lines (JSONL) via `stdout`

## Build & Instalação

```bash
~/.config/quickshell/ii/scripts/rust-helpers.sh build touch_gestures
```

O script compila, instala com `mv` (sobrescrever o binário em execução falha com
`ETXTBSY`) e grava em `.touch_gestures.stamp` o hash do código que originou o
binário — é assim que a shell e o atualizador percebem, depois de uma atualização,
que o daemon ficou para trás (`rust-helpers.sh status`).

## Permissões

O binário precisa de permissão de leitura para `/dev/input/event*` (normalmente pertencente ao grupo `input`).
Se o seu usuário não tiver acesso, adicione-o ao grupo `input`:

```bash
sudo usermod -aG input $USER
```

E reinicie a sessão.

## Protocolo JSONL


Eventos emitidos pelo helper:

- `ready`: `{"type":"ready","version":1}`
- `device_added`: `{"type":"device_added","deviceId":"...","name":"...","path":"/dev/input/eventX","kind":"touch"}`
- `device_removed`: `{"type":"device_removed","deviceId":"..."}`
- `touch_down`: `{"type":"touch_down","deviceId":"...","contactId":0,"x":0.05,"y":0.5,"time":12345678}`
- `touch_move`: `{"type":"touch_move","deviceId":"...","contactId":0,"x":0.2,"y":0.5,"time":12345679}`
- `touch_up`: `{"type":"touch_up","deviceId":"...","contactId":0,"x":0.35,"y":0.5,"time":12345680}`
- `status`: `{"type":"status","code":"no_touchscreen"}`
- `error`: `{"type":"error","code":"permission_denied","message":"..."}`

Notas:

- `kind` é `"pen"` para canetas/digitalizadores (`BTN_TOOL_PEN`/`BTN_STYLUS`) e `"touch"` para dedos. A shell usa isso para decidir se a caneta pode acionar gestos.
- `contactId` é o slot MT (`ABS_MT_SLOT`), não o `ABS_MT_TRACKING_ID`. O tracking id é zerado para `-1` antes do `SYN_REPORT` que encerra o contato, então usá-lo faria o `touch_up` chegar com um id diferente do `touch_down` correspondente.
