//! The phone as this PC's touchpad and keyboard (PROTOCOL.md, "Touchpad and keyboard").
//!
//! The touchpad is a multitouch uinput device shaped like a real one (absolute MT slots,
//! the phone's size in millimetres as its resolution), so libinput gives it everything a
//! laptop touchpad gets: tap to click, two-finger scroll, three and four-finger gestures,
//! the user's acceleration and natural-scroll settings. It needs write access to
//! /dev/uinput (the `input` group); without it the phone is told so.
//!
//! The keyboard is Wayland's virtual keyboard: each character gets a keycode in a keymap
//! of our own (re-sent when a new one appears), so any text types right whatever the
//! layout, as wtype does.
//!
//! Both live on one thread of their own, fed by a channel, and exist only while a phone
//! has its touchpad open.

use std::collections::HashMap;
use std::io::{Seek, Write};
use std::os::fd::AsFd;
use std::sync::mpsc;
use std::time::Instant;

use evdev::uinput::VirtualDevice;
use evdev::{AbsInfo, AbsoluteAxisCode, AttributeSet, EventType, InputEvent, KeyCode, PropType, UinputAbsSetup};
use serde_json::Value;
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_keyboard::KeyState, wl_registry, wl_seat::WlSeat};
use wayland_client::{Connection, Dispatch, EventQueue, QueueHandle};
use wayland_protocols_misc::zwp_virtual_keyboard_v1::client::{
    zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1, zwp_virtual_keyboard_v1::ZwpVirtualKeyboardV1,
};

/// Units per millimetre on the virtual touchpad.
const RES: i32 = 40;
const SLOTS: i32 = 5;

pub enum Cmd {
    /// A phone opened its touchpad: its size in mm. `reply` carries an error back.
    Start { dev: String, w: f64, h: f64, reply: Box<dyn Fn(Value) + Send> },
    /// Every finger down now, `[id, x, y]` with x, y in 0–1. Empty: all lifted.
    Frame { dev: String, fingers: Vec<(i64, f64, f64)> },
    Button { dev: String, button: String, down: bool },
    Text { dev: String, text: String },
    Key { dev: String, key: String, mods: Vec<String> },
    Stop { dev: String },
}

pub fn spawn() -> mpsc::Sender<Cmd> {
    let (tx, rx) = mpsc::channel();
    std::thread::Builder::new()
        .name("input".into())
        .spawn(move || run(rx))
        .expect("input thread");
    tx
}

fn run(rx: mpsc::Receiver<Cmd>) {
    let mut owner = String::new();
    let mut pad: Option<Pad> = None;
    let mut kbd: Option<Keyboard> = None;
    for cmd in rx {
        match cmd {
            Cmd::Start { dev, w, h, reply } => {
                owner = dev;
                pad = None;
                match Pad::new(w, h) {
                    Ok(p) => pad = Some(p),
                    Err(e) => reply(serde_json::json!({"t": "pad", "err": "uinput", "msg": e.to_string()})),
                }
                if kbd.is_none() {
                    kbd = Keyboard::new().ok();
                    if kbd.is_none() {
                        reply(serde_json::json!({"t": "pad", "err": "keyboard"}));
                    }
                }
            }
            Cmd::Frame { dev, fingers } if dev == owner => {
                if let Some(p) = pad.as_mut() {
                    let _ = p.frame(&fingers);
                }
            }
            Cmd::Button { dev, button, down } if dev == owner => {
                if let Some(p) = pad.as_mut() {
                    let _ = p.button(&button, down);
                }
            }
            Cmd::Text { dev, text } if dev == owner => {
                if let Some(k) = kbd.as_mut() {
                    let _ = k.text(&text);
                }
            }
            Cmd::Key { dev, key, mods } if dev == owner => {
                if let Some(k) = kbd.as_mut() {
                    let _ = k.key(&key, &mods);
                }
            }
            Cmd::Stop { dev } if dev == owner => {
                owner.clear();
                pad = None;
                kbd = None;
            }
            _ => {}
        }
    }
}

