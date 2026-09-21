.pragma library

/**
 * The phone's scrcpy windows the island reports, read from Hyprland's client list.
 *
 * The session manager names every window it opens `ii-phone-<type>-<id>`. The full
 * mirror is "mirror-mirror" and an app is "app-app_<package>". The embedded mirror
 * lives under the Phone sidebar and the unlock window is momentary, so neither counts.
 * Reading the windows rather than PhoneScrcpyService keeps working across a shell
 * reload (the windows survive it, the service's state does not) and never constructs
 * that service for someone who has never opened the Phone tab.
 */

const mirrorPrefix = "ii-phone-mirror-";
const appPrefix = "ii-phone-app-app_";

/** [{ address, kind: "mirror"|"app", package, workspace }], the mirror first. */
function sessionsFrom(windowList) {
    const out = [];
    const list = windowList ?? [];
    for (let i = 0; i < list.length; i++) {
        const win = list[i];
        const title = String(win?.title ?? "");
        const kind = title.startsWith(mirrorPrefix) ? "mirror" : title.startsWith(appPrefix) ? "app" : "";
        if (kind === "")
            continue;
        out.push({
            "address": String(win.address ?? ""),
            "kind": kind,
            "package": kind === "app" ? title.substring(appPrefix.length) : "",
            "workspace": win.workspace?.name ?? String(win.workspace?.id ?? "")
        });
    }
    return out.sort((a, b) => (a.kind === "mirror" ? 0 : 1) - (b.kind === "mirror" ? 0 : 1));
}

/** "com.whatsapp" -> "Whatsapp"; the package's last segment, capitalised. */
function appLabel(pkg) {
    const last = String(pkg ?? "").split(".").pop();
    return last.length > 0 ? last.charAt(0).toUpperCase() + last.slice(1) : String(pkg ?? "");
}
