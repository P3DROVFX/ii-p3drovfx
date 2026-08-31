import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property var opts: (Config.options && Config.options.interactions && Config.options.interactions.touchGestures)
        ? Config.options.interactions.touchGestures
        : null

    property string previewOrigin: "leftEdge"

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Touch Gesture Bindings")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "swipe"
            title: Translation.tr("Gesture Bindings")
            tooltip: Translation.tr("Configure actions triggered by edge swipes and corner pulls.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                TouchGestureScreenPreview {
                    Layout.fillWidth: true
                    highlightedOrigin: root.previewOrigin
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: root.width >= 680 ? 2 : 1
                    columnSpacing: 10
                    rowSpacing: 10

                    TouchGestureBindingCard {
                        title: Translation.tr("Left Edge Swipe")
                        description: Translation.tr("Swipe from the left edge toward the center")
                        directionIcon: "arrow_forward"
                        origin: "leftEdge"
                        actionId: (root.opts && root.opts.bindings && root.opts.bindings.leftEdge) ? root.opts.bindings.leftEdge : "sidebarLeft"
                        isHighlighted: root.previewOrigin === "leftEdge"
                        onCardHovered: function(orig) { root.previewOrigin = orig; }
                        onActionSelected: function(act) {
                            if (Config.ready && root.opts && root.opts.bindings) root.opts.bindings.leftEdge = act;
                        }
                    }

                    TouchGestureBindingCard {
                        title: Translation.tr("Right Edge Swipe")
                        description: Translation.tr("Swipe from the right edge toward the center")
                        directionIcon: "arrow_back"
                        origin: "rightEdge"
                        actionId: (root.opts && root.opts.bindings && root.opts.bindings.rightEdge) ? root.opts.bindings.rightEdge : "sidebarRight"
                        isHighlighted: root.previewOrigin === "rightEdge"
                        onCardHovered: function(orig) { root.previewOrigin = orig; }
                        onActionSelected: function(act) {
                            if (Config.ready && root.opts && root.opts.bindings) root.opts.bindings.rightEdge = act;
                        }
                    }

                    TouchGestureBindingCard {
                        title: Translation.tr("Top Edge Swipe")
                        description: Translation.tr("Swipe from the top edge downward")
                        directionIcon: "arrow_downward"
                        origin: "topEdge"
                        actionId: (root.opts && root.opts.bindings && root.opts.bindings.topEdge) ? root.opts.bindings.topEdge : "cheatsheet"
                        isHighlighted: root.previewOrigin === "topEdge"
                        onCardHovered: function(orig) { root.previewOrigin = orig; }
                        onActionSelected: function(act) {
                            if (Config.ready && root.opts && root.opts.bindings) root.opts.bindings.topEdge = act;
                        }
                    }

                    TouchGestureBindingCard {
                        title: Translation.tr("Bottom Edge Swipe")
                        description: Translation.tr("Swipe from the bottom edge upward")
                        directionIcon: "arrow_upward"
                        origin: "bottomEdge"
                        actionId: (root.opts && root.opts.bindings && root.opts.bindings.bottomEdge) ? root.opts.bindings.bottomEdge : "overview"
                        isHighlighted: root.previewOrigin === "bottomEdge"
                        onCardHovered: function(orig) { root.previewOrigin = orig; }
                        onActionSelected: function(act) {
                            if (Config.ready && root.opts && root.opts.bindings) root.opts.bindings.bottomEdge = act;
                        }
                    }

                    TouchGestureBindingCard {
                        title: Translation.tr("Top-Left Corner")
                        description: Translation.tr("Swipe downward from the top-left corner")
                        directionIcon: "south_east"
                        origin: "topLeftCorner"
                        actionId: (root.opts && root.opts.bindings && root.opts.bindings.topLeftCorner) ? root.opts.bindings.topLeftCorner : "none"
                        isHighlighted: root.previewOrigin === "topLeftCorner"
                        onCardHovered: function(orig) { root.previewOrigin = orig; }
                        onActionSelected: function(act) {
                            if (Config.ready && root.opts && root.opts.bindings) root.opts.bindings.topLeftCorner = act;
                        }
                    }

                    TouchGestureBindingCard {
                        title: Translation.tr("Top-Right Corner")
                        description: Translation.tr("Swipe downward from the top-right corner")
                        directionIcon: "south_west"
                        origin: "topRightCorner"
                        actionId: (root.opts && root.opts.bindings && root.opts.bindings.topRightCorner) ? root.opts.bindings.topRightCorner : "none"
                        isHighlighted: root.previewOrigin === "topRightCorner"
                        onCardHovered: function(orig) { root.previewOrigin = orig; }
                        onActionSelected: function(act) {
                            if (Config.ready && root.opts && root.opts.bindings) root.opts.bindings.topRightCorner = act;
                        }
                    }

                    TouchGestureBindingCard {
                        title: Translation.tr("Bottom-Left Corner")
                        description: Translation.tr("Swipe upward from the bottom-left corner")
                        directionIcon: "north_east"
                        origin: "bottomLeftCorner"
                        actionId: (root.opts && root.opts.bindings && root.opts.bindings.bottomLeftCorner) ? root.opts.bindings.bottomLeftCorner : "none"
                        isHighlighted: root.previewOrigin === "bottomLeftCorner"
                        onCardHovered: function(orig) { root.previewOrigin = orig; }
                        onActionSelected: function(act) {
                            if (Config.ready && root.opts && root.opts.bindings) root.opts.bindings.bottomLeftCorner = act;
                        }
                    }

                    TouchGestureBindingCard {
                        title: Translation.tr("Bottom-Right Corner")
                        description: Translation.tr("Swipe upward from the bottom-right corner")
                        directionIcon: "north_west"
                        origin: "bottomRightCorner"
                        actionId: (root.opts && root.opts.bindings && root.opts.bindings.bottomRightCorner) ? root.opts.bindings.bottomRightCorner : "osk"
                        isHighlighted: root.previewOrigin === "bottomRightCorner"
                        onCardHovered: function(orig) { root.previewOrigin = orig; }
                        onActionSelected: function(act) {
                            if (Config.ready && root.opts && root.opts.bindings) root.opts.bindings.bottomRightCorner = act;
                        }
                    }
                }
            }
        }
    }
}
