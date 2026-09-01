import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A duration in seconds, edited as a number plus a unit (s / min / h). The
 * unit follows the value when it is set from outside; switching the unit by
 * hand keeps the number, so "5 min" becomes "5 h", not "300 h".
 */
RowLayout {
    id: root

    property int seconds: 0
    /// Smallest value the spin box accepts, in the current unit.
    property int minimum: 0
    property int maximumHours: 24
    signal committed(int seconds)

    property string unit: root.unitFor(root.seconds)
    readonly property int factor: root.unit === "h" ? 3600 : (root.unit === "min" ? 60 : 1)

    function unitFor(s) {
        if (s > 0 && s % 3600 === 0)
            return "h";
        if (s > 0 && s % 60 === 0)
            return "min";
        return "s";
    }

    // StyledSpinBox writes its own `value` back from the text field as
    // soon as it exists, which drops any binding on it: the number (and
    // the range it has to fit) is pushed in by hand instead.
    function syncValue() {
        spin.to = root.maximumHours * 3600 / root.factor;
        spin.value = Math.round(root.seconds / root.factor);
    }

    onSecondsChanged: {
        if (!spin.activeFocus)
            root.unit = root.unitFor(root.seconds);
        root.syncValue();
    }
    onFactorChanged: root.syncValue()
    Component.onCompleted: root.syncValue()

    spacing: 8

    StyledSpinBox {
        id: spin
        // The Fusion style sizes a spin box for stacked +/- buttons (twice
        // the row height); the buttons sit beside the value here.
        implicitHeight: baseHeight
        from: root.minimum
        onValueModified: root.committed(value * root.factor)
    }

    FormChoice {
        current: root.unit
        onPicked: u => {
            const number = Math.round(root.seconds / root.factor);
            root.unit = u;
            root.committed(number * root.factor);
        }
        options: [
            { displayName: Translation.tr("s"), value: "s" },
            { displayName: Translation.tr("min"), value: "min" },
            { displayName: Translation.tr("h"), value: "h" }
        ]
    }
}
