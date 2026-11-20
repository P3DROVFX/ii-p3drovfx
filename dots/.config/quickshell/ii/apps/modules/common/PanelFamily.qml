pragma Singleton
import QtQuick
import Quickshell

// Apps are desktop windows: the shell's tablet family never applies here.
Singleton {
    readonly property bool isTablet: false
    readonly property bool touchFirst: false
}
