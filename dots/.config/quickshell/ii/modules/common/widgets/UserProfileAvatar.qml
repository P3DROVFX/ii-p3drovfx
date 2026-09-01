pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    implicitWidth: 40
    implicitHeight: 40

    property string imageStyle: Config.options.userProfile.imageStyle
    property string imagePath: Config.options.userProfile.imagePath
    property string avatarShape: Config.options.userProfile.avatarShape
    property string avatarColor: Config.options.userProfile.avatarColor
    property string customName: Config.options.userProfile.customName

    property bool interactive: false
    property bool active: true
    property real fontPixelSize: Math.round(height * 0.42)
    property int fontWeight: Font.DemiBold
    property int cursorShape: interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

    property real borderWidth: 0
    property color borderColor: "transparent"

    readonly property bool isRectangle: root.avatarShape === "Rectangle" || root.avatarShape === "windowRounding"

    signal clicked()

    function resolveShape(s) {
        switch (s) {
        case "Cookie9Sided": return MaterialShape.Shape.Cookie9Sided;
        case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided;
        case "Circle": return MaterialShape.Shape.Circle;
        case "Clover4Leaf": return MaterialShape.Shape.Clover4Leaf;
        case "Burst": return MaterialShape.Shape.Burst;
        case "Heart": return MaterialShape.Shape.Heart;
        case "Bun": return MaterialShape.Shape.Bun;
        case "Flower": return MaterialShape.Shape.Flower;
        case "Puffy": return MaterialShape.Shape.Puffy;
        case "PuffyDiamond": return MaterialShape.Shape.PuffyDiamond;
        case "Sunny": return MaterialShape.Shape.Sunny;
        case "VerySunny": return MaterialShape.Shape.VerySunny;
        case "Cookie4Sided": return MaterialShape.Shape.Cookie4Sided;
        case "Cookie6Sided": return MaterialShape.Shape.Cookie6Sided;
        case "Cookie7Sided": return MaterialShape.Shape.Cookie7Sided;
        case "Ghostish": return MaterialShape.Shape.Ghostish;
        case "Clover8Leaf": return MaterialShape.Shape.Clover8Leaf;
        case "SoftBurst": return MaterialShape.Shape.SoftBurst;
        case "Boom": return MaterialShape.Shape.Boom;
        case "SoftBoom": return MaterialShape.Shape.SoftBoom;
        case "Gem": return MaterialShape.Shape.Gem;
        case "Diamond": return MaterialShape.Shape.Diamond;
        case "Pentagon": return MaterialShape.Shape.Pentagon;
        case "Square": return MaterialShape.Shape.Square;
        case "Arch": return MaterialShape.Shape.Arch;
        case "Fan": return MaterialShape.Shape.Fan;
        case "Arrow": return MaterialShape.Shape.Arrow;
        case "SemiCircle": return MaterialShape.Shape.SemiCircle;
        case "Oval": return MaterialShape.Shape.Oval;
        case "Pill": return MaterialShape.Shape.Pill;
        case "Triangle": return MaterialShape.Shape.Triangle;
        case "Slanted": return MaterialShape.Shape.Slanted;
        case "ClamShell": return MaterialShape.Shape.ClamShell;
        case "PixelCircle": return MaterialShape.Shape.PixelCircle;
        case "PixelTriangle": return MaterialShape.Shape.PixelTriangle;
        default:
            return MaterialShape.Shape.Cookie9Sided;
        }
    }

    readonly property color resolvedColor: {
        switch (root.avatarColor) {
        case "secondary": return Appearance.colors.colSecondary;
        case "tertiary": return Appearance.colors.colTertiary;
        case "error": return Appearance.colors.colError;
        default: return Appearance.colors.colPrimary;
        }
    }

    readonly property color resolvedOnColor: {
        switch (root.avatarColor) {
        case "secondary": return Appearance.colors.colOnSecondary;
        case "tertiary": return Appearance.colors.colOnTertiary;
        case "error": return Appearance.colors.colOnError;
        default: return Appearance.colors.colOnPrimary;
        }
    }

    readonly property string cleanImagePath: {
        let p = root.imagePath || "";
        const qIdx = p.indexOf("?");
        if (qIdx !== -1) {
            p = p.substring(0, qIdx);
        }
        return p;
    }

    readonly property bool isAnimated: {
        const src = root.cleanImagePath.toLowerCase();
        return src.endsWith(".gif") || src.endsWith(".webp");
    }

    readonly property string resolvedImageSource: {
        if (root.imageStyle === "custom") {
            const p = root.cleanImagePath;
            if (!p) return "";
            if (p.startsWith("file://") || p.startsWith("http://") || p.startsWith("https://") || p.startsWith("qrc:/")) {
                return p;
            }
            return "file://" + p;
        }
        if (root.imageStyle === "initial") {
            const acc = Directories.userAvatarPathAccountsService;
            if (!acc) return "";
            return acc.startsWith("file://") ? acc : "file://" + acc;
        }
        return "";
    }

    readonly property string initialLetter: {
        const n = root.customName || SystemInfo.username;
        return n ? n.charAt(0).toUpperCase() : "?";
    }

    readonly property bool shouldPlay: {
        if (!root.active || !root.visible || root.opacity <= 0) return false;
        if (!root.isAnimated) return false;
        if (root.Window.window && !root.Window.window.visible) return false;
        return true;
    }

    readonly property bool hasVisibleImage: (!root.isAnimated && staticImg.visible) || (root.isAnimated && avatarImg.visible)

    // Outer border shape matching avatar shape / rectangle if borderWidth is set
    Rectangle {
        id: borderRect
        anchors.centerIn: parent
        width: parent.width + root.borderWidth * 2
        height: parent.height + root.borderWidth * 2
        radius: Math.max(0, Appearance.rounding.windowRounding + root.borderWidth)
        color: root.borderColor
        visible: root.borderWidth > 0 && root.isRectangle
        z: -1
    }

    MaterialShape {
        id: borderShape
        anchors.centerIn: parent
        width: parent.width + root.borderWidth * 2
        height: parent.height + root.borderWidth * 2
        shape: root.resolveShape(root.avatarShape)
        color: root.borderColor
        visible: root.borderWidth > 0 && !root.isRectangle
        z: -1
    }

    // Base shape with solid color and fallback initial text
    Rectangle {
        id: baseRect
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: root.resolvedColor
        visible: root.isRectangle

        StyledText {
            anchors.centerIn: parent
            text: root.initialLetter
            color: root.resolvedOnColor
            font.pixelSize: root.fontPixelSize
            font.weight: root.fontWeight
            font.family: Appearance.font.family.expressive
            visible: !root.hasVisibleImage
        }
    }

    MaterialShape {
        id: baseShape
        anchors.fill: parent
        shape: root.resolveShape(root.avatarShape)
        color: root.resolvedColor
        visible: !root.isRectangle

        StyledText {
            anchors.centerIn: parent
            text: root.initialLetter
            color: root.resolvedOnColor
            font.pixelSize: root.fontPixelSize
            font.weight: root.fontWeight
            font.family: Appearance.font.family.expressive
            visible: !root.hasVisibleImage
        }
    }

    // Static Image loader (hardware-accelerated, zero QMovie overhead, crisp downsampling)
    Image {
        id: staticImg
        anchors.fill: parent
        source: !root.isAnimated ? root.resolvedImageSource : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: true
        sourceSize: Qt.size(Math.max(256, Math.ceil(root.width * 2)), Math.max(256, Math.ceil(root.height * 2)))
        visible: !root.isAnimated && status === Image.Ready && root.imageStyle !== "expressive"

        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Item {
                width: staticImg.width
                height: staticImg.height

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.windowRounding
                    visible: root.isRectangle
                }

                MaterialShape {
                    anchors.fill: parent
                    shape: root.resolveShape(root.avatarShape)
                    visible: !root.isRectangle
                }
            }
        }
    }

    // Animated GIF loader (only active when isAnimated is true)
    AnimatedImage {
        id: avatarImg
        anchors.fill: parent
        source: root.isAnimated ? root.resolvedImageSource : ""
        fillMode: Image.PreserveAspectCrop
        playing: root.shouldPlay
        paused: !root.shouldPlay
        asynchronous: true
        smooth: true
        mipmap: true
        cache: false
        visible: root.isAnimated && status === Image.Ready && root.imageStyle !== "expressive"

        layer.enabled: true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Item {
                width: avatarImg.width
                height: avatarImg.height

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.windowRounding
                    visible: root.isRectangle
                }

                MaterialShape {
                    anchors.fill: parent
                    shape: root.resolveShape(root.avatarShape)
                    visible: !root.isRectangle
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: root.cursorShape
        hoverEnabled: root.interactive
        onClicked: root.clicked()
    }
}
