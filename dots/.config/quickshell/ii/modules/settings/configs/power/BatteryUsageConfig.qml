import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.usage

/**
 * Power → Battery history: the App usage window's Battery tab, hosted as it is (period
 * controls, the apps the energy went to, the hour/day breakdown). It scrolls itself, so this
 * is a plain Item rather than a ContentPage.
 */
Item {
    id: root

    property bool showBackButton: false
    signal goBack()

    // Its own view state: periods walked here don't move the App usage window.
    QtObject {
        id: historyState
        property string granularity: "day"
        property string metricKey: "fg"
        property int periodOffset: 0
        property string selectedKey: ""
    }

    ConfigSubPageHeader {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        visible: root.showBackButton
        title: Translation.tr("Battery history")
        onBack: root.goBack()
    }

    Item {
        id: body
        focus: true
        anchors {
            left: parent.left
            right: parent.right
            top: header.visible ? header.bottom : parent.top
            bottom: parent.bottom
            topMargin: 12
            leftMargin: 20
            rightMargin: 20
            bottomMargin: 12
        }

        Loader {
            anchors.fill: parent
            active: !AppStats.binaryPresent
            sourceComponent: UsageSetup {}
        }

        Loader {
            id: pageLoader
            anchors.fill: parent
            active: AppStats.binaryPresent
            sourceComponent: UsageBatteryPage {
                layoutWidth: body.width
                viewState: historyState
            }
        }

        Keys.onPressed: event => {
            if (pageLoader.item && pageLoader.item.handleKey(event.key, event.modifiers))
                event.accepted = true;
        }
    }
}
