import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A screen recording, as the island shows it while it holds the centre.
 *
 * Only the contracted face is left here: the expanded one is a file of its own
 * (activities/recording/RecordingExpanded.qml), hosted by the auxiliary bubble's card,
 * and the island never shows a widget expanded. The one control kept here is the pen:
 * drawing over the screen is what a recording asks for mid-take, and walking to the bar
 * for it would put the walk in the video.
 */
Item {
    id: root
    anchors.fill: parent

    /** Example data from the Settings preview (IslandPreviewStage); null on the island. */
    property var sample: null
    readonly property var state: root.sample ? root.sample.state : (Persistent.states.screenRecord ?? null)
    readonly property bool active: root.state ? root.state.active === true : false
    readonly property bool paused: root.state ? root.state.paused === true : false
    readonly property int elapsedSeconds: root.state ? root.state.seconds : 0

    readonly property string timeText: {
        const mins = Math.floor(elapsedSeconds / 60);
        const secs = elapsedSeconds % 60;
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        Rectangle {
            id: dot
            Layout.alignment: Qt.AlignVCenter
            width: 10
            height: 10
            radius: 5
            color: root.paused ? Appearance.colors.colWarning : Appearance.colors.colErrorContainer
            // A steady mark: a held capture is dimmed and goes amber instead of breathing,
            // which is the state said without an animation running for the whole take.
            opacity: root.active ? (root.paused ? 0.65 : 1) : 0

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.bold: true
            font.features: ({
                    "tnum": 1
                })
            color: Appearance.colors.colOnSurface
            text: root.paused ? Translation.tr("PAUSED") : root.timeText
        }

        RippleButton {
            id: drawButton
            readonly property bool drawingOut: LiveDraw.trayOpen
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 28
            implicitHeight: 28
            buttonRadius: drawButton.drawingOut ? Appearance.rounding.verysmall : Appearance.rounding.full
            colBackground: drawButton.drawingOut ? Appearance.colors.colPrimary : "transparent"
            colBackgroundHover: drawButton.drawingOut ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover
            colRipple: drawButton.drawingOut ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer1Active
            onClicked: LiveDraw.toggle()

            Behavior on buttonRadius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "draw"
                fill: drawButton.drawingOut ? 1 : 0
                iconSize: Appearance.font.pixelSize.normal
                color: drawButton.drawingOut ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
            }

            StyledToolTip {
                text: drawButton.drawingOut
                    ? Translation.tr("Put the drawing tools away")
                    : Translation.tr("Draw on the screen")
            }
        }
    }
}