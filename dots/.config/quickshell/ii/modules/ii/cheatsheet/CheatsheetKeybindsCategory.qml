pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property var sectionData
    required property int sectionIndex
    required property var cheatsheetRoot
    required property real cardWidth

    property bool bypassFilter: false

    readonly property string iconName: cheatsheetRoot.categoryIcons[sectionData.name] ?? "keyboard"
    readonly property string shapeName: cheatsheetRoot.sectionShapes[sectionIndex % cheatsheetRoot.sectionShapes.length]

    readonly property bool hasMatches: {
        if (bypassFilter || cheatsheetRoot.filter === "") return true;
        const kbs = sectionData.keybinds;
        for (let i = 0; i < kbs.length; i++) {
            if (cheatsheetRoot.bindMatches(kbs[i], sectionData.name)) return true;
        }
        return false;
    }

    visible: hasMatches || opacity > 0
    opacity: hasMatches ? 1.0 : 0.0
    clip: true

    width: cardWidth
    height: hasMatches ? implicitHeight : 0
    implicitHeight: hasMatches ? (cardContent.implicitHeight + cheatsheetRoot.cardPadding * 2) : 0

    color: Appearance.colors.colLayer4
    radius: Appearance.rounding.large

    Behavior on opacity {
        NumberAnimation {
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasized
        }
    }
    Behavior on height {
        NumberAnimation {
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasized
        }
    }

    component KeyChip: Rectangle {
        id: chipRoot
        property string chipText
        property color textColor: Appearance.colors.colOnSurface
        property color bgColor: Appearance.colors.colSurfaceContainerLow

        implicitWidth: chipLabel.implicitWidth + 16
        implicitHeight: chipLabel.implicitHeight + 10
        radius: Appearance.rounding.small
        color: bgColor

        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            text: chipRoot.chipText
            font.family: Appearance.font.family.monospace
            font.pixelSize: Config.options.cheatsheet.fontSize.key
            font.weight: Font.Bold
            color: chipRoot.textColor
        }
    }

    Column {
        id: cardContent
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: cheatsheetRoot.cardPadding
        }
        spacing: cheatsheetRoot.cardInnerSpacing

        Row {
            spacing: 10
            anchors.left: parent.left
            anchors.right: parent.right

            MaterialShape {
                shapeString: root.shapeName
                implicitSize: 32
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.iconName
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1.0
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    weight: Font.Bold
                }
                color: Appearance.colors.colOnSurface
                text: root.sectionData.name || "Keybinds"
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            radius: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.3
        }

        Column {
            spacing: cheatsheetRoot.cardBindSpacing
            anchors.left: parent.left
            anchors.right: parent.right

            Repeater {
                model: root.sectionData.keybinds

                delegate: Row {
                    id: bindRow
                    required property var modelData
                    readonly property bool matches: root.bypassFilter || cheatsheetRoot.bindMatches(bindRow.modelData, root.sectionData.name)

                    spacing: 12
                    height: matches ? implicitHeight : 0
                    opacity: matches ? 1.0 : 0.0
                    visible: matches || opacity > 0
                    clip: true

                    Behavior on height {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                    }

                    Row {
                        spacing: 4
                        Repeater {
                            model: bindRow.modelData.mods
                            delegate: KeyChip {
                                required property var modelData
                                chipText: cheatsheetRoot.keySubstitutions[modelData] || modelData
                                bgColor: Appearance.colors.colSurfaceContainerLow
                                textColor: Appearance.colors.colOnSurface
                            }
                        }
                        StyledText {
                            visible: Config.options.cheatsheet.splitButtons && !cheatsheetRoot.keyBlacklist.includes(bindRow.modelData.key) && bindRow.modelData.mods.length > 0
                            text: "+"
                            font.pixelSize: Config.options.cheatsheet.fontSize.key
                            color: Appearance.colors.colPrimary
                        }
                        KeyChip {
                            visible: Config.options.cheatsheet.splitButtons && !cheatsheetRoot.keyBlacklist.includes(bindRow.modelData.key)
                            chipText: cheatsheetRoot.keySubstitutions[bindRow.modelData.key] || bindRow.modelData.key
                            bgColor: Appearance.colors.colPrimary
                            textColor: Appearance.colors.colOnPrimary
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurface
                        opacity: 0.7
                        text: bindRow.modelData.comment || ""
                    }
                }
            }
        }
    }
}