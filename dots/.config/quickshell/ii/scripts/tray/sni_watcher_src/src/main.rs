//! sni_watcher — a StatusNotifierWatcher that outlives the shell.
//!
//! Tray icons vanish on a shell restart because the watcher lives inside the
//! shell: stopping it drops the `org.kde.StatusNotifierWatcher` bus name, and
//! the instance that takes the name back starts with an empty item list. The
//! protocol has no way to tell a client that its watcher changed, so what
//! happens next is up to each app. Chromium (so every Electron app) re-registers
//! when the name gets a new owner, and tears its icon down for good if that call
//! fails; Steam, Go clients and older Electron never look again and are simply
//! gone. Either way the user restarts the app to get the icon back.
//!
//! Keeping the name owned by a process that does not restart removes the event
//! entirely: no client ever learns that the shell went away. Quickshell only
//! claims the name when it is free and otherwise acts as a plain host against
//! whoever holds it, so it needs no change to work with this.
//!
//! The name is requested *queued*: if a shell already owns it, ownership passes
//! here the moment that shell exits, with no gap in between. Whenever ownership
//! is gained, the bus is swept for items that are still alive but were
//! registered with the previous watcher, so nothing is lost in that handover
//! either.

use std::collections::HashSet;
use std::time::Duration;

use enumflags2::BitFlags;
use futures_util::future::Either;
use futures_util::stream::StreamExt;
use zbus::fdo;
use zbus::message::Header;
use zbus::names::BusName;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::Value;
use zbus::{connection, interface, Connection};

const WATCHER_NAME: &str = "org.kde.StatusNotifierWatcher";
/// Taken unqueued, purely to notice another copy of this helper: it is started
/// from both Hyprland exec files, and two of them queued behind each other
/// would only waste a process.
const INSTANCE_NAME: &str = "io.github.P3DROVFX.ii.SniWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const ITEM_IFACE: &str = "org.kde.StatusNotifierItem";

/// Object paths the implementations in the wild export their item on. Qt,
/// Steam, older Chromium and most hand-written clients use /StatusNotifierItem;
/// recent Chromium (so current Electron) moved to a numbered path of its own.
/// libayatana-appindicator names its path after the indicator id, and is left
/// out on purpose: it re-registers itself whenever a watcher appears, so it is
/// never among the items that need adopting.
const ITEM_PATHS: [&str; 5] = [
    "/StatusNotifierItem",
    "/StatusNotifierItem/1",
    "/org/chromium/StatusNotifierItem/1",
    "/org/chromium/StatusNotifierItem/2",
    "/org/kde/StatusNotifierItem",
];

/// A connection that answers nothing at all must not hold the sweep up.
const PROBE_TIMEOUT: Duration = Duration::from_millis(500);

#[derive(Default)]
struct Watcher {
    items: Vec<String>,
    hosts: Vec<String>,
}

/// Registrations arrive in three shapes: a bus name, an object path, or the two
/// joined. Normalise them the way every watcher does, so hosts can split the
/// result on the first slash.
fn qualify(item: &str, sender: Option<&str>) -> String {
    let mut qualified = if item.starts_with('/') {
        format!("{}{}", sender.unwrap_or_default(), item)
    } else {
        item.to_owned()
    };
    if !qualified.contains('/') {
        qualified.push_str("/StatusNotifierItem");
    }
    qualified
}