// ── Touchpad ─────────────────────────────────────────────────────────────

struct Pad {
    dev: VirtualDevice,
    max_x: i32,
    max_y: i32,
    /// finger id → slot.
    slots: HashMap<i64, i32>,
    tracking: i32,
}

impl Pad {
    fn new(w_mm: f64, h_mm: f64) -> std::io::Result<Pad> {
        let max_x = ((w_mm.clamp(20.0, 400.0)) * RES as f64) as i32;
        let max_y = ((h_mm.clamp(20.0, 400.0)) * RES as f64) as i32;
        let mut keys = AttributeSet::<KeyCode>::new();
        for k in [
            KeyCode::BTN_LEFT,
            KeyCode::BTN_RIGHT,
            KeyCode::BTN_MIDDLE,
            KeyCode::BTN_TOUCH,
            KeyCode::BTN_TOOL_FINGER,
            KeyCode::BTN_TOOL_DOUBLETAP,
            KeyCode::BTN_TOOL_TRIPLETAP,
            KeyCode::BTN_TOOL_QUADTAP,
            KeyCode::BTN_TOOL_QUINTTAP,
        ] {
            keys.insert(k);
        }
        let mut props = AttributeSet::<PropType>::new();
        props.insert(PropType::POINTER);
        let axis = |code, max| UinputAbsSetup::new(code, AbsInfo::new(0, 0, max, 0, 0, RES));
        let dev = VirtualDevice::builder()?
            .name("ii tools touchpad")
            .with_keys(&keys)?
            .with_properties(&props)?
            .with_absolute_axis(&axis(AbsoluteAxisCode::ABS_X, max_x))?
            .with_absolute_axis(&axis(AbsoluteAxisCode::ABS_Y, max_y))?
            .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_MT_SLOT, AbsInfo::new(0, 0, SLOTS - 1, 0, 0, 0)))?
            .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_MT_TRACKING_ID, AbsInfo::new(0, 0, 65535, 0, 0, 0)))?
            .with_absolute_axis(&axis(AbsoluteAxisCode::ABS_MT_POSITION_X, max_x))?
            .with_absolute_axis(&axis(AbsoluteAxisCode::ABS_MT_POSITION_Y, max_y))?
            .build()?;
        Ok(Pad { dev, max_x, max_y, slots: HashMap::new(), tracking: 0 })
    }

    fn frame(&mut self, fingers: &[(i64, f64, f64)]) -> std::io::Result<()> {
        let abs = |code: AbsoluteAxisCode, v: i32| InputEvent::new(EventType::ABSOLUTE.0, code.0, v);
        let key = |code: KeyCode, v: bool| InputEvent::new(EventType::KEY.0, code.0, v as i32);
        let mut ev = Vec::with_capacity(16);
        let was = self.slots.len();

        // Lifted fingers free their slots.
        let ids: Vec<i64> = fingers.iter().map(|f| f.0).collect();
        let gone: Vec<i64> = self.slots.keys().filter(|id| !ids.contains(id)).copied().collect();
        for id in gone {
            let slot = self.slots.remove(&id).unwrap();
            ev.push(abs(AbsoluteAxisCode::ABS_MT_SLOT, slot));
            ev.push(abs(AbsoluteAxisCode::ABS_MT_TRACKING_ID, -1));
        }
        let mut first = None;
        for &(id, x, y) in fingers.iter().take(SLOTS as usize) {
            let px = (x.clamp(0.0, 1.0) * self.max_x as f64) as i32;
            let py = (y.clamp(0.0, 1.0) * self.max_y as f64) as i32;
            let slot = match self.slots.get(&id) {
                Some(&s) => {
                    ev.push(abs(AbsoluteAxisCode::ABS_MT_SLOT, s));
                    s
                }
                None => {
                    let Some(s) = (0..SLOTS).find(|s| !self.slots.values().any(|v| v == s)) else { continue };
                    self.slots.insert(id, s);
                    self.tracking = (self.tracking + 1) % 65535;
                    ev.push(abs(AbsoluteAxisCode::ABS_MT_SLOT, s));
                    ev.push(abs(AbsoluteAxisCode::ABS_MT_TRACKING_ID, self.tracking));
                    s
                }
            };
            ev.push(abs(AbsoluteAxisCode::ABS_MT_POSITION_X, px));
            ev.push(abs(AbsoluteAxisCode::ABS_MT_POSITION_Y, py));
            if first.is_none() || slot == 0 {
                first = Some((px, py));
            }
        }
        let now = self.slots.len();
        if now != was {
            ev.push(key(KeyCode::BTN_TOUCH, now > 0));
            for (n, k) in [
                (1, KeyCode::BTN_TOOL_FINGER),
                (2, KeyCode::BTN_TOOL_DOUBLETAP),
                (3, KeyCode::BTN_TOOL_TRIPLETAP),
                (4, KeyCode::BTN_TOOL_QUADTAP),
                (5, KeyCode::BTN_TOOL_QUINTTAP),
            ] {
                ev.push(key(k, now == n));
            }
        }
        if let Some((px, py)) = first {
            ev.push(abs(AbsoluteAxisCode::ABS_X, px));
            ev.push(abs(AbsoluteAxisCode::ABS_Y, py));
        }
        self.dev.emit(&ev)
    }

    fn button(&mut self, button: &str, down: bool) -> std::io::Result<()> {
        let code = match button {
            "right" => KeyCode::BTN_RIGHT,
            "middle" => KeyCode::BTN_MIDDLE,
            _ => KeyCode::BTN_LEFT,
        };
        self.dev.emit(&[InputEvent::new(EventType::KEY.0, code.0, down as i32)])
    }
}

