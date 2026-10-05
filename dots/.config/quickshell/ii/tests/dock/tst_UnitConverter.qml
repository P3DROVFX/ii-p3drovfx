import QtQuick
import QtTest
import "../../modules/ii/dock/utilities/UnitConverter.js" as Units

TestCase {
    name: "UnitConverter"

    function near(a, b, eps) {
        verify(Math.abs(a - b) < (eps || 1e-9), a + " ≈ " + b);
    }

    function test_length() {
        near(Units.convert(100, "length", "cm", "in"), 39.37007874015748);
        near(Units.convert(1, "length", "mi", "km"), 1.609344);
    }
    function test_weight() {
        near(Units.convert(1, "weight", "kg", "lb"), 2.2046226218487757);
    }
    function test_temperature() {
        near(Units.convert(100, "temperature", "c", "f"), 212);
        near(Units.convert(32, "temperature", "f", "c"), 0);
        near(Units.convert(0, "temperature", "k", "c"), -273.15);
    }
    function test_data() {
        near(Units.convert(1, "data", "gib", "mb"), 1073.741824);
    }
    function test_badUnits() {
        verify(isNaN(Units.convert(1, "length", "cm", "kg")));
        verify(isNaN(Units.convert("x", "length", "cm", "m")));
    }
    function test_parse() {
        compare(Units.parse("1,5"), 1.5);
        compare(Units.parse("1 500"), 1500);
        compare(Units.parse("1.234,5"), 1234.5);
        compare(Units.parse("1,234.5"), 1234.5);
        compare(Units.parse("-3"), -3);
        verify(isNaN(Units.parse("")));
        verify(isNaN(Units.parse("abc")));
    }
    function test_format() {
        compare(Units.format(39.37007874015748), "39.37");
        compare(Units.format(0.3937007874), "0.3937");
        compare(Units.format(212), "212");
        compare(Units.format(0.000123456), "0.00012346");
        compare(Units.format(0), "0");
        compare(Units.format(NaN), "—");
    }
    function test_defaultPairBelongs() {
        for (const c of Units.categories) {
            const pair = Units.defaultPair(c.id);
            verify(Units.unit(c.id, pair.from) !== null, c.id);
            verify(Units.unit(c.id, pair.to) !== null, c.id);
        }
    }
}