#[interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    async fn register_status_notifier_item(
        &mut self,
        service: &str,
        #[zbus(header)] header: Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        let sender = header.sender().map(|s| s.as_str().to_owned());
        let item = qualify(service, sender.as_deref());
        if self.items.contains(&item) {
            return Ok(());
        }
        println!("registered item {item}");
        self.items.push(item.clone());
        Watcher::status_notifier_item_registered(&emitter, &item).await?;
        self.registered_status_notifier_items_changed(&emitter).await?;
        Ok(())
    }

    async fn register_status_notifier_host(
        &mut self,
        service: &str,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        let host = service.to_owned();
        if self.hosts.contains(&host) {
            return Ok(());
        }
        println!("registered host {host}");
        self.hosts.push(host);
        Watcher::status_notifier_host_registered(&emitter).await?;
        Ok(())
    }

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.items.clone()
    }

    /// Never false. A client that asks while the shell is still starting would
    /// otherwise conclude there is no tray and tear its own icon down -- the
    /// very thing this helper exists to prevent. Quickshell's own watcher
    /// answers the same way, for the same reason.
    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        0
    }

    #[zbus(signal)]
    async fn status_notifier_item_registered(
        emitter: &SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_item_unregistered(
        emitter: &SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_registered(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_unregistered(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

/// Everything a connection lost takes with it: its items, and its host slot.
async fn forget_service(conn: &Connection, service: &str) -> zbus::Result<()> {
    let iface = conn
        .object_server()
        .interface::<_, Watcher>(WATCHER_PATH)
        .await?;
    let emitter = iface.signal_emitter().clone();
    let (gone, lost_host) = {
        let mut watcher = iface.get_mut().await;
        let gone: Vec<String> = watcher
            .items
            .iter()
            .filter(|item| item.split('/').next() == Some(service))
            .cloned()
            .collect();
        watcher.items.retain(|item| !gone.contains(item));
        let had_host = watcher.hosts.iter().any(|host| host == service);
        watcher.hosts.retain(|host| host != service);
        (gone, had_host)
    };

    for item in &gone {
        println!("dropped item {item}");
        Watcher::status_notifier_item_unregistered(&emitter, item).await?;
    }
    if !gone.is_empty() {
        let watcher = iface.get().await;
        watcher
            .registered_status_notifier_items_changed(&emitter)
            .await?;
    }
    if lost_host {
        println!("dropped host {service}");
        Watcher::status_notifier_host_unregistered(&emitter).await?;
    }
    Ok(())
}

/// Ask one connection whether it is a tray item, and under which path.
async fn probe(conn: &Connection, name: &str) -> Option<String> {
    for path in ITEM_PATHS {
        let call = Box::pin(conn.call_method(
            Some(name),
            path,
            Some("org.freedesktop.DBus.Properties"),
            "Get",
            &(ITEM_IFACE, "Id"),
        ));
        let timer = Box::pin(async_io::Timer::after(PROBE_TIMEOUT));
        if let Either::Left((Ok(reply), _)) = futures_util::future::select(call, timer).await {
            if reply.body().deserialize::<Value>().is_ok() {
                return Some(format!("{name}{path}"));
            }
        }
    }
    None
}

/// Adopt the items that are still alive but were registered with whichever
/// watcher held the name before this one. Only ever finds something when the
/// helper is started after a shell -- at login it runs first and sweeps an
/// empty bus.
async fn adopt_existing(conn: &Connection) -> zbus::Result<()> {
    let dbus = fdo::DBusProxy::new(conn).await?;
    let known: HashSet<String> = {
        let iface = conn
            .object_server()
            .interface::<_, Watcher>(WATCHER_PATH)
            .await?;
        let watcher = iface.get().await;
        watcher.items.iter().cloned().collect()
    };

    let names: Vec<String> = dbus
        .list_names()
        .await?
        .into_iter()
        .filter(|name| matches!(name.inner(), BusName::Unique(_)))
        .map(|name| name.as_str().to_owned())
        .filter(|name| !known.iter().any(|item| item.starts_with(name.as_str())))
        .collect();

    let found = futures_util::future::join_all(names.iter().map(|name| probe(conn, name))).await;

    let iface = conn
        .object_server()
        .interface::<_, Watcher>(WATCHER_PATH)
        .await?;
    let emitter = iface.signal_emitter().clone();
    for item in found.into_iter().flatten() {
        {
            let mut watcher = iface.get_mut().await;
            if watcher.items.contains(&item) {
                continue;
            }
            watcher.items.push(item.clone());
        }
        println!("adopted item {item}");
        Watcher::status_notifier_item_registered(&emitter, &item).await?;
    }
    let watcher = iface.get().await;
    watcher
        .registered_status_notifier_items_changed(&emitter)
        .await?;
    Ok(())
}

async fn run() -> zbus::Result<()> {
    let conn = connection::Builder::session()?
        .serve_at(WATCHER_PATH, Watcher::default())?
        .build()
        .await?;

    let dbus = fdo::DBusProxy::new(&conn).await?;
    if dbus
        .request_name(
            INSTANCE_NAME.try_into()?,
            fdo::RequestNameFlags::DoNotQueue.into(),
        )
        .await?
        != fdo::RequestNameReply::PrimaryOwner
    {
        println!("another sni_watcher is already running -- nothing to do");
        return Ok(());
    }

    // Queued, never replacing, and refusing replacement: a shell holding the
    // name keeps it until it exits, ownership then passes here without the name
    // ever being unowned, and no later shell can take it back. The empty flag
    // set is the point -- the default asks not to be queued, which is exactly
    // the request that fails while a shell is up.
    let reply = dbus
        .request_name(WATCHER_NAME.try_into()?, BitFlags::empty())
        .await?;
    let mut owner = matches!(
        reply,
        fdo::RequestNameReply::PrimaryOwner | fdo::RequestNameReply::AlreadyOwner
    );
    if owner {
        println!("holding {WATCHER_NAME}");
        adopt_existing(&conn).await?;
    } else {
        println!("{WATCHER_NAME} is held by the shell -- queued behind it");
    }

    let unique = conn.unique_name().map(|name| name.as_str().to_owned());
    let mut changes = dbus.receive_name_owner_changed().await?;
    while let Some(change) = changes.next().await {
        let args = match change.args() {
            Ok(args) => args,
            Err(_) => continue,
        };
        let name = args.name().as_str().to_owned();
        let new_owner = args.new_owner().as_ref().map(|n| n.as_str().to_owned());

        if name == WATCHER_NAME {
            let ours = new_owner.is_some() && new_owner == unique;
            if ours && !owner {
                owner = true;
                println!("took {WATCHER_NAME} over from the shell");
                adopt_existing(&conn).await?;
            } else if !ours {
                owner = false;
            }
            continue;
        }

        if new_owner.is_none() {
            forget_service(&conn, &name).await?;
        }
    }
    Ok(())
}

fn main() -> zbus::Result<()> {
    async_io::block_on(run())
}
