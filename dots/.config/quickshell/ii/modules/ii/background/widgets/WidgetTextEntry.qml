import QtQuick
import Quickshell
import qs

/*
 * Lets a desktop widget's text field take the keyboard. The desktop's surface
 * normally takes none, so a click on the field cannot focus it by itself:
 * `begin()` raises GlobalStates.widgetTypingOwner for this screen, the surface
 * grabs the keyboard (BackgroundWidgetsWindow), and the field gets the keys.
 * The hold ends when the field loses focus after having had it (a click on a
 * window, Escape, `end()`), or when focus never arrives.
 */
Item {
    id: root

    required property Item field
    visible: false

    property string _uid: ""
    readonly property string screenName: (QsWindow.window as QsWindow)?.screen?.name ?? ""
    readonly property string owner: root.screenName + "|" + root._uid
    readonly property bool holding: root._uid !== "" && GlobalStates.widgetTypingOwner === root.owner
    // The field has had the keyboard since begin(): losing it now means the
    // user went elsewhere, while before that it is only the surface catching up.
    property bool _hadFocus: false

    function begin() {
        if (!root.field)
            return;
        root._hadFocus = false;
        GlobalStates.widgetTypingOwner = root.owner;
        root.field.forceActiveFocus();
        graceTimer.restart();
    }

    function end() {
        graceTimer.stop();
        root._hadFocus = false;
        if (root.holding)
            GlobalStates.widgetTypingOwner = "";
        if (root.field)
            root.field.focus = false;
    }

    Component.onCompleted: root._uid = Date.now().toString(36) + Math.random().toString(36).slice(2, 7)
    Component.onDestruction: {
        if (root.holding)
            GlobalStates.widgetTypingOwner = "";
    }

    Connections {
        target: root.field
        function onActiveFocusChanged() {
            if (root.field.activeFocus) {
                root._hadFocus = true;
                graceTimer.stop();
            } else if (root._hadFocus && root.holding) {
                root.end();
            }
        }
    }

    Timer {
        id: graceTimer
        interval: 1500
        onTriggered: {
            if (!root._hadFocus && root.holding)
                root.end();
        }
    }
}
