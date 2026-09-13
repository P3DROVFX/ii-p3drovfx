import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The Modes tab: the list of modes on the left, the selected one's editor on
 * the right. The same two-pane shape as the Settings app — the only layout
 * that keeps a long per-mode page readable on a wide overlay.
 */
Item {
    id: root

    property string selectedId: ""
    readonly property var selectedMode: Modes.modeById(root.selectedId)

    signal requestClose()

    function selectMode(id) {
        root.selectedId = id;
        if (Config.options.modes.lastModeId !== id)
            Config.options.modes.lastModeId = id;
    }

    // The remembered mode if it still exists, else the first; never nothing
    // while there is something to show.
    function validateSelection() {
        if (Modes.modeById(root.selectedId))
            return;
        const remembered = Modes.modeById(Config.options.modes.lastModeId);
        root.selectMode(remembered ? remembered.id : (Modes.modes[0]?.id ?? ""));
    }

    function selectOffset(delta) {
        const idx = Modes.modeIndex(root.selectedId);
        const next = Math.max(0, Math.min(Modes.modes.length - 1, (idx === -1 ? 0 : idx) + delta));
        if (Modes.modes[next])
            root.selectMode(Modes.modes[next].id);
    }

    function createMode() {
        const id = Modes.addMode({ name: Translation.tr("New mode"), icon: "tune" });
        root.selectMode(id);
        editorLoader.item?.focusName();
    }

    function handleEscape() {
        return editorLoader.item ? editorLoader.item.handleEscape() : false;
    }

    function handleKey(key, modifiers) {
        if (editorLoader.item && editorLoader.item.handleKey(key, modifiers))
            return true;
        switch (key) {
        case Qt.Key_Up:
            root.selectOffset(-1);
            return true;
        case Qt.Key_Down:
            root.selectOffset(1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (root.selectedMode)
                Modes.toggle(root.selectedId);
            return true;
        }
        return false;
    }

    Component.onCompleted: root.validateSelection()

    Connections {
        target: Modes

        function onModesChanged() {
            root.validateSelection();
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        ModeList {
            Layout.preferredWidth: 330
            Layout.fillHeight: true
            selectedId: root.selectedId
            onSelected: id => root.selectMode(id)
            onCreateRequested: root.createMode()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            // Built asynchronously so the list is on screen before the form.
            Loader {
                id: editorLoader
                anchors.fill: parent
                anchors.margins: 4
                asynchronous: true
                active: root.selectedMode !== null
                visible: active
                sourceComponent: ModeEditor {
                    modeId: root.selectedId
                    onRequestClose: root.requestClose()
                    onDeleted: root.validateSelection()
                    onDuplicated: id => root.selectMode(id)
                }
            }

            ColumnLayout {
                visible: root.selectedMode === null
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 60)
                spacing: 12

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "tune"
                    iconSize: 48
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Translation.tr("No modes yet. Create one, or bring the presets back.")
                    color: Appearance.colors.colSubtext
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    RippleButton {
                        implicitHeight: 40
                        implicitWidth: newText.implicitWidth + 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.createMode()

                        contentItem: StyledText {
                            id: newText
                            text: Translation.tr("New mode")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    RippleButton {
                        implicitHeight: 40
                        implicitWidth: presetText.implicitWidth + 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: Modes.seedPresets()

                        contentItem: StyledText {
                            id: presetText
                            text: Translation.tr("Restore presets")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }
}
