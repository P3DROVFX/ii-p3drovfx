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
//! has its touchpad open (the keyboard alone while it is a slide clicker).

use std::collections::{HashMap, VecDeque};
use std::io::{Seek, Write};
use std::os::fd::AsFd;
use std::sync::mpsc;
use std::time::{Duration, Instant};

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
const MAX_DELAY_MS: f64 = 40.0;
const REANCHOR_LAG: Duration = Duration::from_millis(120);
const SKIP_LAG: Duration = Duration::from_millis(40);
const MIN_EMIT_GAP: Duration = Duration::from_millis(2);
const INTERP_STEP_GAP: Duration = Duration::from_millis(3);
const MAX_STEP_MM: f64 = 8.0;
const MAX_INTERP_STEPS: usize = 8;

pub enum Cmd {
    /// A phone opened its touchpad: its size in mm. `reply` carries an error back.
    Start { dev: String, w: f64, h: f64, reply: Box<dyn Fn(Value) + Send> },
    /// Every finger down now, `[id, x, y]` with x, y in 0–1. Empty: all lifted.
    /// `ts` is the phone's monotonic uptime in ms, used to replay bursts at their real cadence.
    Frame { dev: String, fingers: Vec<(i64, f64, f64)>, ts: Option<u64> },
    Button { dev: String, button: String, down: bool },
    Text { dev: String, text: String },
    Key { dev: String, key: String, mods: Vec<String> },
    /// A phone opened its slide clicker: the keyboard alone, no touchpad.
    Keys { dev: String, reply: Box<dyn Fn(Value) + Send> },
    Stop { dev: String },
    /// The phone became a screen here (screen.rs): a touchscreen of that many pixels,
    /// which the shell maps onto the output it shows.
    ScreenStart { w: i32, h: i32 },
    /// Every finger on the phone's screen, x and y in 0–1 of the picture.
    ScreenFrame { fingers: Vec<(i64, f64, f64)> },
    /// Typed on the phone's keyboard over its screen: text as is, or one named key.
    ScreenText { text: String },
    ScreenKey { key: String, mods: Vec<String> },
    ScreenStop,
}

pub fn spawn() -> mpsc::Sender<Cmd> {
    let (tx, rx) = mpsc::channel();
    std::thread::Builder::new()
        .name("input".into())
        .spawn(move || run(rx))
        .expect("input thread");
    tx
}

struct InputState {
    owner: String,
    pad: Option<Pad>,
    kbd: Option<Keyboard>,
    // Apart from the touchpad: one phone can be a screen while another is a touchpad.
    screen: Option<Pad>,
    // Its own keyboard, made on the first key: most screens never type.
    screen_kbd: Option<Keyboard>,
    pacer: Pacer,
}

fn run(rx: mpsc::Receiver<Cmd>) {
    let mut st = InputState {
        owner: String::new(),
        pad: None,
        kbd: None,
        screen: None,
        screen_kbd: None,
        pacer: Pacer::new(),
    };
    loop {
        // Drain queued commands first so frames arriving in one burst are paced together.
        loop {
            match rx.try_recv() {
                Ok(cmd) => handle_cmd(cmd, &mut st),
                Err(mpsc::TryRecvError::Empty) => break,
                Err(mpsc::TryRecvError::Disconnected) => return,
            }
        }
        let now = Instant::now();
        if let Some(p) = st.pad.as_mut() {
            st.pacer.emit_due(p, now);
        } else {
            st.pacer.reset(true);
        }
        let cmd = match st.pacer.next_due() {
            Some(due) => {
                let wait = due.saturating_duration_since(Instant::now());
                match rx.recv_timeout(wait) {
                    Ok(cmd) => cmd,
                    Err(mpsc::RecvTimeoutError::Timeout) => continue,
                    Err(mpsc::RecvTimeoutError::Disconnected) => return,
                }
            }
            None => match rx.recv() {
                Ok(cmd) => cmd,
                Err(_) => return,
            },
        };
        handle_cmd(cmd, &mut st);
    }
}

