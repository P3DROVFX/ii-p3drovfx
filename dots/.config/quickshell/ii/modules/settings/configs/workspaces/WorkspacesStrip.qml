pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "WorkspacesCatalog.js" as Catalog

/**
 * The bar's workspace row drawn from plain values, so the page can show any
 * combination of options (saved or only pointed at) over pretend windows.
 * Every size derives from `unit`; the five styles mirror the bar's widgets.
 */
Item {
    id: root

    property string styleId: "default"
    property string colorMode: "primary"
    property int count: 5
    property var numberMap: []
    property bool showNumbers: true
    property bool showIcons: false
    property bool tintIcons: false
    property real tintAmount: 0.6
    property bool maskIcons: false
    property string maskShape: "Circle"
    property string indicatorMode: "pill"
    property string indicatorShape: "Pentagon"
    property bool dynamic: false
    property int maxWindows: 2
    property int activeSlot: 0
    property bool dockIndicator: true
    property bool dockDots: true
    property bool dockIcons: true
    property bool interactive: false
    property real unit: 26
    property color barColor: Appearance.colors.colLayer1

    readonly property real iconBox: root.unit * 0.85
    readonly property real iconRatio: 0.8
    readonly property real dotSize: Math.max(3, root.unit * 0.16)
    readonly property real indicatorInset: root.unit * 0.07
    readonly property real runStretch: root.unit * 0.46
    readonly property real minimalDot: root.unit * 0.7
    readonly property real minimalGap: root.unit * 0.24
    readonly property real expressiveDiameter: root.unit * 0.82
    readonly property real expressiveGap: root.unit * 0.2
    readonly property real expressiveStretch: 1.5
    readonly property real dockButton: root.unit * 1.1
    readonly property real dockGap: root.unit * 0.08
    readonly property real dockIconRatio: 0.72
    readonly property int dockDotLimit: 3
    readonly property real indexSlot: root.unit * 0.95
    readonly property real indexActiveSize: root.unit * 0.66
    readonly property real indexRestSize: root.unit * 0.38
    readonly property real labelSize: root.unit * 0.42
    readonly property real occupiedMix: 0.6
    readonly property real emptyFade: 0.45
    readonly property real indicatorOvershoot: 1.7
    readonly property int arrowMorph: Math.round(420 * Appearance.animMultiplier)
    readonly property int arrowRest: Math.round(260 * Appearance.animMultiplier)
    readonly property int slideDuration: Math.round(350 * Appearance.animMultiplier)

    signal slotClicked(int index)

    readonly property var spec: Catalog.style(root.styleId)
    readonly property bool usesShape: root.spec.indicator && root.indicatorMode !== "pill"
        && (root.indicatorMode !== "arrow" || root.spec.arrow)
    readonly property bool squareIndicator: root.usesShape && root.indicatorMode !== "shape"

    BarWidgetPalette {
        id: tone
        colorMode: root.colorMode
    }

    readonly property var slots: {
        const out = [];
        for (let i = 0; i < root.count; i++) {
            const occupied = Catalog.DEMO_WINDOWS[i % Catalog.DEMO_WINDOWS.length].length > 0;
            out.push({
                "occupied": occupied,
                "windows": Catalog.demoWindows(i, root.maxWindows),
                "shown": !root.dynamic || occupied || i === root.activeSlot
            });
        }
        return out;
    }

    function extentOf(index) {
        const slot = root.slots[index];
        if (!slot || !slot.shown)
            return 0;
        switch (root.styleId) {
        case "minimal":
            return root.minimalDot;
        case "expressive":
            return index === root.activeSlot ? root.expressiveDiameter * root.expressiveStretch : root.expressiveDiameter;
        case "dock":
            return root.dockButton;
        case "index":
            return root.indexSlot;
        default:
            return root.showIcons && slot.windows.length > 0
                ? Math.max(root.unit, slot.windows.length * root.iconBox + 8) : root.unit;
        }
    }

    readonly property real gap: ({ "minimal": root.minimalGap, "expressive": root.expressiveGap, "dock": root.dockGap })[root.styleId] ?? 0

    readonly property var offsets: {
        const out = [];
        let at = 0;
        for (let i = 0; i < root.slots.length; i++) {
            out.push(at);
            const extent = root.extentOf(i);
            if (extent > 0)
                at += extent + root.gap;
        }
        out.push(Math.max(0, at - root.gap));
        return out;
    }
    readonly property real contentLength: root.offsets[root.offsets.length - 1] ?? 0

    function joined(index) {
        const slot = root.slots[index];
        return !!slot && slot.shown && slot.occupied && index !== root.activeSlot;
    }

    function labelColor(index) {
        if (index === root.activeSlot)
            return tone.colOnBackground;
        if (root.slots[index]?.occupied)
            return tone.colOnContainer;
        return ColorUtils.transparentize(tone.colOnContainer, root.emptyFade);
    }

    implicitWidth: root.contentLength
    implicitHeight: root.styleId === "dock" ? root.dockButton + root.dotSize * 2 : root.unit

    property int previousSlot: 0
    property bool arrowShown: false
    property real arrowRotation: 90
    property string randomShape: Catalog.RANDOM_SHAPES[0]
    property real randomRotation: 0

    onActiveSlotChanged: {
        if (root.previousSlot !== root.activeSlot) {
            root.arrowRotation = root.activeSlot > root.previousSlot ? 90 : 270;
            root.arrowShown = root.indicatorMode === "arrow";
            arrowTimer.restart();
            const pool = Catalog.RANDOM_SHAPES.filter(s => s !== root.randomShape);
            root.randomShape = pool[Math.floor(Math.random() * pool.length)];
            root.randomRotation += 90 * (1 + Math.floor(Math.random() * 2));
        }
        root.previousSlot = root.activeSlot;
    }

    Component.onCompleted: root.previousSlot = root.activeSlot

    Timer {
        id: arrowTimer
        interval: root.arrowMorph + root.arrowRest
        onTriggered: root.arrowShown = false
    }

    Item {
        id: track
        anchors.centerIn: parent
        width: root.contentLength
        height: root.unit

        Repeater {
            model: root.styleId === "default" ? root.slots.length : 0

            delegate: Rectangle {
                id: run
                required property int index
                readonly property bool on: root.joined(run.index)
                readonly property real before: root.joined(run.index - 1) ? root.runStretch : 0
                readonly property real after: root.joined(run.index + 1) ? root.runStretch : 0

                x: root.offsets[run.index] - run.before
                anchors.verticalCenter: parent.verticalCenter
                width: run.on ? root.extentOf(run.index) + run.before + run.after : 0
                height: root.unit
                radius: height / 2
                color: ColorUtils.mix(tone.colContainer, root.barColor, root.occupiedMix)
                opacity: run.on ? 1 : 0
                Behavior on x {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        Item {
            id: indicator
            visible: root.spec.indicator && (root.styleId !== "dock" || root.dockIndicator) && root.activeSlot >= 0 && root.activeSlot < root.count
            readonly property real slotStart: root.offsets[Math.max(0, root.activeSlot)] ?? 0
            readonly property real slotLength: root.extentOf(Math.max(0, root.activeSlot))
            readonly property real side: root.styleId === "dock" ? root.dockButton
                : root.styleId === "minimal" ? root.minimalDot : root.iconBox
            readonly property real length: root.squareIndicator || root.styleId !== "default"
                ? indicator.side : indicator.slotLength - root.indicatorInset * 2

            x: indicator.slotStart + (indicator.slotLength - indicator.length) / 2
            anchors.verticalCenter: parent.verticalCenter
            width: indicator.length
            height: indicator.side
            Behavior on x {
                NumberAnimation {
                    duration: root.slideDuration
                    easing.type: Easing.OutBack
                    easing.overshoot: root.indicatorOvershoot
                }
            }
            Behavior on width {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                visible: !root.usesShape
                radius: root.styleId === "dock" ? Appearance.rounding.small : height / 2
                color: tone.colBackground
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            MaterialShape {
                anchors.fill: parent
                visible: root.usesShape
                shapeString: root.indicatorMode === "arrow" ? (root.arrowShown ? "Triangle" : "Circle")
                    : root.indicatorMode === "random" ? root.randomShape : root.indicatorShape
                rotation: root.indicatorMode === "arrow" ? root.arrowRotation
                    : root.indicatorMode === "random" ? root.randomRotation : 0
                color: tone.colBackground
                Behavior on rotation {
                    enabled: root.indicatorMode === "random"
                    RotationAnimation {
                        duration: root.slideDuration
                        direction: RotationAnimation.Clockwise
                        easing.type: Easing.OutBack
                    }
                }
            }
        }

        Repeater {
            model: root.slots.length

            delegate: Item {
                id: slot
                required property int index
                readonly property var info: root.slots[slot.index]
                readonly property bool active: slot.index === root.activeSlot
                readonly property string label: Catalog.label(root.numberMap, slot.index)

                x: root.offsets[slot.index]
                width: Math.max(0, root.extentOf(slot.index))
                height: parent.height
                opacity: slot.info?.shown ? 1 : 0
                scale: slot.info?.shown ? 1 : 0.6
                Behavior on x {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Loader {
                    anchors.fill: parent
                    sourceComponent: ({
                        "minimal": minimalSlot,
                        "expressive": expressiveSlot,
                        "dock": dockSlot,
                        "index": indexSlot
                    })[root.styleId] ?? defaultSlot

                    Component {
                        id: defaultSlot
                        Item {
                            id: plain
                            readonly property bool withIcons: root.showIcons && slot.info.windows.length > 0
                            Row {
                                anchors.centerIn: parent
                                visible: plain.withIcons
                                Repeater {
                                    model: plain.withIcons ? slot.info.windows : []
                                    delegate: AppGlyph {
                                        required property string modelData
                                        appClass: modelData
                                        size: root.iconBox
                                    }
                                }
                            }
                            StyledText {
                                anchors.centerIn: parent
                                visible: !plain.withIcons
                                text: slot.label
                                opacity: root.showNumbers ? 1 : 0
                                font.pixelSize: root.labelSize
                                font.weight: Font.Black
                                color: root.labelColor(slot.index)
                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                visible: !plain.withIcons
                                width: root.dotSize
                                height: width
                                radius: width / 2
                                opacity: root.showNumbers ? 0 : 1
                                color: root.labelColor(slot.index)
                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }

                    Component {
                        id: minimalSlot
                        Item {
                            Rectangle {
                                anchors.centerIn: parent
                                width: root.minimalDot * (slot.info.occupied ? 0.5 : 0.38)
                                height: width
                                radius: width / 2
                                color: slot.info.occupied ? root.labelColor(slot.index) : "transparent"
                                border.width: slot.info.occupied ? 0 : 1.5
                                border.color: root.labelColor(slot.index)
                                Behavior on width {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }

                    Component {
                        id: expressiveSlot
                        Item {
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: root.expressiveDiameter
                                radius: height / 2
                                color: slot.active ? tone.colAccent
                                    : slot.info.occupied ? tone.colContainer : "transparent"
                                border.width: slot.active || slot.info.occupied ? 0 : 1.5
                                border.color: ColorUtils.transparentize(tone.colOnContainer, root.emptyFade)
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                                StyledText {
                                    anchors.centerIn: parent
                                    visible: slot.active || root.showNumbers
                                    text: slot.label
                                    font.pixelSize: root.labelSize * 0.9
                                    font.weight: Font.Black
                                    color: slot.active ? tone.colOnAccent : tone.colOnContainer
                                    opacity: slot.active || slot.info.occupied ? 1 : 1 - root.emptyFade
                                }
                            }
                        }
                    }

                    Component {
                        id: dockSlot
                        Item {
                            readonly property string app: root.dockIcons && slot.info.windows.length > 0 ? slot.info.windows[0] : ""
                            AppGlyph {
                                anchors.centerIn: parent
                                visible: parent.app !== ""
                                appClass: parent.app
                                size: root.dockButton * root.dockIconRatio
                            }
                            StyledText {
                                anchors.centerIn: parent
                                visible: parent.app === ""
                                text: slot.label
                                font.pixelSize: root.labelSize
                                font.weight: Font.Bold
                                color: root.labelColor(slot.index)
                            }
                            Row {
                                visible: root.dockDots
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: (root.dockButton - root.unit) / 2 + 2
                                spacing: 2
                                Repeater {
                                    model: Math.min(root.dockDotLimit, slot.info.windows.length)
                                    delegate: Rectangle {
                                        width: root.dotSize
                                        height: width
                                        radius: width / 2
                                        color: slot.active ? tone.colBackground : ColorUtils.transparentize(Appearance.colors.colOnLayer1, root.emptyFade)
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: indexSlot
                        Item {
                            StyledText {
                                anchors.centerIn: parent
                                text: slot.label
                                font.pixelSize: slot.active ? root.indexActiveSize : root.indexRestSize
                                font.weight: slot.active ? Font.Black : Font.DemiBold
                                color: slot.active ? tone.colBareAccent : Appearance.colors.colOnLayer1
                                opacity: slot.active || slot.info.occupied ? 1 : 1 - root.emptyFade
                                Behavior on font.pixelSize {
                                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.interactive && (slot.info?.shown ?? false)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.slotClicked(slot.index)
                }
            }
        }
    }

    component AppGlyph: Item {
        id: glyph
        property string appClass: ""
        property real size: root.iconBox

        width: glyph.size
        height: glyph.size

        MaterialShape {
            id: glyphMask
            anchors.fill: parent
            shapeString: root.maskShape
            visible: false
        }

        IconImage {
            id: glyphIcon
            anchors.centerIn: parent
            implicitSize: glyph.size * root.iconRatio
            source: glyph.appClass !== "" ? Quickshell.iconPath(AppSearch.guessIcon(glyph.appClass), "image-missing") : ""
            layer.enabled: root.maskIcons
            layer.effect: OpacityMask {
                maskSource: glyphMask
            }
        }

        Loader {
            active: root.tintIcons
            anchors.fill: glyphIcon
            sourceComponent: Item {
                Desaturate {
                    id: desaturated
                    anchors.fill: parent
                    visible: false
                    source: glyphIcon
                    desaturation: 0.8
                    layer.enabled: root.maskIcons
                    layer.effect: OpacityMask {
                        maskSource: glyphMask
                    }
                }
                ColorOverlay {
                    anchors.fill: desaturated
                    source: desaturated
                    color: ColorUtils.transparentize(tone.colBackground, root.tintAmount)
                }
            }
        }
    }
}
