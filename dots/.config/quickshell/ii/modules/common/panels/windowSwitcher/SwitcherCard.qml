pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/windowSwitcher/WindowSwitcherLogic.js" as Logic

/**
 * One window on the floating switcher: its live picture (or a large icon), then its icon
 * and title. The card does not draw the selection - the panel slides one highlight behind
 * all of them - it only recolours its text when it is the selected one.
 */
Item {
    id: card

    required property var entry
    required property bool selected
    /// Room for the picture; the picture keeps the window's aspect ratio inside it.
    required property real boxWidth
    required property real boxHeight
    required property bool thumbnails
    /// The panel is on screen and this card is inside the scrolled viewport.
    required property bool capturing
    required property real padding

    /// `scenePos` is in window coordinates, so the panel can tell a moving pointer from cards
    /// sliding under a still one.
    signal hovered(point scenePos)
    signal clicked()
    /// The × or a middle click: close this window.
    signal closeRequested()

    readonly property real titleHeight: 22

    // A window opened while the switcher is up fades in instead of appearing.
    property bool born: false
    opacity: card.born ? 1 : 0
    Component.onCompleted: Qt.callLater(() => card.born = true)
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    readonly property string iconPath: {
        const _ = TaskbarApps.iconThemeRevision;
        return Quickshell.iconPath(AppSearch.guessIcon(card.entry?.appClass ?? ""), "image-missing");
    }
    readonly property string title: card.entry?.toplevel?.title || card.entry?.title || card.entry?.appClass || ""

    // The window's own aspect: the captured frame once there is one, Hyprland's size until then.
    readonly property real sourceAspect: {
        if (screencopy.hasContent && screencopy.sourceSize.width > 0 && screencopy.sourceSize.height > 0)
            return screencopy.sourceSize.width / screencopy.sourceSize.height;
        return (card.entry?.width ?? 16) / Math.max(1, card.entry?.height ?? 9);
    }
    readonly property real pictureWidth: Math.min(card.boxWidth, card.boxHeight * card.sourceAspect)
    readonly property real pictureHeight: Math.min(card.boxHeight, card.boxWidth / card.sourceAspect)

    ClippingRectangle {
        id: picture
        visible: card.thumbnails
        x: Math.round((card.width - width) / 2)
        y: card.padding + Math.round((card.boxHeight - height) / 2)
        width: Math.round(card.pictureWidth)
        height: Math.round(card.pictureHeight)
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1

        ScreencopyView {
            id: screencopy
            anchors.fill: parent
            captureSource: card.thumbnails && card.entry?.toplevel ? card.entry.toplevel : null
            live: card.capturing
            constraintSize: Qt.size(Math.round(card.boxWidth), Math.round(card.boxHeight))
        }

        // Until the first frame lands, and for windows that cannot be captured.
        Image {
            anchors.centerIn: parent
            visible: !screencopy.hasContent
            source: card.iconPath
            width: Math.min(48, parent.height * 0.5)
            height: width
            sourceSize: Qt.size(width, height)
            asynchronous: true
        }
    }

    Image {
        id: bigIcon
        visible: !card.thumbnails
        x: Math.round((card.width - width) / 2)
        y: card.padding + Math.round((card.boxHeight - height) / 2)
        width: Math.round(Math.min(card.boxWidth, card.boxHeight))
        height: width
        source: card.iconPath
        sourceSize: Qt.size(width, height)
        asynchronous: true
    }

    RowLayout {
        id: caption
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: card.padding
            rightMargin: card.padding
            bottomMargin: card.padding
        }
        height: card.titleHeight
        spacing: 6

        Image {
            visible: card.thumbnails
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter
            source: card.iconPath
            sourceSize: Qt.size(18, 18)
            asynchronous: true
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: card.thumbnails ? Text.AlignLeft : Text.AlignHCenter
            elide: Text.ElideRight
            // What a search matched, picked out.
            textFormat: Text.StyledText
            text: Logic.highlighted(card.title, WindowSwitcher.query,
                card.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary)
            font.pixelSize: Appearance.font.pixelSize.small
            color: card.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onPositionChanged: mouse => card.hovered(mapToItem(null, mouse.x, mouse.y))
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                card.closeRequested();
            else
                card.clicked();
        }
    }

    SwitcherCloseButton {
        id: cardClose
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 4
        shown: cardMouse.containsMouse || cardClose.containsMouse
        onClicked: card.closeRequested()
    }

    // Counting down to the peek, on the selected card.
    PeekCountdown {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 4
        size: 24
        selected: card.selected
    }

    // Where the window lives, when that is not here.
    WorkspaceChip {
        x: card.thumbnails ? picture.x + 4 : Math.round((card.width - width) / 2)
        y: card.thumbnails ? picture.y + picture.height - height - 4 : card.padding + card.boxHeight - height
        entry: card.entry
    }
}
