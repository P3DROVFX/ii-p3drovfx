pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

import qs.modules.akebono
import qs.modules.akebono.shelf.widgets.controlPanel

Column {
    id: section
    required property var panel
    spacing: 0

    property bool active: section.panel.style === "classic" || section.panel.style === "android"

    function removeToggle(type) {
        let list = [...section.panel.enabledToggles];
        const idx = list.indexOf(type);
        if (idx >= 0)
            list.splice(idx, 1);
        Config.options.akebono.shelf.quickSettings.toggles = list;
    }
    function addToggle(type) {
        let list = [...section.panel.enabledToggles];
        list.push(type);
        Config.options.akebono.shelf.quickSettings.toggles = list;
    }
    function moveToggle(index, offset) {
        let list = [...section.panel.enabledToggles];
        const target = index + offset;
        if (target < 0 || target >= list.length)
            return;
        const tmp = list[index];
        list[index] = list[target];
        list[target] = tmp;
        Config.options.akebono.shelf.quickSettings.toggles = list;
    }

    // ── Add-chips tray (aqebono chips only) ─────────────────────────────────
    Item {
        id: editPanelWrapper
        visible: !section.active
        width: parent.width
        clip: true
        height: section.panel.shelf?.qsEditH ?? 0
        opacity: section.panel.editMode ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Binding {
            target: section.panel.shelf
            property: "qsEditH"
            value: section.panel.editMode ? editCol.implicitHeight : 0
            when: section.panel.shelf !== null
        }

        Column {
            id: editCol
            width: parent.width
            anchors.bottom: parent.bottom
            spacing: 10
            bottomPadding: 10

            Flow {
                id: addFlow
                width: parent.width
                spacing: 6

                Repeater {
                    model: section.panel.allToggleTypes.filter(t => !section.panel.enabledToggles.includes(t))
                    delegate: Item {
                        id: addSlot
                        required property string modelData
                        width: 44
                        height: 44
                        visible: addLoader.item?.shown ?? true
                        opacity: 0.55

                        Loader {
                            id: addLoader
                            anchors.fill: parent
                            sourceComponent: section.panel.registry.toggleFor(addSlot.modelData)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            z: 100
                            onClicked: section.addToggle(addSlot.modelData)
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: 1
                color: Appearance.colors.colOnLayer0
                opacity: 0.14
            }
        }
    }

    // ── aqebono chips row (chips + swap gesture editing) ────────────────────
    Item {
        id: chipsRegion
        visible: !section.active
        width: parent.width
        implicitHeight: Math.max(toggleFlick.height, 48)

        MouseArea {
            id: wheelScrollArea
            anchors.fill: toggleFlick
            z: 1
            visible: section.panel.flickMode && !section.panel.editMode
            acceptedButtons: Qt.NoButton
            property real targetX: toggleFlick.contentX
            onWheel: event => {
                targetX = Math.max(0, Math.min(toggleFlick.contentWidth - toggleFlick.width, targetX - event.angleDelta.y));
                scrollAnim.stop();
                scrollAnim.from = toggleFlick.contentX;
                scrollAnim.to = targetX;
                scrollAnim.restart();
                event.accepted = true;
            }
        }
        NumberAnimation {
            id: scrollAnim
            target: toggleFlick
            property: "contentX"
            duration: 300
            easing.type: Easing.OutCubic
        }

        Flickable {
            id: toggleFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: section.panel.flickMode ? 48 : toggleFlow.implicitHeight
            contentWidth: toggleFlow.width
            contentHeight: toggleFlow.implicitHeight
            flickableDirection: Flickable.HorizontalFlick
            interactive: section.panel.flickMode && !section.panel.editMode
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: toggleFlow
                width: section.panel.flickMode
                    ? (section.panel.enabledToggles.length * 48 + Math.max(0, section.panel.enabledToggles.length - 1) * spacing)
                    : toggleFlick.width
                spacing: 6

                Repeater {
                    model: section.panel.enabledToggles
                    delegate: Item {
                        id: toggleSlot
                        required property string modelData
                        required property int index
                        width: 48
                        height: 48
                        z: dragMouse.dragActive ? 100 : 0
                        visible: toggleLoader.item?.shown ?? true
                        opacity: section.panel.editMode ? 0.6 : 1

                        property real dragX: 0
                        transform: Translate { x: toggleSlot.dragX }

                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Loader {
                            id: toggleLoader
                            anchors.fill: parent
                            sourceComponent: section.panel.registry.toggleFor(toggleSlot.modelData)
                            onLoaded: if (item) item.panel = section.panel
                        }
                        MouseArea {
                            visible: !section.panel.editMode && section.panel.hasDialog(toggleSlot.modelData)
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            z: 50
                            onClicked: section.panel.activeDialog = section.panel.activeDialog === toggleSlot.modelData ? "" : toggleSlot.modelData
                        }
                        MouseArea {
                            id: dragMouse
                            visible: section.panel.editMode
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            z: 100

                            property real pressX: 0
                            property bool dragging: false
                            property bool dragActive: dragging
                            readonly property int cell: 54

                            onPressed: mouse => {
                                pressX = mouse.x;
                                dragging = false;
                            }
                            onPositionChanged: mouse => {
                                if (!dragging && Math.abs(mouse.x - pressX) > 6)
                                    dragging = true;
                                if (dragging)
                                    toggleSlot.dragX = mouse.x - pressX;
                            }
                            onReleased: mouse => {
                                if (dragging) {
                                    const delta = Math.round((mouse.x - pressX) / dragMouse.cell);
                                    section.moveToggle(toggleSlot.index, delta);
                                    toggleSlot.dragX = 0;
                                    dragging = false;
                                }
                            }
                            onCanceled: {
                                toggleSlot.dragX = 0;
                                dragging = false;
                            }
                            onClicked: section.removeToggle(toggleSlot.modelData)
                            onWheel: event => {
                                section.moveToggle(toggleSlot.index, event.angleDelta.y > 0 ? -1 : 1);
                                event.accepted = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // ── shared sidebar panel (classic / android) ────────────────────────────
    Item {
        id: sharedRegion
        visible: section.active
        width: parent.width
        implicitHeight: Math.max(sharedPanel.height, 48)

        SharedQuickPanel {
            id: sharedPanel
            panel: section.panel
            width: parent.width
            editMode: section.panel.editMode
            onOpenAudioOutputDialog: section.panel.activeDialog = "audio"
            onOpenAudioInputDialog: section.panel.activeDialog = "mic"
            onOpenBluetoothDialog: section.panel.activeDialog = "bluetooth"
            onOpenNightLightDialog: section.panel.activeDialog = "nightLight"
            onOpenWifiDialog: section.panel.activeDialog = "network"
            onOpenDarkModeDialog: section.panel.showDarkModeDialog = true
            onOpenLocalSendDialog: section.panel.showLocalSendDialog = true
            onOpenVpnDialog: section.panel.showVpnDialog = true
            onOpenTailscaleDialog: section.panel.showTailscaleDialog = true
            onOpenDnsOverTlsDialog: section.panel.showDnsOverTlsDialog = true
            onOpenIdleInhibitorDialog: section.panel.showIdleInhibitorDialog = true
            onOpenScreenShaderDialog: section.panel.showScreenShaderDialog = true
            onOpenModesDialog: section.panel.showModesDialog = true
        }
    }
}