pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root

    property string title: ""
    property int value: 0
    property int from: 0
    property int to: 100

    signal sliderInteracted(int value, bool isDragging)

    property int localValue: root.value
    property bool isDragging: false

    onValueChanged: {
        if (!root.isDragging) {
            root.localValue = root.value;
        }
    }

    Timer {
        id: debounceTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (root.isDragging) {
                root.sliderInteracted(root.localValue, true);
            }
        }
    }

    Layout.fillWidth: true
    spacing: 4

    RowLayout {
        Layout.fillWidth: true

        StyledText {
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colOnSurface
            Layout.fillWidth: true
        }

        StyledText {
            text: root.localValue + "%"
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colPrimary
        }
    }

    StyledSlider {
        id: slider
        Layout.fillWidth: true
        from: root.from
        to: root.to
        value: root.localValue

        onMoved: {
            root.localValue = Math.round(value);
            if (!root.isDragging) {
                root.isDragging = true;
                root.sliderInteracted(root.localValue, true);
            }
            debounceTimer.restart();
        }

        onPressedChanged: {
            if (!pressed && root.isDragging) {
                root.isDragging = false;
                debounceTimer.stop();
                root.localValue = Math.round(value);
                root.sliderInteracted(root.localValue, false);
            }
        }
    }
}
