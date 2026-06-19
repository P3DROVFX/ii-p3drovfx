import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ColumnLayout {
    id: presetsViewRoot
    property string text: ""
    spacing: 15
    Layout.fillWidth: true

    ListModel {
        id: presetsModel
    }

    Process {
        id: listPresetsProc
        command: ["bash", "-c", `${Directories.scriptPath}/presets.sh list`]
        onRunningChanged: {
            if (running) {
                presetsModel.clear();
            }
        }
        stdout: SplitParser {
            onRead: data => {
                let str = data.trim();
                if (!str)
                    return;
                try {
                    let obj = JSON.parse(str);
                    presetsModel.append(obj);
                } catch (e) {
                    console.log("Failed to parse preset line:", e, str);
                }
            }
        }
    }

    Process {
        id: importPresetProc
        command: ["bash", "-c", `${Directories.scriptPath}/presets.sh import`]
        stdout: SplitParser {
            onRead: data => {
                if (data.trim() === "success") {
                    refreshTimer.restart();
                }
            }
        }
    }

    Component.onCompleted: {
        listPresetsProc.running = true;
    }

    ConfigRow {
        Layout.fillWidth: true
        Layout.preferredHeight: 48

        ToolbarTextField {
            id: presetNameInput
            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholderText: Translation.tr("Preset name...")
            font.pixelSize: Appearance.font.pixelSize.normal
        }

        RippleButtonWithIcon {
            materialIcon: "save"
            mainText: Translation.tr("Save")
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.small
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.small
            Layout.fillHeight: true
            enabled: presetNameInput.text.length > 0
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Directories.scriptPath}/presets.sh save "${presetNameInput.text}"`]);
                refreshTimer.restart();
                presetNameInput.text = "";
            }
        }

        RippleButtonWithIcon {
            materialIcon: "file_upload"
            mainText: Translation.tr("Import")
            topLeftRadius: Appearance.rounding.small
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.small
            bottomRightRadius: Appearance.rounding.full
            Layout.fillHeight: true
            onClicked: {
                importPresetProc.running = false;
                importPresetProc.running = true;
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 500
        onTriggered: listPresetsProc.running = true
    }

    Item {
        id: flowContainer
        Layout.fillWidth: true
        Layout.topMargin: 15
        implicitHeight: flowLayout.implicitHeight
        visible: presetsModel.count > 0

        Flow {
            id: flowLayout
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 15

            readonly property int minWidth: 200
            readonly property int spacingWidth: 15
            readonly property int columns: Math.max(1, Math.floor((width + spacingWidth) / (minWidth + spacingWidth)))
            readonly property real itemWidth: Math.floor((width - (columns - 1) * spacingWidth) / columns)

            add: Transition {
                NumberAnimation {
                    properties: "scale,opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
            }
            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Repeater {
                model: presetsModel

                delegate: Rectangle {
                    id: presetItem
                    width: flowLayout.itemWidth
                    height: width * 0.8
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerLow
                    border.color: presetButton.down ? Appearance.colors.colPrimaryActive : (presetButton.hovered ? Appearance.colors.colPrimary : "transparent")
                    border.width: 2

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    scale: presetButton.down ? 0.95 : 1

                    RippleButton {
                        id: presetButton
                        anchors.fill: parent
                        buttonRadius: Appearance.rounding.normal
                        colBackground: "transparent"
                        colBackgroundHover: "transparent"
                        colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                        onClicked: {
                            Quickshell.execDetached(["bash", "-c", `${Directories.scriptPath}/presets.sh load "${model.name}"`]);
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            StyledImage {
                                id: previewImage
                                anchors.fill: parent
                                sourceSize: Qt.size(400, 400)
                                source: model.wallpaper || `${Directories.assetsPath}/images/default_wallpaper.png`
                                fillMode: Image.PreserveAspectCrop
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: previewImage.width
                                        height: previewImage.height
                                        radius: Appearance.rounding.small
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 30

                            StyledText {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: exportButton.left
                                anchors.rightMargin: 10
                                text: model.name
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }

                            RippleButton {
                                id: deleteButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 30
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colError
                                colBackgroundHover: Appearance.colors.colErrorHover
                                colRipple: Appearance.colors.colErrorActive

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    iconSize: 16
                                    color: Appearance.colors.colOnError
                                }

                                onClicked: {
                                    Quickshell.execDetached(["bash", "-c", `${Directories.scriptPath}/presets.sh delete "${model.name}"`]);
                                    refreshTimer.restart();
                                }

                                StyledToolTip {
                                    text: Translation.tr("Delete preset")
                                }
                            }

                            RippleButton {
                                id: exportButton
                                anchors.right: deleteButton.left
                                anchors.rightMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 30
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colPrimaryContainer
                                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                colRipple: Appearance.colors.colPrimaryContainerActive

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "file_download"
                                    iconSize: 16
                                    color: Appearance.colors.colOnPrimaryContainer
                                }

                                onClicked: {
                                    Quickshell.execDetached(["bash", "-c", `${Directories.scriptPath}/presets.sh export "${model.name}"`]);
                                }

                                StyledToolTip {
                                    text: Translation.tr("Export preset")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
