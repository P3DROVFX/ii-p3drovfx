import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Toolbar {
    id: extraOptions
    z: 20
    implicitWidth: 196 // magic numbers are needed to make the toolbar make 2 rows
    implicitHeight: 90
    radius: Appearance.rounding.large
    visible: false

    ConfigSelectionArray {
        currentValue: wallpaperSelectorContent.activeColorFilter
        onSelected: newValue => {
            wallpaperSelectorContent.activeColorFilter = newValue
        }
        options: [ 
            {
                displayName: "",
                shape: "Pill",
                value: "#ed3802", // we use different values for the filters than the actual colors shown on the buttons 
                color: "#c63c1f"  // to have warmer colors on the UI, but still have the filters work correctly 
            }, 
            {
                displayName: "",
                shape: "Pentagon",
                value: "#f4a40e",
                color: "#c88a1a"
            }, 
            {
                displayName: "",
                shape: "Sunny",
                value: "#f8e115",
                color: "#c6b21a"
            }, 
            {
                displayName: "",
                shape: "Bun",
                value: "#8CD65E",
                color: "#3fa34d"
            }, 
            {
                displayName: "",
                shape: "PixelCircle",
                value: "#2c94fa",
                color: "#3a7bd5"
            }, 
            {
                displayName: "",
                shape: "Arch",
                value: "#831cd7",
                color: "#6e3ac7"
            },
            {
                displayName: "",
                shape: "Heart",
                value: "#f454b1",
                color: "#c94a8a"
            },
            {
                displayName: "",
                shape: "Cookie7Sided",
                value: "#a7a7a9",
                color: "#8c8c8f"
            }
        ]
    }       
}