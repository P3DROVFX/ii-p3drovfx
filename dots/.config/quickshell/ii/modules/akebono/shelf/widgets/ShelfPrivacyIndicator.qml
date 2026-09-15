pragma ComponentBehavior: Bound
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/privacy"

Item {
    id: root
    property real barHeight: 54
    property var shelf

    readonly property bool shelfEmpty: !privacy.shown

    implicitWidth: privacy.implicitWidth
    implicitHeight: barHeight * 0.7
    Layout.alignment: Qt.AlignVCenter

    PrivacyPill {
        id: privacy
        anchors.centerIn: parent
        disablePopup: true
    }
}