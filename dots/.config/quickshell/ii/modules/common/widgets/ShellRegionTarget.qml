import QtQuick
import qs.services

/**
 * Marks an item of a shell surface as a region the region selector can snap
 * to (see services/ShellRegions.qml). Drop it inside the visible card of a
 * full-screen overlay:
 *
 *     ShellRegionTarget { target: card; label: Translation.tr("Cheatsheet") }
 *
 * `namespace` (the surface's layer namespace) is optional and only helps place
 * surfaces that are not full screen.
 */
QtObject {
    id: root

    property Item target: null
    property string label: ""
    property string namespace: ""
    property bool enabled: true

    Component.onCompleted: ShellRegions.add(root)
    Component.onDestruction: ShellRegions.remove(root)
}
