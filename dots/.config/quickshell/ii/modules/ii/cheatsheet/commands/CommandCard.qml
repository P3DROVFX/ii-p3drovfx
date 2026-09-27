pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    readonly property color colBg: Appearance.colors.colSurfaceContainer
    readonly property color colBgHover: Appearance.colors.colSurfaceContainerHigh
    readonly property color colBorder: Appearance.colors.colOutlineVariant

    readonly property color colTagBg: Appearance.colors.colPrimaryContainer
    readonly property color colTagText: Appearance.colors.colOnPrimaryContainer
    
    readonly property color colEditBtnBg: Appearance.colors.colSecondaryContainer
    readonly property color colEditBtnBgHover: Appearance.colors.colSecondaryContainerHover
    readonly property color colEditBtnIcon: Appearance.colors.colOnSecondaryContainer
    
    readonly property color colDeleteBtnBg: Appearance.colors.colErrorContainer
    readonly property color colDeleteBtnBgHover: Appearance.colors.colErrorContainerHover
    readonly property color colDeleteBtnIcon: Appearance.colors.colOnErrorContainer
    
    readonly property color colCodeBg: Appearance.colors.colSurfaceContainerHighest
    readonly property color colCodeBorder: Appearance.colors.colOutlineVariant
    readonly property color colCodeText: Appearance.colors.colOnSurface
    
    readonly property color colCopyBtnBg: Appearance.colors.colPrimary
    readonly property color colCopyBtnBgHover: Appearance.colors.colPrimaryHover
    readonly property color colCopyBtnBgToggled: Appearance.colors.colPrimaryContainer
    readonly property color colCopyBtnIcon: Appearance.colors.colOnPrimary
    readonly property color colCopyBtnIconToggled: Appearance.colors.colOnPrimaryContainer
    
    readonly property color colDescText: Appearance.colors.colOnSurfaceVariant

    property string commandId: ""
    property string command: ""
    property string description: ""
    property var tags: []
    property bool copied: false
    // Keyboard story: the selected card reveals its action buttons and their
    // keybind hints (MonthDayCell pattern).
    property bool keyboardSelected: false
    property bool showShortcutHints: false

    signal editClicked
    signal deleteClicked

    function copyCommand() {
        Quickshell.clipboardText = root.command;
        root.copied = true;
        copyResetTimer.restart();
    }

    implicitHeight: cardColumn.implicitHeight + 32

    HoverHandler { id: hoverHandler }

    Timer {
        id: copyResetTimer
        interval: 1500
        onTriggered: root.copied = false
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: hoverHandler.hovered || root.keyboardSelected ? root.colBgHover : root.colBg
        border.width: hoverHandler.hovered ? 1 : 0
        border.color: root.colBorder
        scale: copyBtn.down ? 0.985 : 1.0

        Behavior on border.width { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type } }
        Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type } }

        ColumnLayout {
            id: cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    visible: root.tags.length > 0
                    radius: Appearance.rounding.full
                    color: root.colTagBg
                    implicitWidth: tagLabel.implicitWidth + 14
                    implicitHeight: 20

                    StyledText {
                        id: tagLabel
                        anchors.centerIn: parent
                        text: root.tags.length > 0 ? root.tags[0].toUpperCase() : ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.colTagText
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 4
                    opacity: hoverHandler.hovered || root.keyboardSelected ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                    RippleButton {
                        implicitWidth: 36; implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.colEditBtnBg
                        colBackgroundHover: root.colEditBtnBgHover
                        onClicked: root.editClicked()
                        TaskShortcutContent {
                            anchors.centerIn: parent
                            symbol: "edit"
                            shortcut: "Ctrl\n+ E"
                            showHint: root.keyboardSelected && root.showShortcutHints
                            iconSize: Appearance.font.pixelSize.small
                            color: root.colEditBtnIcon
                        }
                    }

                    RippleButton {
                        implicitWidth: 36; implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.colDeleteBtnBg
                        colBackgroundHover: root.colDeleteBtnBgHover
                        onClicked: root.deleteClicked()
                        TaskShortcutContent {
                            anchors.centerIn: parent
                            symbol: "delete"
                            shortcut: "Ctrl\n+ D"
                            showHint: root.keyboardSelected && root.showShortcutHints
                            iconSize: Appearance.font.pixelSize.small
                            color: root.colDeleteBtnIcon
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: codeText.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: root.colCodeBg
                    border.width: 1
                    border.color: root.colCodeBorder

                    StyledText {
                        id: codeText
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                        text: root.command
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.colCodeText
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    id: copyBtn
                    implicitWidth: 36; implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.colCopyBtnBg
                    colBackgroundHover: root.colCopyBtnBgHover
                    colBackgroundToggled: root.colCopyBtnBgToggled
                    onClicked: root.copyCommand()
                    TaskShortcutContent {
                        anchors.centerIn: parent
                        symbol: root.copied ? "check" : "content_copy"
                        shortcut: "Ctrl\n+ ↵"
                        showHint: root.keyboardSelected && root.showShortcutHints
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.copied ? root.colCopyBtnIconToggled : root.colCopyBtnIcon
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.colDescText
                wrapMode: Text.WordWrap
                visible: root.description.length > 0
            }
        }
    }
}