fn handle_cmd(cmd: Cmd, st: &mut InputState) {
    match cmd {
        Cmd::ScreenStart { w, h } => st.screen = Pad::screen(w, h).ok(),
        Cmd::ScreenFrame { fingers } => {
            if let Some(p) = st.screen.as_mut() {
                let _ = p.frame(&fingers);
            }
        }
        Cmd::ScreenText { text } if st.screen.is_some() => {
            if st.screen_kbd.is_none() {
                st.screen_kbd = Keyboard::new().ok();
            }
            if let Some(k) = st.screen_kbd.as_mut() {
                let _ = k.text(&text);
            }
        }
        Cmd::ScreenKey { key, mods } if st.screen.is_some() => {
            if st.screen_kbd.is_none() {
                st.screen_kbd = Keyboard::new().ok();
            }
            if let Some(k) = st.screen_kbd.as_mut() {
                let _ = k.key(&key, &mods);
            }
        }
        Cmd::ScreenStop => {
            st.screen = None;
            st.screen_kbd = None;
        }
        Cmd::Start { dev, w, h, reply } => {
            st.owner = dev;
            st.pad = None;
            st.pacer.reset(true);
            match Pad::new(w, h) {
                Ok(p) => st.pad = Some(p),
                Err(e) => reply(serde_json::json!({"t": "pad", "err": "uinput", "msg": e.to_string()})),
            }
            if st.kbd.is_none() {
                st.kbd = Keyboard::new().ok();
                if st.kbd.is_none() {
                    reply(serde_json::json!({"t": "pad", "err": "keyboard"}));
                }
            }
        }
        Cmd::Keys { dev, reply } => {
            st.owner = dev;
            st.pad = None;
            st.pacer.reset(true);
            if st.kbd.is_none() {
                st.kbd = Keyboard::new().ok();
                if st.kbd.is_none() {
                    reply(serde_json::json!({"t": "present", "err": "keyboard"}));
                }
            }
        }
        Cmd::Frame { dev, fingers, ts } if dev == st.owner => {
            if let Some(p) = st.pad.as_mut() {
                match ts {
                    Some(ts) => st.pacer.push(fingers, ts, Instant::now()),
                    None => {
                        st.pacer.reset(true);
                        let _ = p.frame(&fingers);
                    }
                }
            }
        }
        Cmd::Button { dev, button, down } if dev == st.owner => {
            if let Some(p) = st.pad.as_mut() {
                let _ = p.button(&button, down);
            }
        }
        Cmd::Text { dev, text } if dev == st.owner => {
            if let Some(k) = st.kbd.as_mut() {
                let _ = k.text(&text);
            }
        }
        Cmd::Key { dev, key, mods } if dev == st.owner => {
            if let Some(k) = st.kbd.as_mut() {
                let _ = k.key(&key, &mods);
            }
        }
        Cmd::Stop { dev } if dev == st.owner => {
            st.owner.clear();
            st.pad = None;
            st.kbd = None;
            st.pacer.reset(true);
        }
        _ => {}
    }
}

struct Anchor {
    arrival: Instant,
    ts: u64,
}

struct QueuedFrame {
    fingers: Vec<(i64, f64, f64)>,
    due: Instant,
    finger_change: bool,
}

struct Pacer {
    anchor: Option<Anchor>,
    delay_ms: f64,
    queue: VecDeque<QueuedFrame>,
    last_queued_ids: Vec<i64>,
    last_emitted: Vec<(i64, f64, f64)>,
    min_next_emit: Option<Instant>,
}

impl Pacer {
    fn new() -> Self {
        Self {
            anchor: None,
            delay_ms: 0.0,
            queue: VecDeque::new(),
            last_queued_ids: Vec::new(),
            last_emitted: Vec::new(),
            min_next_emit: None,
        }
    }

