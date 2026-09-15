pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.akebono.desktop
import qs.modules.akebono.desktop.widgets

DesktopWidgetBase {
    id: root
    minSize: 160

    property bool previewMode: false
    property bool loading: false

    property int tabIndex: 0
    readonly property int safeIndex: Math.max(0, Math.min(root.tabIndex, NotesService.count - 1))
    readonly property var current: NotesService.tabs[root.safeIndex]
    readonly property var tabMeta: NotesService.tabs.map((t, i) => ({ idx: i, title: t.title, icon: t.icon }))
    readonly property bool tabsVisible: NotesService.count > 1 && (Config.options.notes?.showTabs ?? true)

    function loadCurrent() {
        root.loading = true;
        editor.text = root.current?.content ?? "";
        root.loading = false;
    }
    function switchTo(i) {
        if (i < 0 || i >= NotesService.count)
            return;
        root.tabIndex = i;
        root.loadCurrent();
    }
    function addTab() {
        root.tabIndex = NotesService.addTab();
        root.loadCurrent();
    }
    function closeTab(i) {
        if (NotesService.count <= 1)
            return;
        NotesService.closeTab(i);
        root.tabIndex = Math.max(0, Math.min(i <= root.tabIndex ? root.tabIndex - 1 : root.tabIndex, NotesService.count - 1));
        root.loadCurrent();
    }

    Component.onCompleted: {
        root.tabIndex = root.widgetData?.noteIndex ?? 0;
        root.loadCurrent();
    }
    onTabIndexChanged: DesktopWidgets.setProp(root.wid, "noteIndex", root.tabIndex)
    onCurrentChanged: if (editor && !editor.activeFocus) root.loadCurrent()

    Connections {
        target: DesktopWidgets
        function onReleaseEditing() {
            if (editor.activeFocus)
                editor.focus = false;
        }
    }

    Squircle {
        anchors.fill: parent
        radius: 24
        smoothing: AkebonoAppearance.squircleSmoothing
        color: Appearance.colors.colLayer1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                visible: root.tabsVisible
                clip: true

                ListView {
                    id: tabList
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 2
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    model: ScriptModel {
                        objectProp: "idx"
                        values: root.tabMeta
                    }

                    currentIndex: root.safeIndex
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 200
                    highlightResizeDuration: 200
                    highlight: Item {
                        Rectangle {
                            anchors.bottom: parent.bottom
                            x: 6
                            width: Math.max(0, parent.width - 12)
                            height: 2.5
                            radius: 1.5
                            color: Appearance.colors.colPrimary
                        }
                    }

                    delegate: Item {
                        id: tabDel
                        required property var modelData
                        readonly property bool sel: tabDel.modelData.idx === root.safeIndex
                        implicitWidth: tabContent.implicitWidth + 20
                        height: tabList.height

                        RowLayout {
                            id: tabContent
                            anchors.centerIn: parent
                            spacing: 5

                            MaterialSymbol {
                                text: tabDel.modelData.icon ?? "article"
                                iconSize: 15
                                color: tabDel.sel ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                            StyledText {
                                text: tabDel.modelData.title ?? "Note"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: tabDel.sel ? Font.DemiBold : Font.Normal
                                color: tabDel.sel ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                Layout.maximumWidth: 90
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton)
                                    root.closeTab(tabDel.modelData.idx);
                                else
                                    root.switchTo(tabDel.modelData.idx);
                            }
                        }
                    }
                }

                WheelHandler {
                    onWheel: event => {
                        const max = Math.max(0, tabList.contentWidth - tabList.width);
                        tabList.contentX = Math.max(0, Math.min(max, tabList.contentX - event.angleDelta.y));
                    }
                }
            }
            Item { Layout.fillWidth: true; visible: !root.tabsVisible }

            NoteBtn {
                icon: "add"
                onClicked: root.addTab()
            }
            NoteBtn {
                icon: root.previewMode ? "edit" : "visibility"
                onClicked: root.previewMode = !root.previewMode
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.previewMode
            clip: true

            TextArea {
                id: editor
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                placeholderText: "Write something here...\nUse '-' for bullet points, like this:\n\nSheep fricker\n- 4x Slab\n- 1x Boat\n- 4x Redstone Dust\n- 1x Sticky Piston\n- 1x End Rod\n- 4x Redstone Repeater\n- 1x Redstone Torch\n- 1x Sheep"
                placeholderTextColor: Appearance.colors.colSubtext
                background: null
                onTextChanged: {
                    if (!root.loading && !root.previewMode)
                        NotesService.setContent(root.safeIndex, editor.text);
                }
                onActiveFocusChanged: DesktopWidgets.textEditing = editor.activeFocus

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: {
                        DesktopWidgets.textEditing = true;
                        Qt.callLater(() => editor.forceActiveFocus());
                    }
                }
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.previewMode
            clip: true

            TextArea {
                readOnly: true
                textFormat: TextEdit.MarkdownText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                background: null
                text: root.current?.content ?? ""
            }
        }
    }

    component NoteBtn: Rectangle {
        id: btn
        property string icon: ""
        signal clicked()
        implicitWidth: 26
        implicitHeight: 26
        radius: 13
        color: btnMouse.containsMouse ? Appearance.colors.colLayer2 : "transparent"
        MaterialSymbol {
            anchors.centerIn: parent
            text: btn.icon
            iconSize: 18
            color: Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