// ── Keyboard ─────────────────────────────────────────────────────────────

struct Wl;

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for Wl {
    fn event(_: &mut Self, _: &wl_registry::WlRegistry, _: wl_registry::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<WlSeat, ()> for Wl {
    fn event(_: &mut Self, _: &WlSeat, _: <WlSeat as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwpVirtualKeyboardManagerV1, ()> for Wl {
    fn event(_: &mut Self, _: &ZwpVirtualKeyboardManagerV1, _: <ZwpVirtualKeyboardManagerV1 as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwpVirtualKeyboardV1, ()> for Wl {
    fn event(_: &mut Self, _: &ZwpVirtualKeyboardV1, _: <ZwpVirtualKeyboardV1 as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

struct Keyboard {
    conn: Connection,
    _queue: EventQueue<Wl>,
    kb: ZwpVirtualKeyboardV1,
    /// Keysym names, in keycode order (keycode = index + 9).
    syms: Vec<String>,
    start: Instant,
}

const SHIFT: u32 = 1;
const CTRL: u32 = 4;
const ALT: u32 = 8;
const SUPER: u32 = 64;

impl Keyboard {
    fn new() -> Result<Keyboard, Box<dyn std::error::Error>> {
        let conn = Connection::connect_to_env()?;
        let (globals, queue) = registry_queue_init::<Wl>(&conn)?;
        let qh = queue.handle();
        let seat: WlSeat = globals.bind(&qh, 1..=7, ())?;
        let manager: ZwpVirtualKeyboardManagerV1 = globals.bind(&qh, 1..=1, ())?;
        let kb = manager.create_virtual_keyboard(&seat, &qh, ());
        let mut k = Keyboard { conn, _queue: queue, kb, syms: Vec::new(), start: Instant::now() };
        k.upload()?;
        k._queue.roundtrip(&mut Wl)?;
        Ok(k)
    }

    /// The keymap: one keycode per keysym asked for so far.
    fn upload(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let mut map = String::from("xkb_keymap {\nxkb_keycodes \"(unnamed)\" {\nminimum = 8;\n");
        map += &format!("maximum = {};\n", self.syms.len() + 9 + 1);
        for i in 0..self.syms.len() {
            map += &format!("<K{i}> = {};\n", i + 9);
        }
        map += "};\nxkb_types \"(unnamed)\" { include \"complete\" };\nxkb_compatibility \"(unnamed)\" { include \"complete\" };\nxkb_symbols \"(unnamed)\" {\n";
        for (i, s) in self.syms.iter().enumerate() {
            map += &format!("key <K{i}> {{[{s}]}};\n");
        }
        map += "};\n};\n";
        let bytes = map.into_bytes();
        let path = std::env::temp_dir().join(format!("ii_link_keymap_{}", std::process::id()));
        let mut f = std::fs::OpenOptions::new().read(true).write(true).create(true).truncate(true).open(&path)?;
        let _ = std::fs::remove_file(&path);
        f.write_all(&bytes)?;
        f.write_all(&[0])?;
        f.rewind()?;
        // 1: XKB_V1.
        self.kb.keymap(1, f.as_fd(), bytes.len() as u32 + 1);
        self.conn.flush()?;
        Ok(())
    }

    fn code(&mut self, sym: &str) -> Result<u32, Box<dyn std::error::Error>> {
        if let Some(i) = self.syms.iter().position(|s| s == sym) {
            return Ok(i as u32 + 1);
        }
        self.syms.push(sym.to_string());
        self.upload()?;
        // wl keycodes are evdev ones: the XKB keycode minus 8.
        Ok(self.syms.len() as u32)
    }

    fn time(&self) -> u32 {
        self.start.elapsed().as_millis() as u32
    }

    fn press(&mut self, sym: &str, mods: u32) -> Result<(), Box<dyn std::error::Error>> {
        let code = self.code(sym)?;
        if mods != 0 {
            self.kb.modifiers(mods, 0, 0, 0);
        }
        let t = self.time();
        self.kb.key(t, code, KeyState::Pressed.into());
        self.kb.key(t + 1, code, KeyState::Released.into());
        if mods != 0 {
            self.kb.modifiers(0, 0, 0, 0);
        }
        self.conn.flush()?;
        Ok(())
    }

    fn text(&mut self, text: &str) -> Result<(), Box<dyn std::error::Error>> {
        for c in text.chars() {
            let sym = match c {
                '\n' => "Return".to_string(),
                '\t' => "Tab".to_string(),
                c if c.is_control() => continue,
                c => format!("U{:04X}", c as u32),
            };
            self.press(&sym, 0)?;
        }
        Ok(())
    }

    fn key(&mut self, key: &str, mods: &[String]) -> Result<(), Box<dyn std::error::Error>> {
        // Only names XKB knows, so the keymap can never fail to compile.
        const NAMED: &[&str] = &[
            "Return", "BackSpace", "Tab", "Escape", "Delete", "Insert", "Home", "End", "Page_Up", "Page_Down",
            "Left", "Right", "Up", "Down", "space", "Print", "Menu", "Super_L",
            "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
            "XF86AudioPlay", "XF86AudioNext", "XF86AudioPrev", "XF86AudioMute", "XF86AudioRaiseVolume", "XF86AudioLowerVolume",
        ];
        let sym = if NAMED.contains(&key) {
            key.to_string()
        } else {
            let mut chars = key.chars();
            match (chars.next(), chars.next()) {
                (Some(c), None) if !c.is_control() => format!("U{:04X}", c.to_lowercase().next().unwrap_or(c) as u32),
                _ => return Ok(()),
            }
        };
        let mut mask = 0;
        for m in mods {
            mask |= match m.as_str() {
                "shift" => SHIFT,
                "ctrl" => CTRL,
                "alt" => ALT,
                "super" => SUPER,
                _ => 0,
            };
        }
        self.press(&sym, mask)
    }
}
