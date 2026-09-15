import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

import qs

Popup {
    id: root

    required property Item editor

    padding: 0
    margins: 0

    enter: Transition {
        NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    exit: Transition {
        NumberAnimation { property: "scale"; from: 1; to: 0.9; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
    }

    contentItem: Rectangle {
        implicitWidth: 180
        implicitHeight: menuContent.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Config?.options.appearance.transparency.enable ?? false
            ? Qt.rgba(
                Appearance.colors.colLayer2Base.r,
                Appearance.colors.colLayer2Base.g,
                Appearance.colors.colLayer2Base.b,
                Math.max(0.8, 1 - Config.options.appearance.transparency.backgroundTransparency)
            )
            : Appearance.colors.colLayer2

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: (mouse) => mouse.accepted = true
        }

        ColumnLayout {
            id: menuContent
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            ContextMenuItem {
                iconName: "undo"
                label: Translation.tr("Undo")
                onClicked: { root.editor.undo(); root.close(); }
            }

            ContextMenuItem {
                iconName: "redo"
                label: Translation.tr("Redo")
                onClicked: { root.editor.redo(); root.close(); }
            }

            MenuSeparator {}

            ContextMenuItem {
                iconName: "cut"
                label: Translation.tr("Cut")
                enabled: root.editor.selectedText.length > 0
                onClicked: { root.editor.cut(); root.close(); }
            }

            ContextMenuItem {
                iconName: "content_copy"
                label: Translation.tr("Copy")
                enabled: root.editor.selectedText.length > 0
                onClicked: { root.editor.copy(); root.close(); }
            }

            ContextMenuItem {
                iconName: "content_paste"
                label: Translation.tr("Paste")
                onClicked: { root.editor.paste(); root.close(); }
            }

            ContextMenuItem {
                iconName: "delete"
                label: Translation.tr("Delete")
                enabled: root.editor.selectedText.length > 0
                onClicked: { root.editor.remove(root.editor.selectionStart, root.editor.selectionEnd); root.close(); }
            }

            MenuSeparator {}

            ContextMenuItem {
                iconName: "select_all"
                label: Translation.tr("Select All")
                onClicked: { root.editor.selectAll(); root.close(); }
            }
        }
    }

    background: Item {}

    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.topMargin: 4
        Layout.bottomMargin: 4
        color: Appearance.colors.colLayer2Hover
    }

    component ContextMenuItem: Item {
        id: menuItem
        property string iconName: ""
        property string label: ""
        property bool enabled: true

        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 32 : 0

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            radius: Appearance.rounding.small
            color: !menuItem.enabled ? "transparent" : itemMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"

            MouseArea {
                id: itemMouse
                anchors.fill: parent
                hoverEnabled: menuItem.enabled
                cursorShape: menuItem.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (menuItem.enabled) menuItem.clicked()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                MaterialSymbol {
                    text: menuItem.iconName
                    iconSize: 18
                    color: menuItem.enabled ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: menuItem.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: menuItem.enabled ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                }
            }
        }
    }
}
