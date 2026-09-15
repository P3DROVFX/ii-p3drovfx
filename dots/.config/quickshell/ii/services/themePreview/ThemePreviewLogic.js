.pragma library

/**
 * The decisions behind the wallpaper colour previews.
 *
 * They live here rather than inline in the singleton because they are the part
 * worth testing: which of the two sources answers for a scheme, whether a swatch
 * that found nothing may start the shared generation, and how a wallpaper path
 * is handed to the shell. None of it needs a FileView, a Process or the
 * Quickshell plugin, so a node test can cover every branch - which a QML harness
 * could not, since FileView and Process are C++ and would have to be doubled.
 */

/// The user's own previews win; the seed answers only while the shell is showing
/// the wallpaper it ships with, because it describes that wallpaper and nothing
/// else. Empty otherwise, which is what sends a swatch to the generation.
function resolvePreviews(userPreviews, seedPreviews, defaultWallpaperActive) {
    if (userPreviews && Object.keys(userPreviews).length > 0)
        return userPreviews;
    if (defaultWallpaperActive)
        return seedPreviews || {};
    return {};
}

/// switchwall generates the previews with the mode it was called in, so the
/// seed has one file per mode. A forced dark terminal palette pins both.
function previewMode(forceDarkMode, darkmode) {
    if (forceDarkMode === true)
        return "dark";
    return darkmode ? "dark" : "light";
}

/// One attempt per mode and wallpaper: after a failure the caller has to fall
/// back to its own per-swatch process instead of asking for the same generation
/// again.
function generationKey(mode, wallpaper) {
    return mode + "|" + wallpaper;
}

/// Answers "is someone already handling the colours?".
///
///   handled - the caller must NOT start its own process; the answer is known,
///             or on its way.
///   start   - this call is the one that owns starting the generation.
///
/// The only case that is neither is a failure already recorded for this exact
/// mode and wallpaper, which is the degradation path.
function generationDecision(state) {
    if (state.ready)
        return { handled: true, start: false, reason: "known" };

    const wallpaper = state.wallpaper || "";
    if (wallpaper === "")
        return { handled: false, start: false, reason: "no-wallpaper" };

    if (state.generatedFor === generationKey(state.mode, wallpaper))
        return {
            handled: state.generating === true,
            start: false,
            reason: state.generating === true ? "running" : "attempted"
        };

    return { handled: true, start: true, reason: "start" };
}

/// Bash single-quoting. Everything inside '...' is literal, so the only escape
/// needed is for a quote itself - which keeps a wallpaper path from being read
/// as a command substitution by the bash -c that activates the venv.
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}
