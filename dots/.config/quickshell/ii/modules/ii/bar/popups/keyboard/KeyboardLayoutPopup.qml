import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

StyledPopup {
    id: root
    stickyHover: true

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16

        // Cards Row
        RowLayout {
            spacing: 12

            Repeater {
                model: HyprlandXkb.layoutCodes

                delegate: Rectangle {
                    id: layoutCard
                    readonly property string layoutCodeString: modelData.trim()
                    readonly property bool isActive: HyprlandXkb.currentLayoutCode.startsWith(layoutCodeString)

                    Layout.preferredWidth: 180
                    Layout.preferredHeight: 140
                    radius: Appearance.rounding.normal

                    color: isActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer4
                    border.width: isActive ? 2 : 0
                    border.color: isActive ? Appearance.colors.colOnPrimary : "transparent"

                    readonly property color itemsColor: isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 12

                        MaterialSymbol {
                            text: "keyboard"
                            iconSize: Appearance.font.pixelSize.hugeass
                            color: layoutCard.itemsColor
                        }

                        StyledText {
                            // Convert like "BR" to "BR\nABNT" or simply capitalize
                            // We use a helper function to simulate the multiline split visually
                            text: {
                                // Default logic: simple upper. Better: attempt abbreviation match.
                                // E.g.: "br" -> "BR"
                                // If layoutCode is empty it could break, safe fallback:
                                return (layoutCodeString || "").toUpperCase();
                            }
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Black
                            color: layoutCard.itemsColor
                        }
                    }

                    // Click area
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            // Execute layout switch
                            // hyprctl switchxkblayout all <index>
                            // Using the raw shell:
                            const idx = index;
                            const cmd = "hyprctl switchxkblayout all " + idx;
                            const proc = Qt.createQmlObject('import Quickshell; Process { command: ["bash", "-c", "' + cmd + '"] }', root);
                            proc.running = true;
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }
}
