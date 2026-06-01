import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "commands"

Scope {
    id: root
    property var tabButtonList: {
        let list = [];
        if (Config.options.cheatsheet.enableTimetable) {
            list.push({
                "icon": "calendar_month",
                "name": Translation.tr("Timetable")
            });
        }
        list.push({
            "icon": "keyboard",
            "name": Translation.tr("Keybinds")
        });
        if (Config.options.cheatsheet.enablePeriodicTable) {
            list.push({
                "icon": "experiment",
                "name": Translation.tr("Elements")
            });
        }
        if (Config.options.cheatsheet.enableCommands) {
            list.push({
                "icon": "terminal",
                "name": Translation.tr("Commands")
            });
        }
        if (Config.options.cheatsheet.enableGmail) {
            list.push({
                "icon": "mail",
                "name": Translation.tr("Email")
            });
        }
        return list;
    }

    property bool activeState: false

    Timer {
        id: closeTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.activeState = false;
        }
    }

    function requestOpen() {
        closeTimer.stop();
        root.activeState = true;
        GlobalStates.cheatsheetOpen = true;
    }

    function requestClose() {
        GlobalStates.cheatsheetOpen = false;
        closeTimer.start();
    }

    function requestToggle() {
        if (GlobalStates.cheatsheetOpen) {
            requestClose();
        } else {
            requestOpen();
        }
    }

    Loader {
        id: cheatsheetLoader
        active: root.activeState

        sourceComponent: PanelWindow {
            id: cheatsheetRoot
            visible: GlobalStates.cheatsheetOpen

            Connections {
                target: root
                function onTabButtonListChanged() {
                    if (swipeView.currentIndex >= root.tabButtonList.length) {
                        swipeView.currentIndex = 0;
                    }
                }
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function hide() {
                root.requestClose();
            }
            exclusiveZone: 0
            implicitWidth: cheatsheetBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: cheatsheetBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.cheatsheetOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            mask: Region {
                item: cheatsheetBackground
            }

            Timer {
                id: registerGrabTimer
                interval: 150
                repeat: false
                onTriggered: {
                    GlobalFocusGrab.addDismissable(cheatsheetRoot);
                }
            }

            Component.onCompleted: {
                registerGrabTimer.start();
            }
            Component.onDestruction: {
                registerGrabTimer.stop();
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    cheatsheetRoot.hide();
                }
            }

            StyledRectangularShadow {
                target: cheatsheetBackground
            }
            Rectangle {
                id: cheatsheetBackground
                anchors.centerIn: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.windowRounding
                property real padding: 20

                property real maxBgWidth: cheatsheetRoot.screen ? cheatsheetRoot.screen.width * 0.95 : 1900
                property real maxBgHeight: cheatsheetRoot.screen ? cheatsheetRoot.screen.height * 0.80 : 1000
                
                implicitWidth: Math.min(maxBgWidth, cheatsheetColumnLayout.implicitWidth + padding * 2)
                implicitHeight: Math.min(maxBgHeight, cheatsheetColumnLayout.implicitHeight + padding * 2)

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        cheatsheetRoot.hide();
                    } else if (event.key === Qt.Key_Slash) {
                        swipeView.currentItem.forceActiveFocus();
                        event.accepted = true;
                    }
                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_PageDown) {
                            tabBar.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            tabBar.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex + 1) % root.tabButtonList.length);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length);
                            event.accepted = true;
                        }
                    }
                }

                RippleButton {
                    id: closeButton
                    focus: cheatsheetRoot.visible
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 20
                        rightMargin: 20
                    }

                    onClicked: {
                        cheatsheetRoot.hide();
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.title
                        text: "close"
                    }
                }

                ColumnLayout {
                    id: cheatsheetColumnLayout
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - parent.padding * 2)
                    height: Math.min(implicitHeight, parent.height - parent.padding * 2)
                    spacing: 10

                    Toolbar {
                        Layout.alignment: Qt.AlignHCenter
                        enableShadow: false
                        ToolbarTabBar {
                            id: tabBar
                            tabButtonList: root.tabButtonList

                            Synchronizer on currentIndex {
                                property alias source: swipeView.currentIndex
                            }
                        }
                    }

                    SwipeView {
                        id: swipeView
                        Layout.topMargin: 5
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        
                        property real calculatedWidth: cheatsheetRoot.screen ? cheatsheetRoot.screen.width * 0.92 : 1700
                        property real calculatedHeight: cheatsheetRoot.screen ? cheatsheetRoot.screen.height * 0.75 : 650
                        
                        Layout.preferredWidth: Math.min(1800, Math.max(900, calculatedWidth))
                        Layout.preferredHeight: Math.min(850, Math.max(500, calculatedHeight))
                        spacing: 10
                        currentIndex: Persistent.states.cheatsheet.tabIndex
                        onCurrentIndexChanged: {
                            Persistent.states.cheatsheet.tabIndex = currentIndex;
                        }

                        implicitWidth: Math.max.apply(null, contentChildren.map(child => child.implicitWidth || 0))
                        implicitHeight: Math.max.apply(null, contentChildren.map(child => child.implicitHeight || 0))

                        clip: true
                        // Disable expensive layer compositing while animating to prevent lag
                        layer.enabled: !swipeView.moving
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: swipeView.width
                                height: swipeView.height
                                radius: Appearance.rounding.small
                            }
                        }

                        Repeater {
                            model: root.tabButtonList
                            delegate: Loader {
                                id: tabDelegate
                                required property var modelData
                                required property int index

                                // Timetable & Email: lazy — load only when first visited
                                property bool _lazy: modelData.icon === "calendar_month" || modelData.icon === "mail"
                                property bool _wasSeen: false
                                active: !_lazy || swipeView.currentIndex === index || _wasSeen
                                onActiveChanged: if (active)
                                    _wasSeen = true

                                asynchronous: _lazy
                                source: {
                                    switch (modelData.icon) {
                                    case "calendar_month":
                                        return "CheatsheetTimetable.qml";
                                    case "keyboard":
                                        return "CheatsheetKeybinds.qml";
                                    case "experiment":
                                        return "CheatsheetPeriodicTable.qml";
                                    case "terminal":
                                        return "commands/CheatsheetCommands.qml";
                                    case "mail":
                                        return "CheatsheetEmail.qml";
                                    default:
                                        return "";
                                    }
                                }

                                // Loading indicator for async tabs
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    visible: tabDelegate._lazy && tabDelegate.status !== Loader.Ready
                                    MaterialLoadingIndicator {
                                        anchors.centerIn: parent
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void {
            root.requestToggle();
        }
        function close(): void {
            root.requestClose();
        }
        function open(): void {
            root.requestOpen();
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"
        onPressed: {
            root.requestToggle();
        }
    }

    GlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"
        onPressed: {
            root.requestOpen();
        }
    }

    GlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"
        onPressed: {
            root.requestClose();
        }
    }
}
