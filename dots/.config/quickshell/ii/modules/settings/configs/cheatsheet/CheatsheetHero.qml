pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The cheatsheet without a mock-up: the shortcut that opens it as two big keycaps (they
 * turn primary while it is open), a button that opens it, and a rail of every page it can
 * hold: the pages that exist are filled, the ones switched off stay as dashed outlines, and
 * a click on a page turns it on or off (Keybinds, with no `key`, is always there).
 * `pages`: [{ key, symbol, name, enabled }].
 */
Rectangle {
    id: root

    readonly property real padding: 24
    readonly property real compactBreak: 560
    readonly property real keyHeight: 72
    readonly property real keyPadding: 28
    readonly property real keyGap: 10
    readonly property real keyRadiusRatio: 0.3
    readonly property real keyFontRatio: 0.36
    readonly property real buttonHeight: 48
    readonly property real railHeight: 32
    readonly property real railGap: 8
    readonly property real railHoverAlpha: 0.08
    readonly property real sectionGap: 20
    readonly property var keys: ["Super", "/"]

    property var pages: []

    signal pageToggled(string key, bool value)

    readonly property int pageCount: root.pages.filter(page => page.enabled).length
    readonly property bool compact: root.width < root.compactBreak
    readonly property bool cheatsheetOpen: GlobalStates.cheatsheetOpen

    implicitHeight: layout.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: root.padding
        }
        spacing: root.sectionGap

        GridLayout {
            Layout.fillWidth: true
            columns: root.compact ? 1 : 2
            columnSpacing: root.sectionGap
            rowSpacing: root.sectionGap

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    text: Translation.tr("Cheatsheet shortcut")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                RowLayout {
                    spacing: root.keyGap

                    Repeater {
                        model: root.keys

                        delegate: Rectangle {
                            id: cap

                            required property string modelData

                            implicitHeight: root.keyHeight
                            implicitWidth: Math.max(root.keyHeight, capText.implicitWidth + root.keyPadding * 2)
                            radius: Math.min(height * root.keyRadiusRatio, Appearance.rounding.verylarge)
                            color: root.cheatsheetOpen ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            StyledText {
                                id: capText
                                anchors.centerIn: parent
                                text: cap.modelData
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Math.round(root.keyHeight * root.keyFontRatio)
                                color: root.cheatsheetOpen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 pages ready").arg(root.pageCount)
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                Layout.alignment: root.compact ? Qt.AlignLeft : Qt.AlignRight | Qt.AlignTop
                Layout.fillWidth: root.compact
                implicitHeight: root.buttonHeight
                implicitWidth: openRow.implicitWidth + 40
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.small
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: GlobalStates.toggleCheatsheet()

                contentItem: Item {
                    RowLayout {
                        id: openRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: root.cheatsheetOpen ? "close" : "keyboard"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: root.cheatsheetOpen ? Translation.tr("Close cheatsheet") : Translation.tr("Open cheatsheet")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: root.railGap

            Repeater {
                model: root.pages

                delegate: Rectangle {
                    id: pill

                    required property var modelData
                    readonly property bool engaged: pillHover.hovered && pill.interactive
                    readonly property bool interactive: pill.modelData.key.length > 0
                    readonly property color colContent: pill.modelData.enabled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext

                    implicitHeight: root.railHeight
                    implicitWidth: pillRow.implicitWidth + 24
                    radius: height / 2
                    color: pill.modelData.enabled
                        ? (pill.engaged && pill.interactive ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                        : (pill.engaged ? ColorUtils.applyAlpha(pill.colContent, root.railHoverAlpha) : "transparent")
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    HoverHandler {
                        id: pillHover
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: pill.interactive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pageToggled(pill.modelData.key, !pill.modelData.enabled)
                    }

                    DashedBorder {
                        anchors.fill: parent
                        visible: !pill.modelData.enabled
                        color: ColorUtils.applyAlpha(pill.colContent, 0.55)
                        borderWidth: 1
                        dashLength: 4
                        gapLength: 3
                        radius: height / 2
                    }

                    RowLayout {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: pill.modelData.symbol
                            iconSize: Appearance.font.pixelSize.normal
                            fill: pill.modelData.enabled ? 1 : 0
                            color: pill.colContent
                        }
                        StyledText {
                            text: pill.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: pill.colContent
                        }
                    }
                }
            }
        }
    }
}
