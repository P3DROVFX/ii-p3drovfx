pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import qs.modules.ii.bar.popups.aiPlanUsage
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/aiPlanUsage"

// AI plan usage chip on the shelf. Renders the bar variant for the configured
// aiPlanUsage style; "default" sits inside a shelf pill, the expressive
// variant paints its own capsule. Click cycles the AI provider, exactly like
// the bar widget, and also opens the provider list in the shelf chipPopup slot
// (its bar popup stays disabled here).
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)
    readonly property bool shelfEmpty: !(quotaHolder.item?.shown ?? false)

    implicitWidth: (quotaHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 20)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    Component.onCompleted: {
        if (root.shelf)
            root.shelf.registerChipAnchor(root);
    }
    onXChanged: if (root.shelf?.publishChip) root.shelf.publishChip()
    Component.onDestruction: {
        if (root.shelf)
            root.shelf.unregisterChipAnchor(root);
    }

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
        hovered: quotaHover.hovered
    }

    Loader {
        id: quotaHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? quotaExpressive : quotaDefault
    }

    MouseArea {
        id: quotaClick
        anchors.fill: parent
        propagateComposedEvents: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            if (root.shelf)
                root.shelf.toggleChipPopup(quotaPopoverComp, 420, 430, root, Appearance.rounding.large);
            mouse.accepted = false;
        }
    }

    Component {
        id: quotaDefault
        AiPlanUsageWidget {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: quotaExpressive
        ExpressiveAiPlanUsage {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: quotaPopoverComp
        ShelfPopupSurface {
            AiPlanUsagePopupContent {
                anchors.fill: parent
                opened: root.shelf?.chipPopupOpen ?? false
                popupOpenProgress: root.shelf?.chipPopupProgress ?? 0
            }
        }
    }

    HoverHandler {
        id: quotaHover
        cursorShape: Qt.PointingHandCursor
    }
}