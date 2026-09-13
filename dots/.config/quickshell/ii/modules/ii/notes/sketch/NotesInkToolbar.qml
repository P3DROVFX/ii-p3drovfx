pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.notes

/**
 * The ink tray.
 *
 * Same signals as `DrawToolbar`, so the drawing engine underneath is untouched — only the
 * presentation differs. Three things it does that the tablet's tray does not:
 *
 *   - tools are *shapes* that grow when active, rather than icons that change colour;
 *   - width is a slider that previews the stroke, rather than fixed steps, because "how
 *     thick" is a continuous question and a person answers it by looking;
 *   - pressure appears only once a pen has actually been seen, and says so in words.
 *
 * The palette is `Config.options.tablet.liveDraw.palette` — the documented exception to
 * never hard-coding a colour. This is pigment, not chrome: ink that re-tinted itself with
 * the theme would be ink nobody could trust.
 */
Rectangle {
    id: root

    property var palette: []
    property string currentColor: ""
    property real strokeWidth: 4
    property string tool: "pen"
    property bool usePressure: true
    property bool pressureAvailable: false
    property bool canUndo: false
    property bool canRedo: false
    property string statusText: ""

    signal colorPicked(string color)
    signal widthPicked(real width)
    signal toolPicked(string tool)
    signal pressureToggled()
    signal undoRequested()
    signal redoRequested()
    signal clearRequested()
    signal cancelRequested()
    signal saveRequested()

    implicitWidth: layout.implicitWidth + 24
    implicitHeight: 64
    radius: NotesMetrics.pillRadius(root.implicitHeight)
    color: Appearance.m3colors.m3surfaceContainerHighest

    StyledRectangularShadow {
        target: root
    }

    readonly property var tools: [
        { id: "pen", icon: "edit", name: Translation.tr("Pen") },
        { id: "marker", icon: "format_ink_highlighter", name: Translation.tr("Highlighter") },
        { id: "eraser", icon: "ink_eraser", name: Translation.tr("Eraser") }
    ]

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.tools

            delegate: NotesInkToolButton {
                required property var modelData
                symbol: modelData.icon
                tooltipText: modelData.name
                active: root.tool === modelData.id
                onTriggered: root.toolPicked(modelData.id)
            }
        }

        Item {
            Layout.preferredWidth: 10
        }

        Repeater {
            model: root.palette

            delegate: RippleButton {
                id: swatch
                required property string modelData

                implicitWidth: 38
                implicitHeight: 38
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: root.tool !== "eraser"
                opacity: enabled ? 1 : 0.4

                onClicked: root.colorPicked(swatch.modelData)

                contentItem: Item {
                    anchors.fill: parent

                    Rectangle {
                        anchors.centerIn: parent
                        // The chosen colour is a larger, ringed dot. Same idea as the
                        // tools: the shape says which one, so it reads at a glance and
                        // does not depend on the swatch colours being distinguishable.
                        width: root.currentColor === swatch.modelData ? 24 : 18
                        height: width
                        radius: width / 2
                        color: swatch.modelData
                        border.width: root.currentColor === swatch.modelData ? 3 : 0
                        border.color: Appearance.colors.colOnLayer1
                        antialiasing: true

                        Behavior on width {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        Item {
            Layout.preferredWidth: 10
        }

        // Width, with the stroke it produces drawn beside it. A number would need
        // translating into a look; the dot is the look.
        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            Rectangle {
                anchors.centerIn: parent
                width: Math.max(3, Math.min(24, root.strokeWidth * 1.6))
                height: width
                radius: width / 2
                color: root.tool === "eraser" ? Appearance.colors.colOnLayer1 : root.currentColor
                antialiasing: true
            }
        }

        StyledSlider {
            Layout.preferredWidth: 96
            from: 1
            to: 16
            value: root.strokeWidth
            onMoved: root.widthPicked(value)
        }

        Item {
            Layout.preferredWidth: 8
        }

        NotesInkToolButton {
            symbol: "gesture"
            tooltipText: root.usePressure
                ? Translation.tr("Pressure is on")
                : Translation.tr("Pressure is off")
            active: root.usePressure
            // Only once a device that actually measures has been seen. A pressure toggle
            // on a mouse is a switch with nothing behind it.
            visible: root.pressureAvailable
            onTriggered: root.pressureToggled()
        }

        NotesInkToolButton {
            symbol: "undo"
            tooltipText: Translation.tr("Undo")
            enabled: root.canUndo
            onTriggered: root.undoRequested()
        }

        NotesInkToolButton {
            symbol: "redo"
            tooltipText: Translation.tr("Redo")
            enabled: root.canRedo
            onTriggered: root.redoRequested()
        }

        NotesInkToolButton {
            symbol: "ink_eraser_off"
            tooltipText: Translation.tr("Clear the page")
            enabled: root.canUndo
            onTriggered: root.clearRequested()
        }

        Item {
            Layout.preferredWidth: 8
        }

        StyledText {
            text: root.statusText
            visible: root.statusText.length > 0
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        NotesInkToolButton {
            symbol: "close"
            tooltipText: Translation.tr("Discard these changes")
            onTriggered: root.cancelRequested()
        }

        RippleButton {
            implicitWidth: 46
            implicitHeight: 46
            buttonRadius: NotesMetrics.pillRadius(46)
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colBackgroundActive: Appearance.colors.colPrimaryActive

            onClicked: root.saveRequested()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "check"
                iconSize: 22
                color: Appearance.colors.colOnPrimary
            }

            StyledToolTip {
                text: Translation.tr("Keep it in this note")
            }
        }
    }
}
