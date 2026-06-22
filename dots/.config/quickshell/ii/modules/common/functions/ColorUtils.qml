pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * Returns a color with the hue of color2 and the saturation, value, and alpha of color1.
     *
     * @param {string} color1 - The base color (any Qt.color-compatible string).
     * @param {string} color2 - The color to take hue from.
     * @returns {Qt.rgba} The resulting color.
     */
    function colorWithHueOf(color1, color2) {
        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);
        // Qt.color hsvHue/hsvSaturation/hsvValue/alpha return 0-1
        var hue = c2.hsvHue;
        var sat = c1.hsvSaturation;
        var val = c1.hsvValue;
        var alpha = c1.a;
        return Qt.hsva(hue, sat, val, alpha);
    }

    /**
     * Returns a color with the saturation of color2 and the hue/value/alpha of color1.
     *
     * @param {string} color1 - The base color (any Qt.color-compatible string).
     * @param {string} color2 - The color to take saturation from.
     * @returns {Qt.rgba} The resulting color.
     */
    function colorWithSaturationOf(color1, color2) {
        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);
        var hue = c1.hsvHue;
        var sat = c2.hsvSaturation;
        var val = c1.hsvValue;
        var alpha = c1.a;
        return Qt.hsva(hue, sat, val, alpha);
    }

    /**
     * Returns a color with the given lightness and the hue, saturation, and alpha of the input color (using HSL).
     *
     * @param {string} color - The base color (any Qt.color-compatible string).
     * @param {number} lightness - The lightness value to use (0-1).
     * @returns {Qt.rgba} The resulting color.
     */
    function colorWithLightness(color, lightness) {
        var c = Qt.color(color);
        return Qt.hsla(c.hslHue, c.hslSaturation, lightness, c.a);
    }

    /**
     * Returns a color with the lightness of color2 and the hue, saturation, and alpha of color1 (using HSL).
     *
     * @param {string} color1 - The base color (any Qt.color-compatible string).
     * @param {string} color2 - The color to take lightness from.
     * @returns {Qt.rgba} The resulting color.
     */
    function colorWithLightnessOf(color1, color2) {
        var c2 = Qt.color(color2);
        return colorWithLightness(color1, c2.hslLightness);
    }

    /**
     * Adapts color1 to the accent (hue and saturation) of color2 using HSL, keeping lightness and alpha from color1.
     *
     * @param {string} color1 - The base color (any Qt.color-compatible string).
     * @param {string} color2 - The accent color.
     * @returns {Qt.rgba} The resulting color.
     */
    function adaptToAccent(color1, color2) {
        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);
        var hue = c2.hslHue;
        var sat = c2.hslSaturation;
        var light = c1.hslLightness;
        var alpha = c1.a;
        return Qt.hsla(hue, sat, light, alpha);
    }

    /**
     * Mixes two colors by a given percentage.
     *
     * @param {string} color1 - The first color (any Qt.color-compatible string).
     * @param {string} color2 - The second color.
     * @param {number} percentage - The mix ratio (0-1). 1 = all color1, 0 = all color2.
     * @returns {Qt.rgba} The resulting mixed color.
     */
    function mix(color1, color2, percentage = 0.5) {
        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);
        return Qt.rgba(percentage * c1.r + (1 - percentage) * c2.r, percentage * c1.g + (1 - percentage) * c2.g, percentage * c1.b + (1 - percentage) * c2.b, percentage * c1.a + (1 - percentage) * c2.a);
    }

    /**
     * Transparentizes a color by a given percentage.
     *
     * @param {string} color - The color (any Qt.color-compatible string).
     * @param {number} percentage - The amount to transparentize (0-1).
     * @returns {Qt.rgba} The resulting color.
     */
    function transparentize(color, percentage = 1) {
        var c = Qt.color(color);
        return Qt.rgba(c.r, c.g, c.b, c.a * (1 - percentage));
    }

    /**
     * Sets the alpha channel of a color.
     *
     * @param {string} color - The base color (any Qt.color-compatible string).
     * @param {number} alpha - The desired alpha (0-1).
     * @returns {Qt.rgba} The resulting color with applied alpha.
     */
    function applyAlpha(color, alpha) {
        var c = Qt.color(color);
        var a = Math.max(0, Math.min(1, alpha));
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    /**
     * Generates a hex color code from a string in a deterministic way.
     *
     * @param {string} str - The input string used to generate the color.
     * @returns {string} The resulting hex color in the format "#rrggbb".
     */
    function stringToColor(str) {
        //https://gist.github.com/0x263b/2bdd90886c2036a1ad5bcf06d6e6fb37
        let hash = 0;
        if (str.length === 0)
            return hash;

        for (var i = 0; i < str.length; i++) {
            hash = str.charCodeAt(i) + ((hash << 5) - hash);
            hash = hash & hash;
        }
        let color = '#';
        for (var i = 0; i < 3; i++) {
            let value = (hash >> (i * 8)) & 255;
            color += ('00' + value.toString(16)).substr(-2);
        }
        return color;
    }

    /**
     * Determines a contrasting text color (black or white) based on the background color's luminance.
     *
     * @param {string} bgColor - The background color (any Qt.color-compatible string).
     * @returns {string} The hex color ("#FFFFFF" or "#000000") that ensures high contrast.
     */
    function getContrastingTextColor(bgColor) {
        let color = Qt.color(bgColor);
        // Calculate relative luminance using WCAG formula
        let r = color.r <= 0.03928 ? color.r / 12.92 : Math.pow((color.r + 0.055) / 1.055, 2.4);
        let g = color.g <= 0.03928 ? color.g / 12.92 : Math.pow((color.g + 0.055) / 1.055, 2.4);
        let b = color.b <= 0.03928 ? color.b / 12.92 : Math.pow((color.b + 0.055) / 1.055, 2.4);
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        // Return high contrast color
        return luminance < 0.5 ? "#FFFFFF" : "#000000";
    }

    /**
     * Returns true if the color is considered "dark" (hslLightness < 0.5).
     *
     * @param {string} color - The color to check (any Qt.color-compatible string).
     * @returns {boolean} True if dark, false otherwise.
     */
    function isDark(color) {
        var c = Qt.color(color);
        return c.hslLightness < 0.5;
    }

    /**
     * Clamps a value to the inclusive range [0, 1].
     *
     * @param {number} x - The value to clamp.
     * @returns {number} The clamped value in the range [0, 1].
     */
    function clamp01(x) {
        return Math.min(1, Math.max(0, x));
    }

    /**
     * Solves for the solid overlay color that, when composited over a base color
     * with a given opacity, yields the target color.
     *
     * The compositing equation is:
     *   result = overlay * overlayOpacity + base * (1 - overlayOpacity)
     *
     * This function algebraically inverts that equation per channel.
     *
     * @param {Qt.rgba} baseColor - The base (background) color.
     * @param {Qt.rgba} targetColor - The resulting color after compositing.
     * @param {number} overlayOpacity - The overlay opacity (0-1).
     * @returns {Qt.rgba} The solved overlay color
     */
    function solveOverlayColor(baseColor, targetColor, overlayOpacity) {
        const bc = Qt.color(baseColor);
        const tc = Qt.color(targetColor);
        let invA = 1.0 - overlayOpacity;

        let r = (tc.r - bc.r * invA) / overlayOpacity;
        let g = (tc.g - bc.g * invA) / overlayOpacity;
        let b = (tc.b - bc.b * invA) / overlayOpacity;

        return Qt.rgba(clamp01(r), clamp01(g), clamp01(b), overlayOpacity);
    }

    /**
     * Calculates the distance between two colors using a simple weighted RGB Euclidean formula.
     *
     * @param {string} color1 - The first color.
     * @param {string} color2 - The second color.
     * @returns {number} The distance (0 to ~1).
     */
    function calculateDistance(color1, color2) {
        let c1 = Qt.color(color1);
        let c2 = Qt.color(color2);

        let dr = c1.r - c2.r;
        let dg = c1.g - c2.g;
        let db = c1.b - c2.b;

        return Math.sqrt(dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11);
    }

    /**
     * Builds a per-category accent color with a FIXED hue (in degrees) and a
     * saturation/lightness adapted to the active Material theme, so each section
     * keeps a stable, identifiable identity while staying harmonized with the
     * matugen palette (works in both light and dark modes).
     *
     * The lightness is taken from the supplied theme token, so dark mode yields
     * a deep tinted container and light mode yields a soft pastel — matching M3
     * container behaviour without hardcoding any hex values.
     *
     * @param {number} hueDegrees - Fixed hue for the category (0-360).
     * @param {color} themeColor - A theme token to derive lightness from
     *   (e.g. Appearance.colors.colPrimaryContainer or colLayer2).
     * @param {number} saturation - Target saturation (0-1).
     * @returns {color} The derived accent color.
     */
    function categoryContainer(hueDegrees, themeColor, saturation) {
        var t = Qt.color(themeColor);
        var h = ((hueDegrees % 360) + 360) % 360 / 360;
        var s = Math.min(1, Math.max(0, saturation));
        return Qt.hsla(h, s, t.hslLightness, 1);
    }

    /**
     * Returns a readable "on" color for a category container, tinted with the
     * same hue and with high contrast against the container's lightness.
     *
     * @param {color} containerColor - The result of categoryContainer().
     * @param {number} hueDegrees - The same fixed hue (0-360).
     * @returns {color} The on-container foreground color.
     */
    function categoryOnColor(containerColor, hueDegrees) {
        var c = Qt.color(containerColor);
        var h = ((hueDegrees % 360) + 360) % 360 / 360;
        var lightness = c.hslLightness < 0.5 ? 0.92 : 0.14;
        return Qt.hsla(h, 0.35, lightness, 1);
    }

    /**
     * Mixes a fixed-hue category tint into a base theme color by a given ratio,
     * preserving the base's alpha so the project's transparency architecture is
     * respected (useful for tinted card backgrounds that stay translucent).
     *
     * @param {number} hueDegrees - Fixed category hue (0-360).
     * @param {color} baseColor - The base theme color (e.g. colLayer2).
     * @param {color} lightnessRef - Theme token to derive lightness from.
     * @param {number} saturation - Tint saturation (0-1).
     * @param {number} ratio - How much of the tint to apply (0-1).
     * @returns {color} The subtly tinted background color.
     */
    function categoryTint(hueDegrees, baseColor, lightnessRef, saturation, ratio) {
        var tint = root.categoryContainer(hueDegrees, lightnessRef, saturation);
        return root.mix(tint, baseColor, Math.min(1, Math.max(0, ratio)));
    }
}