    fn reset(&mut self, clear_delay: bool) {
        self.anchor = None;
        if clear_delay {
            self.delay_ms = 0.0;
        }
        self.queue.clear();
        self.last_queued_ids.clear();
        self.last_emitted.clear();
        self.min_next_emit = None;
    }

    fn push(&mut self, fingers: Vec<(i64, f64, f64)>, ts: u64, now: Instant) {
        let was_empty = self.last_queued_ids.is_empty();
        let finger_change = fingers.is_empty() || was_empty || !same_ids(&self.last_queued_ids, &fingers);
        self.last_queued_ids = fingers.iter().map(|f| f.0).collect();

        let new_gesture = was_empty && !fingers.is_empty();
        let due = match self.anchor.as_mut() {
            Some(anchor) if !new_gesture && ts >= anchor.ts => {
                let dt = Duration::from_millis(ts - anchor.ts);
                let expected = anchor.arrival + dt;
                if now < expected {
                    // Anchor arrived with extra network delay; pull it back to the min-latency envelope.
                    if let Some(earlier) = now.checked_sub(dt) {
                        anchor.arrival = earlier;
                    } else {
                        anchor.arrival = now;
                        anchor.ts = ts;
                    }
                    self.delay_ms = (self.delay_ms * 0.98).max(0.0);
                } else {
                    let late = now.duration_since(expected);
                    if late > REANCHOR_LAG {
                        anchor.arrival = now;
                        anchor.ts = ts;
                    } else {
                        let late_ms = late.as_secs_f64() * 1000.0;
                        if late_ms > self.delay_ms {
                            self.delay_ms = (self.delay_ms + 0.35 * (late_ms - self.delay_ms)).min(MAX_DELAY_MS);
                        } else {
                            self.delay_ms = (self.delay_ms - 0.02 * (self.delay_ms - late_ms)).max(0.0);
                        }
                    }
                }
                let dt_anchored = Duration::from_millis(ts.saturating_sub(anchor.ts));
                anchor.arrival + dt_anchored + Duration::from_secs_f64(self.delay_ms / 1000.0)
            }
            _ => {
                self.anchor = Some(Anchor { arrival: now, ts });
                now + Duration::from_secs_f64(self.delay_ms / 1000.0)
            }
        };

        self.queue.push_back(QueuedFrame { fingers, due, finger_change });
        if self.queue.len() > 128 {
            let last = self.queue.pop_back();
            self.queue.retain(|f| f.finger_change);
            if let Some(f) = last {
                self.queue.push_back(f);
            }
        }
    }

    fn next_due(&self) -> Option<Instant> {
        let front = self.queue.front()?;
        Some(match self.min_next_emit {
            Some(min_t) => front.due.max(min_t),
            None => front.due,
        })
    }

    fn emit_due(&mut self, pad: &mut Pad, now: Instant) {
        if let Some(min_t) = self.min_next_emit {
            if now < min_t {
                return;
            }
        }
        // Skip intermediate stale move frames in a behind-schedule burst, preserving finger changes.
        while let Some(front) = self.queue.front() {
            if front.due > now {
                return;
            }
            let skip = !front.finger_change
                && now.saturating_duration_since(front.due) > SKIP_LAG
                && self.queue.get(1).is_some_and(|next| next.due <= now && !next.finger_change);
            if skip {
                self.queue.pop_front();
            } else {
                break;
            }
        }
        let Some(frame) = self.queue.pop_front() else { return };

        let steps = jump_steps(pad, &self.last_emitted, &frame.fingers);
        if steps > 1 {
            let mut interp = Vec::with_capacity(steps - 1);
            for i in 1..steps {
                let t = i as f64 / steps as f64;
                let pts: Vec<(i64, f64, f64)> = self
                    .last_emitted
                    .iter()
                    .map(|&(id, px, py)| {
                        if let Some(&(_, nx, ny)) = frame.fingers.iter().find(|f| f.0 == id) {
                            (id, px + (nx - px) * t, py + (ny - py) * t)
                        } else {
                            (id, px, py)
                        }
                    })
                    .collect();
                interp.push(QueuedFrame {
                    fingers: pts,
                    due: now + INTERP_STEP_GAP * (i - 1) as u32,
                    finger_change: false,
                });
            }
            let first_pts = interp.remove(0).fingers;
            let _ = pad.frame(&first_pts);
            self.last_emitted = first_pts;
            self.queue.push_front(QueuedFrame {
                fingers: frame.fingers,
                due: now + INTERP_STEP_GAP * (steps - 1) as u32,
                finger_change: frame.finger_change,
            });
            for step in interp.into_iter().rev() {
                self.queue.push_front(step);
            }
            self.min_next_emit = Some(now + INTERP_STEP_GAP);
        } else {
            let _ = pad.frame(&frame.fingers);
            self.last_emitted = frame.fingers;
            self.min_next_emit = Some(now + MIN_EMIT_GAP);
        }
    }
}

