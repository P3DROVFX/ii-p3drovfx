pragma Singleton

import Quickshell

/**
 * How the quick-toggle grid's chrome sizes with its cells.
 *
 * The grid's layout unit is the cell height: the ii sidebar uses 56, and a touch host
 * asks for whatever a thumb needs. Everything drawn inside a cell — icon circles, glyphs,
 * label type, corner radii, slider tracks — has to follow, or a touch-sized grid ends up
 * with desktop-sized icons rattling around in it.
 *
 * That derivation used to be `Math.pow(baseCellHeight / 56, 0.65)`, written out
 * identically in the toggle button and in the slider base. Two copies of a curve nobody
 * would recognise as deliberate is how the two drift apart. It lives here now, once.
 *
 * It is a singleton of pure functions rather than an object the host instantiates and
 * threads down, because every value is a function of the cell height the delegates
 * already receive. Adding an instance to plumb through would be ceremony around
 * arithmetic.
 */
Singleton {
    id: root

    /// The cell height the chrome sizes were originally drawn against. Scale is 1 here.
    readonly property real referenceCellHeight: 56

    /**
     * Sub-linear on purpose. Chrome that grew proportionally with the cell would give a
     * touch grid enormous glyphs and no breathing room — a cell twice as tall does not
     * want an icon twice as wide, it wants a slightly larger icon with much more padding
     * around it. The exponent is that "slightly".
     *
     * Never below 1: this only ever grows the desktop values, so a host asking for cells
     * SMALLER than the reference gets the reference chrome rather than something cramped.
     */
    function chromeScale(cellHeight: real): real {
        if (!(cellHeight > 0))
            return 1;
        return Math.max(1, Math.pow(cellHeight / root.referenceCellHeight, 0.65));
    }

    /// A chrome dimension — icon size, padding, radius, font size — for this cell height.
    function scaled(cellHeight: real, value: real): real {
        return Math.round(value * root.chromeScale(cellHeight));
    }

    /**
     * Slider track thickness. Unlike the values above this is not a scaled constant: at
     * the reference cell height the track keeps StyledSlider's fixed M configuration, and
     * only a genuinely larger cell gets a track proportional to it. Returns -1 when the
     * caller should use the M preset, since that is an enum value and not a thickness.
     */
    function sliderTrack(cellHeight: real): real {
        if (root.chromeScale(cellHeight) <= 1)
            return -1;
        return Math.round(cellHeight * 0.62);
    }
}
