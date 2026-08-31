import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay
import qs.modules.ii.sidebarDashboard.volumeMixer

StyledOverlayWidget {
    id: root
    minimumWidth: 300
    minimumHeight: 380

    contentItem: OverlayBackground {
        radius: root.contentRadius
        property real padding: 6

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: parent.padding
            }
            spacing: 8

            SecondaryTabBar {
                id: tabBar

                currentIndex: swipeView.currentIndex
                onCurrentIndexChanged: {
                    if (swipeView.currentIndex !== currentIndex) {
                        swipeView.currentIndex = currentIndex;
                    }
                }

                SecondaryTabButton {
                    buttonIcon: "media_output"
                    buttonText: Translation.tr("Output")
                }
                SecondaryTabButton {
                    buttonIcon: "mic"
                    buttonText: Translation.tr("Input")
                }
            }
            SwipeView {
                id: swipeView
                property bool initialized: false
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: Persistent.states.overlay.volumeMixer.tabIndex ?? 0
                Component.onCompleted: initialized = true
                onCurrentIndexChanged: {
                    if (initialized && Persistent.states.overlay.volumeMixer.tabIndex !== currentIndex) {
                        Persistent.states.overlay.volumeMixer.tabIndex = currentIndex;
                    }
                }
                interactive: !outputContent.isDragging && !inputContent.isDragging
                clip: true

                PaddedVolumeDialogContent {
                    id: outputContent
                    isSink: true 
                }
                PaddedVolumeDialogContent {
                    id: inputContent
                    isSink: false 
                }
            }
        }
    }

    dragLocked: outputContent.isDragging || inputContent.isDragging

    component PaddedVolumeDialogContent: Item {
        id: paddedVolumeDialogContent
        property alias isSink: volDialogContent.isSink
        readonly property bool isDragging: volDialogContent.activePlaybackDragIndex >= 0 || volDialogContent.activeRecordingDragIndex >= 0
        property real padding: 12
        implicitWidth: volDialogContent.implicitWidth + padding * 2
        implicitHeight: volDialogContent.implicitHeight + padding * 2

        VolumeDialogContent {
            id: volDialogContent
            anchors {
                fill: parent
                margins: paddedVolumeDialogContent.padding
            }
        }
    }
}
