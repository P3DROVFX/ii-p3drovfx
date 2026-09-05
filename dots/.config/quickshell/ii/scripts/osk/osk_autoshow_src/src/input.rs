//! Watches physical input devices so the shell can tell *how* a text field was
//! reached: by finger, by pen, or by mouse/keyboard.
//!
//! The Wayland input-method protocol reports that a text field was focused but not
//! which device caused it, so the QML side correlates an `activate` line with the
//! most recent `touch`/`pen` line to decide whether to raise the keyboard.

use std::collections::HashSet;
use std::path::PathBuf;
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

use evdev::{AbsInfo, AbsoluteAxisCode, Device, EventSummary, KeyCode, PropType};

use crate::emit::emit;

#[derive(Clone, Copy, PartialEq)]
enum Role {
    Touch,
    Pen,
    Mouse,
    Keyboard,
}

impl Role {
    fn label(self) -> &'static str {
        match self {
            Role::Touch => "touch",
            Role::Pen => "pen",
            Role::Mouse => "mouse",
            Role::Keyboard => "key",
        }
    }
}

/// Devices whose events we generated ourselves.
///
/// Reacting to these would make the OSK close itself the moment the user pressed one
/// of its own keys, which is what the name check is for.
///
/// It applies to keyboards and pointers only, and that restriction is the whole point:
/// OpenTabletDriver presents a real graphics tablet as "OpenTabletDriver **Virtual**
/// Artist Tablet", so a blanket name filter threw away the one device this daemon
/// exists to notice. A connected Huion reported no pen at all, and tapping a text field
/// with it did nothing — indistinguishable from the daemon not running. Nothing
/// synthesises a pen or a touchscreen on our behalf, so those two roles are never
/// filtered by name.
fn is_injected(name: &str, role: Role) -> bool {
    if matches!(role, Role::Pen | Role::Touch) {
        return false;
    }
    let name = name.to_ascii_lowercase();
    name.contains("ydotool") || name.contains("virtual") || name.contains("uinput")
}

fn classify(dev: &Device) -> Option<Role> {
    let keys = dev.supported_keys()?;

    if keys.contains(KeyCode::BTN_TOOL_PEN) {
        return Some(Role::Pen);
    }
    // INPUT_PROP_DIRECT distinguishes a touchscreen from a touchpad.
    if keys.contains(KeyCode::BTN_TOUCH) && dev.properties().contains(PropType::DIRECT) {
        return Some(Role::Touch);
    }
    if keys.contains(KeyCode::KEY_A) && keys.contains(KeyCode::KEY_Z) && keys.contains(KeyCode::KEY_SPACE) {
        return Some(Role::Keyboard);
    }
    // A pointer, reported so the shell *can* offer a mouse trigger. Not because
    // clicking into a field should raise a keyboard — it should not — but because
    // without it this daemon is untestable on any machine without a touchscreen, and
    // "nothing happens and nothing says why" is how the feature spent its life. The
    // shell ignores these lines unless the user asks for them.
    if keys.contains(KeyCode::BTN_LEFT) && !dev.properties().contains(PropType::DIRECT) {
        return Some(Role::Mouse);
    }
    None
}

/// Spawns one watcher thread per interesting device, then reports what it found.
///
/// The inventory line is the point of this function's return value. A daemon that can
/// read no input device still binds the input method perfectly happily and still emits
/// `activate` — it simply never emits the `touch` line the shell correlates it with, so
/// the keyboard never rises and nothing anywhere says why. Two causes look identical
/// from the outside and have completely different fixes: no touchscreen on this machine
/// (nothing to do), and /dev/input not readable by this user (join the input group). So
/// both are reported rather than inferred.
pub fn spawn_watchers() -> usize {
    let mut watched = HashSet::new();
    let counts = scan(&mut watched);
    emit(&counts.line());
    let total = counts.total();

    // Devices appear after we start, and not only when someone plugs a tablet in: a
    // driver restarting takes its virtual device away and creates a *new* node for it,
    // and OpenTabletDriver's own daemon may well come up after the shell does. The first
    // version enumerated once and never looked again, so any of those left the pen
    // invisible until the shell was restarted — with nothing saying so.
    //
    // The inventory is re-announced on a slow tick as well as on change, because the
    // shell that reads it can be rebuilt at any moment by a config reload, and a report
    // sent once is a report a reloaded consumer never hears.
    thread::spawn(move || {
        let mut ticks_since_report = 0;
        loop {
            thread::sleep(Duration::from_secs(5));
            let fresh = scan(&mut watched);
            ticks_since_report += 1;
            if fresh != counts_snapshot(&fresh) || ticks_since_report >= 6 {
                ticks_since_report = 0;
                emit(&fresh.line());
            }
        }
    });

    total
}

/// What one pass over /dev/input found.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Inventory {
    touch: usize,
    pen: usize,
    mouse: usize,
    denied: bool,
}

impl Inventory {
    fn line(&self) -> String {
        format!("devices {} {} {}", self.touch, self.pen, self.mouse)
    }
    fn total(&self) -> usize {
        self.touch + self.pen + self.mouse
    }
}

/// The previous inventory, so a rescan can tell "nothing changed" from "something did".
fn counts_snapshot(current: &Inventory) -> Inventory {
    static LAST: Mutex<Option<Inventory>> = Mutex::new(None);
    let mut guard = LAST.lock().unwrap_or_else(|e| e.into_inner());
    let previous = guard.unwrap_or(Inventory { touch: usize::MAX, pen: 0, mouse: 0, denied: false });
    *guard = Some(*current);
    previous
}

