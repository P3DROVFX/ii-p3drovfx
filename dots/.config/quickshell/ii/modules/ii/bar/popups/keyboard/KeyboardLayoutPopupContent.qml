import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

// Reusable content for the keyboard-layout popup. Rendered either inside the
// bar's StyledPopup window (bar) or inside the shelf's in-window chipPopup
// slot (akebono shelf), so the popup body is defined exactly once. Drive the
// entrance animation by binding `opened` and `popupOpenProgress`.
Item {
    id: ctn

    property bool opened: false
    property real popupOpenProgress: 0.0

    implicitWidth: cardsRow.implicitWidth + cardsRow.spacing * (Math.max(1, HyprlandXkb.layoutCodes.length) - 1)
    implicitHeight: 140

    RowLayout {
        id: cardsRow
        anchors.centerIn: parent
        spacing: 12

        Repeater {
            model: HyprlandXkb.layoutCodes

            delegate: Rectangle {
                id: layoutCard
                anchors.topMargin: 0
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
                        text: (layoutCodeString || "").toUpperCase()
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

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        const idx = index;
                        const cmd = "hyprctl switchxkblayout all " + idx;
                        const proc = Qt.createQmlObject('import Quickshell; Process { command: ["bash", "-c", "' + cmd + '"] }', ctn);
                        proc.running = true;
                    }
                }

                readonly property bool startAnim: ctn.opened && ctn.popupOpenProgress > 0.6

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
                    target: ctn
                    function onPopupOpenProgressChanged() {
                        if (ctn && ctn.popupOpenProgress === 0.0) {
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
                    x: (ctn.opened && ctn.popupOpenProgress > 0.6) ? 0 : 25
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