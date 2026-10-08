pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "WorkspacesCatalog.js" as Catalog

/**
 * The five styles as cards, each drawing its own row with the page's options.
 * The chosen one wears the primary ring; `tried` is the card under the pointer.
 */
Item {
    id: root

    required property WorkspacesPreviewState preview
    property string currentValue: "default"
    property var names: ({})
    property var lines: ({})

    readonly property real gap: 12
    readonly property real minCardWidth: 210
    readonly property real cardHeight: 156
    readonly property real stageHeight: 64
    readonly property real stageMargin: 10
    readonly property real ringWidth: 2.5
    readonly property real ringGap: 2
    readonly property real ringRoom: root.ringWidth + root.ringGap
    readonly property real unit: 24
    readonly property int columns: Math.max(1, Math.min(Catalog.STYLES.length, Math.floor((width + root.gap) / (root.minCardWidth + root.gap))))
    readonly property real cardWidth: Math.floor((width - root.gap * (root.columns - 1)) / root.columns)
    readonly property int rows: Math.ceil(Catalog.STYLES.length / root.columns)

    property string tried: ""

    signal selected(string value)

    implicitHeight: root.rows * root.cardHeight + (root.rows - 1) * root.gap

    Repeater {
        model: Catalog.STYLES

        delegate: Item {
            id: shell
            required property var modelData
            required property int index
            readonly property bool chosen: root.currentValue === shell.modelData.id
            property real inset: shell.chosen ? root.ringRoom : 0
            Behavior on inset {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            x: (shell.index % root.columns) * (root.cardWidth + root.gap)
            y: Math.floor(shell.index / root.columns) * (root.cardHeight + root.gap)
            width: root.cardWidth
            height: root.cardHeight

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.verylarge + root.ringRoom
                color: "transparent"
                border.width: root.ringWidth
                border.color: Appearance.colors.colPrimary
                opacity: shell.chosen ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            RippleButton {
                id: card
                anchors.fill: parent
                anchors.margins: shell.inset
                buttonRadius: Appearance.rounding.verylarge
                buttonRadiusPressed: Appearance.rounding.large
                colBackground: shell.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                colBackgroundHover: shell.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                colRipple: shell.chosen ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer1Active
                onClicked: root.selected(shell.modelData.id)
                onHoveredChanged: {
                    if (card.hovered)
                        root.tried = shell.modelData.id;
                    else if (root.tried === shell.modelData.id)
                        root.tried = "";
                }

                readonly property color colContent: shell.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

                contentItem: Item {
                    Rectangle {
                        id: stage
                        x: root.stageMargin
                        y: root.stageMargin
                        width: parent.width - root.stageMargin * 2
                        height: root.stageHeight
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        clip: true

                        WorkspacesLiveStrip {
                            anchors.centerIn: parent
                            preview: root.preview
                            styleOverride: shell.modelData.id
                            unit: root.unit
                            barColor: stage.color
                            scale: Math.min(1, (stage.width - 16) / Math.max(1, implicitWidth))
                            slotOverride: card.hovered ? -1 : 1
                        }
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: stage.bottom
                        anchors.margins: root.stageMargin + 4
                        anchors.topMargin: 10
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                Layout.fillWidth: true
                                text: root.names[shell.modelData.id] ?? shell.modelData.id
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.larger
                                color: card.colContent
                                elide: Text.ElideRight
                            }
                            MaterialShapeWrappedMaterialSymbol {
                                text: "check"
                                iconSize: 14
                                padding: 4
                                fill: 1
                                shape: shell.chosen ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                                color: Appearance.colors.colPrimary
                                colSymbol: Appearance.colors.colOnPrimary
                                opacity: shell.chosen ? 1 : 0
                                scale: shell.chosen ? 1 : 0.4
                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on scale {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.lines[shell.modelData.id] ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: card.colContent
                            opacity: 0.78
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
