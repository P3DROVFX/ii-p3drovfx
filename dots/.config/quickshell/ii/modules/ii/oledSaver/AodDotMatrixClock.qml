pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * AOD face: the time in a 5x7 dot matrix, in the manner of a Nothing phone. The
 * time's cells keep their unlit dots as a faint grid; the date under it lights only
 * its own dots, and a row of sixty dots under that walks with the seconds. Few
 * pixels are ever on, which is what an OLED panel wants.
 */
Item {
    id: root

    property bool running: true

    readonly property color litColor: "#ededed"
    readonly property color gridColor: "#161616"
    readonly property color trailColor: "#3a3a3a"
    readonly property color captionColor: "#8c8c8c"

    // 5x7 glyphs, one string per row; "1" is a lit dot. Width follows the strings,
    // so the colon and the dot are a single column.
    readonly property var glyphs: ({
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
        "D": ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
        "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "10001", "01010", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        ":": ["0", "0", "1", "0", "1", "0", "0"],
        ".": ["0", "0", "0", "0", "0", "0", "1"],
        " ": ["000", "000", "000", "000", "000", "000", "000"]
    })

    // Upper case, accents dropped ("sáb." -> "SAB"), anything without a glyph gone.
    function toGlyphText(text) {
        return String(text).normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase()
            .split("").filter(c => root.glyphs[c] !== undefined).join("");
    }

    readonly property string timeText: DateTime.hours + ":" + DateTime.minutes
    readonly property string dateText: root.toGlyphText(DateTime.dayNameShort + " " + DateTime.dayOfMonth + " " + DateTime.monthNameShort)

    // Time: 4 digits (5 columns), the colon (1), and a column between each glyph.
    readonly property int timeColumns: 4 * 5 + 1 + 4
    readonly property real pitch: Math.floor(Math.min(root.width * 0.62 / root.timeColumns, root.height * 0.4 / 7))
    readonly property real smallPitch: Math.max(4, Math.round(root.pitch * 0.32))

    SystemClock {
        id: clock
        enabled: root.running
        precision: SystemClock.Seconds
    }

    Column {
        anchors.centerIn: parent
        spacing: root.pitch * 1.6

        DotText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText
            pitch: root.pitch
            showGrid: true
        }

        DotText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            pitch: root.smallPitch
            litColor: root.captionColor
        }

        // The seconds: a dot per second, the current one lit, the ones behind it dim.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.smallPitch * 0.6
            Repeater {
                model: 60
                delegate: Rectangle {
                    required property int index
                    readonly property int second: clock.date.getSeconds()
                    width: root.smallPitch * 0.5
                    height: width
                    radius: width / 2
                    color: index === second ? root.litColor
                        : index < second ? root.trailColor : root.gridColor
                }
            }
        }
    }

    // A string drawn glyph by glyph, a column apart.
    component DotText: Row {
        id: dotText

        property string text: ""
        property real pitch: 10
        property bool showGrid: false
        property color litColor: root.litColor

        spacing: dotText.pitch

        Repeater {
            model: dotText.text.split("")
            delegate: Grid {
                id: glyph
                required property string modelData
                readonly property var rows: root.glyphs[glyph.modelData] ?? root.glyphs[" "]
                readonly property int cols: glyph.rows[0].length

                columns: glyph.cols
                spacing: 0

                Repeater {
                    model: glyph.cols * 7
                    delegate: Item {
                        id: cell
                        required property int index
                        readonly property bool lit: glyph.rows[Math.floor(cell.index / glyph.cols)].charAt(cell.index % glyph.cols) === "1"
                        width: dotText.pitch
                        height: dotText.pitch

                        Rectangle {
                            anchors.centerIn: parent
                            width: dotText.pitch * 0.72
                            height: width
                            radius: width / 2
                            visible: cell.lit || dotText.showGrid
                            color: cell.lit ? dotText.litColor : root.gridColor
                        }
                    }
                }
            }
        }
    }
}
