import qs.modules.common.widgets.shapes
import "shapes/material-shapes.js" as MaterialShapes
import QtQuick

ShapeCanvas {
    id: root
    enum Shape {
        Circle,
        Square,
        Slanted,
        Arch,
        Fan,
        Arrow,
        SemiCircle,
        Oval,
        Pill,
        Triangle,
        Diamond,
        ClamShell,
        Pentagon,
        Gem,
        Sunny,
        VerySunny,
        Cookie4Sided,
        Cookie6Sided,
        Cookie7Sided,
        Cookie9Sided,
        Cookie12Sided,
        Ghostish,
        Clover4Leaf,
        Clover8Leaf,
        Burst,
        SoftBurst,
        Boom,
        SoftBoom,
        Flower,
        Puffy,
        PuffyDiamond,
        PixelCircle,
        PixelTriangle,
        Bun,
        Heart
    }

    readonly property var shapeMap: ({
        "Circle": MaterialShape.Shape.Circle,
        "Square": MaterialShape.Shape.Square,
        "Slanted": MaterialShape.Shape.Slanted,
        "Circle": MaterialShape.Shape.Circle,
        "Square": MaterialShape.Shape.Square,
        "Slanted": MaterialShape.Shape.Slanted,
        "Arch": MaterialShape.Shape.Arch,
        "Fan": MaterialShape.Shape.Fan,
        "Arrow": MaterialShape.Shape.Arrow,
        "SemiCircle": MaterialShape.Shape.SemiCircle,
        "Oval": MaterialShape.Shape.Oval,
        "Pill": MaterialShape.Shape.Pill,
        "Triangle": MaterialShape.Shape.Triangle,
        "Diamond": MaterialShape.Shape.Diamond,
        "ClamShell": MaterialShape.Shape.ClamShell,
        "Pentagon": MaterialShape.Shape.Pentagon,
        "Gem": MaterialShape.Shape.Gem,
        "Sunny": MaterialShape.Shape.Sunny,
        "VerySunny": MaterialShape.Shape.VerySunny,
        "Cookie4Sided": MaterialShape.Shape.Cookie4Sided,
        "Cookie6Sided": MaterialShape.Shape.Cookie6Sided,
        "Cookie7Sided": MaterialShape.Shape.Cookie7Sided,
        "Cookie9Sided": MaterialShape.Shape.Cookie9Sided,
        "Cookie12Sided": MaterialShape.Shape.Cookie12Sided,
        "Ghostish": MaterialShape.Shape.Ghostish,
        "Clover4Leaf": MaterialShape.Shape.Clover4Leaf,
        "Clover8Leaf": MaterialShape.Shape.Clover8Leaf,
        "Burst": MaterialShape.Shape.Burst,
        "SoftBurst": MaterialShape.Shape.SoftBurst,
        "Boom": MaterialShape.Shape.Boom,
        "SoftBoom": MaterialShape.Shape.SoftBoom,
        "Flower": MaterialShape.Shape.Flower,
        "Puffy": MaterialShape.Shape.Puffy,
        "PuffyDiamond": MaterialShape.Shape.PuffyDiamond,
        "PixelCircle": MaterialShape.Shape.PixelCircle,
        "PixelTriangle": MaterialShape.Shape.PixelTriangle,
        "Bun": MaterialShape.Shape.Bun,
        "Heart": MaterialShape.Shape.Heart
    })

    function getShape(str) {
        return shapeMap[str] !== undefined
            ? shapeMap[str]
            : MaterialShape.Shape.Circle // fallback
    }

    property string shapeString
    property var shape
    property double implicitSize
    implicitHeight: implicitSize
    implicitWidth: implicitSize
    polygonIsNormalized: true

    /**
     * Rotation pivot.
     *
     * `RoundedPolygon.normalized()` fits a shape's *bounding box* into the unit
     * square, which is not the same as centring it on its rotational centre.
     * Even-symmetry shapes land exactly on 0.5; odd-symmetry ones do not — a
     * 7-sided cookie sits 1.2% of its size low, a gem 2%, a triangle 11%.
     * `rotation` pivots on the item's centre, so those shapes orbit that point
     * instead of spinning in place, and the whole silhouette sliding together
     * reads as a wobble well below a pixel.
     *
     * Re-anchoring the *paint* instead would push the shape out of its box (a
     * triangle would have to shrink by a tenth to fit again), changing how every
     * static shape lays out. So the pivot moves and the picture does not: the
     * item's own rotation is undone and re-applied about the polygon's real
     * centre. Both angles are zero whenever `rotation` is, so every caller that
     * never spins is untouched.
     *
     * This lives here rather than in ShapeCanvas because `shapes/` is a git
     * submodule (end-4/rounded-polygon-qmljs) and a fix left in there would be
     * lost on the next submodule update. It assumes the default
     * `transformOrigin` (Item.Center), and a caller that assigns its own
     * `transform` list replaces this one and opts out — which is what the two
     * that do already wanted.
     */
    readonly property real paintScale: root.polygonIsNormalized ? Math.min(root.width, root.height) : 1
    readonly property real pivotX: ((root.roundedPolygon?.centerX ?? 0.5) + root.xOffset) * root.paintScale
    readonly property real pivotY: ((root.roundedPolygon?.centerY ?? 0.5) + root.yOffset) * root.paintScale

    transform: [
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            angle: -root.rotation
        },
        Rotation {
            origin.x: root.pivotX
            origin.y: root.pivotY
            angle: root.rotation
        }
    ]

    onShapeStringChanged: {
        if (!shapeString) return
        shape = getShape(shapeString)
    }

    roundedPolygon: {
        switch (root.shape) {
            case MaterialShape.Shape.Circle: return MaterialShapes.getCircle();
            case MaterialShape.Shape.Square: return MaterialShapes.getSquare();
            case MaterialShape.Shape.Slanted: return MaterialShapes.getSlanted();
            case MaterialShape.Shape.Arch: return MaterialShapes.getArch();
            case MaterialShape.Shape.Fan: return MaterialShapes.getFan();
            case MaterialShape.Shape.Arrow: return MaterialShapes.getArrow();
            case MaterialShape.Shape.SemiCircle: return MaterialShapes.getSemiCircle();
            case MaterialShape.Shape.Oval: return MaterialShapes.getOval();
            case MaterialShape.Shape.Pill: return MaterialShapes.getPill();
            case MaterialShape.Shape.Triangle: return MaterialShapes.getTriangle();
            case MaterialShape.Shape.Diamond: return MaterialShapes.getDiamond();
            case MaterialShape.Shape.ClamShell: return MaterialShapes.getClamShell();
            case MaterialShape.Shape.Pentagon: return MaterialShapes.getPentagon();
            case MaterialShape.Shape.Gem: return MaterialShapes.getGem();
            case MaterialShape.Shape.Sunny: return MaterialShapes.getSunny();
            case MaterialShape.Shape.VerySunny: return MaterialShapes.getVerySunny();
            case MaterialShape.Shape.Cookie4Sided: return MaterialShapes.getCookie4Sided();
            case MaterialShape.Shape.Cookie6Sided: return MaterialShapes.getCookie6Sided();
            case MaterialShape.Shape.Cookie7Sided: return MaterialShapes.getCookie7Sided();
            case MaterialShape.Shape.Cookie9Sided: return MaterialShapes.getCookie9Sided();
            case MaterialShape.Shape.Cookie12Sided: return MaterialShapes.getCookie12Sided();
            case MaterialShape.Shape.Ghostish: return MaterialShapes.getGhostish();
            case MaterialShape.Shape.Clover4Leaf: return MaterialShapes.getClover4Leaf();
            case MaterialShape.Shape.Clover8Leaf: return MaterialShapes.getClover8Leaf();
            case MaterialShape.Shape.Burst: return MaterialShapes.getBurst();
            case MaterialShape.Shape.SoftBurst: return MaterialShapes.getSoftBurst();
            case MaterialShape.Shape.Boom: return MaterialShapes.getBoom();
            case MaterialShape.Shape.SoftBoom: return MaterialShapes.getSoftBoom();
            case MaterialShape.Shape.Flower: return MaterialShapes.getFlower();
            case MaterialShape.Shape.Puffy: return MaterialShapes.getPuffy();
            case MaterialShape.Shape.PuffyDiamond: return MaterialShapes.getPuffyDiamond();
            case MaterialShape.Shape.PixelCircle: return MaterialShapes.getPixelCircle();
            case MaterialShape.Shape.PixelTriangle: return MaterialShapes.getPixelTriangle();
            case MaterialShape.Shape.Bun: return MaterialShapes.getBun();
            case MaterialShape.Shape.Heart: return MaterialShapes.getHeart();
            default: return MaterialShapes.getCircle();
        }
    }
}
