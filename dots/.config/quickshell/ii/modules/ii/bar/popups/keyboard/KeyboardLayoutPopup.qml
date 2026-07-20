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
                            id: keyboardIcon
                            text: "keyboard"
                            iconSize: Appearance.font.pixelSize.hugeass
                            color: layoutCard.itemsColor
                            scale: 0.8
                            rotation: -10

                            SequentialAnimation {
                                id: keyboardIconAnim
                                PauseAnimation { duration: 40 + index * 100 + 60 }
                                ParallelAnimation {
                                    NumberAnimation { target: keyboardIcon; property: "scale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                    NumberAnimation { target: keyboardIcon; property: "rotation"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        StyledText {
                            id: layoutText
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
                            opacity: 0.0

                            SequentialAnimation {
                                id: layoutTextAnim
                                PauseAnimation { duration: 40 + index * 100 + 120 }
                                NumberAnimation { target: layoutText; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                            }
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

                    readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
                    
                    onStartAnimChanged: {
                        if (startAnim) {
                            layoutCard.opacity = 0.0;
                            layoutCard.scale = 0.85;
                            layoutCardTranslate.x = 25;
                            
                            keyboardIcon.scale = 0.8;
                            keyboardIcon.rotation = -10;
                            layoutText.opacity = 0.0;
                            
                            Qt.callLater(function() {
                                layoutCardAnim.start();
                                keyboardIconAnim.start();
                                layoutTextAnim.start();
                            });
                        }
                    }
                    
                    Connections {
                        target: root
                        function onPopupOpenProgressChanged() {
                            if (root && root.popupOpenProgress === 0.0) {
                                layoutCardAnim.stop();
                                keyboardIconAnim.stop();
                                layoutTextAnim.stop();

                                layoutCard.opacity = 0.0;
                                layoutCard.scale = 0.85;
                                layoutCardTranslate.x = 25;
                                
                                keyboardIcon.scale = 0.8;
                                keyboardIcon.rotation = -10;
                                layoutText.opacity = 0.0;
                            }
                        }
                    }
                    
                    opacity: 0.0
                    scale: 1.0
                    transform: Translate {
                        id: layoutCardTranslate
                        x: (root.opened && root.popupOpenProgress > 0.6) ? 0 : 25
                    }
                    
                    SequentialAnimation {
                        id: layoutCardAnim
                        PauseAnimation { duration: 40 + index * 100 }
                        ParallelAnimation {
                            NumberAnimation { target: layoutCard; property: "opacity"; to: 1.0; duration: 300 }
                            NumberAnimation { target: layoutCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                            NumberAnimation { target: layoutCardTranslate; property: "x"; to: 0; duration: 380; easing.type: Easing.OutCubic }
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
