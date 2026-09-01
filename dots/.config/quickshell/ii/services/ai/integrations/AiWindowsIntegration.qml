pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

/** Window/workspace adapter. Addresses are accepted only from live HyprlandData. */
QtObject {
    id: root

    function knownWindow(address): var {
        const key = String(address ?? "").trim();
        return key.length > 0 ? (HyprlandData.windowByAddress?.[key] ?? null) : null;
    }

    function list(): var {
        return Array.from(HyprlandData.windowList ?? []).map(window => ({
            address: String(window.address ?? ""),
            title: String(window.title ?? ""),
            className: String(window.class ?? window.initialClass ?? ""),
            workspace: Number(window.workspace?.id ?? 0),
            workspaceName: String(window.workspace?.name ?? ""),
            monitor: Number(window.monitor ?? 0),
            monitorName: String(window.monitorName ?? ""),
            floating: window.floating === true,
            fullscreen: Number(window.fullscreen ?? 0) > 0
        })).filter(window => window.address.length > 0);
    }

    function previewMove(args): var {
        const address = String(args?.address ?? "").trim();
        const window = root.knownWindow(address);
        const workspace = Number(args?.workspace);
        if (!window)
            return { ok: false, error: "unknownWindow", address: address };
        if (!Number.isInteger(workspace) || workspace < 1 || workspace > 100)
            return { ok: false, error: "invalidWorkspace" };
        return {
            ok: true,
            address: address,
            title: String(window.title ?? window.class ?? "Window"),
            className: String(window.class ?? window.initialClass ?? ""),
            fromWorkspace: Number(window.workspace?.id ?? 0),
            workspace: workspace,
            summary: `${String(window.title ?? window.class ?? "Window")} → workspace ${workspace}`
        };
    }

    function focus(args): var {
        const address = String(args?.address ?? "").trim();
        if (!root.knownWindow(address))
            return { ok: false, error: "unknownWindow" };
        Hyprland.dispatch(`hl.dsp.focus({window = "address:${address}"})`);
        return { ok: true, address: address };
    }

    function move(args): var {
        const preview = root.previewMove(args);
        if (!preview.ok)
            return preview;
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${preview.workspace}, follow = false, window = "address:${preview.address}" })`);
        return preview;
    }

    function switchWorkspace(args): var {
        const workspace = Number(args?.workspace);
        if (!Number.isInteger(workspace) || workspace < 1 || workspace > 100)
            return { ok: false, error: "invalidWorkspace" };
        Hyprland.dispatch(`hl.dsp.focus({workspace = ${workspace}})`);
        return { ok: true, workspace: workspace };
    }
}
