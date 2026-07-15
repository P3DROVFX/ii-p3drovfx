import qs.modules.ii.bar.shared
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

StyledPopup {
    id: popupRoot
    property Item targetItem
    property string appClassText
    property string appTitleText
    property string activeWindowAddress
    property var monitor
    property int popupWidth: 350
    property int maxPopupWidth: 600

    hoverTarget: targetItem
    stickyHover: true

    readonly property bool startAnim: popupRoot.opened && popupRoot.popupOpenProgress > 0.6
    
    onStartAnimChanged: {
        if (startAnim) {
            mainCard.opacity = 0.0;
            mainCard.scale = 0.85;
            mainCardTrans.y = 25;

            appNameContainer.opacity = 0.0;
            appNameContainerTrans.x = -15;

            popupText.opacity = 0.0;
            popupText.scale = 0.95;

            bottomRow.opacity = 0.0;
            bottomRowTrans.y = 10;

            Qt.callLater(function() {
                mainCardAnim.start();
                appNameContainerAnim.start();
                popupTextAnim.start();
                bottomRowAnim.start();
            });
        }
    }

    Rectangle {
        id: mainCard
        implicitWidth: Math.max(popupRoot.popupWidth, Math.min(popupRoot.maxPopupWidth, popupText.implicitWidth + 32))
        implicitHeight: contentCol.implicitHeight + 32
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainerHigh

        opacity: 0.0
        scale: 0.85
        transform: Translate {
            id: mainCardTrans
            y: 25
        }

        SequentialAnimation {
            id: mainCardAnim
            ParallelAnimation {
                NumberAnimation { target: mainCard; property: "opacity"; to: 1.0; duration: 300 }
                NumberAnimation { target: mainCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                NumberAnimation { target: mainCardTrans; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
            }
        }

        ColumnLayout {
            id: contentCol
            anchors {
                fill: parent
                margins: 16
            }
            spacing: 12

            RowLayout {
                spacing: 8

                Rectangle {
                    id: appNameContainer
                    color: Appearance.colors.colPrimaryContainer
                    radius: Appearance.rounding.verysmall
                    implicitWidth: appNameText.implicitWidth + 16
                    implicitHeight: appNameText.implicitHeight + 8

                    opacity: 0.0
                    transform: Translate {
                        id: appNameContainerTrans
                        x: -15
                    }

                    SequentialAnimation {
                        id: appNameContainerAnim
                        PauseAnimation { duration: 80 }
                        ParallelAnimation {
                            NumberAnimation { target: appNameContainer; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: appNameContainerTrans; property: "x"; from: -15; to: 0; duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    StyledText {
                        id: appNameText
                        anchors.centerIn: parent
                        text: popupRoot.appClassText
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                Item { Layout.fillWidth: true }


                StyledText {
                    text: popupRoot.activeWindowAddress
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colSubtext
                    visible: popupRoot.activeWindowAddress !== "0xundefined"
                }
            }

            StyledText {
                id: popupText
                Layout.fillWidth: true
                text: popupRoot.appTitleText
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurface
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight

                opacity: 0.0
                scale: 0.95

                SequentialAnimation {
                    id: popupTextAnim
                    PauseAnimation { duration: 140 }
                    ParallelAnimation {
                        NumberAnimation { target: popupText; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                        NumberAnimation { target: popupText; property: "scale"; from: 0.95; to: 1.0; duration: 300; easing.type: Easing.OutBack }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colLayer0Border
            }

            RowLayout {
                id: bottomRow
                spacing: 6

                opacity: 0.0
                transform: Translate {
                    id: bottomRowTrans
                    y: 10
                }

                SequentialAnimation {
                    id: bottomRowAnim
                    PauseAnimation { duration: 200 }
                    ParallelAnimation {
                        NumberAnimation { target: bottomRow; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                        NumberAnimation { target: bottomRowTrans; property: "y"; from: 10; to: 0; duration: 300; easing.type: Easing.OutCubic }
                    }
                }

                MaterialSymbol {
                    text: "computer"
                    iconSize: 14
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: popupRoot.monitor?.name ?? "Unknown"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: "•"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                MaterialSymbol {
                    text: "grid_view"
                    iconSize: 14
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: `${Translation.tr("Workspace")} ${popupRoot.monitor?.activeWorkspace?.id ?? 1}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
