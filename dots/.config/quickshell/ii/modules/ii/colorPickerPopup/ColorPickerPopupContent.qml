pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar.shared.cards

import "../../common/functions/colorNames.js" as ColorNames

Item {
    id: root

    property string colorHex: GlobalStates.colorPickerPopupColor || "#371319"

    signal dismissed

    // Expose background so ColorPickerPopup.qml can use it as a mask (Bug 3)
    property alias contentBackground: contentBackground
    readonly property bool isHovered: backgroundMa.containsMouse || rootHover.hovered

    HoverHandler {
        id: rootHover
    }

    // Border gap = elevationMargin (Bug 4), same as BluetoothConnectionPopupContent
    implicitWidth: contentBackground.implicitWidth + 2 * Appearance.sizes.elevationMargin
    implicitHeight: contentBackground.implicitHeight + 2 * Appearance.sizes.elevationMargin

    // Computed color properties
    readonly property var colorRgb: {
        let hex = root.colorHex;
        if (!hex || hex.length < 7)
            return {
                r: 0,
                g: 0,
                b: 0
            };
        return {
            r: parseInt(hex.substring(1, 3), 16) || 0,
            g: parseInt(hex.substring(3, 5), 16) || 0,
            b: parseInt(hex.substring(5, 7), 16) || 0
        };
    }

    readonly property string rgbString: {
        let c = root.colorRgb;
        return "RGB(" + c.r + ", " + c.g + ", " + c.b + ")";
    }

    readonly property bool darkBg: {
        let c = root.colorRgb;
        let luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return luminance < 128;
    }

    readonly property bool isMonochrome: {
        let c = root.colorRgb;
        let l = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        let max = Math.max(c.r, c.g, c.b);
        let min = Math.min(c.r, c.g, c.b);
        let s = max === 0 ? 0 : (max - min) / max;
        // If luminance is too low or high, or saturation is almost zero
        return l < 15 || l > 240 || s < 0.05;
    }

    function getContrastColor(bgCol) {
        let c = Qt.color(bgCol);
        let luminance = 0.2126 * (c.r * 255) + 0.7152 * (c.g * 255) + 0.0722 * (c.b * 255);
        return luminance < 128 ? "#FFFFFF" : "#111111";
    }

    readonly property color onColor: getContrastColor(root.colorHex)

    property var palette: null
    property var surfacePalette: null

    readonly property color copiedBgColor: "#1E4620"
    readonly property color copiedOnColor: "#A8E3A9"
    readonly property color copiedAccent: "#2E7D32"

    readonly property real contentPadding: 16
    readonly property real itemSpacing: 10
    readonly property real variantCardHeight: 110
    readonly property real copyBtnSize: 36
    readonly property real spectrumBarHeight: 28
    readonly property real iconClickZone: 48

    property int pillCarouselIndex: 0

    readonly property string hslString: {
        let c = root.colorRgb;
        let r = c.r / 255;
        let g = c.g / 255;
        let b = c.b / 255;

        let max = Math.max(r, g, b);
        let min = Math.min(r, g, b);
        let delta = max - min;
        let h = 0;
        if (delta > 0) {
            if (max === r)
                h = 60 * (((g - b) / delta) % 6);
            else if (max === g)
                h = 60 * (((b - r) / delta) + 2);
            else
                h = 60 * (((r - g) / delta) + 4);
        }
        if (h < 0)
            h += 360;
        let l = (max + min) / 2;
        let s = delta === 0 ? 0 : delta / (1 - Math.abs(2 * l - 1));

        return "hsl(" + Math.round(h) + ", " + Math.round(s * 100) + "%, " + Math.round(l * 100) + "%)";
    }

    readonly property real staggerDelay1: 50
    readonly property real staggerDelay2: 150
    readonly property real staggerDelay3: 250

    Process {
        id: matugenProcess
        command: {
            return ["matugen", "color", "hex", "--dry-run", "-j", "hex", "-t", "scheme-content", root.colorHex];
        }
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (data.startsWith("{")) {
                    try {
                        let json = JSON.parse(data);
                        let useDarkTheme = Qt.color(root.colorHex).hslLightness >= 0.45;
                        root.palette = useDarkTheme ? json.colors.dark : json.colors.light;
                        root.surfacePalette = json.colors.dark;
                    } catch (e) {}
                }
            }
        }
    }

    onColorHexChanged: {
        matugenProcess.running = false;
        Qt.callLater(() => {
            matugenProcess.running = true;
        });
    }

    property bool rgbCopied: false
    Timer {
        id: rgbCopiedTimer
        interval: 2000
        onTriggered: root.rgbCopied = false
    }

    property bool hexCopied: false
    Timer {
        id: hexCopiedTimer
        interval: 2000
        onTriggered: root.hexCopied = false
    }

    property bool formatCopied: false
    Timer {
        id: formatCopiedTimer
        interval: 2000
        onTriggered: root.formatCopied = false
    }

    // Auto-dismiss timer — stays open while hovered
    Timer {
        id: dismissTimer
        interval: 6000
        running: !root.isHovered && !matugenProcess.running
        repeat: false
        onTriggered: root.dismissed()
    }

    // Timer to trigger staggered entrance
    property bool entrance1: false
    property bool entrance2: false
    property bool entrance3: false

    Timer {
        interval: root.staggerDelay1
        running: true
        onTriggered: root.entrance1 = true
    }
    Timer {
        interval: root.staggerDelay2
        running: true
        onTriggered: root.entrance2 = true
    }
    Timer {
        interval: root.staggerDelay3
        running: true
        onTriggered: root.entrance3 = true
    }

    // Targeted animations for internal components (to avoid modifying Bar cards)
    SequentialAnimation {
        id: headerPillEntrance
        running: root.entrance1
        PauseAnimation {
            duration: root.staggerDelay3
        }
        NumberAnimation {
            target: headerCard.children[1]
            property: "scale"
            from: 0
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

    SequentialAnimation {
        id: rgbPillIconBounce
        NumberAnimation {
            target: rgbPill.children.length > 0 ? rgbPill.children[0] : null
            property: "scale"
            from: 1.0
            to: 1.35
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutBack
            easing.overshoot: 2.5
        }
        NumberAnimation {
            target: rgbPill.children.length > 0 ? rgbPill.children[0] : null
            property: "scale"
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: formatPillIconBounce
        NumberAnimation {
            target: formatPill.children.length > 0 ? formatPill.children[0] : null
            property: "scale"
            from: 1.0
            to: 1.35
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutBack
            easing.overshoot: 2.5
        }
        NumberAnimation {
            target: formatPill.children.length > 0 ? formatPill.children[0] : null
            property: "scale"
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    // Expose a static, unscaled item for the window input mask to prevent coordinate bugs during scale
    property alias staticMaskTarget: staticMaskTarget
    Item {
        id: staticMaskTarget
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
    }

    // Hover scale for the InfoPill icons
    Binding {
        target: rgbPill.children.length > 0 ? rgbPill.children[0] : null
        property: "scale"
        value: rgbCopyMa.containsMouse ? 1.15 : 1.0
        when: !rgbPillIconBounce.running
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: formatPill.children.length > 0 ? formatPill.children[0] : null
        property: "scale"
        value: formatCopyMa.containsMouse ? 1.15 : 1.0
        when: !formatPillIconBounce.running
        restoreMode: Binding.RestoreBindingOrValue
    }

    Component.onCompleted: {
        // Garantir que a pílula comece invisível para a animação de entrada
        if (headerCard.children.length > 1) {
            headerCard.children[1].scale = 0;
        }
        entranceAnim.start()
    }

    // === BACKGROUND with shadow and rounding (mask target) ===
    Rectangle {
        id: contentBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        implicitWidth: mainLayout.implicitWidth + root.contentPadding * 2
        implicitHeight: mainLayout.implicitHeight + root.contentPadding * 2

        radius: Appearance.rounding.large
        color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer

        // Animations applied on the card itself to keep root window input mapping clean
        opacity: 0
        scale: 0.88
        transformOrigin: Item.TopRight

        ParallelAnimation {
            id: entranceAnim
            NumberAnimation {
                target: contentBackground
                property: "opacity"
                from: 0; to: 1
                duration: Appearance.animation.menuDecel.duration
                easing.type: Appearance.animation.menuDecel.type
            }
            NumberAnimation {
                target: contentBackground
                property: "scale"
                from: 0.88; to: 1.0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }

        MouseArea {
            id: backgroundMa
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            onWheel: wheel => wheel.accepted = true
            onClicked: mouse => mouse.accepted = true
            onPressed: mouse => mouse.accepted = true
            onReleased: mouse => mouse.accepted = true
        }

        ColumnLayout {
            id: mainLayout
            anchors {
                fill: parent
                margins: root.contentPadding
            }
            spacing: 12

            // ═══ SECTION 1: HeroCard ═══
            HeroCard {
                id: headerCard
                Layout.fillWidth: true

                // Entrance
                opacity: root.entrance1 ? 1.0 : 0.0
                Layout.topMargin: root.entrance1 ? 0 : 10
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }
                Behavior on Layout.topMargin {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                // Stable, theme-compliant background
                color: Appearance.colors.colLayer2Base

                // Cookie shape with the EXACT captured color and high-contrast paint bucket icon
                shapeString: "Cookie12Sided"
                shapeColor: Qt.color(root.colorHex)
                icon: "format_color_fill"
                symbolColor: root.getContrastColor(root.colorHex)
                iconSize: 100

                // Text: guaranteed high-contrast text on the stable card background
                textColor: Appearance.colors.colOnSurface
                title: ColorNames.getColorName(root.colorHex)
                subtitle: root.colorHex.toUpperCase()
                titleSize: Appearance.font.pixelSize.huge
                subtitleSize: Appearance.font.pixelSize.large

                // "Copied" Pill — use HeroCard properties
                pillText: qsTr("Copied")
                pillIcon: "check"
                pillColor: root.copiedBgColor
                pillTextColor: root.copiedOnColor
                pillIconColor: root.copiedOnColor

                // Click to copy main hex
                MouseArea {
                    id: headerMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.clipboardText = root.colorHex;
                        root.hexCopied = true;
                        hexCopiedTimer.restart();
                    }
                }

                // Animated rotation of the cookie shape
                RotationAnimation on shapeRotation {
                    from: 0
                    to: 360
                    duration: 15000
                    loops: Animation.Infinite
                    running: true
                    direction: RotationAnimation.Clockwise
                }
            }

            // ═══ SECTION 2: InfoPill Carousel ═══
            Item {
                id: pillCarouselContainer
                Layout.fillWidth: true
                implicitHeight: rgbPill.implicitHeight

                opacity: root.entrance2 ? 1.0 : 0.0
                Layout.topMargin: root.entrance2 ? 0 : 8
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }
                Behavior on Layout.topMargin {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                clip: true

                Item {
                    id: pillTrack
                    width: pillCarouselContainer.width * 2
                    height: pillCarouselContainer.implicitHeight

                    x: pillInteractionArea.isDragging ? pillInteractionArea.dragX : (root.pillCarouselIndex === 0 ? 0 : -pillCarouselContainer.width)

                    Behavior on x {
                        enabled: !pillInteractionArea.isDragging
                        NumberAnimation {
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                    }

                    InfoPill {
                        id: rgbPill
                        width: pillCarouselContainer.width
                        anchors.top: parent.top

                        containerColor: root.rgbCopied ? root.copiedBgColor : (root.palette ? root.palette.secondary_container : Appearance.colors.colSecondaryContainer)
                        shapeColor: root.rgbCopied ? root.copiedAccent : (rgbCopyMa.containsMouse ? (root.palette ? Appearance.colors.colSecondaryHover : Appearance.colors.colSecondary) : (root.palette ? root.palette.secondary : Qt.color(root.colorHex)))
                        symbolColor: root.rgbCopied ? root.copiedOnColor : root.getContrastColor(shapeColor)
                        textColor: root.rgbCopied ? root.copiedOnColor : root.getContrastColor(containerColor)
                        shapeString: "Cookie12Sided"
                        icon: root.rgbCopied ? "check" : "content_copy"
                        text: root.rgbCopied ? qsTr("Copied") : root.rgbString
                    }

                    MouseArea {
                        id: rgbCopyMa
                        parent: rgbPill
                        width: root.iconClickZone
                        height: root.iconClickZone
                        anchors {
                            left: parent.left
                            leftMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        z: 1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.clipboardText = root.rgbString;
                            root.rgbCopied = true;
                            rgbCopiedTimer.restart();
                            rgbPillIconBounce.restart();
                        }
                    }

                    InfoPill {
                        id: formatPill
                        width: pillCarouselContainer.width
                        anchors.top: parent.top
                        anchors.left: rgbPill.right

                        containerColor: root.formatCopied ? root.copiedBgColor : (root.palette ? root.palette.secondary_container : Appearance.colors.colSecondaryContainer)
                        shapeColor: root.formatCopied ? root.copiedAccent : (formatCopyMa.containsMouse ? (root.palette ? Appearance.colors.colSecondaryHover : Appearance.colors.colSecondary) : (root.palette ? root.palette.secondary : Qt.color(root.colorHex)))
                        symbolColor: root.formatCopied ? root.copiedOnColor : root.getContrastColor(shapeColor)
                        textColor: root.formatCopied ? root.copiedOnColor : root.getContrastColor(containerColor)
                        shapeString: "Cookie12Sided"
                        icon: root.formatCopied ? "check" : "content_copy"
                        text: root.formatCopied ? qsTr("Copied") : root.hslString
                    }

                    MouseArea {
                        id: formatCopyMa
                        parent: formatPill
                        width: root.iconClickZone
                        height: root.iconClickZone
                        anchors {
                            left: parent.left
                            leftMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        z: 1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.clipboardText = root.hslString;
                            root.formatCopied = true;
                            formatCopiedTimer.restart();
                            formatPillIconBounce.restart();
                        }
                    }
                }

                MouseArea {
                    id: pillInteractionArea
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    // Default cursor as requested
                    cursorShape: Qt.ArrowCursor

                    property real startX: 0
                    property real dragX: 0
                    property bool isDragging: false

                    onPressed: mouse => {
                        startX = mouse.x;
                        dragX = root.pillCarouselIndex === 0 ? 0 : -pillCarouselContainer.width;
                        isDragging = true;
                    }

                    onPositionChanged: mouse => {
                        if (isDragging) {
                            let diff = mouse.x - startX;
                            let base = root.pillCarouselIndex === 0 ? 0 : -pillCarouselContainer.width;
                            dragX = Math.max(-pillCarouselContainer.width, Math.min(0, base + diff));
                        }
                    }

                    onReleased: mouse => {
                        if (isDragging) {
                            let diff = mouse.x - startX;
                            if (Math.abs(diff) > 40) {
                                if (diff > 0)
                                    root.pillCarouselIndex = 0;
                                else
                                    root.pillCarouselIndex = 1;
                            }
                            isDragging = false;
                        }
                    }

                    onWheel: event => {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                        if (delta < 0) {
                            root.pillCarouselIndex = 1;
                        } else if (delta > 0) {
                            root.pillCarouselIndex = 0;
                        }
                        event.accepted = true;
                    }
                }
            }

            Row {
                id: pillIndicator
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                Repeater {
                    model: 2
                    Rectangle {
                        id: indicatorDot
                        required property int index
                        width: root.pillCarouselIndex === index ? 18 : 8
                        height: 8
                        radius: Appearance.rounding.full
                        color: root.pillCarouselIndex === index ? (root.palette ? root.palette.secondary : Appearance.colors.colSecondary) : Appearance.colors.colOnLayer1

                        Behavior on width {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pillCarouselIndex = index
                        }
                    }
                }
            }

            // ═══ SECTION 3: Color Variants ═══
            GridLayout {
                id: variantsContainer
                Layout.fillWidth: true
                columns: 2
                rows: 2
                columnSpacing: root.itemSpacing
                rowSpacing: root.itemSpacing

                Repeater {
                    model: [
                        {
                            title: "Primary",
                            color: root.palette ? root.palette.primary : root.colorHex
                        },
                        {
                            title: "Secondary",
                            color: root.palette ? root.palette.secondary : Qt.darker(Qt.color(root.colorHex), 1.2)
                        },
                        {
                            title: "Tertiary",
                            color: root.palette ? root.palette.tertiary : Qt.darker(Qt.color(root.colorHex), 1.4)
                        },
                        {
                            title: "Neutral",
                            color: root.palette ? root.palette.surface_variant : Qt.darker(Qt.color(root.colorHex), 1.6)
                        }
                    ]

                    Rectangle {
                        id: variantCard
                        required property var modelData
                        readonly property int index: model.index
                        Layout.fillWidth: true
                        implicitHeight: root.variantCardHeight
                        radius: Appearance.rounding.normal
                        color: modelData.color
                        clip: true

                        readonly property bool isCardDark: root.getContrastColor(variantCard.color) === "#FFFFFF"

                        // Entrance
                        opacity: root.entrance3 ? 1.0 : 0.0
                        scale: root.entrance3 ? 1.0 : 0.92

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveEnter.duration
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                            }
                        }

                        Behavior on scale {
                            SpringAnimation {
                                spring: 5.0
                                damping: 0.5
                            }
                        }

                        MouseArea {
                            id: variantCardMa
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        // Top Texts
                        StyledText {
                            id: titleText
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 12
                            text: modelData.title
                            color: root.getContrastColor(variantCard.color)
                            font.pixelSize: Appearance.font.pixelSize.medium
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            id: hexText
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 12
                            text: {
                                let c = (variantCard.color.toString()).toUpperCase();
                                if (c.length === 9 && c.startsWith("#FF")) {
                                    c = "#" + c.substring(3);
                                }
                                return c;
                            }
                            color: root.getContrastColor(variantCard.color)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.monospace
                        }

                        // Glassy Copy Pill
                        Item {
                            id: btnCopy
                            anchors.top: hexText.bottom
                            anchors.topMargin: 2
                            anchors.right: parent.right
                            anchors.rightMargin: 12

                            width: root.copyBtnSize
                            height: root.copyBtnSize

                            MaterialCookie {
                                anchors.fill: parent
                                sides: 12
                                color: variantCard.copied ? root.copiedAccent : (pillMa.containsMouse ? (isCardDark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.3)) : (isCardDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.15)))
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: variantCard.copied ? "check" : "content_copy"
                                iconSize: 16
                                color: variantCard.copied ? root.copiedOnColor : root.getContrastColor(variantCard.color)
                            }

                            scale: variantCard.copied ? 1.15 : (pillMa.pressed ? 0.92 : (pillMa.containsMouse ? 1.05 : 1))
                            Behavior on scale {
                                SpringAnimation {
                                    spring: 6.0
                                    damping: 0.4
                                }
                            }

                            MouseArea {
                                id: pillMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let c = (variantCard.color.toString()).toUpperCase();
                                    if (c.length === 9 && c.startsWith("#FF")) {
                                        c = "#" + c.substring(3);
                                    }
                                    Quickshell.clipboardText = c;
                                    variantCard.copied = true;
                                    cardCopiedTimer.restart();
                                }
                            }
                        }

                        Item {
                            id: btnInsert
                            anchors.top: titleText.bottom
                            anchors.topMargin: 2
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            width: root.copyBtnSize
                            height: root.copyBtnSize

                            MaterialShape {
                                anchors.fill: parent
                                shapeString: "Cookie4Sided"
                                color: variantCard.applied ? root.copiedAccent : (insertMa.containsMouse ? (isCardDark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.3)) : (isCardDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.15)))
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: variantCard.applied ? "check" : "arrow_insert"
                                iconSize: 16
                                color: variantCard.applied ? root.copiedOnColor : root.getContrastColor(variantCard.color)
                            }

                            scale: variantCard.applied ? 1.15 : (insertMa.pressed ? 0.92 : (insertMa.containsMouse ? 1.05 : 1))
                            Behavior on scale {
                                SpringAnimation {
                                    spring: 6.0
                                    damping: 0.4
                                }
                            }

                            MouseArea {
                                id: insertMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let c = (variantCard.color.toString()).toUpperCase();
                                    if (c.length === 9 && c.startsWith("#FF")) {
                                        c = "#" + c.substring(3);
                                    }
                                    Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", c]);
                                    variantCard.applied = true;
                                    cardAppliedTimer.restart();
                                }
                            }
                        }

                        // Spectrum Bar
                        Canvas {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: root.spectrumBarHeight

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);

                                // Path for bottom rounded rectangle matching the Card
                                let r = variantCard.radius;
                                ctx.beginPath();
                                ctx.moveTo(0, 0);
                                ctx.lineTo(width, 0);
                                ctx.lineTo(width, height - r);
                                ctx.arcTo(width, height, width - r, height, r);
                                ctx.lineTo(r, height);
                                ctx.arcTo(0, height, 0, height - r, r);
                                ctx.closePath();
                                ctx.clip();

                                // Draw the 11 luminance blocks
                                let w = width / 11;
                                let baseColor = Qt.color(modelData.color);
                                let baseHue = baseColor.hslHue;
                                let baseSat = baseColor.hslSaturation;

                                for (let i = 0; i <= 10; i++) {
                                    let colorObj = Qt.hsla(baseHue, baseSat, i / 10.0, 1.0);
                                    ctx.fillStyle = colorObj.toString();
                                    ctx.fillRect(Math.floor(i * w), 0, Math.ceil(w + 1.0), height);
                                }
                            }

                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                        }

                        property bool copied: false
                        Timer {
                            id: cardCopiedTimer
                            interval: 2000
                            onTriggered: variantCard.copied = false
                        }

                        property bool applied: false
                        Timer {
                            id: cardAppliedTimer
                            interval: 2000
                            onTriggered: variantCard.applied = false
                        }
                    }
                }
            }
        }
    }
}
