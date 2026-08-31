import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.portWatcher
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Port Watcher — default bar style.
 *
 * Deliberately plain: the glyph and the number of ports currently being
 * served, nothing else. The BarGroup around it supplies padding and
 * background, exactly like the default Weather and Resources widgets.
 *
 * No `activated` property on purpose: the popup opens on hover, so a group
 * highlight driven by it would just be a hover colour change.
 */
MouseArea {
    id: root

    property bool vertical: false

    readonly property int portCount: PortWatcher.enabled ? PortWatcher.count : 0
    readonly property bool shown: PortWatcher.enabled
        && (!(Config.options.bar.portWatcher.hideWhenEmpty ?? false) || root.portCount > 0)

    readonly property color contentColor: Appearance.colors.colOnLayer1

    visible: root.shown
    implicitWidth: root.shown ? content.implicitWidth + 10 : 0
    implicitHeight: root.vertical ? (root.shown ? content.implicitHeight + 10 : 0) : Appearance.sizes.baseBarHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    onClicked: PortWatcher.refresh()

    GridLayout {
        id: content

        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        rows: root.vertical ? 2 : 1
        columnSpacing: 5
        rowSpacing: 0

        MaterialSymbol {
            text: "lan"
            iconSize: root.vertical ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.larger
            color: root.contentColor
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            text: String(root.portCount)
            font.pixelSize: root.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            font.weight: Font.Bold
            color: root.contentColor
            animateChange: true
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    PortWatcherPopup {
        id: popup
        hoverTarget: root
    }
}
