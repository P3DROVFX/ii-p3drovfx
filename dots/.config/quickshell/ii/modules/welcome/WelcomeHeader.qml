pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string currentPageId: "hello"
    property string outgoingPageId: ""
    property string incomingPageId: ""
    property int transitionDirection: 1
    property bool transitionRunning: false
    property bool transitionReady: false
    property bool compactWidth: width < 760
    /** Only the guided bar step has somewhere to step aside to. */
    property bool collapsible: false
    signal closeRequested()
    signal collapseRequested()

    implicitHeight: Math.max(84, headerViewport.implicitHeight)

    function accentContainerFor(pageId: string): color {
        const page = WelcomePageRegistry.pageById(pageId);
        if (page && page.accentRole === "secondary")
            return Appearance.colors.colSecondaryContainer;
        if (page && page.accentRole === "tertiary")
            return Appearance.colors.colTertiaryContainer;
        return Appearance.colors.colPrimaryContainer;
    }

    function accentForegroundFor(pageId: string): color {
        const page = WelcomePageRegistry.pageById(pageId);
        if (page && page.accentRole === "secondary")
            return Appearance.colors.colOnSecondaryContainer;
        if (page && page.accentRole === "tertiary")
            return Appearance.colors.colOnTertiaryContainer;
        return Appearance.colors.colOnPrimaryContainer;
    }

    component HeaderContent: RowLayout {
        required property string pageId
        property bool compactWidth: false

        spacing: 14

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: {
                const page = WelcomePageRegistry.pageById(parent.pageId);
                return page ? page.icon : "waving_hand";
            }
            shape: WelcomePageRegistry.headerShapeFor(parent.pageId)
            iconSize: Appearance.font.pixelSize.large
            padding: parent.compactWidth ? 11 : 13
            fill: 1
            color: root.accentContainerFor(parent.pageId)
            colSymbol: root.accentForegroundFor(parent.pageId)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

            StyledText {
                Layout.fillWidth: true
                text: WelcomePageRegistry.titleFor(parent.parent.pageId)
                color: Appearance.colors.colOnLayer0
                font.family: Appearance.font.family.title
                font.pixelSize: parent.parent.compactWidth
                    ? Appearance.font.pixelSize.huge
                    : Appearance.font.pixelSize.hugeass
                font.variableAxes: Appearance.font.variableAxes.title
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: WelcomePageRegistry.subtitleFor(parent.parent.pageId)
                color: Appearance.colors.colOnLayer2
                font.pixelSize: parent.parent.compactWidth
                    ? Appearance.font.pixelSize.small
                    : Appearance.font.pixelSize.normal
                font.weight: Font.Normal
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 14

        Item {
            id: headerViewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: Math.max(outgoingLayer.implicitHeight, incomingLayer.implicitHeight)
            clip: true

            HeaderContent {
                id: outgoingLayer
                anchors.fill: parent
                compactWidth: root.compactWidth
                pageId: root.transitionRunning ? root.outgoingPageId : root.currentPageId
                x: 0
                opacity: 1
                scale: 1

                property real visualBlur: 0
                layer.enabled: visualBlur > 0.01
                layer.effect: MultiEffect {
                    blurEnabled: outgoingLayer.visualBlur > 0.01
                    blurMax: WelcomeMotion.blurMax
                    blur: outgoingLayer.visualBlur
                }
            }

            HeaderContent {
                id: incomingLayer
                anchors.fill: parent
                compactWidth: root.compactWidth
                pageId: root.transitionRunning ? root.incomingPageId : root.currentPageId
                x: 0
                opacity: 1
                scale: 1

                property real visualBlur: 0
                layer.enabled: visualBlur > 0.01
                layer.effect: MultiEffect {
                    blurEnabled: incomingLayer.visualBlur > 0.01
                    blurMax: WelcomeMotion.blurMax
                    blur: incomingLayer.visualBlur
                }
            }
        }

        // Step aside. The inward diagonal is the exact opposite of the arrow
        // the collapsed pill carries, so the pair reads as one movement in two
        // directions.
        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            visible: root.collapsible
            implicitWidth: 48
            implicitHeight: 48
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colBackgroundActive: Appearance.colors.colLayer1Active
            colRipple: Appearance.colors.colLayer1Active
            Accessible.name: Translation.tr("Step aside")

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close_fullscreen"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
            }

            StyledToolTip {
                text: Translation.tr("Get out of the way while you edit")
            }

            onClicked: root.collapseRequested()
        }

        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 48
            implicitHeight: 48
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colBackgroundActive: Appearance.colors.colLayer1Active
            colRipple: Appearance.colors.colLayer1Active
            Accessible.name: Translation.tr("Close")

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
            }

            onClicked: root.closeRequested()
        }
    }

    ParallelAnimation {
        id: headerTransition

        NumberAnimation {
            target: outgoingLayer
            property: "x"
            to: root.transitionDirection > 0 ? -WelcomeMotion.offsetFor(headerViewport.width) : WelcomeMotion.offsetFor(headerViewport.width)
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: outgoingLayer
            property: "opacity"
            to: WelcomeMotion.pageOpacityOut
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: outgoingLayer
            property: "visualBlur"
            to: WelcomeMotion.blurProgress
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: outgoingLayer
            property: "scale"
            to: WelcomeMotion.pageScale
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: incomingLayer
            property: "x"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: incomingLayer
            property: "opacity"
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: incomingLayer
            property: "visualBlur"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: incomingLayer
            property: "scale"
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    function prepareTransition(): void {
        headerTransition.stop();
        outgoingLayer.x = 0;
        outgoingLayer.opacity = 1;
        outgoingLayer.visualBlur = 0;
        outgoingLayer.scale = 1;
        incomingLayer.x = root.transitionDirection > 0
            ? WelcomeMotion.offsetFor(headerViewport.width)
            : -WelcomeMotion.offsetFor(headerViewport.width);
        incomingLayer.opacity = WelcomeMotion.pageOpacityIn;
        incomingLayer.visualBlur = 0;
        incomingLayer.scale = 1;
    }

    function normalize(): void {
        headerTransition.stop();
        outgoingLayer.x = 0;
        outgoingLayer.opacity = 0;
        outgoingLayer.visualBlur = 0;
        outgoingLayer.scale = 1;
        incomingLayer.x = 0;
        incomingLayer.opacity = 1;
        incomingLayer.visualBlur = 0;
        incomingLayer.scale = 1;
    }

    onTransitionRunningChanged: {
        if (root.transitionRunning)
            root.prepareTransition();
        else
            root.normalize();
    }

    onTransitionReadyChanged: {
        if (root.transitionRunning && root.transitionReady) {
            if (WelcomeMotion.motionEnabled) {
                incomingLayer.visualBlur = WelcomeMotion.blurProgress;
                incomingLayer.scale = WelcomeMotion.pageScale;
                headerTransition.start();
            } else {
                root.normalize();
            }
        }
    }
}
