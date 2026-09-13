import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The search pill on the left of the dock.
 *
 * Shaped like the desktop's Android search widget — an outer capsule holding an inner pill
 * — so the two read as the same control in two places. It searches nothing itself: it is a
 * door, and it opens the app drawer with the field already focused, because the drawer's
 * search is where results belong on this family.
 *
 * Either end is a button the user chooses, and the whole thing collapses to a single circle
 * for people who want the dock to be apps and nothing else. The bar knows how to draw an
 * action and nothing about what one does; the dock decides that, so a new action is a line
 * there rather than a new dependency here.
 */
Item {
    id: root

    property real barHeight: Appearance.sizes.minimumTouchTarget
    /// "extended" is the pill; "compact" is a single circular button.
    property string barStyle: "extended"
    /// "none", "search", "apps", or "tool:<SearchPanelRegistry id>".
    property string leadingAction: "search"
    property string trailingAction: "apps"
    /// Empty falls back to the translated default.
    property string placeholderText: ""

    readonly property bool compact: root.barStyle === "compact"

    /// The pill body was tapped — plain "open the drawer and let me type".
    signal activated
    /// One of the two end buttons was tapped, with whatever the user assigned to it.
    signal actionTriggered(string actionId)

    implicitHeight: root.barHeight
    implicitWidth: root.compact ? root.barHeight : 320

    function actionSymbol(actionId) {
        if (actionId === "apps")
            return "apps";
        if (actionId === "search")
            return "search";
        if (String(actionId).startsWith("tool:")) {
            const panelId = String(actionId).substring(5);
            return SearchPanelRegistry.panels.find(panel => panel.id === panelId)?.icon ?? "wand_stars";
        }
        return "";
    }

    // Declared BEFORE the pill, so the end buttons drawn inside it stack above and win the
    // press. Doing this with a negative z instead is how an earlier version lost taps to
    // the wrong handler entirely; declaration order says the same thing and cannot be
    // reinterpreted by a parent.
    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: {
            if (root.compact) {
                root.actionTriggered(root.leadingAction);
                return;
            }
            root.activated();
        }
    }

    Rectangle {
        id: capsule
        anchors.fill: parent
        radius: height / 2
        color: Appearance.colors.colLayer1

        Rectangle {
            id: innerPill
            anchors.fill: parent
            anchors.margins: Math.round(root.barHeight * 0.08)
            radius: height / 2
            color: tapArea.pressed ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            // Compact: one symbol, centred, and the whole circle is the button. There is no
            // room for a second action and no label to explain one.
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.compact
                text: root.actionSymbol(root.leadingAction).length > 0
                    ? root.actionSymbol(root.leadingAction) : "search"
                iconSize: Math.round(root.barHeight * 0.46)
                color: Appearance.colors.colOnLayer2
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Math.round(root.barHeight * 0.34)
                anchors.rightMargin: Math.round(root.barHeight * 0.28)
                spacing: Math.round(root.barHeight * 0.24)
                visible: !root.compact

                MaterialSymbol {
                    id: leadingSymbol
                    visible: root.actionSymbol(root.leadingAction).length > 0
                    text: root.actionSymbol(root.leadingAction)
                    iconSize: Math.round(root.barHeight * 0.46)
                    color: Appearance.colors.colOnLayer2

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Math.round(root.barHeight * 0.16)
                        onClicked: root.actionTriggered(root.leadingAction)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.placeholderText.length > 0
                        ? root.placeholderText : Translation.tr("Search")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    id: trailingSymbol
                    visible: root.actionSymbol(root.trailingAction).length > 0
                    text: root.actionSymbol(root.trailingAction)
                    iconSize: Math.round(root.barHeight * 0.42)
                    color: Appearance.colors.colOnLayer2
                    opacity: 0.75

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Math.round(root.barHeight * 0.16)
                        onClicked: root.actionTriggered(root.trailingAction)
                    }
                }
            }
        }
    }
}
