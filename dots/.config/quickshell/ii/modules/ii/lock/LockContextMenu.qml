import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell

Item {
    id: root

    property var targetField: null
    property var lockContext: null
    property bool active: false

    signal closed()
    signal opened()

    implicitWidth: menuBackground.implicitWidth
    implicitHeight: menuBackground.implicitHeight
    width: implicitWidth
    height: implicitHeight

    visible: opacity > 0.001
    opacity: active ? 1.0 : 0.0
    scale: active ? 1.0 : 0.88
    transformOrigin: Item.Bottom

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    onActiveChanged: {
        if (active) {
            root.opened();
        } else {
            root.closed();
        }
    }

    function openAt(targetX, targetY) {
        const menuW = menuBackground.implicitWidth;
        const menuH = menuBackground.implicitHeight;
        const parentW = parent ? parent.width : 1920;
        const parentH = parent ? parent.height : 1080;

        let posX = targetX - (menuW / 2);
        posX = Math.max(12, Math.min(parentW - menuW - 12, posX));

        let posY = targetY - menuH - 12;
        if (posY < 12) {
            posY = Math.min(parentH - menuH - 12, targetY + 12);
        }

        root.x = Math.round(posX);
        root.y = Math.round(posY);
        root.active = true;
    }

    function open() {
        root.active = true;
    }

    function close() {
        root.active = false;
    }

    function toggle() {
        root.active = !root.active;
    }

    function doCopy() {
        if (!targetField) return;
        if (targetField.selectionEnd > targetField.selectionStart) {
            const sub = targetField.text.substring(targetField.selectionStart, targetField.selectionEnd);
            Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(sub)}' | wl-copy`]);
        }
    }

    function doCut() {
        if (!targetField) return;
        if (targetField.selectionEnd > targetField.selectionStart) {
            const start = targetField.selectionStart;
            const end = targetField.selectionEnd;
            const sub = targetField.text.substring(start, end);
            Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(sub)}' | wl-copy`]);
            targetField.remove(start, end);
            if (lockContext) lockContext.currentText = targetField.text;
        }
    }

    property int menuMargins: 6
    readonly property int outerRadius: Appearance.rounding.windowRounding
    readonly property int innerRadius: Math.max(0, outerRadius - menuMargins)

    // Shadow
    Loader {
        active: root.visible
        anchors.fill: menuBackground
        sourceComponent: StyledRectangularShadow {
            target: menuBackground
            anchors.fill: undefined
        }
    }

    Rectangle {
        id: menuBackground
        anchors.fill: parent
        radius: root.outerRadius
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        implicitWidth: 200
        implicitHeight: menuLayout.implicitHeight + (root.menuMargins * 2)

        // Block click-through to lock surface
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            onClicked: mouse => mouse.accepted = true
        }

        ColumnLayout {
            id: menuLayout
            anchors {
                fill: parent
                margins: root.menuMargins
            }
            spacing: 2

            // Undo
            MenuItem {
                symbolName: "undo"
                labelText: Translation.tr("Undo")
                shortcutHint: "Ctrl+Z"
                enabled: root.targetField ? root.targetField.canUndo : false
                onTriggered: {
                    if (root.targetField) {
                        root.targetField.undo();
                        if (root.lockContext) root.lockContext.currentText = root.targetField.text;
                        root.targetField.forceActiveFocus();
                    }
                }
            }

            // Redo
            MenuItem {
                symbolName: "redo"
                labelText: Translation.tr("Redo")
                shortcutHint: "Ctrl+Y"
                enabled: root.targetField ? root.targetField.canRedo : false
                onTriggered: {
                    if (root.targetField) {
                        root.targetField.redo();
                        if (root.lockContext) root.lockContext.currentText = root.targetField.text;
                        root.targetField.forceActiveFocus();
                    }
                }
            }

            MenuSeparator {}

            // Cut
            MenuItem {
                symbolName: "content_cut"
                labelText: Translation.tr("Cut")
                shortcutHint: "Ctrl+X"
                enabled: root.targetField ? (root.targetField.selectionEnd > root.targetField.selectionStart) : false
                onTriggered: {
                    root.doCut();
                    if (root.targetField) root.targetField.forceActiveFocus();
                }
            }

            // Copy
            MenuItem {
                symbolName: "content_copy"
                labelText: Translation.tr("Copy")
                shortcutHint: "Ctrl+C"
                enabled: root.targetField ? (root.targetField.selectionEnd > root.targetField.selectionStart) : false
                onTriggered: {
                    root.doCopy();
                    if (root.targetField) root.targetField.forceActiveFocus();
                }
            }

            // Paste
            MenuItem {
                symbolName: "content_paste"
                labelText: Translation.tr("Paste")
                shortcutHint: "Ctrl+V"
                enabled: root.targetField ? root.targetField.canPaste : true
                onTriggered: {
                    if (root.targetField) {
                        root.targetField.paste();
                        if (root.lockContext) root.lockContext.currentText = root.targetField.text;
                        root.targetField.forceActiveFocus();
                    }
                }
            }

            MenuSeparator {}

            // Select all
            MenuItem {
                symbolName: "select_all"
                labelText: Translation.tr("Select all")
                shortcutHint: "Ctrl+A"
                enabled: root.targetField ? (root.targetField.length > 0) : false
                onTriggered: {
                    if (root.targetField) {
                        root.targetField.selectAll();
                        root.targetField.forceActiveFocus();
                    }
                }
            }

            // Clear
            MenuItem {
                symbolName: "backspace"
                labelText: Translation.tr("Clear")
                shortcutHint: "Esc"
                enabled: root.targetField ? (root.targetField.length > 0) : false
                onTriggered: {
                    if (root.targetField) root.targetField.text = "";
                    if (root.lockContext) root.lockContext.currentText = "";
                    if (root.targetField) root.targetField.forceActiveFocus();
                }
            }
        }
    }

    component MenuItem: RippleButton {
        id: itemRoot
        property string symbolName: ""
        property string labelText: ""
        property string shortcutHint: ""
        property bool isDestructive: false
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 34
        buttonRadius: root.innerRadius

        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        opacity: enabled ? 1.0 : 0.38
        releaseAction: () => {
            if (itemRoot.enabled) {
                itemRoot.triggered();
                root.close();
            }
        }

        readonly property color itemContentColor: isDestructive ? Appearance.colors.colError : Appearance.m3colors.m3onSurface

        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 10

            MaterialSymbol {
                text: itemRoot.symbolName
                iconSize: 18
                color: itemRoot.itemContentColor
            }

            StyledText {
                Layout.fillWidth: true
                text: itemRoot.labelText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: itemRoot.itemContentColor
                elide: Text.ElideRight
            }

            StyledText {
                visible: itemRoot.shortcutHint !== ""
                text: itemRoot.shortcutHint
                font.pixelSize: (Appearance.font && Appearance.font.pixelSize && Appearance.font.pixelSize.verySmall) ? Appearance.font.pixelSize.verySmall : 11
                font.weight: Font.DemiBold
                color: Appearance.colors.colSubtext
            }
        }
    }

    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Layout.bottomMargin: 2
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        implicitHeight: 1
        color: Appearance.colors.colLayer0Border
    }
}
