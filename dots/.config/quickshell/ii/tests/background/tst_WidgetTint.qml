import QtQuick
import QtTest
import qs.services
import qs.modules.common
import qs.modules.ii.background.widgets.utility
import qs.modules.ii.background.widgets.clock

TestCase {
    id: testCase
    name: "WidgetTint"
    when: windowShown
    width: 800
    height: 260

    property QtObject options: Config.options.background.widgets
    property color albumColor: Qt.rgba(0.2, 0.4, 0.7, 0.8)
    readonly property color albumBackground: WidgetColorScheme.tintBackground(albumColor)

    QuoteWidget { id: quote; width: 240; height: 240 }
    MonthClock { id: month; x: 250; width: 240; height: 240 }
    TripleRingClock { id: triple; x: 500; width: 240; height: 240 }
    SignalSpy { id: monthPaint; target: month; signalName: "painted" }
    SignalSpy { id: triplePaint; target: triple; signalName: "painted" }

    function near(actual, expected) {
        verify(Math.abs(actual - expected) <= 1 / 255 + 0.00001, actual + " != " + expected);
    }

    // Compare rendered channels: text paints quantize to 8-bit RGB, and QColor
    // may store equivalent HSL and RGB specs.
    function sameColor(actual, expected) {
        near(actual.r, expected.r);
        near(actual.g, expected.g);
        near(actual.b, expected.b);
        near(actual.a, expected.a);
    }

    function initTestCase() {
        compare(options.tintOpacityEnabled, false);
        compare(options.tintOpacity, 0.55);
    }

    function init() {
        options.tintOpacityEnabled = false;
        options.tintOpacity = 0.55;
        options.colorScheme = "default";
    }

    function test_all_palettes_preserve_rgb_and_foreground() {
        const bg = findChild(quote, "background");
        const text = findChild(quote, "quoteText");
        for (const scheme of WidgetColorScheme.availableSchemes) {
            options.colorScheme = scheme;
            const raw = WidgetColorScheme.getCardBgColor(scheme);
            const ink = WidgetColorScheme.textColorOnBg;
            for (const amount of [0, 0.25, 0.55, 1]) {
                options.tintOpacityEnabled = true;
                options.tintOpacity = amount;
                near(bg.color.a, raw.a * amount);
                near(bg.color.r, raw.r);
                near(bg.color.g, raw.g);
                near(bg.color.b, raw.b);
                sameColor(text.color, ink);
                compare(text.opacity, 1);
                compare(quote.opacity, 1);
                sameColor(WidgetColorScheme.cardBgColor, raw);
            }
            options.tintOpacityEnabled = false;
            // QColor can store the input as HSL and the bound paint as RGB.
            // Compare channels, not the internal color-space representation.
            near(bg.color.r, raw.r);
            near(bg.color.g, raw.g);
            near(bg.color.b, raw.b);
            near(bg.color.a, raw.a);
        }
    }

    function test_preexisting_alpha_and_album_changes() {
        options.tintOpacityEnabled = true;
        options.tintOpacity = 0.5;
        albumColor = Qt.rgba(0.2, 0.4, 0.7, 0.8);
        near(albumBackground.a, 0.4);
        albumColor = Qt.rgba(0.7, 0.3, 0.1, 0.4);
        near(albumBackground.a, 0.2);
        near(albumBackground.r, 0.7);
        options.tintOpacityEnabled = false;
        sameColor(albumBackground, albumColor);
        compare(options.tintOpacity, 0.5);
        options.tintOpacityEnabled = true;
        near(albumBackground.a, 0.2);
    }

    function test_clamps_invalid_persisted_values() {
        options.tintOpacityEnabled = true;
        options.tintOpacity = -10;
        compare(WidgetColorScheme.backgroundTintOpacity, 0);
        options.tintOpacity = 10;
        compare(WidgetColorScheme.backgroundTintOpacity, 1);
        options.tintOpacity = NaN;
        compare(WidgetColorScheme.backgroundTintOpacity, 0.55);
        options.tintOpacity = Infinity;
        compare(WidgetColorScheme.backgroundTintOpacity, 0.55);
        options.tintOpacityEnabled = false;
        compare(WidgetColorScheme.backgroundTintOpacity, 1);
    }

    function test_theme_color_changes_update_existing_widgets() {
        options.colorScheme = "expressive_primary";
        options.tintOpacityEnabled = true;
        options.tintOpacity = 0.4;
        const previous = Appearance.colors.colPrimaryContainer;
        Appearance.colors.colPrimaryContainer = Qt.rgba(0.7, 0.2, 0.6, 0.5);
        const bg = findChild(quote, "background");
        near(bg.color.a, 0.2);
        near(bg.color.r, 0.7);
        Appearance.colors.colPrimaryContainer = previous;
    }

    function test_canvas_repaints_without_clock_tick() {
        wait(50);
        monthPaint.clear();
        triplePaint.clear();
        options.tintOpacityEnabled = true;
        options.tintOpacity = 0.3;
        near(month.tintedBgColor.a, 0.3);
        near(triple.tintedBgColor.a, 0.3);
        tryVerify(() => monthPaint.count > 0);
        tryVerify(() => triplePaint.count > 0);
        options.tintOpacityEnabled = false;
        near(month.tintedBgColor.a, 1);
        near(triple.tintedBgColor.a, 1);
    }
}
