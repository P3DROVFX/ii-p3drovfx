import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell

Menu {
    id: root

    property var targetField: null
    property int menuPadding: 6
    readonly property int outerRadius: Appearance.rounding.windowRounding
    readonly property int innerRadius: Math.max(0, outerRadius - menuPadding)

    implicitWidth: 216
    padding: menuPadding
    topPadding: menuPadding
    bottomPadding: menuPadding
    leftPadding: menuPadding
    rightPadding: menuPadding

    background: Item {
        implicitWidth: 216
        implicitHeight: root.contentHeight + (root.menuPadding * 2)

        StyledRectangularShadow {
            target: menuBackground
        }

        Rectangle {
            id: menuBackground
            anchors.fill: parent
            radius: root.outerRadius
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }

    function doCopy() {
        if (!targetField) return;
        const start = targetField.selectionStart;
        const end = targetField.selectionEnd;
        if (end > start) {
            if (targetField.echoMode !== undefined && targetField.echoMode !== TextInput.Normal) {
                const sub = targetField.text.substring(start, end);
                Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(sub)}' | wl-copy`]);
            } else {
                targetField.copy();
            }
        }
    }

    function doCut() {
        if (!targetField) return;
        const start = targetField.selectionStart;
        const end = targetField.selectionEnd;
        if (end > start) {
            if (targetField.echoMode !== undefined && targetField.echoMode !== TextInput.Normal) {
                const sub = targetField.text.substring(start, end);
                Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(sub)}' | wl-copy`]);
                targetField.remove(start, end);
            } else {
                targetField.cut();
            }
        }
    }

    function doClear() {
        if (!targetField) return;
        if (typeof targetField.clear === "function") {
            targetField.clear();
        } else {
            targetField.text = "";
        }
    }

    StyledContextMenuItem {
        symbolName: "undo"
        text: Translation.tr("Undo")
        shortcutHint: "Ctrl+Z"
        enabled: (root.targetField && root.targetField.canUndo !== undefined) ? root.targetField.canUndo : false
        onTriggered: {
            if (root.targetField) {
                root.targetField.undo();
                root.targetField.forceActiveFocus();
            }
        }
    }

    StyledContextMenuItem {
        symbolName: "redo"
        text: Translation.tr("Redo")
        shortcutHint: "Ctrl+Y"
        enabled: (root.targetField && root.targetField.canRedo !== undefined) ? root.targetField.canRedo : false
        onTriggered: {
            if (root.targetField) {
                root.targetField.redo();
                root.targetField.forceActiveFocus();
            }
        }
    }

    StyledContextMenuSeparator {}

    StyledContextMenuItem {
        symbolName: "content_cut"
        text: Translation.tr("Cut")
        shortcutHint: "Ctrl+X"
        enabled: root.targetField ? (root.targetField.selectionEnd > root.targetField.selectionStart) : false
        onTriggered: {
            root.doCut();
            if (root.targetField) root.targetField.forceActiveFocus();
        }
    }

    StyledContextMenuItem {
        symbolName: "content_copy"
        text: Translation.tr("Copy")
        shortcutHint: "Ctrl+C"
        enabled: root.targetField ? (root.targetField.selectionEnd > root.targetField.selectionStart) : false
        onTriggered: {
            root.doCopy();
            if (root.targetField) root.targetField.forceActiveFocus();
        }
    }

    StyledContextMenuItem {
        symbolName: "content_paste"
        text: Translation.tr("Paste")
        shortcutHint: "Ctrl+V"
        enabled: (root.targetField && root.targetField.canPaste !== undefined) ? root.targetField.canPaste : true
        onTriggered: {
            if (root.targetField) {
                root.targetField.paste();
                root.targetField.forceActiveFocus();
            }
        }
    }

    StyledContextMenuSeparator {}

    StyledContextMenuItem {
        symbolName: "select_all"
        text: Translation.tr("Select all")
        shortcutHint: "Ctrl+A"
        enabled: root.targetField ? (root.targetField.length > 0) : false
        onTriggered: {
            if (root.targetField) {
                root.targetField.selectAll();
                root.targetField.forceActiveFocus();
            }
        }
    }

    StyledContextMenuItem {
        symbolName: "backspace"
        text: Translation.tr("Clear")
        shortcutHint: "Esc"
        enabled: root.targetField ? (root.targetField.length > 0) : false
        onTriggered: {
            root.doClear();
            if (root.targetField) root.targetField.forceActiveFocus();
        }
    }

    component StyledContextMenuItem: MenuItem {
        id: itemRoot
        property string symbolName: ""
        property string shortcutHint: ""

        implicitWidth: 204
        implicitHeight: 34
        padding: 0
        leftPadding: 8
        rightPadding: 8
        topPadding: 0
        bottomPadding: 0

        background: Rectangle {
            radius: root.innerRadius
            color: itemRoot.down
                ? Appearance.colors.colLayer1Active
                : (itemRoot.hovered ? Appearance.colors.colLayer1Hover : "transparent")
            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }

        contentItem: RowLayout {
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: itemRoot.symbolName
                iconSize: 18
                color: itemRoot.enabled ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                opacity: itemRoot.enabled ? 1.0 : 0.38
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: itemRoot.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: itemRoot.enabled ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                opacity: itemRoot.enabled ? 1.0 : 0.38
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: itemRoot.shortcutHint !== ""
                implicitWidth: shortcutText.implicitWidth + 10
                implicitHeight: 20
                radius: 4
                color: itemRoot.hovered ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                opacity: itemRoot.enabled ? 0.8 : 0.3

                StyledText {
                    id: shortcutText
                    anchors.centerIn: parent
                    text: itemRoot.shortcutHint
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: itemRoot.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
    }

    component StyledContextMenuSeparator: MenuSeparator {
        implicitHeight: 9
        topPadding: 4
        bottomPadding: 4
        leftPadding: 4
        rightPadding: 4
        contentItem: Rectangle {
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
            opacity: 0.7
        }
    }
}
