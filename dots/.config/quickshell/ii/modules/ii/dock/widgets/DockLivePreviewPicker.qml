pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.dock
import qs.services

PopupWindow {
    id: root

    property Item anchorItem: null
    property bool opened: true
    signal dismissed()

    readonly property string dockPosition: root.anchorItem?.dockContent?.dockPos
        ?? dock.dockEffectivePosition
    readonly property real popupGap: Appearance.sizes.elevationMargin
    readonly property real popupWidth: Appearance.sizes.dockButtonSize * 5.8
    readonly property real rowHeight: Math.max(Appearance.sizes.dockButtonSize * 0.72, 42)
    readonly property var rows: {
        const result = [];
        for (const app of (TaskbarApps.apps ?? [])) {
            const windows = app?.toplevels ?? [];
            if (windows.length === 0) {
                result.push({
                    appId: app?.appId ?? "",
                    toplevel: null,
                    title: Translation.tr("Not running"),
                    appName: TaskbarApps.getCachedDesktopEntry(app?.appId ?? "")?.name
                        || app?.appId
                        || ""
                });
                continue;
            }

            for (const toplevel of windows) {
                result.push({
                    appId: toplevel?.appId ?? app?.appId ?? "",
                    toplevel: toplevel,
                    title: toplevel?.title ?? Translation.tr("Untitled window"),
                    appName: TaskbarApps.getCachedDesktopEntry(toplevel?.appId ?? app?.appId ?? "")?.name
                        || toplevel?.appId
                        || app?.appId
                        || ""
                });
            }
        }
        return result;
    }

    function chooseRow(row) {
        if (row.toplevel)
            DockLivePreviewService.selectWindow(row.toplevel);
        else
            DockLivePreviewService.selectApp(row.appId);
        root.close();
    }

    function requestAnchorUpdate() {
        if (root.opened && root.anchor.window)
            anchorUpdateTimer.restart();
    }

    function close() {
        if (!root.opened)
            return;
        root.opened = false;
        root.dismissed();
    }

    implicitWidth: root.popupWidth
    implicitHeight: pickerSurface.implicitHeight
    visible: root.opened
    color: "transparent"

    Timer {
        id: anchorUpdateTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root.opened && root.anchor.window)
                root.anchor.updateAnchor();
        }
    }

    anchor {
        window: root.anchorItem?.QsWindow?.window ?? null
        adjustment: PopupAdjustment.None
        edges: Edges.Top | Edges.Left

        rect.x: {
            if (!root.anchorItem)
                return 0;
            const mapped = root.anchorItem.mapToItem(null, root.anchorItem.width / 2, 0);
            if (root.dockPosition === "left")
                return mapped.x + root.anchorItem.width + root.popupGap;
            if (root.dockPosition === "right")
                return mapped.x - root.popupWidth - root.popupGap;
            return mapped.x - root.popupWidth / 2;
        }

        rect.y: {
            if (!root.anchorItem)
                return 0;
            const mappedTop = root.anchorItem.mapToItem(null, 0, 0);
            const mappedBottom = root.anchorItem.mapToItem(null, 0, root.anchorItem.height);
            if (root.dockPosition === "top")
                return mappedBottom.y + root.popupGap;
            if (root.dockPosition === "bottom")
                return mappedTop.y - root.implicitHeight - root.popupGap;
            return (mappedTop.y + mappedBottom.y) / 2 - root.implicitHeight / 2;
        }
    }

    Connections {
        target: root.anchorItem
        function onXChanged() { root.requestAnchorUpdate(); }
        function onYChanged() { root.requestAnchorUpdate(); }
        function onWidthChanged() { root.requestAnchorUpdate(); }
        function onHeightChanged() { root.requestAnchorUpdate(); }
        function onScaleChanged() { root.requestAnchorUpdate(); }
    }

    Rectangle {
        id: pickerSurface
        implicitWidth: root.popupWidth
        readonly property real popupPadding: Appearance.sizes.elevationMargin
        implicitHeight: pickerColumn.implicitHeight + pickerSurface.popupPadding * 2
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: pickerColumn
            anchors.fill: parent
            anchors.margins: pickerSurface.popupPadding
            spacing: Appearance.sizes.elevationMargin / 2

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Live Preview")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                }

                RippleButton {
                    width: root.rowHeight * 0.72
                    height: width
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                    onClicked: root.close()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: root.rowHeight * 0.78
                    buttonRadius: Appearance.rounding.small
                    toggled: Config.options?.dock?.livePreviewFollowActiveWindow ?? true
                    buttonText: Translation.tr("Follow active window")
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: {
                        DockLivePreviewService.followActive();
                        root.close();
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: root.rowHeight * 0.78
                    buttonRadius: Appearance.rounding.small
                    buttonText: Translation.tr("Clear")
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: {
                        DockLivePreviewService.clearSelection();
                        root.close();
                    }
                }
            }

            ListView {
                id: rowList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(root.rowHeight * 5, contentHeight)
                implicitHeight: Math.min(root.rowHeight * 5, contentHeight)
                clip: true
                model: root.rows
                spacing: Appearance.sizes.elevationMargin / 4

                delegate: RippleButton {
                    required property var modelData
                    width: rowList.width
                    height: root.rowHeight
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: root.chooseRow(modelData)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.sizes.elevationMargin / 2
                        anchors.rightMargin: Appearance.sizes.elevationMargin / 2
                        spacing: Appearance.sizes.elevationMargin / 2

                        DockIcon {
                            Layout.preferredWidth: root.rowHeight * 0.56
                            Layout.preferredHeight: Layout.preferredWidth
                            appId: modelData.appId
                            desktopEntry: TaskbarApps.getCachedDesktopEntry(modelData.appId)
                            isRunning: modelData.toplevel !== null
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.appName
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                            }
                        }

                        MaterialSymbol {
                            visible: modelData.toplevel?.activated ?? false
                            text: "check"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            StyledText {
                visible: rowList.count === 0
                Layout.fillWidth: true
                text: Translation.tr("No running applications")
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
