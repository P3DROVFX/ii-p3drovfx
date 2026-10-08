pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "WorkspacesCatalog.js" as Catalog

/**
 * How the active workspace is marked, as four tiles that each act their mode out:
 * a dot hops along three workspaces as a pill, the chosen shape, a new shape per
 * hop, or an arrow aimed the way it went. They play while chosen or pointed at.
 */
Item {
    id: root

    property string currentValue: "pill"
    property string shapeName: "Pentagon"
    property var names: ({})
    property var lines: ({})
    property var unavailable: ({})

    readonly property real gap: 10
    readonly property real minTileWidth: 150
    readonly property real tileHeight: 150
    readonly property real demoHeight: 54
    readonly property real dotSize: 6
    readonly property real markSize: 24
    readonly property real stepSize: 34
    readonly property int hopInterval: 900
    readonly property int arrowHold: 520
    readonly property int columns: width >= root.minTileWidth * 4 + root.gap * 3 ? 4 : 2
    readonly property real tileWidth: Math.floor((width - root.gap * (root.columns - 1)) / root.columns)

    property string tried: ""

    signal selected(string value)

    implicitHeight: Math.ceil(Catalog.INDICATORS.length / root.columns) * (root.tileHeight + root.gap) - root.gap

    Repeater {
        model: Catalog.INDICATORS

        delegate: RippleButton {
            id: tile
            required property var modelData
            required property int index
            readonly property string mode: tile.modelData.id
            readonly property bool chosen: root.currentValue === tile.mode
            readonly property bool blocked: root.unavailable[tile.mode] === true
            readonly property color colContent: tile.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
            readonly property color colMark: tile.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSecondary

            x: (tile.index % root.columns) * (root.tileWidth + root.gap)
            y: Math.floor(tile.index / root.columns) * (root.tileHeight + root.gap)
            width: root.tileWidth
            height: root.tileHeight
            opacity: tile.blocked ? 0.5 : 1
            buttonRadius: tile.chosen ? Appearance.rounding.verylarge : Appearance.rounding.large
            buttonRadiusPressed: Appearance.rounding.normal
            colBackground: tile.chosen ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
            colBackgroundHover: tile.chosen ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
            colRipple: tile.chosen ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active
            onClicked: {
                if (!tile.blocked)
                    root.selected(tile.mode);
            }
            onHoveredChanged: {
                if (tile.hovered)
                    root.tried = tile.mode;
                else if (root.tried === tile.mode)
                    root.tried = "";
            }

            StyledToolTip {
                visible: tile.blocked && tile.hovered
                text: root.unavailable[tile.mode + "Text"] ?? ""
            }

            contentItem: Item {
                Item {
                    id: demo
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 16
                    width: root.stepSize * 2 + root.markSize
                    height: root.demoHeight

                    property int at: 0
                    property int step: 1
                    property bool moving: false
                    property int hop: 0

                    Timer {
                        interval: root.hopInterval
                        repeat: true
                        running: tile.chosen || tile.hovered
                        onTriggered: {
                            if (demo.at + demo.step > 2 || demo.at + demo.step < 0)
                                demo.step = -demo.step;
                            demo.at += demo.step;
                            demo.hop++;
                            demo.moving = true;
                            arrowRelease.restart();
                        }
                    }
                    Timer {
                        id: arrowRelease
                        interval: root.arrowHold
                        onTriggered: demo.moving = false
                    }

                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            x: index * root.stepSize + (root.markSize - root.dotSize) / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.dotSize
                            height: root.dotSize
                            radius: root.dotSize / 2
                            color: tile.colContent
                            opacity: 0.35
                        }
                    }

                    Item {
                        id: mark
                        x: demo.at * root.stepSize - (tile.mode === "pill" ? root.markSize * 0.25 : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        width: tile.mode === "pill" ? root.markSize * 1.5 : root.markSize
                        height: root.markSize
                        Behavior on x {
                            NumberAnimation {
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.7
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: tile.mode === "pill"
                            radius: height / 2
                            color: tile.colMark
                        }
                        MaterialShape {
                            anchors.fill: parent
                            visible: tile.mode !== "pill"
                            color: tile.colMark
                            shapeString: tile.mode === "shape" ? root.shapeName
                                : tile.mode === "random" ? Catalog.RANDOM_SHAPES[demo.hop % Catalog.RANDOM_SHAPES.length]
                                : (demo.moving ? "Triangle" : "Circle")
                            rotation: tile.mode === "arrow" ? (demo.step > 0 ? 90 : 270)
                                : tile.mode === "random" ? demo.hop * 90 : 0
                        }
                    }
                }

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 14
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: root.names[tile.mode] ?? tile.mode
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: tile.colContent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.lines[tile.mode] ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: tile.colContent
                        opacity: 0.75
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
