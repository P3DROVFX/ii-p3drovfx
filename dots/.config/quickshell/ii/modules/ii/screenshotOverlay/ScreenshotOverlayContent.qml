pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    signal dismissed

    readonly property bool isHovered: backgroundMa.containsMouse

    property bool _closing: false

    Timer {
        id: dismissTimer
        interval: 6000
        repeat: false
        running: !isHovered
        onTriggered: root._startClose()
    }

    onIsHoveredChanged: {
        if (isHovered)
            dismissTimer.stop();
        else
            dismissTimer.restart();
    }

    Connections {
        target: GlobalStates
        function onScreenshotOverlayImagePathChanged() {
            if (GlobalStates.screenshotOverlayImagePath !== "") {
                root._closing = false;
                dismissTimer.restart();
            }
        }
    }

    // Outer layout dimensions
    property real maxPreviewWidth: 320
    property real maxPreviewHeight: 220

    property real regionAspect: {
        var rw = GlobalStates.screenshotOverlayRegionW;
        var rh = GlobalStates.screenshotOverlayRegionH;
        if (rw > 0 && rh > 0)
            return rw / rh;
        var iw = previewImage.implicitWidth;
        var ih = previewImage.implicitHeight;
        if (iw > 0 && ih > 0)
            return iw / ih;
        return 16 / 9;
    }

    property real previewW: Math.min(maxPreviewWidth, maxPreviewHeight * regionAspect)
    property real previewH: previewW / regionAspect

    property real toolbarBtnHeight: 48
    property real toolbarSpacing: 10
    property real toolbarPadding: 8
    property real toolbarH: toolbarBtnHeight + toolbarPadding * 2

    implicitWidth: Math.max(previewW, toolbar.implicitWidth)
    implicitHeight: previewH + 14 + toolbarH

    // Slide-in entrance & opacity animation
    ParallelAnimation {
        running: true
        NumberAnimation {
            target: mainColumn
            property: "opacity"
            from: 0
            to: 1
            duration: 350
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: mainColumn
            property: "x"
            from: -100
            to: 0
            duration: 350
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            NumberAnimation {
                target: mainColumn
                property: "opacity"
                from: 1
                to: 0
                duration: 250
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: mainColumn
                property: "x"
                from: 0
                to: -100
                duration: 250
                easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: root.dismissed()
        }
    }

    function _startClose() {
        if (root._closing)
            return;
        root._closing = true;
        closeAnim.start();
    }

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: 4

        // Screenshot preview container with thick outer border and rounded clip
        Item {
            Layout.preferredWidth: root.previewW
            Layout.preferredHeight: root.previewH
            Layout.alignment: Qt.AlignLeft

            // Outer border container
            Rectangle {
                id: imageCard
                anchors.fill: parent
                radius: 24
                color: Appearance.colors.colLayer0

                // Masked image item using OpacityMask
                Item {
                    id: maskedContainer
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: maskedContainer.width
                            height: maskedContainer.height
                            radius: imageCard.radius
                        }
                    }

                    Image {
                        id: previewImage
                        source: GlobalStates.screenshotOverlayImagePath !== "" ? "file://" + GlobalStates.screenshotOverlayImagePath : ""
                        asynchronous: true
                        smooth: true
                        visible: status === Image.Ready

                        property real rW: GlobalStates.screenshotOverlayRegionW
                        property real rH: GlobalStates.screenshotOverlayRegionH
                        property real rX: GlobalStates.screenshotOverlayRegionX
                        property real rY: GlobalStates.screenshotOverlayRegionY

                        property bool hasCrop: rW > 0 && rH > 0

                        property real imgW: sourceSize.width > 0 ? sourceSize.width : implicitWidth
                        property real imgH: sourceSize.height > 0 ? sourceSize.height : implicitHeight

                        property real activeW: hasCrop ? rW : imgW
                        property real activeH: hasCrop ? rH : imgH

                        property real scaleFactor: {
                            if (activeW <= 0 || activeH <= 0)
                                return 1;
                            return Math.max(parent.width / activeW, parent.height / activeH);
                        }

                        width: hasCrop ? (imgW * scaleFactor) : parent.width
                        height: hasCrop ? (imgH * scaleFactor) : parent.height
                        fillMode: hasCrop ? Image.Stretch : Image.PreserveAspectCrop

                        x: hasCrop ? (-(rX * scaleFactor) + (parent.width - rW * scaleFactor) / 2) : 0
                        y: hasCrop ? (-(rY * scaleFactor) + (parent.height - rH * scaleFactor) / 2) : 0
                    }
                }

                // Border frame overlay
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 5
                    border.color: Qt.darker(Appearance.colors.colPrimaryContainer, 1.4)
                    z: 10
                }
            }
        }

        // Toolbar — smooth pill without border, button radius matching toolbar (height / 2)
        Rectangle {
            id: toolbar
            Layout.preferredHeight: root.toolbarH
            Layout.alignment: Qt.AlignLeft
            implicitWidth: rowLayout.implicitWidth + root.toolbarPadding * 2
            radius: height / 2
            color: Appearance.colors.colLayer0

            RowLayout {
                id: rowLayout
                anchors.fill: parent
                anchors.margins: root.toolbarPadding
                spacing: root.toolbarSpacing

                // Extended Save button with icon + translated text
                Rectangle {
                    id: saveBtn
                    Layout.preferredHeight: root.toolbarBtnHeight
                    implicitWidth: saveRow.implicitWidth + 32
                    radius: root.toolbarBtnHeight / 2
                    color: saveMa.pressed ? Qt.darker(Appearance.colors.colPrimaryContainer, 1.25) : (saveMa.containsMouse ? Qt.lighter(Appearance.colors.colPrimaryContainer, 1.1) : Appearance.colors.colPrimaryContainer)

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    RowLayout {
                        id: saveRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: "save"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            text: Translation.tr("Save")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    MouseArea {
                        id: saveMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var saveDir = (Config.options.screenSnip.savePath || (Directories.home + "/Pictures/Screenshots")).toString().replace(/^file:\/\//, "");
                            var timestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_hh.mm.ss");
                            var fullPath = saveDir + "/screenshot-" + timestamp + ".png";

                            var hasCrop = GlobalStates.screenshotOverlayRegionW > 0 && GlobalStates.screenshotOverlayRegionH > 0;
                            var srcPath = GlobalStates.screenshotOverlayImagePath;

                            var esc = function (s) {
                                return String(s).replace(/'/g, "'\\''");
                            };
                            var cmd = "mkdir -p '" + esc(saveDir) + "'";

                            if (hasCrop) {
                                cmd += " && magick '" + esc(srcPath) + "' -crop " + Math.round(GlobalStates.screenshotOverlayRegionW) + "x" + Math.round(GlobalStates.screenshotOverlayRegionH) + "+" + Math.round(GlobalStates.screenshotOverlayRegionX) + "+" + Math.round(GlobalStates.screenshotOverlayRegionY) + " +repage '" + esc(fullPath) + "'";
                            } else {
                                cmd += " && cp '" + esc(srcPath) + "' '" + esc(fullPath) + "'";
                            }

                            cmd += " && notify-send -i camera-photo -t 4000 'Screenshot saved' 'Saved to: " + esc(fullPath) + "'";
                            Quickshell.execDetached(["bash", "-c", cmd]);
                            root._startClose();
                        }
                    }
                }

                // Edit button - opens Swappy
                Rectangle {
                    id: editBtn
                    Layout.preferredWidth: root.toolbarBtnHeight
                    Layout.preferredHeight: root.toolbarBtnHeight
                    radius: root.toolbarBtnHeight / 2
                    color: editMa.pressed ? Qt.darker(Appearance.colors.colPrimaryContainer, 1.25) : (editMa.containsMouse ? Qt.lighter(Appearance.colors.colPrimaryContainer, 1.1) : Appearance.colors.colPrimaryContainer)

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "edit"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    MouseArea {
                        id: editMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var esc = function (s) {
                                return String(s).replace(/'/g, "'\\''");
                            };
                            var hasCrop = GlobalStates.screenshotOverlayRegionW > 0 && GlobalStates.screenshotOverlayRegionH > 0;
                            var targetPath = GlobalStates.screenshotOverlayImagePath;
                            var cmd = "";
                            if (hasCrop) {
                                var tempCrop = "/tmp/quickshell-snip-crop-" + Date.now() + ".png";
                                cmd = "magick '" + esc(targetPath) + "' -crop " + Math.round(GlobalStates.screenshotOverlayRegionW) + "x" + Math.round(GlobalStates.screenshotOverlayRegionH) + "+" + Math.round(GlobalStates.screenshotOverlayRegionX) + "+" + Math.round(GlobalStates.screenshotOverlayRegionY) + " +repage '" + esc(tempCrop) + "' && swappy -f '" + esc(tempCrop) + "'";
                            } else {
                                cmd = "swappy -f '" + esc(targetPath) + "'";
                            }
                            Quickshell.execDetached(["bash", "-c", cmd]);
                            root._startClose();
                        }
                    }
                }

                // Delete button
                Rectangle {
                    id: deleteBtn
                    Layout.preferredWidth: root.toolbarBtnHeight
                    Layout.preferredHeight: root.toolbarBtnHeight
                    radius: root.toolbarBtnHeight / 2
                    color: deleteMa.pressed ? Qt.darker(Appearance.colors.colPrimaryContainer, 1.25) : (deleteMa.containsMouse ? Qt.lighter(Appearance.colors.colPrimaryContainer, 1.1) : Appearance.colors.colPrimaryContainer)

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    MouseArea {
                        id: deleteMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Clear active Wayland clipboard
                            Quickshell.execDetached(["bash", "-c", "wl-copy --clear"]);
                            // Delete from Cliphist service if available
                            if (typeof Cliphist !== "undefined" && Cliphist.entries && Cliphist.entries.length > 0) {
                                Cliphist.deleteEntry(Cliphist.entries[0]);
                            }
                            root._startClose();
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: backgroundMa
        anchors.fill: parent
        z: -1
        hoverEnabled: true
    }
}
