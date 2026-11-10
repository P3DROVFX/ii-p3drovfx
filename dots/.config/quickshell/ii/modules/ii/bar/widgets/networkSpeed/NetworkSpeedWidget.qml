import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Network speed — default bar style.
 *
 * Plain on purpose: an arrow and a rate per direction, nothing else. The
 * BarGroup around it supplies the padding and the background, exactly like the
 * default Weather and Port Watcher widgets.
 *
 * No `activated`: there is no popup, so a group highlight would have nothing
 * to say.
 */
MouseArea {
    id: root

    property bool vertical: false

    NetworkSpeedReadout {
        id: net
    }

    visible: net.shown
    hoverEnabled: true
    implicitWidth: net.shown ? (root.vertical ? Appearance.sizes.verticalBarWidth : content.implicitWidth + net.tight(10, 4)) : 0
    implicitHeight: !net.shown ? 0 : (root.vertical ? content.implicitHeight + net.tight(10, 4) : Appearance.sizes.baseBarHeight)
    opacity: net.online ? 1 : 0.5

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    GridLayout {
        id: content

        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        columnSpacing: net.tight(10, 6)
        rowSpacing: net.tight(6, 2)

        NetworkSpeedCell {
            visible: net.showDown
            vertical: root.vertical
            readout: net
            rate: net.down
            iconName: "arrow_downward"
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }

        NetworkSpeedCell {
            visible: net.showUp
            vertical: root.vertical
            readout: net
            rate: net.up
            iconName: "arrow_upward"
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }
    }

    StyledToolTip {
        requireOverlay: false
        text: net.tooltipText
    }
}
