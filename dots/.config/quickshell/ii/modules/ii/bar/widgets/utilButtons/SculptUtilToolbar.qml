pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * `toolbar` variant of the Sculpt utility buttons — a floating toolbar and its FAB.
 *
 * The first button leaves the row and becomes the FAB: a rounded square on the
 * vivid tone, its corners loosening under the pointer and tightening while it
 * is held. The rest are bare icons on a soft toolbar; a toggle that latched gets
 * a filled disc inside the toolbar, the way an editor marks the tool in use.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property BarWidgetPalette tones
    property UtilButtonActions actionSet
    property var actions: []

    readonly property string fabKey: root.actions.length > 0 ? root.actions[0] : ""
    readonly property var toolKeys: root.actions.slice(1)
    readonly property real gap: 4
    readonly property real itemSize: root.thickness - 6
    readonly property bool sharp: Appearance.rounding.scale === 0

    implicitWidth: root.vertical ? root.thickness : layout.implicitWidth
    implicitHeight: root.vertical ? layout.implicitHeight : root.thickness

    Grid {
        id: layout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        spacing: root.gap

        // ── The toolbar ─────────────────────────────────────────────────────
        Rectangle {
            visible: root.toolKeys.length > 0
            width: root.vertical ? root.thickness : tools.implicitWidth + 6
            height: root.vertical ? tools.implicitHeight + 6 : root.thickness
            radius: root.sharp ? 0 : root.thickness / 2
            color: root.tones.colBackgroundVariant

            Grid {
                id: tools
                anchors.centerIn: parent
                columns: root.vertical ? 1 : Math.max(1, root.toolKeys.length)
                spacing: 1

                Repeater {
                    model: root.toolKeys

                    delegate: Item {
                        id: tool
                        required property string modelData
                        readonly property bool active: root.actionSet.activeFor(tool.modelData)

                        implicitWidth: root.itemSize
                        implicitHeight: root.itemSize

                        Rectangle {
                            anchors.fill: parent
                            radius: root.sharp ? 0 : width / 2
                            color: tool.active
                                ? (press.containsMouse ? root.tones.colBackgroundHover : root.tones.colBackground)
                                : ColorUtils.transparentize(root.tones.colOnBackgroundVariant, press.containsMouse ? 0.88 : 1)
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.actionSet.iconFor(tool.modelData)
                            iconSize: Math.round(root.thickness * 0.53)
                            fill: tool.active ? 1 : 0
                            color: tool.active ? root.tones.colOnBackground : root.tones.colOnBackgroundVariant
                        }

                        SculptUtilPress {
                            id: press
                            key: tool.modelData
                            actionSet: root.actionSet
                        }
                    }
                }
            }
        }

        // ── The FAB ─────────────────────────────────────────────────────────
        Rectangle {
            id: fab
            readonly property bool active: root.actionSet.activeFor(root.fabKey)
            readonly property real corner: root.sharp ? 0
                : fabPress.pressed ? root.thickness * 0.2
                : fab.active ? root.thickness / 2
                : fabPress.containsMouse ? root.thickness * 0.4 : root.thickness * 0.3

            width: root.thickness
            height: root.thickness
            radius: fab.animatedCorner
            property real animatedCorner: fab.corner
            Behavior on animatedCorner {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(fab)
            }
            color: fabPress.containsMouse ? root.tones.colBackgroundHover : root.tones.colBackground
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(fab)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.actionSet.iconFor(root.fabKey)
                iconSize: Math.round(root.thickness * 0.6)
                fill: fab.active ? 1 : 0
                color: root.tones.colOnBackground
            }

            SculptUtilPress {
                id: fabPress
                key: root.fabKey
                actionSet: root.actionSet
            }
        }
    }
}
