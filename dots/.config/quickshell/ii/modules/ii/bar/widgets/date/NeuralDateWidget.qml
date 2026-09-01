pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.clock

/**
 * Neural Expressive date widget.
 *
 * Where the Expressive family is about type hierarchy, this family is about the
 * date being *positioned in something* — a month that has a length, a weekday
 * the number sits inside of, plates that stack.
 *
 *   orbit   Day inside a ring that fills as the month runs out.
 *   glyph   Weekday abbreviation with the day substituted for its middle letter.
 *   inlay   Day number punched clean through a solid month plate.
 */
Item {
    id: root

    property bool vertical: false

    readonly property string variant: Config.options.bar.dateWidget.neuralVariant ?? "orbit"
    readonly property bool uppercase: Config.options.bar.dateWidget.uppercase ?? true
    readonly property bool showYear: (Config.options.bar.dateWidget.showYear ?? false) && !root.vertical

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

    readonly property real labelPixelSize: Math.max(9, Math.round(root.thickness * (root.vertical ? 0.27 : 0.33)))
    readonly property real subLabelPixelSize: Math.max(8, Math.round(root.thickness * (root.vertical ? 0.24 : 0.30)))

    function cased(text) {
        return root.uppercase ? String(text).toUpperCase() : String(text);
    }

    readonly property string weekdayText: root.cased(DateTime.dayNameShort)
    readonly property string monthText: root.cased(DateTime.monthNameShort)
    readonly property string dayText: DateTime.dayOfMonth

    // The `glyph` variant opens the weekday abbreviation and drops the day into
    // the gap. Locales abbreviate differently — "Sun", "dom.", "Sa" — so strip
    // the punctuation first and fall back to whatever letters are left rather
    // than assuming three of them.
    readonly property string weekdayLetters: root.weekdayText.replace(/[^A-Za-zÀ-ÿ]/g, "")
    readonly property string glyphHead: root.weekdayLetters.length > 0 ? root.weekdayLetters.charAt(0) : ""
    readonly property string glyphTail: root.weekdayLetters.length > 1
        ? root.weekdayLetters.charAt(root.weekdayLetters.length - 1)
        : ""

    BarWidgetPalette {
        id: theme
        colorMode: Config.options.bar.dateWidget.colorMode ?? "tonal"
    }

    readonly property real targetLength: root.vertical
        ? Math.max(root.thickness, contentLoader.implicitHeight)
        : Math.max(root.thickness, contentLoader.implicitWidth)
    property real animatedLength: root.targetLength

    // One driver for the slot and the surface both — see AGENTS.md §6.1.
    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength
    implicitHeight: root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        width: root.vertical ? root.thickness : root.animatedLength
        height: root.vertical ? root.animatedLength : root.thickness
        sourceComponent: {
            if (root.variant === "glyph")
                return glyphVariant;
            if (root.variant === "inlay")
                return inlayVariant;
            return orbitVariant;
        }
    }

    // ── orbit ────────────────────────────────────────────────────────────────
    Component {
        id: orbitVariant

        GridLayout {
            columns: root.vertical ? 1 : 2
            rowSpacing: 1
            columnSpacing: Math.round(root.thickness * 0.24)

            Item {
                Layout.alignment: Qt.AlignCenter
                implicitWidth: root.thickness
                implicitHeight: root.thickness

                CircularProgress {
                    anchors.centerIn: parent
                    implicitSize: root.thickness
                    lineWidth: Math.max(2, Math.round(root.thickness * 0.09))
                    // How far through the month we are. The ring is the only
                    // part of this widget that says something the numerals do
                    // not.
                    value: DateTime.monthProgress
                    colPrimary: theme.accent
                    colSecondary: ColorUtils.transparentize(theme.accent, 0.8)
                    gapAngle: 0
                }

                StyledText {
                    anchors.centerIn: parent
                    text: root.dayText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Math.round(root.thickness * 0.44)
                    font.variableAxes: ({
                        "wght": 800
                    })
                    font.features: ({
                        "tnum": 1
                    })
                    font.letterSpacing: -0.6
                    color: theme.bare
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignCenter
                spacing: -1

                StyledText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                    text: root.weekdayText
                    font.family: Appearance.font.family.title
                    font.pixelSize: root.labelPixelSize
                    font.variableAxes: ({
                        "wght": 750
                    })
                    font.letterSpacing: 1.0
                    color: theme.bare
                }

                StyledText {
                    Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignLeft
                    text: root.showYear ? `${root.monthText} ${DateTime.yearShort}` : root.monthText
                    font.family: Appearance.font.family.title
                    font.pixelSize: root.subLabelPixelSize
                    font.variableAxes: ({
                        "wght": 500
                    })
                    font.letterSpacing: 1.0
                    color: theme.bareAccent
                    opacity: 0.8
                }
            }
        }
    }

    // ── glyph ────────────────────────────────────────────────────────────────
    Component {
        id: glyphVariant

        GridLayout {
            columns: root.vertical ? 1 : 3
            rowSpacing: -Math.round(root.thickness * 0.1)
            columnSpacing: -Math.round(root.thickness * 0.04)

            StyledText {
                Layout.alignment: Qt.AlignCenter
                visible: root.glyphHead !== ""
                text: root.glyphHead
                font.family: Appearance.font.family.title
                font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.5 : 0.86))
                font.variableAxes: ({
                    "wght": 800,
                    "wdth": 85
                })
                font.letterSpacing: -1.0
                color: theme.bare
            }

            MaterialShape {
                Layout.alignment: Qt.AlignCenter
                implicitSize: Math.round(root.thickness * (root.vertical ? 0.78 : 0.86))
                shape: MaterialShape.Shape.SoftBurst
                color: theme.accent

                StyledText {
                    anchors.centerIn: parent
                    text: root.dayText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.34 : 0.38))
                    font.variableAxes: ({
                        "wght": 800
                    })
                    font.features: ({
                        "tnum": 1
                    })
                    font.letterSpacing: -0.6
                    color: theme.onAccent
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignCenter
                visible: root.glyphTail !== ""
                text: root.glyphTail
                font.family: Appearance.font.family.title
                font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.5 : 0.86))
                font.variableAxes: ({
                    "wght": 800,
                    "wdth": 85
                })
                font.letterSpacing: -1.0
                color: theme.bare
            }
        }
    }

    // ── inlay ────────────────────────────────────────────────────────────────
    Component {
        id: inlayVariant

        NeuralDateInlay {
            vertical: root.vertical
            thickness: root.thickness
            dayText: root.dayText
            monthText: root.showYear ? `${root.monthText} ${DateTime.yearShort}` : root.monthText
            colPlate: theme.accent
            colOnPlate: theme.onAccent
        }
    }

    MouseArea {
        id: dateMouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ClockWidgetPopup {
            compact: Config.options.bar.tooltips.compactPopups
            hoverTarget: dateMouseArea
        }
    }
}
