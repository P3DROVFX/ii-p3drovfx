import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The Routines tab: the list (with the templates group under it) on the
 * left, the selected routine's editor on the right.
 */
Item {
    id: root

    property string selectedId: ""
    readonly property var selectedRoutine: Modes.routineById(root.selectedId)
    /// A template being previewed in the right pane instead of the editor.
    property string previewTemplate: ""
    readonly property bool previewing: root.previewTemplate.length > 0

    signal requestClose()

    function selectRoutine(id) {
        root.previewTemplate = "";
        root.selectedId = id;
        if (Config.options.modes.lastRoutineId !== id)
            Config.options.modes.lastRoutineId = id;
    }

    function validateSelection() {
        if (Modes.routineById(root.selectedId))
            return;
        const remembered = Modes.routineById(Config.options.modes.lastRoutineId);
        root.selectRoutine(remembered ? remembered.id : (Modes.routines[0]?.id ?? ""));
    }

    function selectOffset(delta) {
        const idx = Modes.routineIndex(root.selectedId);
        const next = Math.max(0, Math.min(Modes.routines.length - 1, (idx === -1 ? 0 : idx) + delta));
        if (Modes.routines[next])
            root.selectRoutine(Modes.routines[next].id);
    }

    function createRoutine() {
        const id = Modes.addRoutine({ name: Translation.tr("New routine"), icon: "bolt", enabled: true });
        root.selectRoutine(id);
        editorLoader.item?.focusName();
    }

    readonly property var pane: root.previewing ? previewLoader.item : editorLoader.item

    function handleEscape() {
        return root.pane ? root.pane.handleEscape() : false;
    }

    function handleKey(key, modifiers) {
        if (root.pane && root.pane.handleKey(key, modifiers))
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
            if (root.selectedRoutine && !root.previewing)
                Modes.toggleRoutine(root.selectedId);
            return true;
        }
        return false;
    }

    Component.onCompleted: root.validateSelection()

    Connections {
        target: Modes

        function onRoutinesChanged() {
            root.validateSelection();
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        ModeList {
            id: list
            Layout.preferredWidth: 330
            Layout.fillHeight: true
            routines: true
            selectedId: root.previewing ? "" : root.selectedId
            onSelected: id => root.selectRoutine(id)
            onCreateRequested: root.createRoutine()

            footer: RoutineTemplates {
                id: templates
                previewKey: root.previewTemplate
                onPreviewRequested: key => root.previewTemplate = key
                onAdded: id => {
                    if (id.length)
                        root.selectRoutine(id);
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            Loader {
                id: editorLoader
                anchors.fill: parent
                anchors.margins: 4
                asynchronous: true
                active: root.selectedRoutine !== null && !root.previewing
                visible: active
                sourceComponent: RoutineEditor {
                    routineId: root.selectedId
                    onRequestClose: root.requestClose()
                    onDeleted: root.validateSelection()
                    onDuplicated: id => root.selectRoutine(id)
                }
            }

            Loader {
                id: previewLoader
                anchors.fill: parent
                anchors.margins: 4
                asynchronous: true
                active: root.previewing
                visible: active
                sourceComponent: TemplatePreview {
                    templateKey: root.previewTemplate
                    onAdded: id => root.selectRoutine(id)
                    onDismissed: root.previewTemplate = ""
                }
            }

            ColumnLayout {
                visible: root.selectedRoutine === null && !root.previewing
                anchors.centerIn: parent
                width: Math.min(440, parent.width - 60)
                spacing: 12

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "bolt"
                    iconSize: 48
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Translation.tr("No routines yet. Start from a template, or build one from scratch.")
                    color: Appearance.colors.colSubtext
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    RippleButton {
                        implicitHeight: 40
                        implicitWidth: templateText.implicitWidth + 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: list.footerItem.expanded = true

                        contentItem: StyledText {
                            id: templateText
                            text: Translation.tr("Browse templates")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    RippleButton {
                        implicitHeight: 40
                        implicitWidth: newText.implicitWidth + 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: root.createRoutine()

                        contentItem: StyledText {
                            id: newText
                            text: Translation.tr("New routine")
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
