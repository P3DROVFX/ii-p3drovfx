import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets

import qs
import qs.modules.common
import qs.modules.common.dock
import qs.modules.common.widgets
import qs.services

// Tablet-local counterpart of ii's DockContextMenu. It intentionally carries the same
// actions and popup treatment, while keeping modules/tablet free of qs.modules.ii imports.
Loader {
    id: root

    property Item anchorItem: parent
    property string appId: ""
    property var appToplevels: []
    readonly property var desktopEntry: TaskbarApps.getCachedDesktopEntry(root.appId)
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

    active: false
    visible: active

    sourceComponent: PopupWindow {
        id: popupWindow

        visible: true
        color: "transparent"
        readonly property real popupMargin: Appearance.sizes.elevationMargin * 2
        readonly property real shadowMargin: Appearance.sizes.elevationMargin * 2
        property real menuOffset: popupMargin

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
                const scaledHeight = item.height * (item.scale ?? 1) / 2;
                anchor.rect.x = mapped.x - popupWindow.implicitWidth / 2;
                anchor.rect.y = mapped.y - scaledHeight - popupWindow.implicitHeight - popupWindow.menuOffset;
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

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Appearance.sizes.elevationMargin
                    spacing: Appearance.sizes.elevationMargin / 2

                    DockIcon {
                        Layout.preferredWidth: Appearance.font.pixelSize.large
                        Layout.preferredHeight: Appearance.font.pixelSize.large
                        appId: root.appId
                        isRunning: root.appToplevels.length > 0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.maximumWidth: Appearance.sizes.minimumTouchTarget * 5
                        text: root.desktopEntry?.name ?? root.appId
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideMiddle
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Appearance.sizes.elevationMargin / 2
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                Repeater {
                    model: root.desktopEntry?.actions ?? []

                    delegate: MenuAction {
                        required property var modelData
                        required property int index

                        shapeString: ["Flower", "Gem", "SoftBurst", "Clover4Leaf", "Heart", "Puffy"]
                            [index % 6]
                        labelText: modelData.name ?? ""
                        onTriggered: {
                            modelData.execute()
                            root.close();
                        }
                    }
                }

                Rectangle {
                    visible: (root.desktopEntry?.actions?.length ?? 0) > 0
                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.sizes.elevationMargin / 2
                    Layout.bottomMargin: Appearance.sizes.elevationMargin / 2
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                MenuAction {
                    Layout.fillWidth: true
                    symbolName: "launch"
                    labelText: Translation.tr("Launch")
                    onTriggered: {
                        root.desktopEntry?.execute();
                        root.close();
                    }
                }

                MenuAction {
                    Layout.fillWidth: true
                    visible: root.appId.length > 0
                    symbolName: "live_tv"
                    labelText: Config.options?.dock?.enableLivePreviewWidget ?? false
                        ? Translation.tr("Set as Live Preview")
                        : Translation.tr("Enable Live Preview")
                    onTriggered: {
                        Config.options.dock.enableLivePreviewWidget = true;
                        DockLivePreviewService.selectApp(root.appId);
                        root.close();
                    }
                }

                MenuAction {
                    Layout.fillWidth: true
                    symbolName: TaskbarApps.isPinned(root.appId) ? "keep_off" : "keep"
                    labelText: TaskbarApps.isPinned(root.appId)
                        ? Translation.tr("Unpin")
                        : Translation.tr("Pin")
                    onTriggered: {
                        TaskbarApps.togglePin(root.appId);
                        root.close();
                    }
                }

                MenuAction {
                    Layout.fillWidth: true
                    visible: root.appToplevels.length > 0
                    symbolName: "close"
                    labelText: root.appToplevels.length > 1
                        ? Translation.tr("Close all windows")
                        : Translation.tr("Close window")
                    destructive: true
                    onTriggered: {
                        for (const toplevel of root.appToplevels)
                            toplevel.close();
                        root.close();
                    }
                }
            }
        }
    }

    component MenuAction: RippleButton {
        id: actionButton

            property string symbolName: ""
            property string shapeString: ""
            property string labelText: ""
            property bool destructive: false
            signal triggered

            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.minimumTouchTarget
            buttonRadius: Appearance.rounding.normal
            colBackground: Appearance.colors.colLayer0
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colBackgroundActive: Appearance.colors.colLayer1Active
            colRipple: Appearance.colors.colLayer1Active
            releaseAction: () => actionButton.triggered()

            readonly property color contentColor: destructive
                ? Appearance.colors.colError
                : Appearance.colors.colOnLayer0

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Appearance.sizes.elevationMargin / 2
            anchors.rightMargin: Appearance.sizes.elevationMargin / 2
            spacing: Appearance.sizes.elevationMargin / 2

            Loader {
                active: actionButton.shapeString.length > 0
                sourceComponent: MaterialShape {
                    shapeString: actionButton.shapeString
                    implicitSize: Appearance.font.pixelSize.normal
                    color: actionButton.contentColor
                }
            }

            MaterialSymbol {
                visible: actionButton.symbolName.length > 0 && actionButton.shapeString.length === 0
                text: actionButton.symbolName
                iconSize: Appearance.font.pixelSize.normal
                color: actionButton.contentColor
            }

            StyledText {
                Layout.fillWidth: true
                text: actionButton.labelText
                font.pixelSize: Appearance.font.pixelSize.small
                color: actionButton.contentColor
            }
        }
    }
}
