pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One open window in the recents carousel: its icon and title on a header strip, its
 * contents below.
 *
 * Flinging the card upwards closes the window, as on Android. The threshold is deliberately
 * generous — closing something by accident while scrubbing sideways through the carousel is
 * far worse than having to repeat a deliberate flick.
 */
Item {
    id: root

    required property var toplevel
    property real cardRadius: Appearance.rounding.large

    signal activated
    signal closed
    /// The header strip was decoration. On Android it is the handle for everything you can
    /// do to a window without opening it, so it raises this with its own position.
    signal menuRequested(real x, real y)

    readonly property string appId: root.toplevel?.appId ?? ""
    readonly property string title: root.toplevel?.title ?? ""

    /// The app you were in when Recents opened. Every card looked identical, so the one
    /// thing the screen is certain about — where you just came from — was the one thing it
    /// did not say. Marked by filling its header, not by an outline or a size: this project
    /// bans borders outright and treats a permanent scale difference as decoration.
    property bool isCurrent: false

    // How far up the card has been dragged. Reset unless the drag commits.
    property real dragOffset: 0
    readonly property real dismissDistance: Math.max(120, root.height * 0.28)

    Behavior on dragOffset {
        enabled: !dragArea.drag.active
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    transform: Translate {
        y: -root.dragOffset
    }
    opacity: Math.max(0, 1 - (root.dragOffset / (root.dismissDistance * 1.6)))

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // The header is its own hit target, above the card's drag area. Tapping the app's
        // icon is how Android reaches split, floating and app info, and the card itself
        // still means "go here" — two gestures, two targets, neither guessed from the other.
        RippleButton {
            id: header
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(Appearance.sizes.minimumTouchTarget - 12, 32)

            buttonRadius: Appearance.rounding.full
            colBackground: root.isCurrent ? Appearance.colors.colSecondaryContainer : "transparent"
            colBackgroundHover: root.isCurrent
                ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
            colRipple: root.isCurrent
                ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer1Active

            onClicked: {
                const point = header.mapToItem(null, header.width / 2, header.height);
                root.menuRequested(point.x, point.y);
            }

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                IconImage {
                    implicitSize: 22
                    source: Quickshell.iconPath(TaskbarApps.getCachedIcon(root.appId), "image-missing")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.title.length > 0 ? root.title : root.appId
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.isCurrent
                        ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    text: "more_horiz"
                    iconSize: 18
                    color: root.isCurrent
                        ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                }
            }
        }

        ClippingRectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.cardRadius
            color: Appearance.colors.colLayer1

            ScreencopyView {
                anchors.fill: parent
                captureSource: root.toplevel
                // One capture per open, not a live feed: a carousel of live captures is a
                // continuous screencopy per card, and the window is not moving anyway.
                live: false
            }

            // Fallback for a window that will not capture — better a labelled surface than
            // an empty rectangle nobody can identify.
            IconImage {
                anchors.centerIn: parent
                implicitSize: 64
                visible: root.toplevel === null
                source: Quickshell.iconPath(TaskbarApps.getCachedIcon(root.appId), "image-missing")
            }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        // Stops short of the header. This is declared after the layout, so it sits on top and
        // would otherwise swallow every press meant for the header's own button.
        anchors.topMargin: header.height + 8

        // No `drag` block: the card itself must not move — only dragOffset does, so the
        // layout stays put — and a MouseArea with a drag target suppresses `clicked`, which
        // cost the tap-to-focus path until it was removed.
        property real pressY: 0

        onPressed: mouse => {
            dragArea.pressY = mouse.y;
        }

        onPositionChanged: mouse => {
            if (!dragArea.pressed)
                return;
            root.dragOffset = Math.max(0, dragArea.pressY - mouse.y);
        }

        onReleased: {
            if (root.dragOffset >= root.dismissDistance) {
                root.closed();
                return;
            }
            root.dragOffset = 0;
        }

        onClicked: {
            if (root.dragOffset < 4)
                root.activated();
        }
    }
}
