pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * A small desktop drawn with the page's values: two tiled windows over the wallpaper
 * (gaps, border, border colour, rounding) - the first see-through like the shell's
 * panels, the wallpaper blurred behind it - and the open/close animation
 * Hyprland is given — the second window closes and reopens when "Play" is pressed, when an
 * animation value changes, and over and over while `autoLoop` is on.
 *
 * The desktop is 1100 px wide scaled to the card, so gaps and borders keep about their
 * real size. `highlight` ("gapsIn", "gapsOut", "border", "glass") marks what is adjusted.
 */
Item {
    id: root

    property string highlight: ""
    /// The replay on animation changes, and the Play pill unless `compact`.
    property bool showAnimation: true
    /// Small copies (the page's sticky one) leave the Play pill out.
    property bool compact: false
    /// Plays over and over while true (the page sets it while its animation settings are on screen).
    property bool autoLoop: false
    onAutoLoopChanged: if (root.autoLoop && !sequence.running) root.play()

    readonly property var appearance: Config.options.appearance
    readonly property var anim: Config.options.appearance.appLaunchAnimation

    readonly property real ratio: root.width / 1100
    function px(value: real): real {
        return value * root.ratio;
    }

    readonly property real gapsIn: root.appearance.gapsIn ?? 4
    readonly property real gapsOut: root.appearance.gapsOut ?? 5
    readonly property real borderSize: Appearance.borderless ? 0 : Appearance.borderWidth
    readonly property real rounding: Appearance.windowRounding

    // ── Layout: the work area split in two ─────────────────────────────────
    readonly property rect area: Qt.rect(root.px(root.gapsOut), root.px(root.gapsOut),
        root.width - root.px(root.gapsOut * 2), root.height - root.px(root.gapsOut * 2))
    readonly property real gutter: root.px(root.gapsIn * 2)
    readonly property real halfWidth: (root.area.width - root.gutter) / 2
    /// 1: both windows side by side; 0: the first alone (the second closed).
    property real split: 1
    readonly property rect firstBox: Qt.rect(root.area.x, root.area.y,
        root.area.width - (root.halfWidth + root.gutter) * root.split, root.area.height)
    readonly property rect secondBox: Qt.rect(root.area.x + root.halfWidth + root.gutter, root.area.y,
        root.area.width - root.halfWidth - root.gutter, root.area.height)

    // ── The animation, as HyprlandSettings.appLaunchEntries hands it to Hyprland ──
    readonly property bool animEnabled: root.anim.enable ?? true
    readonly property bool slide: (root.anim.style ?? "scale") === "slide"
    readonly property real speed: Math.max(1, Math.min(10, Number(root.anim.speed) || 4))
    readonly property int startPercent: Math.max(5, Math.min(95, Math.round(Number(root.anim.startPercent) || 20)))
    readonly property int outPercent: Math.min(90, Math.round(root.startPercent + (100 - root.startPercent) * 0.5))
    readonly property int openDuration: root.animEnabled ? Math.round(root.speed * 100 * (root.slide ? 1.12 : 1)) : 0
    readonly property int fadeInDuration: root.animEnabled ? Math.round(root.speed * 100 * (root.slide ? 0.5 : 0.7)) : 0
    readonly property int closeDuration: root.animEnabled ? Math.round(root.speed * 65) : 0
    // windowsMove: the neighbour resizing into the freed space (still animated with the rest off).
    readonly property int moveDuration: root.animEnabled ? Math.round(root.speed * 100) : 300
    readonly property string direction: {
        const d = root.anim.slideDirection ?? "auto";
        return d === "auto" ? "right" : d; // The second window's nearest edge is the right one.
    }
    readonly property point offscreen: {
        switch (root.direction) {
        case "left": return Qt.point(-(root.secondBox.x + root.secondBox.width), 0);
        case "top": return Qt.point(0, -(root.secondBox.y + root.secondBox.height));
        case "bottom": return Qt.point(0, root.height - root.secondBox.y);
        default: return Qt.point(root.width - root.secondBox.x, 0);
        }
    }
    readonly property bool playing: sequence.running

    function play(): void {
        sequence.stop();
        root.rest();
        sequence.start();
    }

    function rest(): void {
        root.split = 1;
        second.opacity = 1;
        second.zoom = 1;
        second.tx = 0;
        second.ty = 0;
    }

    readonly property color colHighlight: Appearance.colors.colPrimary
    readonly property Item wallpaperItem: wallpaper

    /// A tiled window: border around the rounded window, content clipped to it.
    component Window: Item {
        id: win

        property rect box
        property bool focused: false
        property color surface: Appearance.m3colors.m3surfaceContainerLow
        /// The window's surface is see-through like the shell's panels: the wallpaper behind it,
        /// blurred, under the surface at the panels' transparency.
        property bool glass: false
        default property alias content: body.data
        readonly property real border: root.borderSize > 0 ? Math.max(1, root.px(root.borderSize)) : 0
        readonly property real corner: Math.max(0, root.px(root.rounding))

        x: win.box.x
        y: win.box.y
        width: Math.max(0, win.box.width)
        height: Math.max(0, win.box.height)

        Rectangle {
            anchors.fill: parent
            visible: win.border > 0
            radius: win.corner + win.border
            color: win.focused ? Appearance.activeBorderColor : ColorUtils.applyAlpha(Appearance.colors.colOutlineVariant, 0.9)
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        ClippingRectangle {
            id: body
            anchors.fill: parent
            anchors.margins: win.border
            radius: win.corner
            color: win.glass ? "transparent" : win.surface

            // Blurred as the compositor would: each pass widens the kernel.
            ShaderEffectSource {
                id: under
                anchors.fill: parent
                visible: false
                sourceItem: win.glass ? root.wallpaperItem : null
                sourceRect: Qt.rect(win.x + win.border, win.y + win.border, body.width, body.height)
            }
            MultiEffect {
                anchors.fill: parent
                visible: win.glass
                source: under
                readonly property real radiusPx: root.px((root.appearance.blurSize ?? 0) * Math.max(1, root.appearance.blur?.passes ?? 1) * 1.6)
                blurEnabled: (root.appearance.blurSize ?? 0) > 0
                blurMax: 64
                blur: Math.min(1, radiusPx / 64)
                autoPaddingEnabled: false
                brightness: Math.max(-1, Math.min(1, ((root.appearance.blur?.brightness ?? 1) - 1) * 0.5))
                contrast: Math.max(-1, Math.min(1, (root.appearance.blur?.contrast ?? 1) - 1))
                saturation: Math.max(-1, Math.min(1, (root.appearance.blur?.vibrancy ?? 0) * 0.8))
            }
            Rectangle {
                anchors.fill: parent
                visible: win.glass
                color: ColorUtils.transparentize(win.surface, Appearance.backgroundTransparency)
            }
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: Appearance.colors.colLayer1

        // ── What the glass sits on (and blurs) ──────────────────────────────
        Item {
            id: scene
            anchors.fill: parent

            ColorsWallpaperImage {
                id: wallpaper
                anchors.fill: parent
                targetMode: "desktop"
            }

            // A gallery, see-through like the shell's panels (solid when they are).
            Window {
                id: first
                box: root.firstBox
                focused: root.split < 0.5
                glass: true
                surface: Appearance.m3colors.m3surfaceContainer

                Column {
                    id: gallery
                    readonly property real unit: first.height / 100
                    x: Math.round(parent.width * 0.09)
                    y: Math.round(gallery.unit * 9)
                    width: parent.width - x * 2
                    spacing: Math.round(gallery.unit * 4.5)

                    // An avatar beside a name and a line.
                    Row {
                        spacing: Math.round(gallery.unit * 3)
                        Rectangle {
                            width: Math.round(gallery.unit * 12)
                            height: width
                            radius: width / 2
                            color: Appearance.colors.colPrimary
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Math.round(gallery.unit * 2.2)
                            Rectangle {
                                width: gallery.width * 0.4
                                height: Math.round(gallery.unit * 5)
                                radius: height / 2
                                color: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.75)
                            }
                            Rectangle {
                                width: gallery.width * 0.26
                                height: Math.max(2, Math.round(gallery.unit * 3))
                                radius: height / 2
                                color: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.22)
                            }
                        }
                    }

                    // Three pictures in a row.
                    Row {
                        id: pictures
                        spacing: Math.round(gallery.unit * 3)
                        readonly property real tile: (gallery.width - pictures.spacing * 2) / 3
                        Repeater {
                            model: [
                                { fill: Appearance.colors.colPrimaryContainer, ink: Appearance.colors.colOnPrimaryContainer, shape: MaterialShape.Shape.Cookie9Sided },
                                { fill: Appearance.colors.colSecondaryContainer, ink: Appearance.colors.colOnSecondaryContainer, shape: MaterialShape.Shape.Clover4Leaf },
                                { fill: Appearance.colors.colTertiaryContainer, ink: Appearance.colors.colOnTertiaryContainer, shape: MaterialShape.Shape.Flower }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: pictures.tile
                                height: Math.round(gallery.unit * 27)
                                radius: Math.min(height / 3, Appearance.rounding.normal)
                                color: modelData.fill

                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: Math.round(parent.height * 0.5)
                                    shape: parent.modelData.shape
                                    color: parent.modelData.ink
                                    opacity: 0.85
                                }
                            }
                        }
                    }

                    // Three list rows: a dot and a line.
                    Repeater {
                        model: [0.62, 0.48, 0.7]
                        delegate: Row {
                            required property real modelData
                            spacing: Math.round(gallery.unit * 3)
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.round(gallery.unit * 6)
                                height: width
                                radius: width / 2
                                color: Appearance.colors.colTertiary
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: gallery.width * parent.modelData
                                height: Math.max(2, Math.round(gallery.unit * 3))
                                radius: height / 2
                                color: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.22)
                            }
                        }
                    }
                }
            }

            // A plain document: the window that opens and closes.
            Window {
                id: second

                property real zoom: 1
                property real tx: 0
                property real ty: 0

                box: root.secondBox
                focused: true
                surface: Appearance.m3colors.m3surfaceContainer
                transform: [
                    Scale {
                        origin.x: second.width / 2
                        origin.y: second.height / 2
                        xScale: second.zoom
                        yScale: second.zoom
                    },
                    Translate {
                        x: second.tx
                        y: second.ty
                    }
                ]

                Column {
                    id: doc
                    readonly property real unit: second.height / 100
                    x: Math.round(parent.width * 0.09)
                    y: Math.round(doc.unit * 9)
                    width: parent.width - x * 2
                    spacing: Math.round(doc.unit * 4.5)

                    Rectangle {
                        width: doc.width * 0.55
                        height: Math.round(doc.unit * 6.5)
                        radius: height / 2
                        color: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.75)
                    }
                    Repeater {
                        model: [1, 0.92, 0.6]
                        delegate: Rectangle {
                            required property real modelData
                            width: doc.width * modelData
                            height: Math.max(2, Math.round(doc.unit * 3))
                            radius: height / 2
                            color: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.22)
                        }
                    }
                    Rectangle {
                        width: doc.width
                        height: Math.round(doc.unit * 30)
                        radius: Math.min(height / 3, Appearance.rounding.normal)
                        color: Appearance.colors.colTertiaryContainer

                        MaterialShape {
                            anchors.centerIn: parent
                            implicitSize: Math.round(parent.height * 0.62)
                            shape: MaterialShape.Shape.SoftBurst
                            color: Appearance.colors.colOnTertiaryContainer
                            opacity: 0.85
                        }
                    }
                    Rectangle {
                        width: Math.round(doc.width * 0.3)
                        height: Math.round(doc.unit * 10)
                        radius: height / 2
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }

        // Marks the glass while transparency or blur is adjusted.
        Rectangle {
            x: root.firstBox.x - 4
            y: root.firstBox.y - 4
            width: root.firstBox.width + 8
            height: root.firstBox.height + 8
            radius: root.px(root.rounding) + 4
            color: "transparent"
            border.width: 2.5
            border.color: root.colHighlight
            opacity: root.highlight === "glass" ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        // ── What is being adjusted ──────────────────────────────────────────
        Rectangle {
            readonly property real band: Math.max(3, root.px(root.gapsOut))
            x: root.area.x - band
            y: root.area.y - band
            width: root.area.width + band * 2
            height: root.area.height + band * 2
            radius: Appearance.rounding.windowRounding
            color: "transparent"
            border.width: band
            border.color: ColorUtils.applyAlpha(root.colHighlight, 0.8)
            opacity: root.highlight === "gapsOut" ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
        Rectangle {
            readonly property real band: Math.max(3, root.gutter)
            x: root.firstBox.x + root.firstBox.width + (root.gutter - band) / 2
            y: root.area.y
            width: band
            height: root.area.height
            radius: band / 2
            color: root.colHighlight
            opacity: root.highlight === "gapsIn" ? 0.9 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
        Repeater {
            model: [root.firstBox, root.secondBox]
            delegate: Rectangle {
                required property rect modelData
                x: modelData.x - 4
                y: modelData.y - 4
                width: modelData.width + 8
                height: modelData.height + 8
                radius: root.px(root.rounding) + 4
                color: "transparent"
                border.width: 2.5
                border.color: root.colHighlight
                opacity: root.highlight === "border" ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        // ── Play ────────────────────────────────────────────────────────────
        RippleButton {
            id: playButton
            visible: root.showAnimation && !root.compact
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: 16
            }
            implicitHeight: 40
            implicitWidth: playRow.implicitWidth + 32
            buttonRadius: height / 2
            buttonRadiusPressed: Appearance.rounding.small
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colBackgroundActive: Appearance.colors.colPrimaryActive
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: root.play()

            contentItem: Item {
                RowLayout {
                    id: playRow
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: root.playing ? "motion_play" : "play_arrow"
                        fill: 1
                        iconSize: 20
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: root.animEnabled ? Translation.tr("Play · %1 ms").arg(root.openDuration) : Translation.tr("Play · instant")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // Close the second window, then open it again: the neighbour resizes into the space.
    SequentialAnimation {
        id: sequence

        ParallelAnimation {
            NumberAnimation {
                target: second; property: "zoom"
                to: root.slide || !root.animEnabled ? 1 : root.outPercent / 100
                duration: root.closeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1]
            }
            NumberAnimation {
                target: second; property: "tx"
                to: root.slide && root.animEnabled ? root.offscreen.x : 0
                duration: root.closeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1]
            }
            NumberAnimation {
                target: second; property: "ty"
                to: root.slide && root.animEnabled ? root.offscreen.y : 0
                duration: root.closeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1]
            }
            NumberAnimation {
                target: second; property: "opacity"; to: 0
                duration: root.closeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1]
            }
            SequentialAnimation {
                PauseAnimation { duration: Math.round(root.closeDuration * 0.5) }
                NumberAnimation {
                    target: root; property: "split"; to: 0
                    duration: root.moveDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                }
            }
        }
        PauseAnimation { duration: 450 }
        ScriptAction {
            script: {
                second.zoom = root.slide || !root.animEnabled ? 1 : root.startPercent / 100;
                second.tx = root.slide && root.animEnabled ? root.offscreen.x : 0;
                second.ty = root.slide && root.animEnabled ? root.offscreen.y : 0;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "split"; to: 1
                duration: root.moveDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
            }
            NumberAnimation {
                target: second; property: "zoom"; to: 1
                duration: root.openDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.slide ? [0.3, 0.7, 0.1, 1, 1, 1] : [0.22, 1, 0.36, 1, 1, 1]
            }
            NumberAnimation {
                target: second; properties: "tx,ty"; to: 0
                duration: root.openDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.3, 0.7, 0.1, 1, 1, 1]
            }
            NumberAnimation {
                target: second; property: "opacity"; to: 1
                duration: root.fadeInDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.2, 0.6, 0.35, 1, 1, 1]
            }
        }
    }

    // Around again after a breath, while looping.
    Connections {
        target: sequence
        function onRunningChanged() {
            if (!sequence.running && root.autoLoop)
                loopPause.restart();
        }
    }
    Timer {
        id: loopPause
        interval: 900
        onTriggered: if (root.autoLoop && !sequence.running) root.play()
    }

    // Replays once an animation value has settled.
    Timer {
        id: replay
        interval: 320
        onTriggered: root.play()
    }
    Connections {
        target: root.showAnimation ? root.anim : null
        function onStyleChanged() { replay.restart(); }
        function onSlideDirectionChanged() { replay.restart(); }
        function onStartPercentChanged() { replay.restart(); }
        function onSpeedChanged() { replay.restart(); }
        function onEnableChanged() { replay.restart(); }
    }
}