fn same_ids(prev: &[i64], fingers: &[(i64, f64, f64)]) -> bool {
    prev.len() == fingers.len() && fingers.iter().all(|(id, _, _)| prev.contains(id))
}

fn jump_steps(pad: &Pad, prev: &[(i64, f64, f64)], next: &[(i64, f64, f64)]) -> usize {
    if prev.is_empty() || next.is_empty() {
        return 1;
    }
    let w_mm = pad.max_x as f64 / RES as f64;
    let h_mm = pad.max_y as f64 / RES as f64;
    let mut max_mm = 0.0_f64;
    for &(id, nx, ny) in next {
        if let Some(&(_, px, py)) = prev.iter().find(|f| f.0 == id) {
            let d = ((nx - px) * w_mm).hypot((ny - py) * h_mm);
            if d > max_mm {
                max_mm = d;
            }
        }
    }
    if max_mm <= MAX_STEP_MM {
        1
    } else {
        (max_mm / MAX_STEP_MM).ceil().clamp(2.0, MAX_INTERP_STEPS as f64) as usize
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
    /// A touchscreen (the phone as a screen) rather than a touchpad: no finger-count tools.
    direct: bool,
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
        Ok(Pad { dev, max_x, max_y, slots: HashMap::new(), tracking: 0, direct: false })
    }

    /// A touchscreen as large as the output it stands for, in pixels; Hyprland maps it
    /// there (`hl.device({ name = "ii-tools-screen", output = … })`).
    fn screen(w: i32, h: i32) -> std::io::Result<Pad> {
        let (max_x, max_y) = (w.clamp(16, 16384) - 1, h.clamp(16, 16384) - 1);
        let mut keys = AttributeSet::<KeyCode>::new();
        keys.insert(KeyCode::BTN_TOUCH);
        let mut props = AttributeSet::<PropType>::new();
        props.insert(PropType::DIRECT);
        let axis = |code, max| UinputAbsSetup::new(code, AbsInfo::new(0, 0, max, 0, 0, 0));
        let dev = VirtualDevice::builder()?
            .name("ii tools screen")
            .with_keys(&keys)?
            .with_properties(&props)?
            .with_absolute_axis(&axis(AbsoluteAxisCode::ABS_X, max_x))?
            .with_absolute_axis(&axis(AbsoluteAxisCode::ABS_Y, max_y))?
            .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_MT_SLOT, AbsInfo::new(0, 0, SLOTS - 1, 0, 0, 0)))?
            .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_MT_TRACKING_ID, AbsInfo::new(0, 0, 65535, 0, 0, 0)))?
            .with_absolute_axis(&axis(AbsoluteAxisCode::ABS_MT_POSITION_X, max_x))?
            .with_absolute_axis(&axis(AbsoluteAxisCode::ABS_MT_POSITION_Y, max_y))?
            .build()?;
        Ok(Pad { dev, max_x, max_y, slots: HashMap::new(), tracking: 0, direct: true })
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
        }
        if now != was && !self.direct {
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
