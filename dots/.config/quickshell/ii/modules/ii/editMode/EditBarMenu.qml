import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The bar widget's right-click menu in Edit Mode: Center this (centre list
 * only) and Remove. Drawn by the chrome surface; the writes go through the
 * bar's own controller.
 */
Rectangle {
    id: root

    property var controller: null
    property int bucket: -1
    property int index: -1
    property bool centered: false
    signal dismissRequested()

    readonly property real padding: 6

    implicitWidth: 200
    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.windowRounding
    color: Appearance.colors.colSurfaceContainer

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    StyledRectangularShadow {
        target: root
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 2

        EditMenuRow {
            Layout.fillWidth: true
            visible: root.bucket === 1
            cardPadding: root.padding
            symbol: root.centered ? "check" : "align_horizontal_center"
            label: root.centered ? Translation.tr("Centered") : Translation.tr("Center this")
            onClicked: {
                root.dismissRequested();
                root.controller?.toggleCenter(root.bucket, root.index);
            }
        }

        EditMenuRow {
            Layout.fillWidth: true
            cardPadding: root.padding
            symbol: "delete"
            label: Translation.tr("Remove")
            colText: Appearance.m3colors.m3error
            onClicked: {
                root.dismissRequested();
                root.controller?.removeAt(root.bucket, root.index);
            }
        }
    }
}
