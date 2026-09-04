//! Reports text-field focus changes so the Quickshell on-screen keyboard can raise
//! itself when a touchscreen or pen user taps into a text field.
//!
//! Binds `zwp_input_method_v2` purely as an observer: it never grabs the keyboard
//! and never commits text, so key events reach applications exactly as before.
//! Actual typing is still done by the shell through ydotool.
//!
//! Output protocol, one event per line on stdout:
//!   activate            a text field gained focus
//!   deactivate          the focused text field went away
//!   touch <x> <y>       finger contact, coordinates normalized to 0..1
//!   pen <x> <y>         pen contact, coordinates normalized to 0..1
//!   mouse -1 -1         a left click on a relative pointer; ignored unless asked for
//!   key                 a press on a physical keyboard
//!   devices <t> <p> <m> how many touch, pen and pointer devices could be opened
//!   denied              at least one input device could not be opened for permissions
//!   unavailable         another input method holds the seat; the daemon exits

mod emit;
mod input;

use emit::emit;
use wayland_client::protocol::{wl_registry, wl_seat};
use wayland_client::{delegate_noop, Connection, Dispatch, QueueHandle};
use wayland_protocols_misc::zwp_input_method_v2::client::{
    zwp_input_method_manager_v2::ZwpInputMethodManagerV2,
    zwp_input_method_v2::{self, ZwpInputMethodV2},
};

#[derive(Default)]
struct App {
    seat: Option<wl_seat::WlSeat>,
    manager: Option<ZwpInputMethodManagerV2>,
    /// Applied state, mirroring what the compositor last committed.
    active: bool,
    /// Staged state; `activate`/`deactivate` only take effect on `done`.
    pending_active: bool,
}

impl Dispatch<wl_registry::WlRegistry, ()> for App {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        let wl_registry::Event::Global { name, interface, version } = event else {
            return;
        };

        match interface.as_str() {
            "wl_seat" => {
                state.seat = Some(registry.bind(name, version.min(7), qh, ()));
            }
            "zwp_input_method_manager_v2" => {
                state.manager = Some(registry.bind(name, 1, qh, ()));
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwpInputMethodV2, ()> for App {
    fn event(
        state: &mut Self,
        _: &ZwpInputMethodV2,
        event: zwp_input_method_v2::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            zwp_input_method_v2::Event::Activate => state.pending_active = true,
            zwp_input_method_v2::Event::Deactivate => state.pending_active = false,

            zwp_input_method_v2::Event::Done => {
                if state.pending_active != state.active {
                    state.active = state.pending_active;
                    emit(if state.active { "activate" } else { "deactivate" });
                }
            }

            zwp_input_method_v2::Event::Unavailable => {
                emit("unavailable");
                std::process::exit(0);
            }
            _ => {}
        }
    }
}

delegate_noop!(App: ignore wl_seat::WlSeat);
delegate_noop!(App: ignore ZwpInputMethodManagerV2);

fn main() {
    input::spawn_watchers();

    let conn = Connection::connect_to_env().expect("no Wayland display");
    let mut queue = conn.new_event_queue();
    let qh = queue.handle();
    conn.display().get_registry(&qh, ());

    let mut app = App::default();
    queue.roundtrip(&mut app).expect("registry roundtrip failed");

    let manager = app.manager.clone().expect("compositor does not support zwp_input_method_manager_v2");
    let seat = app.seat.clone().expect("no wl_seat");
    // Held for the process lifetime; dropping it would release the input method.
    let _input_method = manager.get_input_method(&seat, &qh, ());

    while queue.blocking_dispatch(&mut app).is_ok() {}
}
