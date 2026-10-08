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

    readonly property int defaultCount: sectionData.defaultCount ?? sectionData.keybinds.length
    readonly property var defaultKeybinds: sectionData.keybinds.slice(0, defaultCount)
    readonly property var customKeybinds: sectionData.keybinds.slice(defaultCount)

    function listHasMatches(kbs) {
        if (bypassFilter || cheatsheetRoot.filter === "") return kbs.length > 0;
        for (let i = 0; i < kbs.length; i++) {
            if (cheatsheetRoot.bindMatches(kbs[i], sectionData.name)) return true;
        }
        return false;
    }

    readonly property bool hasDefaultMatches: listHasMatches(defaultKeybinds)
    readonly property bool hasCustomMatches: listHasMatches(customKeybinds)
    readonly property bool hasMatches: hasDefaultMatches || hasCustomMatches
    readonly property bool showSourceSplit: hasDefaultMatches && hasCustomMatches

    visible: hasMatches || opacity > 0
    opacity: hasMatches ? 1.0 : 0.0
    clip: true

    width: cardWidth
    height: hasMatches ? implicitHeight : 0
    implicitHeight: hasMatches ? (cardContent.implicitHeight + cheatsheetRoot.cardPadding * 2) : 0

    color: Appearance.colors.colLayer4
    radius: Appearance.rounding.large

    transform: Translate {
        id: cardFlyInTrans
        y: 20
    }

    Component.onCompleted: {
        entryTimer.start();
    }

    Timer {
        id: entryTimer
        // The last card lands with the tab's own fade-in (~460 ms) rather
        // than 700 ms after the page was ready.
        interval: Math.min(sectionIndex * 20, 160)
        repeat: false
        onTriggered: {
            entryAnim.start();
        }
    }

    ParallelAnimation {
        id: entryAnim
        NumberAnimation {
            target: cardFlyInTrans
            property: "y"
            to: 0
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

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

    component KeybindRow: Row {
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
                delegate: Row {
                    required property var modelData
                    required property int index
                    spacing: 4

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Config.options.cheatsheet.splitButtons && index > 0
                        text: "+"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Config.options.cheatsheet.fontSize.key
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }
                    KeyChip {
                        chipText: cheatsheetRoot.keySubstitutions[modelData] || modelData
                        bgColor: Appearance.colors.colSurfaceContainerLow
                        textColor: Appearance.colors.colOnSurface
                    }
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.options.cheatsheet.splitButtons && !cheatsheetRoot.keyBlacklist.includes(bindRow.modelData.key) && bindRow.modelData.mods.length > 0
                text: "+"
                font.family: Appearance.font.family.monospace
                font.pixelSize: Config.options.cheatsheet.fontSize.key
                font.weight: Font.Bold
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
                model: root.defaultKeybinds
                delegate: KeybindRow {}
            }

            Item {
                visible: root.showSourceSplit
                height: visible ? 9 : 0
                anchors.left: parent.left
                anchors.right: parent.right

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    radius: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.45
                }
            }

            Repeater {
                model: root.customKeybinds
                delegate: KeybindRow {}
            }
        }
    }
}
