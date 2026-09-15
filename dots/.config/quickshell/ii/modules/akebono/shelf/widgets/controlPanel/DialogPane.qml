import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: pane
    required property var panel

    visible: panel.width > panel.mainW + 40
    opacity: Math.max(0, Math.min(1, (panel.width - panel.mainW) / panel.dialogW))

    property string displayDialog: ""
    onVisibleChanged: if (!visible) displayDialog = ""

    Connections {
        target: pane.panel
        function onActiveDialogChanged() {
            if (pane.panel.activeDialog === "")
                return;
            if (pane.displayDialog !== "" && pane.displayDialog !== pane.panel.activeDialog)
                dialogSwapAnim.restart();
            else
                pane.displayDialog = pane.panel.activeDialog;
        }
    }
    SequentialAnimation {
        id: dialogSwapAnim
        NumberAnimation { target: dialogContent; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InCubic }
        ScriptAction { script: pane.displayDialog = pane.panel.activeDialog }
        NumberAnimation { target: dialogContent; property: "opacity"; to: 1; duration: 150; easing.type: Easing.OutCubic }
    }

    ColumnLayout {
        id: dialogContent
        anchors.top: parent.top
        anchors.topMargin: 18
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: pane.panel.dialogOnLeft ? pane.panel.edgePad : 0
        anchors.rightMargin: pane.panel.dialogOnLeft ? 0 : pane.panel.edgePad
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: pane.panel.registry.titleFor(pane.displayDialog)
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
                elide: Text.ElideRight
            }
            ActionButton {
                size: 30
                iconSize: 19
                flat: true
                icon: "check"
                onClicked: pane.panel.activeDialog = ""
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colOnLayer0
            opacity: 0.14
        }
        Loader {
            id: dialogLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: pane.panel.registry.detailFor(pane.displayDialog)
            onLoaded: {
                if (item && item.maxListHeight !== undefined)
                    item.maxListHeight = Qt.binding(() => Math.max(120, dialogLoader.height - 16));
            }
        }
    }
}
