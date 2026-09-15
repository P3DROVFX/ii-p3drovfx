pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common

Item {
    id: root

    property string activePanelId: ""
    property string searchQuery: ""
    property bool inNotchMode: false
    property var activePanel: SearchPanelRegistry.byId(activePanelId)
    property Item activeItem: null
    readonly property bool keepAlive: {
        for (let index = 0; index < panelRepeater.count; index++) {
            const loader = panelRepeater.itemAt(index);
            if (loader?.keepAlive === true)
                return true;
        }
        return false;
    }

    // The registry owns hosted-panel geometry. Individual panels may retain
    // legacy implicit widths, but they fill this host and must not shrink it.
    implicitWidth: root.activePanel?.width?.() ?? (root.activeItem?.implicitWidth ?? 0)
    implicitHeight: root.activeItem?.implicitHeight ?? (root.activePanel ? 520 : 0)

    function queryFor(panel) {
        const prefix = SearchPanelRegistry.prefixOf(panel);
        return prefix.length > 0 && root.searchQuery.startsWith(prefix)
            ? root.searchQuery.slice(prefix.length)
            : root.searchQuery;
    }

    Repeater {
        id: panelRepeater
        model: SearchPanelRegistry.enabledPanels

        delegate: Loader {
            id: panelLoader
            required property var modelData

            readonly property bool isActive: root.activePanelId === modelData.id
            readonly property bool keepAlive: item?.keepAlive === true

            anchors.fill: parent
            // A hidden file operation must be allowed to finish after Search
            // returns to its default level. Destroying the Loader here used to
            // terminate an in-flight cross-filesystem move halfway through.
            active: isActive || opacity > 0.01 || keepAlive
            visible: opacity > 0.01
            source: modelData.source
            opacity: isActive ? 1.0 : 0.0

            transform: Translate {
                y: (1.0 - panelLoader.opacity) * 16
            }

            layer.enabled: opacity > 0.001 && opacity < 0.999
            layer.effect: MultiEffect {
                blurEnabled: (1.0 - panelLoader.opacity) > 0.001
                blurMax: 32.0
                blur: (1.0 - panelLoader.opacity) * 0.5
            }

            Behavior on opacity {
                enabled: !root.inNotchMode
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            onLoaded: {
                if (isActive)
                    root.activeItem = item;
            }
            onIsActiveChanged: {
                if (isActive && status === Loader.Ready)
                    root.activeItem = item;
            }

            Binding {
                target: panelLoader.item
                property: modelData.queryProperty ?? "searchQuery"
                value: root.queryFor(modelData)
                when: panelLoader.status === Loader.Ready && String(modelData.queryProperty ?? "").length > 0
            }
        }
    }

    onActivePanelIdChanged: {
        // Never route keys or geometry to the panel that just faded out while
        // the next Loader is still incubating.
        activeItem = null;
    }
}
