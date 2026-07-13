import QtQuick

QtObject {
    id: root

    required property string mode
    required property bool hoverActive

    property string _displayMode: mode
    property bool _modeStable: true

    readonly property bool notchModeEnabled: false
    readonly property bool expanded: true

    onModeChanged: {
        root._displayMode = root.mode;
        root._modeStable = true;
    }
}
