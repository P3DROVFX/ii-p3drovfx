import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property bool vertical: Config.options.bar.vertical
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? 1

    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - 1) / root.workspacesShown)
    property int workspaceButtonWidth: vertical ? Appearance.sizes.verticalBarWidth - 8 : Appearance.sizes.barHeight - 8

    property bool showNumbers: false
    Timer {
        id: showNumbersTimer
        interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
        repeat: false
        onTriggered: {
            root.showNumbers = true;
        }
    }
    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                return;
            if (GlobalStates.superDown)
                showNumbersTimer.restart();
            else {
                showNumbersTimer.stop();
                root.showNumbers = false;
            }
        }
    }

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLayout.implicitWidth)
    implicitHeight: vertical ? (contentLayout.implicitHeight) : Appearance.sizes.barHeight

    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y < 0)
                Hyprland.dispatch(`workspace r+1`);
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch(`workspace r-1`);
        }
    }

    GridLayout {
        id: contentLayout
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
        columns: root.vertical ? 1 : 99
        rows: root.vertical ? 99 : 1

        Repeater {
            model: root.workspacesShown
            delegate: Button {
                id: button
                property int workspaceValue: workspaceGroup * root.workspacesShown + index + 1
                property var wsWindows: HyprlandData.windowList.filter(w => w.workspace.id === workspaceValue)

                visible: {
                    const isActive = workspaceValue === effectiveActiveWorkspaceId;
                    const isOccupied = wsWindows.length > 0;
                    return !Config.options.bar.workspaces.dynamicWorkspaces || isActive || isOccupied;
                }

                implicitWidth: workspaceButtonWidth
                implicitHeight: workspaceButtonWidth

                background: Item {
                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colPrimary
                        radius: Appearance.rounding.full
                        opacity: button.hovered ? 0.15 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                    }
                    // Active workspace indicator
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.effectiveActiveWorkspaceId === button.workspaceValue ? parent.width * 0.5 : 0
                        height: 2
                        radius: 1
                        color: Appearance.colors.colPrimary
                        Behavior on width {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height

                        // Number / Dot / Symbol (standard logic)
                        WorkspaceBackgroundIndicator {
                            workspaceValue: button.workspaceValue
                            activeWorkspace: root.effectiveActiveWorkspaceId === button.workspaceValue
                            hasWindows: button.wsWindows.length > 0
                        }

                        // Icons (side by side layout)
                        GridLayout {
                            anchors.centerIn: parent
                            columnSpacing: 2
                            rowSpacing: 2
                            columns: root.vertical ? 1 : 2
                            rows: root.vertical ? 2 : 1
                            visible: !root.showNumbers && Config.options.bar.workspaces.showAppIcons && button.wsWindows.length > 0

                            Repeater {
                                model: button.wsWindows.slice(0, Config.options.bar.workspaces.maxWindowCount)
                                delegate: Item {
                                    width: 18
                                    height: 18

                                    MaterialShape {
                                        id: mask
                                        anchors.fill: parent
                                        shapeString: Config.options.appearance.icons.shapeMask
                                        visible: false
                                    }

                                    IconImage {
                                        id: icon
                                        anchors.fill: parent
                                        source: {
                                            const _ = TaskbarApps.iconThemeRevision;
                                            return Quickshell.iconPath(AppSearch.guessIcon(modelData?.class), "image-missing");
                                        }
                                        layer.enabled: Config.options.appearance.icons.enableShapeMask
                                        layer.effect: MultiEffect {
                                            maskEnabled: Config.options.appearance.icons.enableShapeMask
                                            maskSource: mask
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                onPressed: Hyprland.dispatch(`workspace ${workspaceValue}`)
            }
        }
    }

    component WorkspaceBackgroundIndicator: Rectangle {
        property int workspaceValue
        property bool activeWorkspace
        property bool hasWindows
        property bool showNumbers: Config.options.bar.workspaces.alwaysShowNumbers || root.showNumbers
        property color indColor: (activeWorkspace) ? Appearance.colors.colPrimary : (hasWindows ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant)

        anchors.centerIn: parent
        width: 4
        height: 4
        radius: 2
        visible: (!Config.options.bar.workspaces.showAppIcons || !hasWindows) || showNumbers
        color: !showNumbers ? indColor : "transparent"

        StyledText {
            opacity: showNumbers ? 1 : 0
            anchors.centerIn: parent
            text: Config.options?.bar.workspaces.numberMap[workspaceValue - 1] || workspaceValue
            font.pixelSize: 10
            font.weight: Font.Black
            color: indColor
        }
    }
}
