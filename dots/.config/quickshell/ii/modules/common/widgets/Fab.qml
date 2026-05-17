pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

Item {
    id: root

    signal clicked(event: var)
    property alias iconText: fabWidget.iconText
    default property alias fabData: fabWidget.data
    property alias baseSize: fabWidget.baseSize
    property alias buttonRadius: fabWidget.buttonRadius
    property bool enableShadow: true

    property color colBackground: Appearance.colors.colPrimaryContainer
    property color colBackgroundHover: Appearance.colors.colPrimaryContainerHover
    property color colRipple: Appearance.colors.colPrimaryContainerActive
    property color colOnBackground: Appearance.colors.colOnPrimaryContainer

    anchors {
        verticalCenter: parent.verticalCenter
    }
    implicitWidth: fabWidget.implicitWidth
    implicitHeight: fabWidget.implicitHeight
    Loader {
        active: root.enableShadow
        anchors.fill: parent
        sourceComponent: StyledRectangularShadow {
            target: fabWidget
            radius: fabWidget.buttonRadius
        }
    }
    FloatingActionButton {
        id: fabWidget
        onClicked: e => root.clicked(e)
        // baseSize: 30 // Removed fixed baseSize to allow parent control
        colBackground: root.colBackground
        colBackgroundHover: root.colBackgroundHover
        colRipple: root.colRipple
        colOnBackground: root.colOnBackground
    }
}