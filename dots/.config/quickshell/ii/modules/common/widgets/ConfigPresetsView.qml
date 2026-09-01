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

    // Applying is the owner's call, not this view's: it holds the dialog that
    // shows what the preset would let run before anything is written.
    signal applyRequested(string name, var scanResult)
    // Publishing and pulling both belong to the page that owns the dialogs;
    // this view only knows which preset a button was pressed on.
    signal publishRequested(string name)
    signal updateRequested(string name)

    property string pendingApplyName: ""

    ListModel {
        id: presetsModel
    }

    function requestApply(name) {
        presetsViewRoot.pendingApplyName = name;
        scanPresetProc.reported = false;
        scanPresetProc.running = false;
        scanPresetProc.command = ["bash", "-c", `${Directories.scriptPath}/presets.sh scan "${name}"`];
        scanPresetProc.running = true;
    }

    function applyPreset(name) {
        if (!name)
            return;
        // Through the store rather than straight to the script: it queues the
        // apply behind any install or update touching the same files, and it
        // is what keeps track of which preset the settings came from.
        PresetStore.applyPreset(name);
    }

    Process {
        id: scanPresetProc
        // The dialog must open even when the scan cannot speak for itself, so
        // a failed run still reports, once.
        property bool reported: false

        function report(result) {
            if (scanPresetProc.reported)
                return;
            scanPresetProc.reported = true;
            presetsViewRoot.applyRequested(presetsViewRoot.pendingApplyName, result);
        }

        stdout: StdioCollector {
            onStreamFinished: {
                let result = null;
                try {
                    result = JSON.parse(text.trim());
                } catch (e) {
                    result = null;
                }
                scanPresetProc.report(result);
            }
        }
        onExited: scanPresetProc.report(null)
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
        PresetStore.ensureLoaded();
    }

    // Installing or updating a preset from the store rewrites this folder.
    Connections {
        target: PresetStore
        function onPresetFilesChanged() {
            refreshTimer.restart();
        }
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
                    // The preset the current settings came from is worth
                    // pointing at: it is what the undo button undoes.
                    readonly property bool inUse: PresetStore.activePreset === String(model.name)
                    // Exported before schema versioning existed reads as 0,
                    // which is unknown rather than old — those still apply.
                    readonly property bool tooNew: model.configVersion > 0
                        && model.configVersion > Config.currentConfigVersion
                    border.color: presetButton.down ? Appearance.colors.colPrimaryActive : (presetButton.hovered ? Appearance.colors.colPrimary : (presetItem.inUse ? Appearance.colors.colSecondary : "transparent"))
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
                        onClicked: presetsViewRoot.requestApply(String(model.name))

                        StyledToolTip {
                            text: Translation.tr("Made for a newer version of the shell")
                            extraVisibleCondition: presetItem.tooNew
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

                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                visible: presetItem.tooNew
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colErrorContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "system_update_alt"
                                    iconSize: 16
                                    color: Appearance.colors.colOnErrorContainer
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 30

                            StyledText {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: storeButton.left
                                anchors.rightMargin: 10
                                text: model.name
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }

                            RippleButton {
                                id: storeButton
                                // What this button does depends on where the
                                // preset came from: offer the update if one is
                                // waiting, offer a release if it is yours, and
                                // stay out of the way for somebody else's.
                                readonly property string presetName: String(model.name)
                                readonly property bool hasUpdate: PresetStore.updateFor(storeButton.presetName) !== null
                                readonly property bool owned: PresetStore.isOwned(storeButton.presetName)
                                readonly property bool foreign: PresetStore.isFromStore(storeButton.presetName) && !storeButton.owned

                                anchors.right: updateButton.left
                                anchors.rightMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 30
                                implicitHeight: 30
                                visible: !storeButton.foreign || storeButton.hasUpdate
                                enabled: !PresetStore.busyFor(storeButton.presetName)
                                buttonRadius: Appearance.rounding.full
                                colBackground: storeButton.hasUpdate ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSecondaryContainer
                                colBackgroundHover: storeButton.hasUpdate ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colSecondaryContainerHover
                                colRipple: storeButton.hasUpdate ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colSecondaryContainerActive

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: storeButton.hasUpdate ? "download" : (storeButton.owned ? "publish" : "share")
                                    iconSize: 16
                                    color: storeButton.hasUpdate ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSecondaryContainer
                                }

                                onClicked: {
                                    if (storeButton.hasUpdate) {
                                        presetsViewRoot.updateRequested(storeButton.presetName);
                                        return;
                                    }
                                    presetsViewRoot.publishRequested(storeButton.presetName);
                                }

                                StyledToolTip {
                                    text: storeButton.hasUpdate ? Translation.tr("An update is waiting")
                                        : (storeButton.owned ? Translation.tr("Release an update") : Translation.tr("Publish to the store"))
                                }
                            }

                            RippleButton {
                                    id: updateButton
                                    anchors.right: exportButton.left
                                    anchors.rightMargin: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colTertiaryContainer
                                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                                    colRipple: Appearance.colors.colTertiaryContainerActive

                                    contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "save"
                                    iconSize: 16
                                    color: Appearance.colors.colOnTertiaryContainer
                                }

                                    onClicked: {
                                    Quickshell.execDetached(["bash", "-c", `${Directories.scriptPath}/presets.sh update "${model.name}"`]);
                                    refreshTimer.restart();
                                }

                                    StyledToolTip {
                                    text: Translation.tr("Save settings to this preset")
                                }
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
                                    // A preset that came from a repository has
                                    // to be removed through the store as well,
                                    // or its link outlives it and the same
                                    // preset can never be installed again.
                                    let name = String(model.name);
                                    if (PresetStore.isFromStore(name)) {
                                        PresetStore.uninstall(name);
                                    } else {
                                        Quickshell.execDetached([
                                            Directories.scriptPath + "/presets.sh", "delete", name]);
                                    }
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
                                    Quickshell.execDetached([Directories.scriptPath + "/presets.sh", "export", String(model.name)]);
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
