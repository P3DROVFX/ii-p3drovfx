pragma Singleton
import QtQuick

/**
 * Everything the shell's Appearance gives the lock screen, rebuilt from the
 * greeter's `config` (theme.conf, overridden by the synced theme.conf.user).
 * Main.qml hands `config` in through `cfg`: singletons do not reliably see
 * the greeter's context properties.
 */
QtObject {
    id: root

    property var cfg: null

    // ── config readers ─────────────────────────────────────────────────────
    function str(key, fallback) {
        const v = root.cfg ? root.cfg[key] : undefined;
        return (v === undefined || v === null || String(v) === "") ? fallback : String(v);
    }
    function num(key, fallback) {
        const v = parseFloat(root.str(key, ""));
        return isNaN(v) ? fallback : v;
    }
    function bool(key, fallback) {
        const v = root.str(key, "").toLowerCase();
        if (v === "true" || v === "1")
            return true;
        if (v === "false" || v === "0")
            return false;
        return fallback;
    }
    function list(key, fallback) {
        const v = root.str(key, null);
        if (v === null)
            return fallback;
        return v.split(",").map(s => s.trim()).filter(s => s.length > 0);
    }
    function col(token, fallback) {
        const v = root.str("color_" + token, "");
        return /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(v) ? v : fallback;
    }
    function fileUrl(path) {
        return path === "" ? "" : (path.startsWith("file:") ? path : "file://" + path);
    }

    // ── colour maths, as in the shell's ColorUtils ─────────────────────────
    function mix(c1, c2, p) {
        const a = Qt.color(c1), b = Qt.color(c2);
        return Qt.rgba(p * a.r + (1 - p) * b.r, p * a.g + (1 - p) * b.g, p * a.b + (1 - p) * b.b, p * a.a + (1 - p) * b.a);
    }
    function transparentize(c, p) {
        const a = Qt.color(c);
        return Qt.rgba(a.r, a.g, a.b, a.a * (1 - p));
    }

    // ── m3 tokens ──────────────────────────────────────────────────────────
    readonly property color m3background: col("background", "#141313")
    readonly property color m3onBackground: col("on_background", "#e6e1e1")
    readonly property color m3surfaceContainerLow: col("surface_container_low", "#1c1b1c")
    readonly property color m3surfaceContainer: col("surface_container", "#201f20")
    readonly property color m3surfaceContainerHigh: col("surface_container_high", "#2b2a2a")
    readonly property color m3surfaceContainerHighest: col("surface_container_highest", "#363435")
    readonly property color m3onSurface: col("on_surface", "#e6e1e1")
    readonly property color m3surfaceVariant: col("surface_variant", "#49464a")
    readonly property color m3onSurfaceVariant: col("on_surface_variant", "#cbc5ca")
    readonly property color m3outline: col("outline", "#948f94")
    readonly property color m3shadow: col("shadow", "#000000")
    readonly property color m3primary: col("primary", "#cbc4cb")
    readonly property color m3onPrimary: col("on_primary", "#322f34")
    readonly property color m3secondaryContainer: col("secondary_container", "#4d4b4d")
    readonly property color m3onSecondaryContainer: col("on_secondary_container", "#ece6e9")
    readonly property color m3error: col("error", "#ffb4ab")
    readonly property color m3onError: col("on_error", "#690005")

    // ── derived colours (Appearance.colors) ────────────────────────────────
    readonly property bool extraBackgroundTint: bool("extra_background_tint", true)
    readonly property color colLayer0: mix(m3background, m3primary, extraBackgroundTint ? 0.99 : 1)
    readonly property color colLayer1: m3surfaceContainerLow
    readonly property color colOnLayer1: m3onSurfaceVariant
    readonly property color colLayer1Hover: mix(colLayer1, colOnLayer1, 0.92)
    readonly property color colLayer1Active: mix(colLayer1, colOnLayer1, 0.85)
    readonly property color colSubtext: m3outline
    readonly property color colPrimaryHover: mix(m3primary, colLayer1Hover, 0.87)
    readonly property color colPrimaryActive: mix(m3primary, colLayer1Active, 0.7)
    readonly property color colSecondaryContainerHover: mix(m3secondaryContainer, m3onSecondaryContainer, 0.90)
    readonly property color colSecondaryContainerActive: mix(m3secondaryContainer, m3onSecondaryContainer, 0.54)
    readonly property color colSurfaceContainerHighestHover: mix(m3surfaceContainerHighest, m3onSurface, 0.95)
    readonly property color colShadow: transparentize(m3shadow, 0.7)
    readonly property color colTooltip: m3surfaceContainerHigh
    readonly property color colOnTooltip: m3onSurface

    // ── shape and motion ───────────────────────────────────────────────────
    readonly property bool transparency: bool("transparency", false)
    readonly property bool sharpMode: bool("sharp_mode", false)
    readonly property real roundingScale: {
        const rv = num("rounding_value", 28);
        return rv > 0 ? rv / 24 : (rv < 0 ? 1 : 0);
    }
    readonly property int roundingVerySmall: Math.round(8 * roundingScale)
    readonly property int roundingSmall: Math.round(12 * roundingScale)
    readonly property int roundingNormal: Math.round(17 * roundingScale)
    readonly property int roundingFull: roundingScale === 0 ? 0 : 9999
    readonly property real toolbarHeight: 46
    readonly property real elevationMargin: 10

    readonly property real animMultiplier: Math.max(0, num("anim_multiplier", 1))
    function ms(duration) {
        return Math.round(duration * root.animMultiplier);
    }
    readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1]
    readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1]
    readonly property var expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
    readonly property var emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var standardDecel: [0, 0, 0, 1, 1, 1]

    // ── fonts ──────────────────────────────────────────────────────────────
    // Synced font files live in /var/lib/ii-sddm/fonts: the greeter cannot read
    // the user's ~/.local/share/fonts. A family that failed to load falls back
    // to its name, which still works when the font is installed system-wide.
    readonly property FontLoader mainLoader: FontLoader {
        source: root.fileUrl(root.str("font_main", ""))
    }
    readonly property FontLoader numbersLoader: FontLoader {
        source: root.fileUrl(root.str("font_numbers", ""))
    }
    readonly property FontLoader expressiveLoader: FontLoader {
        source: root.fileUrl(root.str("font_expressive", ""))
    }
    readonly property FontLoader iconsLoader: FontLoader {
        source: root.fileUrl(root.str("font_icons", ""))
    }
    function family(loader, key, fallback) {
        return loader.status === FontLoader.Ready ? loader.font.family : root.str(key, fallback);
    }
    readonly property string fontMain: family(mainLoader, "family_main", "Google Sans Flex")
    readonly property string fontNumbers: family(numbersLoader, "family_numbers", "Google Sans Flex")
    readonly property string fontExpressive: family(expressiveLoader, "family_expressive", "Space Grotesk")
    readonly property string fontIcons: family(iconsLoader, "family_icons", "Material Symbols Rounded")
    readonly property bool roundnessFull: bool("roundness_full", true)
    readonly property var axesMain: ({
            "wght": 450,
            "wdth": 100,
            "ROND": roundnessFull ? 100 : 0
        })
    readonly property var axesNumbers: ({
            "wght": 450,
            "ROND": roundnessFull ? 100 : 0
        })

    readonly property int pxSmallest: 10
    readonly property int pxSmaller: 12
    readonly property int pxSmall: 15
    readonly property int pxNormal: 16
    readonly property int pxLarge: 17
    readonly property int pxLarger: 19
    readonly property int pxHuge: 22
    readonly property int pxHugeass: 23

    // ── lock look ──────────────────────────────────────────────────────────
    readonly property string wallpaper: fileUrl(str("wallpaper", ""))
    readonly property bool blurEnable: bool("blur_enable", true)
    readonly property real blurRadius: Math.max(0, Math.min(50, num("blur_radius", 45)))
    readonly property bool desaturateEnable: bool("desaturate_enable", true)
    readonly property real desaturateAmount: Math.max(0, Math.min(1, num("desaturate_amount", 0.25)))
    readonly property bool colorWashEnable: bool("colorwash_enable", false)
    readonly property real colorWashAmount: Math.max(0, Math.min(1, num("colorwash_amount", 0.5)))
    readonly property bool vignetteEnable: bool("vignette_enable", true)
    readonly property real vignetteAmount: Math.max(0, Math.min(1, num("vignette_amount", 0.3)))
    readonly property bool materialShapeChars: bool("material_shape_chars", true)

    readonly property var islandsLeft: list("islands_left", ["battery", "capsLock", "keyboardLayout"])
    readonly property var islandsRight: list("islands_right", ["session", "sleep", "power", "reboot"])
    readonly property var islandsHidden: list("islands_hidden", [])
    function islandShown(id) {
        return !root.islandsHidden.includes(id);
    }

    readonly property string clockStyle: str("clock_style", "none")
    readonly property string timeFormat: str("clock_time_format", "hh:mm")
    readonly property string dateFormat: str("clock_date_format", "MM/dd, ddd")
}
