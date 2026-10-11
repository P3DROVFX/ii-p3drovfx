import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import "shapes"
import "shapes/geometry/offset.js" as Offset
import "shapes/shapes/corner-rounding.js" as CornerRounding
import "shapes/shapes/rounded-polygon.js" as RoundedPolygon
import "shapes/material-shapes.js" as MaterialShapes

/**
 * The shell's cookie clock (widgets/clock/CookieClock.qml and its parts) in one
 * file, with the options of background.widgets.clock_cookie (cookie_* keys) and
 * the widget colour scheme the shell resolved (widget_* colours). Wallpaper
 * categorisation (AI styling) is not mirrored: it rewrites those same options,
 * which arrive here already applied.
 */
Column {
    id: root
    spacing: 10

    // ── options ────────────────────────────────────────────────────────────
    readonly property int sides: Theme.num("cookie_sides", 14)
    readonly property string backgroundStyle: Theme.str("cookie_background_style", "cookie")
    readonly property string backgroundShape: Theme.str("cookie_background_shape", "Arch")
    readonly property string dialStyle: Theme.str("cookie_dial_style", "full")
    readonly property string hourHandStyle: Theme.str("cookie_hour_hand", "fill")
    readonly property string minuteHandStyle: Theme.str("cookie_minute_hand", "medium")
    readonly property string secondHandStyle: Theme.str("cookie_second_hand", "dot")
    readonly property string dateStyle: Theme.str("cookie_date_style", "bubble")
    readonly property bool timeIndicators: Theme.bool("cookie_time_indicators", true)
    readonly property bool hourMarks: Theme.bool("cookie_hour_marks", false)
    readonly property bool constantlyRotate: Theme.bool("cookie_constantly_rotate", false)
    readonly property string quote: Theme.str("cookie_quote", "")
    readonly property bool shadows: Theme.bool("widget_shadows", true) && !Theme.transparency

    // ── widget colour scheme ("default" fallbacks) ─────────────────────────
    function w(token, fallback) {
        return Theme.col("widget_" + token, fallback);
    }
    readonly property color colBackground: w("card_bg_color", Theme.m3surfaceContainerHigh)
    readonly property color colOnBackground: w("text_color_on_bg", Theme.m3onSurfaceVariant)
    readonly property color colBackgroundInfo: w("inner_shape_color", Theme.m3surfaceContainerHighest)
    readonly property color colAccent: w("accent_color", Theme.m3primary)
    readonly property color colSubtext: w("subtext_color_on_bg", Theme.transparentize(Theme.m3onSurfaceVariant, 0.4))
    readonly property color colSurfaceVariant: w("surface_variant_color", Theme.m3surfaceVariant)
    readonly property color colPillBg: w("pill_bg_color", Theme.m3surfaceContainerHighest)
    readonly property color colPillFill: w("pill_fill_color", Theme.m3secondaryContainer)
    readonly property color colOnPillFill: w("text_color_on_pill_fill", Theme.m3onSecondaryContainer)
    readonly property color colOnPillTrack: w("text_color_on_pill_track", Theme.m3onSurface)
    readonly property color colTimeColumn: Qt.rgba(colOnPillTrack.r, colOnPillTrack.g, colOnPillTrack.b, 0.5)

    // ── time ───────────────────────────────────────────────────────────────
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }
    readonly property var clockNumbers: Qt.formatTime(root.now, Theme.timeFormat).split(/[: ]/)
    readonly property int clockHour: parseInt(clockNumbers[0]) % 12
    readonly property int clockMinute: root.now.getMinutes()
    readonly property int clockSecond: root.now.getSeconds()

    component HandRotation: RotationAnimation {
        direction: RotationAnimation.Clockwise
        duration: 300
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
    }

    Item {
        id: dial
        implicitWidth: 240
        implicitHeight: 240

        // ── background shape ───────────────────────────────────────────────
        Item {
            id: cookieShapeContainer
            anchors.fill: parent
            RotationAnimation on rotation {
                running: root.constantlyRotate
                duration: 30000
                easing.type: Easing.Linear
                loops: Animation.Infinite
                from: 360
                to: 0
            }

            Item {
                id: backgroundShape
                anchors.fill: parent
                visible: !root.shadows

                ShapeCanvas {
                    anchors.fill: parent
                    visible: root.backgroundStyle !== "sine"
                    color: root.colBackground
                    polygonIsNormalized: true
                    roundedPolygon: {
                        if (root.backgroundStyle === "shape") {
                            const getter = MaterialShapes["get" + root.backgroundShape];
                            return typeof getter === "function" ? getter() : MaterialShapes.getCircle();
                        }
                        switch (root.sides) {
                        case 0:
                        case 1: return MaterialShapes.getCircle();
                        case 4: return MaterialShapes.getCookie4Sided();
                        case 6: return MaterialShapes.getCookie6Sided();
                        case 7: return MaterialShapes.getCookie7Sided();
                        case 9: return MaterialShapes.getCookie9Sided();
                        case 12: return MaterialShapes.getCookie12Sided();
                        default: {
                            const rounding = new CornerRounding.CornerRounding((root.sides < 17 ? 1.5 : 1.1) / Math.max(root.sides, 1));
                            return RoundedPolygon.RoundedPolygon.star(root.sides, 1, 0.8, rounding)
                                .transformed((x, y) => MaterialShapes.rotate30.map(new Offset.Offset(x, y)))
                                .normalized();
                        }
                        }
                    }
                }

                // Sine cookie: a circle with a sine wave along its edge.
                Shape {
                    anchors.fill: parent
                    visible: root.backgroundStyle === "sine"
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 0
                        fillColor: root.colBackground
                        PathPolyline {
                            path: {
                                const points = [];
                                const size = 240, amplitude = size / 50, steps = 360;
                                const radius = size / 2 - amplitude;
                                for (let i = 0; i <= steps; i++) {
                                    const angle = (i / steps) * 2 * Math.PI;
                                    const wave = Math.sin(angle * root.sides + Math.PI / 2) * amplitude;
                                    points.push(Qt.point(Math.cos(angle) * (radius + wave) + size / 2, Math.sin(angle) * (radius + wave) + size / 2));
                                }
                                return points;
                            }
                        }
                    }
                }
            }
            DropShadow {
                anchors.fill: backgroundShape
                source: backgroundShape
                visible: root.shadows
                radius: 8
                samples: 17
                color: Theme.colShadow
                transparentBorder: true
            }
        }

        // ── dial marks ─────────────────────────────────────────────────────
        Item {
            id: marks
            anchors.fill: parent
            anchors.margins: root.dialStyle === "numbers" ? 0 : 10

            // Lines: 12 hour lines + 60 minute lines
            Repeater {
                model: root.dialStyle === "full" ? 12 : 0
                Item {
                    required property int index
                    rotation: 30 * index
                    anchors.fill: parent
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                        implicitWidth: 18
                        implicitHeight: 4
                        radius: implicitWidth / 2
                        color: root.colSubtext
                    }
                }
            }
            Repeater {
                model: root.dialStyle === "full" ? 60 : 0
                Item {
                    required property int index
                    rotation: 6 * index
                    anchors.fill: parent
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                        implicitWidth: 7
                        implicitHeight: 2
                        radius: implicitWidth / 2
                        color: root.colSubtext
                    }
                }
            }
            // Dots
            Repeater {
                model: root.dialStyle === "dots" ? 12 : 0
                Item {
                    required property int index
                    rotation: 30 * index
                    anchors.fill: parent
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                        implicitWidth: 12
                        implicitHeight: 12
                        radius: 6
                        color: root.colSubtext
                    }
                }
            }
            // Material shapes, the cardinal ones tinted with the accent
            Repeater {
                model: root.dialStyle === "shapes" ? 12 : 0
                Item {
                    required property int index
                    readonly property bool isCardinal: index % 3 === 0
                    rotation: 30 * index
                    anchors.fill: parent
                    MaterialShape {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                        implicitSize: 24
                        shape: ["Circle", "Pill", "Cookie6Sided", "Cookie9Sided", "Cookie12Sided", "Clover4Leaf", "Clover8Leaf",
                            "Burst", "SoftBurst", "Puffy", "Gem", "Cookie4Sided"][parent.index % 12]
                        color: parent.isCardinal ? Theme.mix(root.colSubtext, root.colAccent, 0.3) : root.colSubtext
                    }
                }
            }
            // 3-6-9-12
            Repeater {
                model: root.dialStyle === "numbers" ? 4 : 0
                Item {
                    id: numberItem
                    required property int index
                    rotation: 90 * (index + 1)
                    anchors.fill: parent
                    Item {
                        implicitWidth: 80
                        implicitHeight: 80
                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 10 }
                        StyledText {
                            anchors.centerIn: parent
                            color: root.colSubtext
                            text: 3 * (numberItem.index + 1)
                            rotation: -numberItem.rotation
                            font {
                                family: Theme.str("family_reading", "Readex Pro")
                                pixelSize: 80
                                weight: Font.Black
                                variableAxes: ({})
                            }
                        }
                    }
                }
            }
        }

        // ── extra hour marks ───────────────────────────────────────────────
        Rectangle {
            anchors.centerIn: parent
            visible: root.hourMarks
            color: root.colSubtext
            implicitWidth: 135
            implicitHeight: 135
            radius: width / 2
            Repeater {
                model: 12
                Item {
                    required property int index
                    anchors.fill: parent
                    rotation: 30 * index
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
                        implicitWidth: 12
                        implicitHeight: 4
                        radius: width / 2
                        color: Theme.mix(root.colBackgroundInfo, root.colOnBackground, 0.5)
                    }
                }
            }
        }

        // ── time column ────────────────────────────────────────────────────
        Column {
            anchors.centerIn: parent
            visible: root.timeIndicators
            spacing: -16
            Repeater {
                model: root.clockNumbers
                delegate: StyledText {
                    required property string modelData
                    text: modelData.padStart(2, "0")
                    readonly property bool isAmPm: !text.match(/\d{2}/i)
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.colTimeColumn
                    font {
                        family: Theme.fontNumbers
                        weight: Font.Bold
                        pixelSize: root.hourMarks ? (isAmPm ? 20 : 40) : (isAmPm ? 26 : 68)
                        variableAxes: ({ "wght": 900 })
                    }
                }
            }
        }

        // ── minute hand ────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            z: 1
            visible: root.minuteHandStyle !== "hide"
            readonly property real handWidth: root.minuteHandStyle === "bold" ? 20 : root.minuteHandStyle === "medium" ? 12 : 5
            rotation: -90 + 6 * root.clockMinute
            Behavior on rotation { HandRotation {} }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width / 2 - parent.handWidth / 2 - (root.minuteHandStyle === "classic" ? 15 : 0)
                width: 95
                height: parent.handWidth
                radius: root.minuteHandStyle === "classic" ? 2 : parent.handWidth / 2
                color: root.colSubtext
            }
        }

        // ── hour hand ──────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            z: root.hourHandStyle === "hollow" ? 0 : 2
            visible: root.hourHandStyle !== "hide"
            rotation: -90 + 30 * (root.clockHour + root.clockMinute / 60)
            Behavior on rotation { HandRotation {} }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: (parent.width - 20) / 2 - (root.hourHandStyle === "classic" ? 15 : 0)
                width: 72
                height: root.hourHandStyle === "classic" ? 8 : 20
                radius: root.hourHandStyle === "classic" ? 2 : 10
                color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, root.hourHandStyle === "hollow" ? 0 : 1)
                border.color: root.colAccent
                border.width: 4
            }
        }

        // ── second hand ────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            z: root.secondHandStyle === "line" ? 2 : 3
            visible: root.secondHandStyle !== "hide"
            rotation: 6 * root.clockSecond + 90
            Behavior on rotation {
                enabled: root.constantlyRotate
                RotationAnimation {
                    direction: RotationAnimation.Clockwise
                    duration: 1000
                    easing.type: Easing.InOutQuad
                }
            }
            Rectangle {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 + (root.secondHandStyle === "dot" ? 20 : 0) }
                implicitWidth: root.secondHandStyle === "dot" ? 20 : 95
                implicitHeight: root.secondHandStyle === "dot" ? 20 : 2
                radius: Math.min(width, height) / 2
                color: root.colSurfaceVariant
            }
            Rectangle {
                visible: root.secondHandStyle === "classic"
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 40 }
                implicitWidth: 14
                implicitHeight: 14
                radius: Theme.roundingSmall
                color: root.colSurfaceVariant
            }
        }

        // ── centre dot ─────────────────────────────────────────────────────
        Rectangle {
            z: 4
            anchors.centerIn: parent
            visible: root.minuteHandStyle !== "bold"
            color: root.minuteHandStyle === "medium" ? root.colBackground : root.colPillFill
            implicitWidth: 6
            implicitHeight: 6
            radius: 3
        }

        // ── date ───────────────────────────────────────────────────────────
        Repeater {
            // Bubble: the day in a pentagon (top left), the month in a pill (bottom right)
            model: root.dateStyle === "bubble" ? [false, true] : []
            Item {
                required property bool modelData
                readonly property bool isMonth: modelData
                width: 64
                height: 64
                x: isMonth ? dial.width - 64 : 0
                y: isMonth ? dial.height - 64 : 0
                MaterialShape {
                    anchors.centerIn: parent
                    shape: parent.isMonth ? "Pill" : "Pentagon"
                    color: parent.isMonth ? root.colPillBg : root.colPillFill
                    implicitSize: 64
                }
                StyledText {
                    anchors.centerIn: parent
                    text: Qt.formatDate(root.now, parent.isMonth ? "MM" : "d")
                    color: parent.isMonth ? root.colOnPillTrack : root.colOnPillFill
                    font {
                        family: Theme.fontExpressive
                        pixelSize: 30
                        weight: Font.Black
                        variableAxes: ({})
                    }
                }
            }
        }
        Rectangle {
            // Rect: today's number at the right edge
            visible: root.dateStyle === "rect"
            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 10 }
            implicitWidth: 45
            implicitHeight: 30
            radius: Theme.roundingSmall
            color: root.colBackgroundInfo
            StyledText {
                anchors.centerIn: parent
                color: root.colAccent
                text: Qt.formatDate(root.now, "dd")
                font {
                    family: Theme.fontExpressive
                    pixelSize: 20
                    weight: 1000
                    variableAxes: ({})
                }
            }
        }
        Item {
            // Border: the date written around the rim
            anchors.fill: parent
            visible: root.dateStyle === "border"
            readonly property real angleStep: 12 * Math.PI / 180
            readonly property string dateText: Qt.formatDate(root.now, "ddd dd")
            Repeater {
                model: parent.dateText.length
                delegate: Text {
                    required property int index
                    readonly property real angle: index * parent.angleStep - Math.PI / 2
                    x: parent.width / 2 + 90 * Math.cos(angle) - width / 2
                    y: parent.height / 2 + 90 * Math.sin(angle) - height / 2
                    rotation: angle * 180 / Math.PI + 90
                    color: root.colBackgroundInfo
                    font {
                        family: Theme.fontMain
                        pixelSize: 30
                        variableAxes: ({ "wght": 550, "ROND": Theme.roundnessFull ? 100 : 0 })
                    }
                    text: parent.dateText.charAt(index)
                }
            }
        }
    }

    // ── quote ──────────────────────────────────────────────────────────────
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.quote !== ""
        implicitWidth: quoteBox.implicitWidth
        implicitHeight: quoteBox.implicitHeight
        DropShadow {
            source: quoteBox
            anchors.fill: quoteBox
            verticalOffset: 2
            radius: 12
            samples: 25
            color: Theme.colShadow
            transparentBorder: true
        }
        Rectangle {
            id: quoteBox
            implicitWidth: quoteRow.implicitWidth + 16
            implicitHeight: quoteRow.implicitHeight + 8
            radius: Theme.roundingSmall
            color: root.colBackgroundInfo
            Row {
                id: quoteRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    anchors.top: parent.top
                    iconSize: Theme.pxHuge
                    text: "format_quote"
                    color: root.colAccent
                }
                StyledText {
                    text: root.quote
                    color: root.colOnBackground
                    font {
                        family: Theme.str("family_reading", "Readex Pro")
                        pixelSize: Theme.pxLarge
                        weight: Font.Normal
                        variableAxes: ({})
                    }
                }
            }
        }
    }
}