/// One pass over the input devices, spawning a watcher for each one not already watched.
fn scan(watched: &mut HashSet<PathBuf>) -> Inventory {
    let mut touch = 0;
    let mut pen = 0;
    let mut mouse = 0;
    let mut denied = false;

    for (path, dev) in evdev::enumerate() {
        let name = dev.name().unwrap_or_default().to_string();

        // Classified before the name is judged: what a device *is* decides whether we
        // could have synthesised it. See is_injected.
        let Some(role) = classify(&dev) else {
            continue;
        };
        if is_injected(&name, role) {
            continue;
        }
        drop(dev);

        // Opened once here rather than trusting enumerate(): a device that enumerates
        // but cannot be opened is exactly the permission case, and the watcher thread
        // would otherwise swallow it into its retry loop forever.
        match Device::open(&path) {
            Ok(_) => match role {
                Role::Touch => touch += 1,
                Role::Pen => pen += 1,
                Role::Mouse => mouse += 1,
                Role::Keyboard => {}
            },
            Err(error) => {
                if error.kind() == std::io::ErrorKind::PermissionDenied {
                    denied = true;
                }
                continue;
            }
        }

        // Counted every pass, but watched only once: a rescan must not stack a second
        // reader on a device that already has one.
        if !watched.insert(path.clone()) {
            continue;
        }

        thread::spawn(move || loop {
            if watch(&path, role).is_err() {
                // Device disappeared (suspend, unplug). Back off and retry so a
                // resumed touchscreen starts reporting again without a restart.
                thread::sleep(Duration::from_secs(2));
            }
        });
    }

    if denied {
        emit("denied");
    }

    Inventory { touch, pen, mouse, denied }
}

fn axis_range(dev: &Device, axis: AbsoluteAxisCode) -> Option<AbsInfo> {
    dev.get_absinfo().ok()?.find(|(code, _)| *code == axis).map(|(_, info)| info)
}

fn normalize(value: i32, info: Option<AbsInfo>) -> f32 {
    let Some(info) = info else {
        return -1.0;
    };
    let span = (info.maximum() - info.minimum()) as f32;
    if span <= 0.0 {
        return -1.0;
    }
    ((value - info.minimum()) as f32 / span).clamp(0.0, 1.0)
}

fn watch(path: &PathBuf, role: Role) -> std::io::Result<()> {
    let mut dev = Device::open(path)?;

    // Multitouch panels report contacts on ABS_MT_*; pens and single-touch panels
    // use plain ABS_X/ABS_Y.
    let (x_axis, y_axis) = if role == Role::Touch && axis_range(&dev, AbsoluteAxisCode::ABS_MT_POSITION_X).is_some() {
        (AbsoluteAxisCode::ABS_MT_POSITION_X, AbsoluteAxisCode::ABS_MT_POSITION_Y)
    } else {
        (AbsoluteAxisCode::ABS_X, AbsoluteAxisCode::ABS_Y)
    };
    let x_info = axis_range(&dev, x_axis);
    let y_info = axis_range(&dev, y_axis);

    let mut x = 0.0f32;
    let mut y = 0.0f32;
    let mut last_key = Instant::now() - Duration::from_secs(1);
    // Bitmask of barrel buttons currently down, so motion is only forwarded while one is.
    let mut held_buttons: u8 = 0;
    let mut moved = false;

    loop {
        for event in dev.fetch_events()? {
            match event.destructure() {
                EventSummary::AbsoluteAxis(_, code, value) if code == x_axis => {
                    x = normalize(value, x_info);
                    moved = true;
                }
                EventSummary::AbsoluteAxis(_, code, value) if code == y_axis => {
                    y = normalize(value, y_info);
                    moved = true;
                }

                // One line per SYN batch while a barrel button is held, and none at all
                // otherwise. A pen reports motion continuously whenever it is anywhere
                // near the tablet; forwarding all of that would be thousands of lines a
                // minute for something the shell only cares about mid-drag.
                EventSummary::Synchronization(_, _, _) => {
                    if held_buttons != 0 && moved {
                        emit(&format!("penmove {x:.4} {y:.4}"));
                    }
                    moved = false;
                }

                EventSummary::Key(_, code, value @ (0 | 1)) => {
                    // The barrel buttons on a stylus, either edge. Reported for both
                    // states because the shell binds press *and* hold to them: holding
                    // one and moving the pen is how a window gets dragged, and a
                    // press-only report cannot express the end of a hold.
                    if code == KeyCode::BTN_STYLUS || code == KeyCode::BTN_STYLUS2 {
                        let index: u8 = if code == KeyCode::BTN_STYLUS { 0 } else { 1 };
                        if value == 1 {
                            held_buttons |= 1 << index;
                        } else {
                            held_buttons &= !(1 << index);
                        }
                        emit(&format!("penbutton {index} {value} {x:.4} {y:.4}"));
                        continue;
                    }

                    if value == 0 {
                        continue;
                    }

                    if role == Role::Keyboard {
                        // A held key repeats; one line per burst is enough to hide the OSK.
                        if last_key.elapsed() >= Duration::from_millis(200) {
                            last_key = Instant::now();
                            emit(role.label());
                        }
                    } else if role == Role::Mouse {
                        if code == KeyCode::BTN_LEFT {
                            // A relative pointer has no absolute position to report, and
                            // -1 is the same "unknown" the axis normaliser already uses.
                            emit("mouse -1 -1");
                        }
                    } else if code == KeyCode::BTN_TOUCH {
                        // Contact down — the position from this same SYN batch is current.
                        emit(&format!("{} {:.4} {:.4}", role.label(), x, y));
                    }
                }
                _ => {}
            }
        }
    }
}
