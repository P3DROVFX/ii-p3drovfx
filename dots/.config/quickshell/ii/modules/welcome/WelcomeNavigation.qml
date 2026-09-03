pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property int pageIndex: 0
    property int pageCount: WelcomePageRegistry.pages.length
    property bool transitionRunning: false
    property string nextLabel: ""
    property string nextIcon: "arrow_forward"
    property bool skipVisible: false
    property string skipLabel: ""
    // The bottom-left slot, free on the first page because there is nothing to
    // go back to there. A phone asks "restore from a backup?" before it asks
    // anything else, and this is the same offer in the same place.
    property bool restoreVisible: false
    readonly property bool nextButtonHovered: primaryButton.hovered
    signal previousRequested()
    signal nextRequested()
    signal skipRequested()
    signal finishRequested()
    signal restoreRequested()

    implicitHeight: Math.max(previousButtonWrapper.implicitHeight,
        Math.max(skipButtonWrapper.implicitHeight, nextButtonWrapper.implicitHeight))

    RowLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.small

        Item {
            id: previousButtonWrapper
            property real targetWidth: root.pageIndex > 0 ? 56 : 0
            property real animatedWidth: targetWidth
            visible: animatedWidth > 0.5 || opacity > 0.01
            opacity: root.pageIndex > 0 ? 1 : 0
            clip: true

            Layout.preferredWidth: animatedWidth
            Layout.preferredHeight: 56
            implicitWidth: animatedWidth
            implicitHeight: 56

            Behavior on animatedWidth {
                enabled: WelcomeMotion.motionEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Behavior on opacity {
                enabled: WelcomeMotion.motionEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            RippleButtonWithIcon {
                id: previousButton
                anchors.fill: parent
                implicitWidth: 56
                implicitHeight: 56
                centerContent: true
                materialIcon: "arrow_back"
                mainText: ""
                mainTextWeight: Font.Bold
                mainTextFontFamily: Appearance.font.family.title
                mainTextVariableAxes: Appearance.font.variableAxes.titleRounded
                iconPixelSize: Appearance.font.pixelSize.hugeass + Appearance.rounding.verysmall
                materialIconFill: true
                buttonRadius: Appearance.rounding.full
                colText: Appearance.colors.colOnSecondaryContainer
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                colRipple: Appearance.colors.colSecondaryContainerActive
                Accessible.name: Translation.tr("Previous")
                onClicked: if (!root.transitionRunning) root.previousRequested()
            }
        }

        Item {
            id: restoreButtonWrapper
            property real targetWidth: root.restoreVisible ? restoreButton.implicitWidth : 0
            property real animatedWidth: targetWidth
            visible: animatedWidth > 0.5 || opacity > 0.01
            opacity: root.restoreVisible ? 1 : 0
            clip: true

            Layout.preferredWidth: animatedWidth
            Layout.preferredHeight: 56
            implicitWidth: animatedWidth
            implicitHeight: 56

            Behavior on animatedWidth {
                enabled: WelcomeMotion.motionEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Behavior on opacity {
                enabled: WelcomeMotion.motionEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            RippleButtonWithIcon {
                id: restoreButton
                anchors.fill: parent
                implicitWidth: contentImplicitWidth + 34
                implicitHeight: 56
                centerContent: true
                materialIcon: "settings_backup_restore"
                mainText: Translation.tr("Restore a backup")
                mainTextWeight: Font.Bold
                mainTextFontFamily: Appearance.font.family.title
                mainTextVariableAxes: Appearance.font.variableAxes.titleRounded
                textPixelSize: Appearance.font.pixelSize.normal
                buttonRadius: Appearance.rounding.full
                colText: Appearance.colors.colOnSecondaryContainer
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                colRipple: Appearance.colors.colSecondaryContainerActive
                Accessible.name: mainText
                onClicked: if (!root.transitionRunning) root.restoreRequested()
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Item {
            id: skipButtonWrapper
            property real targetWidth: root.skipVisible ? primaryButton.implicitWidth : 0
            property real animatedWidth: targetWidth
            visible: animatedWidth > 0.5 || opacity > 0.01
            opacity: root.skipVisible ? 1 : 0
            clip: false

            Layout.preferredWidth: animatedWidth
            Layout.preferredHeight: primaryButton.implicitHeight
            implicitWidth: animatedWidth
            implicitHeight: primaryButton.implicitHeight

            Behavior on animatedWidth {
                enabled: WelcomeMotion.motionEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Behavior on opacity {
                enabled: WelcomeMotion.motionEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            RippleButtonWithIcon {
                id: skipButton
                anchors.fill: parent
                implicitWidth: primaryButton.implicitWidth
                implicitHeight: primaryButton.implicitHeight
                centerContent: true
                materialIcon: ""
                mainText: root.skipLabel || Translation.tr("Skip")
                mainTextWeight: Font.Bold
                mainTextFontFamily: Appearance.font.family.title
                mainTextVariableAxes: Appearance.font.variableAxes.titleRounded
                textPixelSize: Appearance.font.pixelSize.larger
                buttonRadius: Appearance.rounding.full
                colText: Appearance.colors.colOnLayer0
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer0, 1)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colLayer0, 1)
                colBackgroundActive: ColorUtils.transparentize(Appearance.colors.colLayer0, 1)
                colRipple: Appearance.colors.colOutlineVariant
                borderWidth: Appearance.borderWidth
                borderColor: Appearance.colors.colOutline
                Accessible.name: mainText
                onClicked: if (!root.transitionRunning) root.skipRequested()
            }
        }

        Item {
            id: nextButtonWrapper
            property real targetWidth: primaryButton.implicitWidth
            property real animatedWidth: targetWidth

            Layout.preferredWidth: animatedWidth
            Layout.preferredHeight: primaryButton.implicitHeight
            implicitWidth: animatedWidth
            implicitHeight: primaryButton.implicitHeight

            Behavior on animatedWidth {
                enabled: WelcomeMotion.motionEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            RippleButtonWithIcon {
                id: primaryButton
                anchors.fill: parent
                implicitWidth: Math.max(148, contentImplicitWidth + 34)
                implicitHeight: 56
                centerContent: true
                iconOnRight: true
                materialIcon: root.nextIcon || WelcomePageRegistry.nextIconFor(WelcomePageRegistry.pages[root.pageIndex]?.id || "hello")
                hoverMaterialIcon: root.pageIndex > 0 && root.pageIndex < root.pageCount - 1
                    ? "arrow_forward" : ""
                mainText: root.nextLabel || WelcomePageRegistry.nextLabelFor(WelcomePageRegistry.pages[root.pageIndex]?.id || "hello")
                mainTextWeight: Font.Bold
                mainTextFontFamily: Appearance.font.family.title
                mainTextVariableAxes: Appearance.font.variableAxes.titleRounded
                textPixelSize: Appearance.font.pixelSize.larger
                iconPixelSize: Appearance.font.pixelSize.hugeass + Appearance.rounding.verysmall
                materialIconFill: true
                buttonRadius: Appearance.rounding.full
                colText: Appearance.colors.colOnPrimary
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colBackgroundActive: Appearance.colors.colPrimaryActive
                colRipple: Appearance.colors.colPrimaryActive
                Accessible.name: mainText
                onClicked: {
                    if (!root.transitionRunning) {
                        hoverIconSuppressed = true;
                        if (root.pageIndex >= root.pageCount - 1)
                            root.finishRequested();
                        else
                            root.nextRequested();
                    }
                }
                onHoveredChanged: {
                    if (!hovered)
                        hoverIconSuppressed = false;
                }
            }
        }
    }

    Connections {
        target: root

        function onTransitionRunningChanged() {
            if (root.transitionRunning)
                primaryButton.hoverIconSuppressed = true;
        }
    }
}
