pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: root

    signal dismissed

    // How long the preview stays when left alone.
    readonly property int dismissDelay: 4000
    readonly property bool isHovered: hover.hovered || swipe.active

    property bool _closing: false

    // Horizontal slide. 0 = in place; the hidden position clears the window's
    // left edge, so the card arrives from the screen edge (or the vertical bar).
    readonly property real hiddenOffset: -(root.implicitWidth + 32)
    property real cardOffset: hiddenOffset
    property real toolbarOffset: hiddenOffset
    // Live finger/pointer drag of a swipe-to-dismiss, added on top.
    property real swipeOffset: 0
    // Auto-dismiss clock, 1 → 0. Drawn as the bar along the preview's foot.
    property real remaining: 1

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
    property real toolbarSpacing: 8
    property real toolbarPadding: 8
    property real toolbarH: toolbarBtnHeight + toolbarPadding * 2
    readonly property real columnSpacing: 8

    implicitWidth: Math.max(previewW, toolbar.implicitWidth)
    implicitHeight: previewH + columnSpacing + toolbarH

    HoverHandler {
        id: hover
    }

    onIsHoveredChanged: {
        if (root._closing)
            return;
        if (root.isHovered)
            countdown.stop();
        else
            countdown.restart();
    }

    NumberAnimation {
        id: countdown
        target: root
        property: "remaining"
        from: 1
        to: 0
        duration: root.dismissDelay
        onFinished: root._startClose()
    }

    Connections {
        target: GlobalStates
        function onScreenshotOverlayImagePathChanged() {
            if (GlobalStates.screenshotOverlayImagePath !== "")
                root._enter();
        }
    }

    Component.onCompleted: root._enter()

    // ── Entrance: card slides in, toolbar follows a beat later, the photo
    // settles from a slight zoom under a fading flash. Also replayed when a new
    // screenshot lands while the preview is still up.
    function _enter() {
        closeAnim.stop();
        root._closing = false;
        root.swipeOffset = 0;
        enterAnim.restart();
        if (!root.isHovered)
            countdown.restart();
    }

    ParallelAnimation {
        id: enterAnim

        NumberAnimation {
            target: root
            property: "cardOffset"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        SequentialAnimation {
            PauseAnimation {
                duration: Math.round(70 * Appearance.animMultiplier)
            }
            NumberAnimation {
                target: root
                property: "toolbarOffset"
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
        NumberAnimation {
            target: previewImage
            property: "settle"
            from: 1.12
            to: 1
            duration: Math.round(Appearance.animation.elementMoveEnter.duration * 1.5)
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: flash
            property: "opacity"
            from: 0.55
            to: 0
            duration: Math.round(Appearance.animation.elementMoveEnter.duration * 1.2)
            easing.type: Easing.OutCubic
        }
    }

    // ── Exit: the reverse, from wherever a swipe left it; toolbar leaves first.
    SequentialAnimation {
        id: closeAnim

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "toolbarOffset"
                to: root.hiddenOffset
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: Math.round(40 * Appearance.animMultiplier)
                }
                NumberAnimation {
                    target: root
                    property: "cardOffset"
                    to: root.hiddenOffset
                    duration: Appearance.animation.elementMoveExit.duration
                    easing.type: Appearance.animation.elementMoveExit.type
                    easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                }
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
        countdown.stop();
        enterAnim.stop();
        // Fold an in-progress swipe into the offsets so the exit continues it.
        root.cardOffset += root.swipeOffset;
        root.toolbarOffset += root.swipeOffset;
        root.swipeOffset = 0;
        closeAnim.start();
    }

    // Swipe left to dismiss; a short swipe springs back.
    DragHandler {
        id: swipe
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        onTranslationChanged: {
            if (!root._closing)
                root.swipeOffset = Math.min(0, translation.x) + Math.max(0, translation.x) * 0.15;
        }
        onActiveChanged: {
            if (active || root._closing)
                return;
            if (root.swipeOffset < -Math.min(120, root.implicitWidth * 0.3))
                root._startClose();
            else
                swipeBack.restart();
        }
    }

    NumberAnimation {
        id: swipeBack
        target: root
        property: "swipeOffset"
        to: 0
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    // Screenshot preview
    Item {
        id: previewWrap
        width: root.previewW
        height: root.previewH
        opacity: Math.max(0, Math.min(1, 1 + (root.cardOffset + root.swipeOffset) / (root.implicitWidth * 0.8)))
        transform: Translate {
            x: root.cardOffset + root.swipeOffset
        }

        ClippingRectangle {
            id: imageCard
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0

            Image {
                id: previewImage
                // Entrance zoom, around the preview's centre.
                property real settle: 1
                source: GlobalStates.screenshotOverlayImagePath !== "" ? "file://" + GlobalStates.screenshotOverlayImagePath : ""
                asynchronous: true
                smooth: true
                visible: status === Image.Ready
                transform: Scale {
                    origin.x: imageCard.width / 2 - previewImage.x
                    origin.y: imageCard.height / 2 - previewImage.y
                    xScale: previewImage.settle
                    yScale: previewImage.settle
                }

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

            // Shutter flash, fades as the photo settles.
            Rectangle {
                id: flash
                anchors.fill: parent
                color: "white"
                opacity: 0
            }

            // Time left before the preview goes away; freezes while hovered.
            Rectangle {
                id: countdownTrack
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    margins: 14
                }
                height: 4
                radius: height / 2
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.35)
                opacity: root.isHovered || root._closing ? 0 : 1

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: parent.width * root.remaining
                    radius: parent.radius
                    color: Appearance.colors.colPrimary
                }
            }
        }

        // Border frame overlay
        Rectangle {
            anchors.fill: parent
            radius: imageCard.radius
            color: "transparent"
            border.width: 5
            border.color: Qt.darker(Appearance.colors.colPrimaryContainer, 1.4)
        }
    }

    // Toolbar — pill without border, buttons in the primary-container voice.
    Rectangle {
        id: toolbar
        y: root.previewH + root.columnSpacing
        height: root.toolbarH
        width: implicitWidth
        implicitWidth: buttonRow.implicitWidth + root.toolbarPadding * 2
        radius: height / 2
        color: Appearance.colors.colLayer0
        opacity: Math.max(0, Math.min(1, 1 + (root.toolbarOffset + root.swipeOffset) / (root.implicitWidth * 0.8)))
        transform: Translate {
            x: root.toolbarOffset + root.swipeOffset
        }

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: root.toolbarSpacing

            OverlayButton {
                size: root.toolbarBtnHeight
                symbol: "keyboard_double_arrow_left"
                onClicked: root._startClose()
            }

            OverlayButton {
                size: root.toolbarBtnHeight
                symbol: "save"
                label: Translation.tr("Save")
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

            // Opens Swappy
            OverlayButton {
                size: root.toolbarBtnHeight
                symbol: "edit"
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

            OverlayButton {
                size: root.toolbarBtnHeight
                symbol: "delete"
                danger: true
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

    // Pill button: circle (or pill with a label) at rest, squares off under the
    // pointer, dips on press. Destructive buttons turn error on hover.
    component OverlayButton: Rectangle {
        id: btn

        signal clicked

        property real size: 48
        property string symbol: ""
        property string label: ""
        property bool danger: false
        readonly property bool hot: btnHover.hovered
        readonly property bool sharp: Appearance.rounding.scale === 0
        readonly property color colContent: danger && hot ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer

        height: size
        width: label.length > 0 ? btnRow.implicitWidth + 32 : size
        radius: sharp ? 0 : (hot ? Math.min(size * 0.3, Appearance.rounding.normal) : size / 2)
        color: {
            if (danger && hot)
                return btnTap.pressed ? Appearance.colors.colErrorContainerActive : Appearance.colors.colErrorContainerHover;
            if (btnTap.pressed)
                return Appearance.colors.colPrimaryContainerActive;
            return hot ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer;
        }
        scale: btnTap.pressed ? 0.95 : 1

        Behavior on radius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 8

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.symbol
                iconSize: 20
                fill: btn.hot ? 1 : 0
                color: btn.colContent
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: btn.label.length > 0
                text: btn.label
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: btn.colContent
            }
        }

        HoverHandler {
            id: btnHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: btnTap
            onTapped: btn.clicked()
        }
    }
}
