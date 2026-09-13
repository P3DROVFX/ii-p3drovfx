import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray

PopupWindow {
    id: root
    required property QsMenuHandle trayItemMenuHandle
    // Prefer the item over its id: ids are not unique for Electron/Chrome tray icons.
    property SystemTrayItem trayItem: null
    property string trayItemId: ""
    readonly property var pinTarget: root.trayItem ?? root.trayItemId
    property real popupBackgroundMargin: 0

    signal menuClosed
    signal menuOpened(qsWindow: var) // Correct type is QsWindow, but QML does not like that

    color: "transparent"
    property real padding: Appearance.sizes.elevationMargin

    implicitHeight: (stackView.currentItem ? stackView.currentItem.implicitHeight : 100) + popupBackground.padding * 2 + root.padding * 2
    implicitWidth: (stackView.currentItem ? stackView.currentItem.implicitWidth : 200) + popupBackground.padding * 2 + root.padding * 2

    function open() {
        root.visible = true;
        root.menuOpened(root);
    }

    function close() {
        root.visible = false;
        while (stackView.depth > 1)
            stackView.pop();
        root.menuClosed();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton) && stackView.depth > 1)
                stackView.pop();
        }

        StyledRectangularShadow {
            target: popupBackground
            opacity: popupBackground.opacity
        }

        Rectangle {
            id: popupBackground
            readonly property real padding: 4
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: BarPlacement.vertical ? parent.verticalCenter : undefined
                top: BarPlacement.vertical ? undefined : BarPlacement.bottom ? undefined : parent.top
                bottom: BarPlacement.vertical ? undefined : BarPlacement.bottom ? parent.bottom : undefined
                margins: root.padding
            }

            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            opacity: 0
            Component.onCompleted: opacity = 1
            implicitWidth: stackView.implicitWidth + popupBackground.padding * 2
            implicitHeight: stackView.implicitHeight + popupBackground.padding * 2

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            StackView {
                id: stackView
                anchors {
                    fill: parent
                    margins: popupBackground.padding
                }
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}

                implicitWidth: currentItem ? currentItem.implicitWidth : 180
                implicitHeight: currentItem ? currentItem.implicitHeight : 80

                initialItem: SubMenu {
                    handle: root.trayItemMenuHandle
                }
            }
        }
    }

    component NoAnim: Transition {
        NumberAnimation {
            duration: 0
        }
    }

    component SubMenu: ColumnLayout {
        id: submenu
        required property QsMenuHandle handle
        property bool isSubMenu: false
        property bool shown: false
        opacity: shown ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        QsMenuOpener {
            id: menuOpener
            menu: submenu.handle
        }

        spacing: 0

        Loader {
            Layout.fillWidth: true
            visible: submenu.isSubMenu
            active: visible
            sourceComponent: RippleButton {
                id: backButton
                buttonRadius: popupBackground.radius - popupBackground.padding
                horizontalPadding: 12
                implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
                implicitHeight: 36

                downAction: () => stackView.pop()

                contentItem: RowLayout {
                    anchors {
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        right: parent.right
                        leftMargin: backButton.horizontalPadding
                        rightMargin: backButton.horizontalPadding
                    }
                    spacing: 8
                    MaterialSymbol {
                        iconSize: 20
                        text: "chevron_left"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Back")
                    }
                }
            }
        }
        RippleButton {
            id: pinEntry
            buttonRadius: popupBackground.radius - popupBackground.padding
            horizontalPadding: 12
            implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
            implicitHeight: 36
            Layout.topMargin: 0
            Layout.bottomMargin: 0
            Layout.fillWidth: true

            visible: root.trayItemId !== undefined && root.trayItemId.length > 0 && stackView.depth === 1
            // Repinning moves the item between the bar and the overflow popup, which
            // destroys whatever this menu is anchored to. Close first, then defer the
            // toggle so the menu PopupWindow finishes tearing down before its anchor
            // host is removed from the bar/overflow.
            releaseAction: () => {
                const target = root.pinTarget;
                root.close();
                Qt.callLater(() => TrayService.togglePin(target));
            }

            contentItem: RowLayout {
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    right: parent.right
                    leftMargin: pinEntry.horizontalPadding
                    rightMargin: pinEntry.horizontalPadding
                }
                spacing: 8

                MaterialSymbol {
                    iconSize: 18
                    text: "push_pin"
                }

                StyledText {
                    Layout.fillWidth: true
                    text: TrayService.isPinned(root.pinTarget) ? Translation.tr("Unpin") : Translation.tr("Pin")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colSubtext
            Layout.topMargin: 4
            Layout.bottomMargin: 4
        }

        Repeater {
            id: menuEntriesRepeater
            property bool iconColumnNeeded: {
                if (!menuOpener || !menuOpener.children || !menuOpener.children.values) return false;
                let vals = menuOpener.children.values;
                for (let i = 0; i < vals.length; i++) {
                    let entry = vals[i];
                    if (entry && entry.icon && entry.icon.length > 0)
                        return true;
                }
                return false;
            }
            property bool specialInteractionColumnNeeded: {
                if (!menuOpener || !menuOpener.children || !menuOpener.children.values) return false;
                let vals = menuOpener.children.values;
                for (let i = 0; i < vals.length; i++) {
                    let entry = vals[i];
                    if (entry && entry.buttonType !== undefined && entry.buttonType !== QsMenuButtonType.None)
                        return true;
                }
                return false;
            }
            model: menuOpener.children
            delegate: SysTrayMenuEntry {
                required property QsMenuEntry modelData
                forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                forceSpecialInteractionColumn: menuEntriesRepeater.specialInteractionColumnNeeded
                menuEntry: modelData

                buttonRadius: popupBackground.radius - popupBackground.padding

                onDismiss: root.close()
                onOpenSubmenu: handle => {
                    stackView.push(subMenuComponent.createObject(null, {
                        handle: handle,
                        isSubMenu: true
                    }));
                }
            }
        }
    }

    Component {
        id: subMenuComponent
        SubMenu {}
    }
}
