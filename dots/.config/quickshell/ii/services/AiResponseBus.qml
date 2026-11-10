pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Lightweight event bus for surfaces that only need to react to a completed
// AI response. Keeping this projection independent from Ai prevents a bar
// indicator from constructing the full chat/catalogue/tool graph at startup.
Singleton {
    signal responseFinished(var result)
}
