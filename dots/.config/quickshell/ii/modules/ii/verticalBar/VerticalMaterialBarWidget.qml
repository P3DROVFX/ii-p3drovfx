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

    readonly property bool secondaryIsAbove:
        showPrimary && showSecondary && secondaryOpposite

    readonly property bool onlySecondary:
        !showPrimary && showSecondary

    property real primaryPadding: 8
    property real primaryExtraMargin: 0
    property real primaryHeightOffset: -4
    property real secondaryExtraMargin: 4

    readonly property real baseMargin: 4
    readonly property real componentsPadding: 4

    readonly property Component primarySource:
        swapPrimaryWithSecondary ? secondaryComponent : primaryComponent

    readonly property Component secondarySource:
        swapPrimaryWithSecondary ? primaryComponent : secondaryComponent

    readonly property real topPadding:
        baseMargin + (
            showPrimary && showSecondary
                ? (secondaryIsAbove ? secondaryExtraMargin : primaryExtraMargin)
                : primaryExtraMargin
        )

    readonly property real bottomPadding:
        baseMargin + (
            showPrimary && showSecondary
                ? (secondaryIsAbove ? primaryExtraMargin : secondaryExtraMargin)
                : primaryExtraMargin
        )

    readonly property real primaryHeight:
        showPrimary && primaryMeasure.item
            ? primaryMeasure.item.implicitHeight
            : 0

    readonly property real secondaryHeight:
        showSecondary && secondaryMeasure.item
            ? secondaryMeasure.item.implicitHeight
            : 0

    implicitWidth:
        Appearance.sizes.baseVerticalBarWidth - 8

    implicitHeight:
        topPadding
        + bottomPadding
        + primaryHeight
        + secondaryHeight
        + ((showPrimary && showSecondary) ? componentsPadding : 0)

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

        Column {
            anchors {
                fill: parent
                topMargin: root.topPadding
                bottomMargin: root.bottomPadding
            }

            spacing:
                root.showPrimary && root.showSecondary
                    ? root.componentsPadding
                    : 0

            Loader {
                anchors.horizontalCenter: parent.horizontalCenter

                active:
                    root.showPrimary || root.onlySecondary

                sourceComponent:
                    root.onlySecondary
                        ? root.secondarySource
                        : root.secondaryIsAbove
                            ? root.secondarySource
                            : primaryWrapper
            }

            Loader {
                anchors.horizontalCenter: parent.horizontalCenter

                active:
                    root.showPrimary && root.showSecondary

                sourceComponent:
                    root.secondaryIsAbove
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

            implicitWidth:
                pill.width - root.primaryPadding

            implicitHeight:
                root.primaryIsCircle && !root.swapPrimaryWithSecondary
                    ? implicitWidth
                    : (content.item ? content.item.implicitHeight : 0)
                        + root.primaryPadding * 2
                        + root.primaryHeightOffset

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