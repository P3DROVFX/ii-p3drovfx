.pragma library

// Paths, URIs and labels for the file widgets (Files, Screenshots, Shelf, Send).

function pathFromUrl(url) {
    var s = String(url || "");
    if (s.indexOf("file://") === 0) {
        s = s.slice(7);
        try {
            s = decodeURIComponent(s);
        } catch (e) {
        }
    }
    return s;
}

// A file:// URI another app accepts: encoded, with # and ? escaped too.
function fileUri(path) {
    return "file://" + encodeURI(String(path || "")).replace(/#/g, "%23").replace(/\?/g, "%3F");
}

function uriList(paths) {
    return (paths || []).map(fileUri).join("\r\n");
}

function baseName(path) {
    var parts = String(path || "").split("/").filter(function (s) { return s.length > 0; });
    return parts.length > 0 ? parts[parts.length - 1] : "";
}

function isImage(path) {
    return /\.(png|jpe?g|webp|gif|bmp|svg|avif|tiff?)$/i.test(String(path || ""));
}

function symbolFor(path) {
    var p = String(path || "").toLowerCase();
    if (isImage(p))
        return "image";
    if (/\.(mp3|flac|ogg|opus|wav|aac|m4a)$/.test(p))
        return "music_note";
    if (/\.(mp4|mkv|webm|avi|mov)$/.test(p))
        return "movie";
    if (p.endsWith(".pdf"))
        return "picture_as_pdf";
    if (/\.(txt|md|rst|log|json|csv)$/.test(p))
        return "description";
    if (/\.(zip|tar|gz|xz|zst|rar|7z)$/.test(p))
        return "folder_zip";
    if (/\.(appimage|rpm|deb|flatpakref|exe|msi)$/.test(p))
        return "deployed_code";
    var last = baseName(p);
    return last.indexOf(".") >= 0 ? "draft" : "folder";
}

// "just now", "5 min", "3 h", "2 d" — how long ago a file arrived.
function age(ms, now, tr) {
    var t = tr || function (s) { return s; };
    if (!isFinite(ms) || ms <= 0 || !isFinite(now))
        return "";
    var seconds = Math.max(0, Math.round((now - ms) / 1000));
    if (seconds < 60)
        return t("just now");
    var minutes = Math.round(seconds / 60);
    if (minutes < 60)
        return t("%1 min ago").replace("%1", String(minutes));
    var hours = Math.round(minutes / 60);
    if (hours < 24)
        return t("%1 h ago").replace("%1", String(hours));
    return t("%1 d ago").replace("%1", String(Math.round(hours / 24)));
}

// Paths from a drop (urls, or a text/uri-list), deduplicated.
function dedupe(paths) {
    var seen = {};
    var out = [];
    for (var i = 0; i < (paths || []).length; i++) {
        var p = pathFromUrl(paths[i]);
        if (!p || seen[p])
            continue;
        seen[p] = true;
        out.push(p);
    }
    return out;
}
