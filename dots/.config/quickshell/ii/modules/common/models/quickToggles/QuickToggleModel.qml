import QtQuick

QtObject {
    // Textual info
    required property string name
    property string statusText
    property string tooltipText: ""
    property string icon: "close"

    // The one reading a big expressive tile is about (volume, battery, signal...):
    // the number, its unit, and 0..1 for faces that draw it as a level (-1 = none).
    property string heroValue: ""
    property string heroUnit: ""
    property real heroLevel: -1

    // State
    property bool hasStatusText: true
    property bool available: true
    property bool toggled: false

    // Interactions
    required property var mainAction
    property bool hasMenu: false
    property var altAction: null

    // Allow stuff like Processes to be declared freely
    default property list<QtObject> data
}
