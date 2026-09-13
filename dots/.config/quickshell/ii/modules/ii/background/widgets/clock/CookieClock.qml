import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock.dateIndicator
import qs.modules.ii.background.widgets.clock.minuteMarks

Item {
    id: root

    property real implicitSize: 240

    property color colShadow: Appearance.colors.colShadow
    property color colBackground: WidgetColorScheme.cardBgColor
    property color colOnBackground: WidgetColorScheme.textColorOnBg
    property color colBackgroundInfo: WidgetColorScheme.innerShapeColor
    property color colHourHand: WidgetColorScheme.accentColor
    property color colMinuteHand: WidgetColorScheme.subtextColorOnBg
    property color colSecondHand: WidgetColorScheme.surfaceVariantColor
    property color colHourMarks: WidgetColorScheme.subtextColorOnBg
    property color colMinuteMarks: WidgetColorScheme.subtextColorOnBg
    property color colTimeColumn: Qt.rgba(WidgetColorScheme.textColorOnPillTrack.r, WidgetColorScheme.textColorOnPillTrack.g, WidgetColorScheme.textColorOnPillTrack.b, 0.5)
    property color colCenterDot: WidgetColorScheme.pillFillColor

    readonly property var clockNumbers: DateTime.time.split(/[: ]/)
    readonly property int clockHour: parseInt(clockNumbers[0]) % 12
    readonly property int clockMinute: DateTime.clock.minutes
    property int clockSecond: DateTime.clock.seconds

    readonly property bool secondHandVisible: Config.options.background.widgets.clock_cookie.secondHandStyle !== "hide"

    Timer {
        running: root.secondHandVisible && !Config.options.time.secondPrecision
        repeat: true
        interval: 1000
        onTriggered: root.clockSecond = new Date().getSeconds()
    }

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    function applyStyle(sides, dialStyle, hourHandStyle, minuteHandStyle, secondHandStyle, dateStyle) {
        Config.options.background.widgets.clock_cookie.sides = sides
        Config.options.background.widgets.clock_cookie.dialNumberStyle = dialStyle
        Config.options.background.widgets.clock_cookie.hourHandStyle = hourHandStyle
        Config.options.background.widgets.clock_cookie.minuteHandStyle = minuteHandStyle
        Config.options.background.widgets.clock_cookie.secondHandStyle = secondHandStyle
        Config.options.background.widgets.clock_cookie.dateStyle = dateStyle
    }

    function setClockPreset(category) {
        if (!Config.options.background.widgets.clock_cookie.aiStyling) return;
        if (category === "") return;
        print("[Cookie clock] Setting clock preset for category: " + category)
        // "abstract", "anime", "city", "minimalist", "landscape", "plants", "person", "space"
        if (category == "abstract") {
            applyStyle(9, "none", "fill", "medium", "dot", "bubble")
        } else if (category == "anime") {
            applyStyle(7, "none", "fill", "bold", "dot", "bubble")
        } else if (category == "city" || category == "space") {
            applyStyle(23, "full", "hollow", "thin", "classic", "bubble")
        } else if (category == "minimalist") {
            applyStyle(6, "none", "fill", "bold", "dot", "hide")
        } else if (category == "landscape") {
            applyStyle(14, "full", "hollow", "medium", "classic", "bubble")
        } else if (category == "plants") {
            applyStyle(9, "dots", "fill", "bold", "dot", "border")
        } else if (category == "person") {
            applyStyle(14, "full", "classic", "classic", "classic", "rect")
        }
    }

    FileView {
        id: categoryFileView
        path: Config.ready ? Directories.generatedWallpaperCategoryPath : ""
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: {
            root.setClockPreset(categoryFileView.text().trim())
        }
    }

    readonly property bool enableShadows: Config.options.background.widgets.enableShadows ?? true
    property string backgroundStyle: Config.options.background.widgets.clock_cookie.backgroundStyle

    Item {
        id: cookieShapeContainer
        anchors.fill: parent

        RotationAnimation on rotation {
            running: Config.options.background.widgets.clock_cookie.constantlyRotate
            duration: 30000
            easing.type: Easing.Linear
            loops: Animation.Infinite
            from: 360
            to: 0
        }

        StyledDropShadow {
            target: backgroundStyle === "sine" ? sineCookieLoader : backgroundStyle === "shape" ? materialShapeCookieLoader : roundedPolygonCookieLoader
            visible: root.enableShadows
        }
        Loader {
            id: sineCookieLoader
            z: 0
            visible: !root.enableShadows // Show target directly when shadows are disabled
            active: backgroundStyle === "sine"
            sourceComponent: SineCookie {
                implicitSize: root.implicitSize
                sides: Config.options.background.widgets.clock_cookie.sides
                color: WidgetColorScheme.tintBackground(root.colBackground)
            }
        }
        Loader {
            id: roundedPolygonCookieLoader
            z: 0
            visible: !root.enableShadows // Show target directly when shadows are disabled
            active: backgroundStyle === "cookie"
            sourceComponent: MaterialCookie {
                implicitSize: root.implicitSize
                sides: Config.options.background.widgets.clock_cookie.sides
                color: WidgetColorScheme.tintBackground(root.colBackground)
            }
        }
        Loader {
            id: materialShapeCookieLoader
            z: 0
            visible: !root.enableShadows // Show target directly when shadows are disabled
            active: backgroundStyle === "shape"
            sourceComponent: MaterialShape {
                implicitSize: root.implicitSize
                color: WidgetColorScheme.tintBackground(root.colBackground)
                shapeString: Config.options.background.widgets.clock_cookie.backgroundShape
            }
        }
    }

    // Hour/minutes numbers/dots/lines
    MinuteMarks {
        anchors.fill: parent
        color: root.colMinuteMarks
    }

    // Stupid extra hour marks in the middle
    FadeLoader {
        id: hourMarksLoader
        anchors.centerIn: parent
        shown: Config.options.background.widgets.clock_cookie.hourMarks
        sourceComponent: HourMarks {
            implicitSize: 135 * (1.75 - 0.75 * hourMarksLoader.opacity)
            color: root.colHourMarks
            colOnBackground: ColorUtils.mix(root.colBackgroundInfo, root.colOnBackground, 0.5)
        }
    }

    // Number column in the middle
    FadeLoader {
        id: timeColumnLoader
        anchors.centerIn: parent
        shown: Config.options.background.widgets.clock_cookie.timeIndicators
        scale: 1.4 - 0.4 * timeColumnLoader.shown
        Behavior on scale {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        sourceComponent: TimeColumn {
            color: root.colTimeColumn
        }
    }

    // Minute hand
    FadeLoader {
        anchors.fill: parent
        z: 1
        shown: Config.options.background.widgets.clock_cookie.minuteHandStyle !== "hide"
        sourceComponent: MinuteHand {
            anchors.fill: parent
            clockMinute: root.clockMinute
            style: Config.options.background.widgets.clock_cookie.minuteHandStyle
            color: root.colMinuteHand
        }
    }

    // Hour hand
    FadeLoader {
        anchors.fill: parent
        z: (item && item.style === "hollow") ? 0 : 2
        shown: Config.options.background.widgets.clock_cookie.hourHandStyle !== "hide"
        sourceComponent: HourHand {
            clockHour: root.clockHour
            clockMinute: root.clockMinute
            style: Config.options.background.widgets.clock_cookie.hourHandStyle
            color: root.colHourHand
        }
    }

    // Second hand
    FadeLoader {
        id: secondHandLoader
        z: (Config.options.background.widgets.clock_cookie.secondHandStyle === "line") ? 2 : 3
        shown: Config.options.background.widgets.clock_cookie.secondHandStyle !== "hide"
        anchors.fill: parent
        sourceComponent: SecondHand {
            id: secondHand
            clockSecond: root.clockSecond
            style: Config.options.background.widgets.clock_cookie.secondHandStyle
            color: root.colSecondHand
        }
    }

    // Center dot
    FadeLoader {
        z: 4
        anchors.centerIn: parent
        shown: Config.options.background.widgets.clock_cookie.minuteHandStyle !== "bold"
        sourceComponent: Rectangle {
            color: Config.options.background.widgets.clock_cookie.minuteHandStyle === "medium" ? root.colBackground : root.colCenterDot
            implicitWidth: 6
            implicitHeight: implicitWidth
            radius: width / 2
        }
    }

    // Date
    FadeLoader {
        anchors.fill: parent
        shown: Config.options.background.widgets.clock_cookie.dateStyle !== "hide"

        sourceComponent: DateIndicator {
            color: root.colBackgroundInfo
            style: Config.options.background.widgets.clock_cookie.dateStyle
        }
    }
}
