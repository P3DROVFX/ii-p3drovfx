import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Choosing the page.
 *
 * Each option draws itself with the same shader the page uses, because a list of names
 * ("isometric", "graph") tells you nothing about what you are about to get and a swatch
 * tells you everything.
 */
Rectangle {
    id: root

    property string current: "plain"

    signal picked(string style)

    readonly property var options: [
        { id: "plain", name: Translation.tr("Plain") },
        { id: "grid", name: Translation.tr("Grid") },
        { id: "dots", name: Translation.tr("Dots") },
        { id: "ruled", name: Translation.tr("Ruled") },
        { id: "ruled-margin", name: Translation.tr("Ruled with margin") },
        { id: "isometric", name: Translation.tr("Isometric") },
        { id: "graph", name: Translation.tr("Graph") }
    ]

    implicitWidth: layout.implicitWidth + 20
    implicitHeight: layout.implicitHeight + 20
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainerHighest

    StyledRectangularShadow {
        target: root
    }

    GridLayout {
        id: layout
        anchors.centerIn: parent
        columns: 4
        rowSpacing: 6
        columnSpacing: 6

        Repeater {
            model: root.options

            delegate: RippleButton {
                id: swatch
                required property var modelData

                implicitWidth: 92
                implicitHeight: 78
                buttonRadius: Appearance.rounding.normal
                toggled: root.current === swatch.modelData.id
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover

                onClicked: root.picked(swatch.modelData.id)

                contentItem: ColumnLayout {
                    spacing: 4

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 74
                        Layout.preferredHeight: 40
                        radius: Appearance.rounding.verysmall
                        color: Appearance.m3colors.m3surfaceContainerLowest
                        clip: true

                        NotesPaper {
                            anchors.fill: parent
                            paperStyle: swatch.modelData.id
                            // Tighter and stronger than the page, so a 74px swatch shows
                            // the pattern rather than one line of it.
                            paperSpacing: 9
                            paperStrength: 0.85
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Aa")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            opacity: 0.7
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: 84
                        text: swatch.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: swatch.toggled
                            ? Appearance.m3colors.m3onSecondaryContainer
                            : Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
