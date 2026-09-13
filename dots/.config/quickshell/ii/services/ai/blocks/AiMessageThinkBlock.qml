pragma ComponentBehavior: Bound

import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects

/**
 * The model's reasoning, kept out of the answer.
 *
 * It writes itself open so the wait is not a blank panel, then folds away the
 * moment the answer starts — the thinking is interesting while it is the only
 * thing happening and clutter once it is not. Opening or closing one by hand
 * is remembered, so whoever wants to read every thought only says so once.
 */
Item {
    id: root

    // Passed through to the text block, and set by the legacy markdown path.
    property bool editing: false
    property bool renderMarkdown: Config.options.sidebar.ai.renderMarkdown
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var messageData: null
    property bool done: true

    /** The reasoning itself. */
    property string thoughtText: (typeof segmentContent === "string") ? segmentContent : ""
    /** False while the thought is still being written. */
    property bool completed: false
    property real durationMs: 0
    property int tokens: -1

    property real maxContentHeight: 260
    property real headerPaddingVertical: 3
    property real headerPaddingHorizontal: 10
    property real backgroundRounding: Appearance.rounding.small

    component ThinkBlockButton: RippleButton {
        id: button
        property string symbol
        property real iconRotation: 0
        property bool activated: false
        property bool parentHovered: false
        property string tooltipText: ""

        implicitWidth: 22
        implicitHeight: 22
        colBackground: button.parentHovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: button.symbol
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer2
            rotation: button.iconRotation

            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledToolTip {
            text: button.tooltipText
        }
    }

    property bool expanded: true

    // Finishing collapses it: reasoning is worth watching live and worth
    // getting out of the way once there is an answer to read instead. A
    // manual peek after that lasts for this one block only — it used to be
    // remembered as a standing preference, which pinned every thought in
    // every future message open the first time anyone clicked one, and the
    // transcript never got shorter again.
    onCompletedChanged: root.expanded = !root.completed
    Component.onCompleted: root.expanded = !root.completed

    function toggle() {
        root.expanded = !root.expanded;
    }

    function summary(): string {
        if (!root.completed)
            return Translation.tr("Thinking") + ".".repeat(dotsTimer.dots);
        let parts = [];
        if (root.durationMs >= 100)
            parts.push(Translation.tr("Thought for %1 s").arg((root.durationMs / 1000).toFixed(1)));
        else
            parts.push(Translation.tr("Thought"));
        if (root.tokens > 0)
            parts.push(Translation.tr("%1 tokens").arg(root.tokens));
        return parts.join(" · ");
    }

    Layout.fillWidth: true
    implicitHeight: header.implicitHeight + content.implicitHeight
    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.backgroundRounding
        }
    }

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    Timer {
        id: dotsTimer
        property int dots: 0
        running: !root.completed
        repeat: true
        interval: 400
        onTriggered: dots = (dots + 1) % 4
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        Rectangle {
            id: header
            color: Appearance.colors.colSurfaceContainerHighest
            Layout.fillWidth: true
            implicitHeight: headerRowLayout.implicitHeight + root.headerPaddingVertical * 2

            MouseArea {
                id: headerMouseArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: root.toggle()
            }

            RowLayout {
                id: headerRowLayout
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: root.headerPaddingHorizontal
                anchors.rightMargin: root.headerPaddingHorizontal
                spacing: 10

                MaterialSymbol {
                    Layout.topMargin: 7
                    Layout.bottomMargin: 7
                    Layout.leftMargin: 3
                    text: "neurology"
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignLeft
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer2
                    text: root.summary()
                }

                ThinkBlockButton {
                    id: copyButton
                    symbol: activated ? "inventory" : "content_copy"
                    parentHovered: headerMouseArea.containsMouse
                    tooltipText: Translation.tr("Copy reasoning")
                    onClicked: {
                        AiOutputController.copyText(root.thoughtText);
                        copyButton.activated = true;
                        copyResetTimer.restart();
                    }

                    Timer {
                        id: copyResetTimer
                        interval: 1500
                        onTriggered: copyButton.activated = false
                    }
                }

                ThinkBlockButton {
                    symbol: "keyboard_arrow_down"
                    iconRotation: root.expanded ? 180 : 0
                    parentHovered: headerMouseArea.containsMouse
                    tooltipText: root.expanded ? Translation.tr("Hide reasoning") : Translation.tr("Show reasoning")
                    onClicked: root.toggle()
                }
            }
        }

        Item {
            id: content
            Layout.fillWidth: true
            implicitHeight: root.expanded ? Math.min(thoughtFlickable.contentHeight, root.maxContentHeight) : 0
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer2
            }

            Flickable {
                id: thoughtFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: thoughtColumn.implicitHeight
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                // While the thought is still arriving, stay at the bottom so
                // the newest line is the one being read.
                onContentHeightChanged: {
                    if (!root.completed)
                        contentY = Math.max(0, contentHeight - height);
                }

                Column {
                    id: thoughtColumn
                    width: thoughtFlickable.width

                    AiMessageTextBlock {
                        width: parent.width
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        messageData: root.messageData
                        done: root.done
                        segmentContent: root.thoughtText
                        forceDisableChunkSplitting: true
                    }
                }
            }
        }
    }
}
