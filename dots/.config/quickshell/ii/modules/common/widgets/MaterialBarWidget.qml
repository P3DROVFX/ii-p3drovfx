import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property Component primaryComponent
    property Component secondaryComponent

    property bool primaryIsCircle: false
    property bool secondaryOpposite: false
    property bool swapPrimaryWithSecondary: false
    property bool showPrimary: true
    property bool showSecondary: true

    readonly property bool secondaryIsLeft:
        showPrimary && showSecondary && secondaryOpposite

    readonly property bool onlySecondary:
        !showPrimary && showSecondary

    property real primaryPadding: 8
    property real primaryExtraMargin: 0
    property real primaryWidthOffset: 2
    property real secondaryExtraMargin: 8
    property real secondaryOnlyMargin: 8
    property real componentsPadding: 8

    readonly property real baseMargin: 4

    readonly property Component primarySource:
        swapPrimaryWithSecondary ? secondaryComponent : primaryComponent

    readonly property Component secondarySource:
        swapPrimaryWithSecondary ? primaryComponent : secondaryComponent

    readonly property real leftPadding:
        baseMargin + (
            showPrimary && showSecondary
                ? (secondaryIsLeft ? secondaryExtraMargin : primaryExtraMargin)
                : (onlySecondary ? secondaryOnlyMargin : primaryExtraMargin)
        )

    readonly property real rightPadding:
        baseMargin + (
            showPrimary && showSecondary
                ? (secondaryIsLeft ? primaryExtraMargin : secondaryExtraMargin)
                : (onlySecondary ? secondaryOnlyMargin : primaryExtraMargin)
        )

    readonly property real primaryWidth:
        showPrimary && primaryMeasure.item
            ? primaryMeasure.item.implicitWidth
            : 0

    readonly property real secondaryWidth:
        showSecondary && secondaryMeasure.item
            ? secondaryMeasure.item.implicitWidth
            : 0

    implicitWidth:
        leftPadding
        + rightPadding
        + primaryWidth
        + secondaryWidth
        + ((showPrimary && showSecondary)
            ? componentsPadding
            : 0)

    implicitHeight:
        Appearance.sizes.baseBarHeight - 8

    Loader {
        id: primaryMeasure

        visible: false
        active: root.showPrimary

        sourceComponent: primaryWrapper
    }

    Loader {
        id: secondaryMeasure

        visible: false
        active: root.showSecondary

        sourceComponent: secondarySource
    }

    Rectangle {
        id: pill

        anchors.centerIn: parent

        width: root.implicitWidth
        height: root.implicitHeight

        color: Appearance.colors.colPrimaryContainer
        radius: Appearance.rounding.full

        Row {
            anchors {
                fill: parent
                leftMargin: root.leftPadding
                rightMargin: root.rightPadding
            }

            spacing:
                root.showPrimary && root.showSecondary
                    ? root.componentsPadding
                    : 0

            Loader {
                anchors.verticalCenter: parent.verticalCenter

                active:
                    root.showPrimary || root.onlySecondary

                sourceComponent:
                    root.onlySecondary
                        ? root.secondarySource
                        : root.secondaryIsLeft
                            ? root.secondarySource
                            : primaryWrapper
            }

            Loader {
                anchors.verticalCenter: parent.verticalCenter

                active:
                    root.showPrimary && root.showSecondary

                sourceComponent:
                    root.secondaryIsLeft
                        ? primaryWrapper
                        : root.secondarySource
            }
        }
    }

    Component {
        id: primaryWrapper

        Rectangle {
            color: Appearance.colors.colPrimary
            radius: Appearance.rounding.full

            implicitHeight:
                pill.height - root.primaryPadding

            implicitWidth:
                root.primaryIsCircle && !root.swapPrimaryWithSecondary
                    ? implicitHeight
                    : (content.item
                        ? content.item.implicitWidth
                        : 0)
                      + root.primaryPadding * 2
                      + root.primaryWidthOffset

            width: implicitWidth
            height: implicitHeight

            Loader {
                id: content

                anchors.centerIn: parent

                sourceComponent:
                    root.primarySource
            }
        }
    }
}