import QtQuick

/**
 * Loader for a lazily built bar popup that keeps itself alive while it is shown.
 *
 * Bind `active: … || held`. `held` mirrors the popup's own `active`, but is written
 * imperatively: reading `item?.active` inside the Loader's `active` binding
 * re-evaluated that binding while the Loader was still creating or destroying the
 * item, which Qt logged as a binding loop on "active".
 */
Loader {
    id: root

    property bool held: false

    onLoaded: root.held = root.item?.active ?? false
    onActiveChanged: if (!root.active) root.held = false

    Connections {
        target: root.item
        ignoreUnknownSignals: true
        function onActiveChanged() {
            root.held = root.item?.active ?? false;
        }
    }
}
