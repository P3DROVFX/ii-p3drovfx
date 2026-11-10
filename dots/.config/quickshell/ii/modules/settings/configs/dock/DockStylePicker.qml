pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The dock's seven trays as cards in two families — the ones that float off the
 * edge and the ones that sit on it — each with its silhouette against a screen
 * edge, drawn light on the dark desktop so it reads on any theme. The chosen card
 * fills with the secondary container, opens its corners and draws its tray in
 * primary (no ring); pointing at a card tries it on the page's live dock (`tried`).
 */
Item {
    id: root

    property string currentValue: "floating"
    /** The style under the pointer, "" when none. */
    property string tried: ""
    readonly property int gap: 10
    readonly property real minCard: 132

    signal selected(string value)

    readonly property var families: [
        {
            "title": Translation.tr("Floating"),
            "styles": [
                { "value": "floating", "title": Translation.tr("Floating") },
                { "value": "islands", "title": Translation.tr("Islands") },
                { "value": "transparent", "title": Translation.tr("Transparent") }
            ]
        },
        {
            "title": Translation.tr("On the edge"),
            "styles": [
                { "value": "hug", "title": Translation.tr("Hug") },
                { "value": "dynamic_island", "title": Translation.tr("Dynamic Island") },
                { "value": "full_width", "title": Translation.tr("Full width") },
                { "value": "full_width_concave", "title": Translation.tr("Full width · rounded") }
            ]
        }
    ]

    /** Wide enough for all seven in one row: the two families side by side. */
    readonly property real familyGap: 14
    readonly property bool sideBySide: root.width >= 7 * root.minCard + 5 * root.gap + root.familyGap + 120
    implicitHeight: familyFlow.implicitHeight

    Flow {
        id: familyFlow
        width: root.width
        spacing: root.familyGap

    Repeater {
        model: root.families
        delegate: ColumnLayout {
            id: family
            required property var modelData
            readonly property int count: family.modelData.styles.length
            width: root.sideBySide ? Math.floor((root.width - root.familyGap - root.gap * 5) * family.count / 7 + root.gap * (family.count - 1)) : root.width
            // All in one row when they fit; otherwise rows of two, never a lone card.
            readonly property int cols: (family.width - root.gap * (family.count - 1)) / family.count >= root.minCard
                ? family.count : (family.count % 2 === 0 ? 2 : family.count)
            readonly property real cardWidth: Math.floor((family.width - root.gap * (family.cols - 1)) / family.cols)
            spacing: 8

            StyledText {
                text: family.modelData.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colSubtext
            }

            Flow {
                Layout.fillWidth: true
                spacing: root.gap
                Repeater {
                    model: family.modelData.styles
                    delegate: StyleCard {
                        required property var modelData
                        value: modelData.value
                        title: modelData.title
                        width: family.cardWidth
                    }
                }
            }
        }
    }
    }

    component StyleCard: Item {
        id: shell

        required property string value
        required property string title
        readonly property bool chosen: root.currentValue === shell.value
        height: 124

        RippleButton {
            id: card
            anchors.fill: parent
            readonly property color colContent: shell.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            // Chosen: the corners open out and the card fills — shape and colour, no ring.
            buttonRadius: shell.chosen ? Appearance.rounding.verylarge : Appearance.rounding.normal
            buttonRadiusPressed: Appearance.rounding.small
            colBackground: shell.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest
            colBackgroundHover: shell.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
            colRipple: shell.chosen ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
            onClicked: root.selected(shell.value)
            onHoveredChanged: {
                if (card.hovered)
                    root.tried = shell.value;
                else if (root.tried === shell.value)
                    root.tried = "";
            }

            contentItem: Item {
                // The screen's edge, and the tray against it.
                Rectangle {
                    id: edge
                    x: 10
                    y: 10
                    width: parent.width - 20
                    height: 66
                    // The desktop: the darkest step, so the light tray stands out on it.
                    color: Appearance.colors.colLayer0
                    radius: shell.chosen ? Appearance.rounding.large : Appearance.rounding.small
                    Behavior on radius {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    clip: true

                    // Hovering swells the tray a little, as if picking it up.
                    property real swell: card.hovered ? 1 : 0
                    Behavior on swell {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }

                    DockSilhouette {
                        anchors.fill: parent
                        styleName: shell.value
                        swell: edge.swell
                        trayColor: shell.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        dotColor: shell.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colLayer0
                        accentColor: shell.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                    }
                }

                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 10
                    height: 30
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: shell.title
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.normal
                        // Narrow cards shrink a long name before they cut it.
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: Appearance.font.pixelSize.smaller
                        color: card.colContent
                        elide: Text.ElideRight
                    }
                }

                MaterialShapeWrappedMaterialSymbol {
                    anchors.right: edge.right
                    anchors.top: edge.top
                    anchors.margins: 6
                    text: "check"
                    iconSize: 14
                    padding: 4
                    fill: 1
                    shape: shell.chosen ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                    opacity: shell.chosen ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
