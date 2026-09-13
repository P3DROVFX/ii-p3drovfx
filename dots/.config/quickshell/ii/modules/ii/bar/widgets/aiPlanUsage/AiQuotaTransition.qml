pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.services

Item {
    id: root

    property bool vertical: false
    property bool useAccentForeground: false
    property color contentColor: Appearance.colors.colOnLayer1
    property var animatedItems: []
    property string renderedTargetId: ""

    implicitWidth: transitionContent.implicitWidth
    implicitHeight: transitionContent.implicitHeight

    function syncNow(): void {
        root.animatedItems = Array.from(AiPlanUsage.selectedItems);
        root.renderedTargetId = AiPlanUsage.displayedProviderId;
        transitionContent.opacity = 1.0;
        contentTranslate.x = 0;
        contentTranslate.y = 0;
    }

    function transitionToCurrentTarget(): void {
        if (root.renderedTargetId.length === 0) {
            root.syncNow();
            return;
        }
        providerSwap.stop();
        providerSwap.start();
    }

    Component.onCompleted: root.syncNow()

    Connections {
        target: AiPlanUsage

        function onDisplayedProviderIdChanged(): void {
            root.transitionToCurrentTarget();
        }

        function onItemsChanged(): void {
            refreshSync.restart();
        }
    }

    Timer {
        id: refreshSync
        interval: 0
        repeat: false
        onTriggered: {
            if (!providerSwap.running
                    && root.renderedTargetId === AiPlanUsage.displayedProviderId)
                root.animatedItems = Array.from(AiPlanUsage.selectedItems);
        }
    }

    GridLayout {
        id: transitionContent
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, quotaRepeater.count)
        rows: root.vertical ? Math.max(1, quotaRepeater.count) : 1
        columnSpacing: root.vertical ? 0 : 6
        rowSpacing: root.vertical ? 6 : 0

        transform: Translate {
            id: contentTranslate
        }

        Repeater {
            id: quotaRepeater
            model: root.animatedItems

            delegate: AiQuotaIndicator {
                required property var modelData

                quota: modelData
                vertical: root.vertical
                useAccentForeground: root.useAccentForeground
                visualization: Config.options.bar.aiPlanUsage.visualization
                showWindowLabel: Config.options.bar.aiPlanUsage.showWindowLabel
                contentColor: root.contentColor
            }
        }
    }

    SequentialAnimation {
        id: providerSwap

        ParallelAnimation {
            NumberAnimation {
                target: transitionContent
                property: "opacity"
                to: 0.0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            NumberAnimation {
                target: contentTranslate
                property: "x"
                to: root.vertical ? 0 : -8
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            NumberAnimation {
                target: contentTranslate
                property: "y"
                to: root.vertical ? -8 : 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        ScriptAction {
            script: {
                root.animatedItems = Array.from(AiPlanUsage.selectedItems);
                root.renderedTargetId = AiPlanUsage.displayedProviderId;
                contentTranslate.x = root.vertical ? 0 : 8;
                contentTranslate.y = root.vertical ? 8 : 0;
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: transitionContent
                property: "opacity"
                to: 1.0
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
            NumberAnimation {
                target: contentTranslate
                property: "x"
                to: 0
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
            NumberAnimation {
                target: contentTranslate
                property: "y"
                to: 0
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
    }
}
