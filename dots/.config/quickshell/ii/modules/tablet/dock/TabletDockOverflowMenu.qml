import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.common
import qs.modules.common.dock
import qs.modules.common.widgets
import qs.services

/**
 * The overflow group's page: everything the dock could not fit, as rows big enough to hit.
 *
 * A PopupWindow rather than an in-surface panel, because the dock's layer is only as tall as
 * the dock: anything drawn above it would be cut off at the surface edge.
 *
 * Activating a row raises the window instead of re-running the launcher. Every app in here
 * is running by definition — that is the only reason it is in the dock at all — and
 * executing its desktop entry again would open a second copy of something the user was
 * trying to get back to.
 */
Loader {
    id: root

    property Item anchorItem: parent
    property var appIds: []
    property bool closing: false

    function open() {
        if (active && !closing)
            return;
        closing = false;
        active = true;
        if (item)
            item.startOpenAnimation();
    }

    function close() {
        if (!active || closing)
            return;
        closing = true;
        if (item)
            item.startCloseAnimation();
    }

    function raiseApp(appId) {
        const normalized = TaskbarApps.normalizeAppId(appId);
        const toplevel = Array.from(ToplevelManager.toplevels?.values ?? []).find(candidate =>
            TaskbarApps.normalizeAppId(candidate?.appId ?? "") === normalized);
        if (toplevel)
            toplevel.activate();
        else
            TaskbarApps.getCachedDesktopEntry(appId)?.execute();
        root.close();
    }

    active: false
    visible: active

    sourceComponent: PopupWindow {
        id: popupWindow

        visible: true
        color: "transparent"
        readonly property real shadowMargin: Appearance.sizes.elevationMargin * 2
        readonly property real menuOffset: Appearance.sizes.elevationMargin * 2

        implicitWidth: menuContent.implicitWidth + shadowMargin * 2
        implicitHeight: menuContent.implicitHeight + shadowMargin * 2

        function startOpenAnimation() {
            menuContent.scale = 1;
            menuContent.opacity = 1;
        }

        function startCloseAnimation() {
            menuContent.scale = 0.8;
            menuContent.opacity = 0;
        }

        anchor {
            adjustment: PopupAdjustment.None
            window: root.anchorItem ? root.anchorItem.QsWindow.window : null
            onAnchoring: {
                const item = root.anchorItem;
                if (!item)
                    return;
                const mapped = item.mapToItem(null, item.width / 2, item.height / 2);
                anchor.rect.x = mapped.x - popupWindow.implicitWidth / 2;
                anchor.rect.y = mapped.y - item.height / 2 - popupWindow.implicitHeight - popupWindow.menuOffset;
            }
        }

        HyprlandFocusGrab {
            active: root.active && !root.closing
            windows: [popupWindow]
            onCleared: root.close()
        }

        StyledRectangularShadow {
            target: menuContent
            opacity: menuContent.opacity
            visible: menuContent.visible
        }

        Rectangle {
            id: menuContent

            anchors.centerIn: parent
            color: Config.options.appearance.transparency.popups
                ? Appearance.colors.colLayer0
                : Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            implicitWidth: menuColumn.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: menuColumn.implicitHeight + Appearance.sizes.elevationMargin * 2
            opacity: 0
            scale: 0.8

            Component.onCompleted: popupWindow.startOpenAnimation()

            Behavior on opacity {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on scale {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            onOpacityChanged: {
                if (opacity === 0 && root.closing) {
                    root.active = false;
                    root.closing = false;
                }
            }

            ColumnLayout {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: Appearance.sizes.elevationMargin
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Appearance.sizes.elevationMargin / 2
                    text: Translation.tr("More open apps")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

                Repeater {
                    model: root.appIds

                    delegate: RippleButton {
                        id: appRowButton
                        required property string modelData

                        Layout.fillWidth: true
                        // A finger, not a pointer: the row is the target, all of it.
                        implicitHeight: Math.max(Appearance.sizes.minimumTouchTarget, 52)
                        implicitWidth: Math.max(260, rowContent.implicitWidth + 32)
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colBackgroundActive: Appearance.colors.colLayer1Active
                        colRipple: Appearance.colors.colLayer1Active
                        releaseAction: () => root.raiseApp(appRowButton.modelData)

                        contentItem: RowLayout {
                            id: rowContent
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 14
                            spacing: 12

                            DockIcon {
                                Layout.preferredWidth: Appearance.font.pixelSize.huge
                                Layout.preferredHeight: Appearance.font.pixelSize.huge
                                appId: appRowButton.modelData
                                isRunning: true
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: TaskbarApps.getCachedDesktopEntry(appRowButton.modelData)?.name
                                    ?? appRowButton.modelData
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
