pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

/** Theme and configured-local-wallpaper adapter for AI actions. */
QtObject {
    id: root

    function bounded(value, maximum = 180): string {
        return String(value ?? "").trim().slice(0, maximum);
    }

    function search(query, limit = 8): var {
        const needle = String(query ?? "").trim().slice(0, 80).toLocaleLowerCase();
        const results = [];
        const model = Wallpapers.sortedFolderModel;
        for (let i = 0; i < model.count && results.length < Math.max(1, Math.min(20, Number(limit) || 8)); i++) {
            const entry = model.get(i);
            const path = String(entry?.filePath ?? "");
            const name = String(entry?.fileName ?? "");
            if (path.length === 0 || (needle.length > 0 && name.toLocaleLowerCase().indexOf(needle) < 0))
                continue;
            results.push({
                ref: path,
                title: name,
                thumbnail: String(entry?.fileUrl ?? path),
                source: "configured-local-folder",
                networkUsed: false
            });
        }
        return { results: results, source: "configured-local-folder", networkUsed: false };
    }

    function configuredRef(ref): bool {
        const candidate = String(ref ?? "").trim();
        const directory = String(Wallpapers.effectiveDirectory ?? "").replace(/\/$/, "");
        return candidate.length > 0 && directory.length > 0 && (candidate === directory || candidate.startsWith(directory + "/"));
    }

    function previewSet(args): var {
        const ref = String(args?.ref ?? "").trim();
        if (!root.configuredRef(ref))
            return { ok: false, error: "wallpaperNotFromConfiguredSource" };
        const oldRef = String(Config.options?.background?.wallpaperPath ?? "");
        return {
            ok: true,
            ref: ref,
            title: ref.split("/").pop() ?? ref,
            thumbnail: `file://${ref}`,
            previousRef: oldRef,
            undo: { ref: oldRef },
            networkUsed: false,
            summary: `Wallpaper → ${ref.split("/").pop() ?? ref}`
        };
    }

    function apply(preview): var {
        const ref = String(preview?.ref ?? "");
        if (!root.configuredRef(ref))
            return { ok: false, error: "wallpaperNotFromConfiguredSource" };
        Wallpapers.apply(ref, Appearance.m3colors.darkmode);
        return { ok: true, ref: ref, thumbnail: preview.thumbnail, networkUsed: false };
    }

    function undo(preview): var {
        const oldRef = String(preview?.previousRef ?? preview?.undo?.ref ?? "");
        if (oldRef.length === 0 || !root.configuredRef(oldRef))
            return { ok: false, error: "previousWallpaperUnavailable" };
        Wallpapers.apply(oldRef, Appearance.m3colors.darkmode);
        return { ok: true, ref: oldRef, networkUsed: false };
    }
}
