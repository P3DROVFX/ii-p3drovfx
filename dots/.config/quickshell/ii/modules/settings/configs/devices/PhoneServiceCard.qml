import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * M3E Phone Integration Card: high-contrast neutral surface with primary tint
 * when active, morphing MaterialShape emblem, telemetry plate, and sharp CTA contrast.
 */
Rectangle {
    id: card

    property string overline: ""
    property string title: ""
    property string description: ""
    property string symbol: "smartphone"
    property int shapeActive: MaterialShape.Shape.Cookie7Sided
    property int shapeIdle: MaterialShape.Shape.Circle
    property bool active: false
    property bool connected: false
    property bool switchEnabled: true

    property string primaryStatLabel: ""
    property string primaryStatValue: ""
    property string secondaryStatLabel: ""
    property string secondaryStatValue: ""

    property string statusText: ""
    property string actionLabel: ""
    property string actionIcon: "tune"
    property bool showAction: true

    signal toggled(bool wantActive)
    signal actionRequested()

    implicitHeight: contentCol.implicitHeight + 40
    radius: Appearance.rounding.verylarge
    color: cardHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    // Subtle M3E tonal wash when this card is the active service (keeps text contrast crisp)
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: card.active
        color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08)
    }

    HoverHandler {
        id: cardHover
    }

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        // Header: morphing emblem + overline/title + switch
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                shape: card.active ? card.shapeActive : card.shapeIdle
                implicitSize: 50
                padding: 8
                iconSize: 22
                text: card.symbol
                fill: card.active ? 1 : 0
                color: card.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                colSymbol: card.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    visible: card.overline !== ""
                    text: card.overline
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.variableAxes: ({ "wght": 750, "wdth": 115, "ROND": 0 })
                    font.letterSpacing: 1.2
                    color: card.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: card.title
                    font.pixelSize: 20
                    font.variableAxes: ({ "wght": 750, "wdth": 100, "ROND": 0 })
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledSwitch {
                enabled: card.switchEnabled
                checked: card.active
                onToggled: card.toggled(!card.active)
            }
        }

        // Concise description
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            lineHeight: 1.25
            text: card.description
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        // AppCard-style inner telemetry plate
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: plateRow.implicitHeight + 20
            radius: Appearance.rounding.large
            color: card.active
                ? Appearance.colors.colLayer0
                : Appearance.colors.colLayer2

            RowLayout {
                id: plateRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: card.primaryStatLabel
                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: card.primaryStatValue
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnLayer1
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2
                    implicitWidth: 1
                    visible: card.secondaryStatLabel !== ""
                    color: ColorUtils.applyAlpha(Appearance.colors.colOutlineVariant, 0.45)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: card.secondaryStatLabel !== ""
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: card.secondaryStatLabel
                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: card.secondaryStatValue
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        // Footer: status badge + high-contrast action button
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 10

            Rectangle {
                implicitWidth: statusPillRow.implicitWidth + 20
                implicitHeight: 32
                radius: Appearance.rounding.full
                color: card.connected
                    ? Appearance.colors.colPrimary
                    : (card.active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2)

                RowLayout {
                    id: statusPillRow
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        implicitWidth: 7
                        implicitHeight: 7
                        radius: 4
                        color: card.connected
                            ? Appearance.colors.colOnPrimary
                            : (card.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext)
                    }

                    StyledText {
                        text: card.statusText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: card.connected
                            ? Appearance.colors.colOnPrimary
                            : (card.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                visible: card.showAction
                materialIcon: card.actionIcon
                mainText: card.actionLabel
                buttonRadius: Appearance.rounding.full
                colBackground: card.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                colBackgroundHover: card.active ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                colText: card.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                onClicked: card.actionRequested()
            }
        }
    }
}
