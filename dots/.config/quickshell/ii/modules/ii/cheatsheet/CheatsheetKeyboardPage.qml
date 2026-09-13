pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overview.typing
import qs.services
import "../../common/functions/KeyboardMap.js" as KeyboardMap

Item {
    id: root
    required property string pageId
    property Item keyNavTarget: null
    property bool tabActive: true
    property int activeLayer: 0
    property int selectedKey: -1
    property bool waitingForDetection: false
    property bool confirmingDelete: false
    property real zoom: 1
    property string message: ""
    readonly property var page: {
        const revision = KeybindsService.revision;
        return KeybindsService.pageById(root.pageId);
    }
    readonly property var board: root.page?.keyboard ?? null
    readonly property var layerEntries: root.board?.layers?.[root.activeLayer] ?? []
    readonly property bool editorVisible: editor.isOpen || editor.isAnimating
    readonly property bool navigationLocked: root.editorVisible || keyboardName.activeFocus
        || presetPicker.activeFocus || presetPicker.popup.visible
    readonly property var presets: ["qwerty", "qwertz", "azerty", "dvorak", "colemak"]
    readonly property bool layerShortcutsEnabled: root.visible && root.tabActive && !root.editorVisible
        && !keyboardName.activeFocus && !presetPicker.activeFocus && !presetPicker.popup.visible
        && (root.board?.layers?.length ?? 0) > 1

    function detect(): void {
        if (VialKeyboard.loading) return;
        root.message = "";
        root.waitingForDetection = true;
        VialKeyboard.refresh();
    }

    function addLayer(): void {
        if (!root.board || root.board.layers.length >= 32) return;
        const next = KeyboardMap.copy(root.board);
        next.layers.push(next.keys.map(() => ({ label: "" })));
        next.layerNames.push("");
        if (KeybindsService.setKeyboardMap(root.pageId, next)) {
            editor.close();
            root.activeLayer = next.layers.length - 1;
        }
    }

    function selectLayer(layer): void {
        if (!root.board || layer < 0 || layer >= root.board.layers.length) return;
        editor.close();
        root.selectedKey = -1;
        root.activeLayer = layer;
        root.forceActiveFocus();
    }

    function stepLayer(direction): void {
        const count = root.board?.layers?.length ?? 0;
        if (count) root.selectLayer((root.activeLayer + direction + count) % count);
    }

    Shortcut {
        sequence: "Left"
        context: Qt.WindowShortcut
        enabled: root.layerShortcutsEnabled
        onActivated: root.stepLayer(-1)
    }
    Shortcut {
        sequence: "Right"
        context: Qt.WindowShortcut
        enabled: root.layerShortcutsEnabled
        onActivated: root.stepLayer(1)
    }
    Repeater {
        model: 10
        delegate: Item {
            id: layerShortcut
            required property int index
            Shortcut {
                sequence: String(layerShortcut.index)
                context: Qt.WindowShortcut
                enabled: root.layerShortcutsEnabled && layerShortcut.index < (root.board?.layers?.length ?? 0)
                onActivated: root.selectLayer(layerShortcut.index)
            }
        }
    }

    onPageIdChanged: {
        editor.close();
        root.activeLayer = 0;
        root.selectedKey = -1;
        root.message = "";
        root.waitingForDetection = false;
        root.confirmingDelete = false;
        root.zoom = 1;
    }
    onBoardChanged: {
        if (root.activeLayer >= (root.board?.layers?.length ?? 0)) root.activeLayer = 0;
    }

    Connections {
        target: VialKeyboard
        function onReadFinished(success) {
            if (!root.waitingForDetection) return;
            root.waitingForDetection = false;
            if (!success) {
                root.message = Translation.tr("No Vial keyboard could be read. Check the USB connection and permissions, then try again.");
                return;
            }
            if (KeybindsService.importKeyboardSnapshot(VialKeyboard.snapshot)) {
                editor.close();
                root.selectedKey = -1;
            }
        }
    }

    Timer { id: deleteTimer; interval: 4000; onTriggered: root.confirmingDelete = false }

    component Action: RippleButtonWithIcon {
        mainText: ""
        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        centerContent: true
        scale: 1
        textPixelSize: Appearance.font.pixelSize.small
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                MaterialSymbol { text: "keyboard"; iconSize: Appearance.font.pixelSize.huge; color: Appearance.colors.colPrimary }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledTextInput {
                        id: keyboardName
                        objectName: "keyboardName"
                        Layout.fillWidth: true
                        text: root.page?.name ?? ""
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Bold
                        maximumLength: 100
                        clip: true
                        Accessible.name: Translation.tr("Keyboard name")
                        onEditingFinished: {
                            if (text.trim() && text !== root.page?.name)
                                KeybindsService.updatePage(root.pageId, text.trim(), "keyboard", "");
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 keys · %2 layers").arg(String(root.board?.keys?.length ?? 0)).arg(String(root.board?.layers?.length ?? 0))
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                Action {
                    materialIcon: "language"
                    mainText: KeybindsService.detectingSystemKeyboard ? Translation.tr("Reading…") : Translation.tr("Detect layout")
                    enabled: KeybindsService.writable && !KeybindsService.detectingSystemKeyboard
                    onClicked: KeybindsService.detectSystemKeyboard()
                    StyledToolTip { text: Translation.tr("Read the active system layout, including ABNT2, Shift and AltGr.") }
                }
                Action {
                    materialIcon: "usb"
                    mainText: VialKeyboard.loading ? Translation.tr("Reading…") : Translation.tr("Detect Vial")
                    enabled: KeybindsService.writable && !VialKeyboard.loading
                    onClicked: root.detect()
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.message || ((root.board?.source === "system" ? Translation.tr("System layout") + " · " : "")
                    + Translation.tr("Choose a layer, then click a key to edit its label or icon."))
                wrapMode: Text.Wrap
                color: root.message ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledFlickable {
                id: viewport
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: Math.max(width, diagram.implicitWidth + 24)
                contentHeight: Math.max(height, diagram.implicitHeight + 24)
                KeyboardDiagram {
                    id: diagram
                    objectName: "keyboardDiagram"
                    x: Math.max(12, (viewport.width - width) / 2)
                    y: Math.max(12, (viewport.height - height) / 2)
                    keys: root.board?.keys ?? []
                    entries: root.layerEntries
                    unitWidth: root.board?.width ?? 1
                    unitHeight: root.board?.height ?? 1
                    // Fill the available canvas. Small windows scroll instead
                    // of shrinking legends below readable keycap dimensions.
                    unit: Math.max(42, Math.min(86, (viewport.width - 24) / unitWidth, (viewport.height - 24) / unitHeight)) * root.zoom
                    keySpacing: 6
                    labelSize: Appearance.font.pixelSize.normal
                    interactive: KeybindsService.writable
                    showSymbols: true
                    selectedKey: root.editorVisible ? root.selectedKey : -1
                    onKeyClicked: keyIndex => {
                        root.selectedKey = keyIndex;
                        editor.openKeyboardKey(root.activeLayer, keyIndex, root.layerEntries[keyIndex]);
                    }
                }
            }

            RowLayout {
                id: bottomToolbar
                Layout.fillWidth: true
                spacing: 12

                Flickable {
                    id: layerFlickable
                    Layout.fillWidth: false
                    Layout.maximumWidth: Math.max(100, bottomToolbar.width - layoutControlsRow.implicitWidth - (layerHintText.visible ? layerHintText.implicitWidth + 24 : 0) - 24)
                    implicitWidth: Math.min(layerButtonsRow.implicitWidth, Layout.maximumWidth)
                    implicitHeight: 40
                    contentWidth: layerButtonsRow.implicitWidth
                    contentHeight: 40
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: layerButtonsRow
                        spacing: 6
                        Repeater {
                            model: root.board?.layers?.length ?? 0
                            delegate: Action {
                                required property int index
                                mainText: Translation.tr("Layer %1").arg(String(index))
                                    + (root.board?.layerNames?.[index] ? " · " + root.board.layerNames[index] : "")
                                materialIcon: ""
                                colBackground: root.activeLayer === index ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                colText: root.activeLayer === index ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                onClicked: root.selectLayer(index)
                            }
                        }
                        Action {
                            visible: root.board?.source === "manual"
                            enabled: KeybindsService.writable && (root.board?.layers?.length ?? 0) < 32
                            materialIcon: "add"
                            mainText: Translation.tr("Layer")
                            onClicked: root.addLayer()
                        }
                    }
                }

                StyledText {
                    id: layerHintText
                    visible: (root.board?.layers?.length ?? 0) > 1
                    text: Translation.tr("← / →  Previous / next layer     ·     0–9  Go to layer")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                }

                Item {
                    Layout.fillWidth: true
                }

                Row {
                    id: layoutControlsRow
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter

                    StyledComboBox {
                        id: presetPicker
                        objectName: "presetPicker"
                        width: 210
                        model: [Translation.tr("Add another layout…"), "QWERTY", "QWERTZ", "AZERTY", "Dvorak", "Colemak", "Português (Brasil · ABNT2)"]
                        enabled: KeybindsService.writable && !KeybindsService.detectingSystemKeyboard
                        onActivated: index => {
                            if (index === 6) {
                                KeybindsService.detectSystemKeyboard("abnt2");
                                currentIndex = 0;
                            } else if (index > 0) {
                                const preset = root.presets[index - 1];
                                KeybindsService.createKeyboardPage(KeyboardMap.manual(TypingKeyboardLayouts.rowsFor(preset), preset));
                                currentIndex = 0;
                            }
                            root.forceActiveFocus();
                        }
                    }
                    Action { objectName: "zoomOut"; materialIcon: "remove"; Accessible.name: Translation.tr("Zoom out"); enabled: root.zoom > 0.8; onClicked: root.zoom = Math.max(0.8, root.zoom - 0.2) }
                    Action { mainText: Math.round(root.zoom * 100) + "%"; Accessible.name: Translation.tr("Reset zoom"); onClicked: root.zoom = 1 }
                    Action { materialIcon: "add"; Accessible.name: Translation.tr("Zoom in"); enabled: root.zoom < 2; onClicked: root.zoom = Math.min(2, root.zoom + 0.2) }
                    Action { materialIcon: "download"; Accessible.name: Translation.tr("Export keyboard map"); onClicked: KeybindsService.openExportDialog(root.pageId) }
                    Action {
                        materialIcon: root.confirmingDelete ? "delete_forever" : "delete"
                        mainText: root.confirmingDelete ? Translation.tr("Delete?") : ""
                        Accessible.name: Translation.tr("Delete keyboard page")
                        enabled: KeybindsService.writable
                        onClicked: {
                            if (root.confirmingDelete) KeybindsService.deletePage(root.pageId);
                            else { root.confirmingDelete = true; deleteTimer.restart(); }
                        }
                    }
                }
            }
        }
        Item {
            id: editorSlot
            Layout.fillHeight: true
            Layout.preferredWidth: root.editorVisible ? Math.min(380, root.width * 0.48) : 0
            visible: Layout.preferredWidth > 1
            clip: true
            Behavior on Layout.preferredWidth { animation: Appearance.animation.elementMove.numberAnimation.createObject(editorSlot) }
            DeferredKeybindEditor {
                id: editor
                editorObjectName: "keyboardEditor"
                anchors.fill: parent
                pageId: root.pageId
                keyNavTarget: root.keyNavTarget
                onCloseRequested: root.selectedKey = -1
            }
        }
    }
}
