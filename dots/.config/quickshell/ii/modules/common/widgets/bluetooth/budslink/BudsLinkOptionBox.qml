pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property var boxData: null
    property var device: null

    signal sliderChanged(int value, bool isDragging)
    signal checkChanged(int checkIndex, bool state)
    signal radioChanged(int state)

    readonly property bool hasContent: root.boxData && (root.boxData.hasSlider || (root.boxData.checkButtons && root.boxData.checkButtons.length > 0) || root.boxData.hasRadio)

    visible: root.hasContent
    Layout.fillWidth: true
    implicitHeight: mainCol.implicitHeight + 24
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSurfaceContainerHigh

    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // Slider if present
        Loader {
            active: root.boxData && root.boxData.hasSlider && root.boxData.slider
            Layout.fillWidth: true
            sourceComponent: BudsLinkSlider {
                title: (root.boxData && root.boxData.slider) ? root.boxData.slider.title : ""
                value: (root.boxData && root.boxData.slider) ? root.boxData.slider.value : 0
                onSliderInteracted: (val, isDrag) => {
                    root.sliderChanged(val, isDrag);
                }
            }
        }

        // Checkbuttons if present
        Loader {
            active: root.boxData && root.boxData.hasCheck && root.boxData.checkButtons && root.boxData.checkButtons.length > 0
            Layout.fillWidth: true
            sourceComponent: BudsLinkCheckOptions {
                checkButtons: (root.boxData && root.boxData.checkButtons) ? root.boxData.checkButtons : []
                onCheckToggled: (checkIdx, st) => {
                    root.checkChanged(checkIdx, st);
                }
            }
        }

        // Radio if present
        Loader {
            active: root.boxData && root.boxData.hasRadio && root.boxData.radio
            Layout.fillWidth: true
            sourceComponent: BudsLinkRadioOptions {
                title: (root.boxData && root.boxData.radio) ? root.boxData.radio.title : ""
                currentState: (root.boxData && root.boxData.radio) ? root.boxData.radio.state : 0
                onRadioSelected: st => {
                    root.radioChanged(st);
                }
            }
        }
    }
}
