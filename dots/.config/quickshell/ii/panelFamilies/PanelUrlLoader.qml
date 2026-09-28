import QtQuick

import qs.modules.common

/**
 * A PanelLoader that also compiles its panel in its own schedule slot.
 *
 * Quickshell serves the config through the `qs:` scheme, which Qt's QML disk cache
 * refuses, so every type is compiled from source on every start. An inline
 * `component: X {}` compiles X and its whole import closure together with the family:
 * with ~50 panels that is ~2.8 s of main-thread compilation before the bar can be
 * created. By URL, the bar compiles alone (~0.5 s), shows, and every later panel pays
 * for its own compilation when its slot comes up.
 *
 * The family file must keep importing each panel's module: those imports are how the
 * QmlScanner finds (and synthesizes qmldirs for, and hot-reloads) the panel's files.
 *
 * `active` depends on `source` on purpose: setActive(true) before the component exists
 * is a silent no-op (see PanelFamilyLoader in shell.qml).
 */
PanelLoader {
    id: root

    required property string panelUrl

    readonly property bool slotReady: root.wanted && root.ticket > 0 && PanelSchedule.released >= root.ticket

    source: root.slotReady ? root.panelUrl : ""
    active: root.slotReady && root.source !== ""
}
