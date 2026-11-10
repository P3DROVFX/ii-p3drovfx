import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One line of custom/execs.lua as a card. On: the primary container, the icon morphs from a
 * circle to the card's shape. Off (the line is commented out): the pane colour, content
 * dimmed. The app's own icon when the command resolves to a desktop entry, a shape-wrapped
 * symbol otherwise; the command in mono under the name; run / edit / remove in the footer.
 */
Rectangle {
    id: root

    required property var entry
    property var shape: MaterialShape.Shape.Cookie9Sided

    signal editRequested()

    readonly property bool on: root.entry.enabled
    readonly property var app: StartupManager.desktopEntryFor(root.entry.command)
    readonly property string delay: {
        const m = String(root.entry.command).match(/^\s*sleep\s+([\d.]+)\s*&&/);
        return m ? m[1] : "";
    }
    readonly property color colContent: root.on ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
    readonly property bool engaged: cardHover.hovered

    radius: Appearance.rounding.verylarge
    color: root.on ? (root.engaged ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimaryContainer, 0.92) : Appearance.colors.colPrimaryContainer)
        : (root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    HoverHandler { id: cardHover }
    // Under the content, so the switch and the actions keep their clicks
    TapHandler {
        onTapped: root.editRequested()
    }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 18
            rightMargin: 16
            topMargin: 16
            bottomMargin: 12
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                implicitWidth: 48
                implicitHeight: 48
                MaterialShapeWrappedMaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.app
                    text: root.entry.kind === "lua" ? "code" : "terminal"
                    iconSize: 22
                    padding: 13
                    fill: root.on ? 1 : 0
                    shape: root.on ? root.shape : MaterialShape.Shape.Circle
                    color: root.on ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                    colSymbol: root.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
                MaterialShape {
                    anchors.fill: parent
                    visible: !!root.app
                    shape: root.on ? root.shape : MaterialShape.Shape.Circle
                    color: root.on ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 28
                        source: root.app ? Quickshell.iconPath(root.app.icon, "application-x-executable") : ""
                        opacity: root.on ? 1 : 0.6
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: StartupManager.displayName(root.entry) || (root.app?.name ?? "")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: root.colContent
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: !root.on ? Translation.tr("Off")
                        : root.delay !== "" ? Translation.tr("At login, after %1 s").arg(root.delay)
                        : Translation.tr("At login")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: root.colContent
                    opacity: 0.75
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                Layout.alignment: Qt.AlignTop
                sizeScale: 0.85
                checked: root.on
                enabled: !StartupManager.busy
                inactiveColor: Appearance.colors.colSurfaceContainerHighest
                onToggled: StartupManager.setEnabled(root.entry, checked)
            }
        }

        StyledText {
            id: cmdText
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.entry.command
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colContent
            opacity: root.on ? 0.8 : 0.6
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                visible: !root.entry.editable || root.entry.kind === "lua"
                implicitHeight: 26
                implicitWidth: luaRow.implicitWidth + 16
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize(root.colContent, 0.88)
                RowLayout {
                    id: luaRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: "data_object"
                        iconSize: 14
                        color: root.colContent
                    }
                    StyledText {
                        text: root.entry.editable ? Translation.tr("Lua") : Translation.tr("Lua code · edit in file")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: root.colContent
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            CircleAction {
                symbol: "play_arrow"
                tip: Translation.tr("Run now")
                colContent: root.colContent
                colFill: ColorUtils.transparentize(root.colContent, 0.9)
                enabled: root.entry.editable
                onClicked: StartupManager.runNow(root.entry.command)
            }
            CircleAction {
                symbol: root.entry.editable ? "edit" : "open_in_new"
                tip: root.entry.editable ? Translation.tr("Edit") : Translation.tr("Open execs.lua")
                colContent: root.colContent
                colFill: ColorUtils.transparentize(root.colContent, 0.9)
                onClicked: root.editRequested()
            }
            // Two clicks: the first arms it (error colours) for 3 s
            CircleAction {
                id: removeButton
                property bool armed: false
                symbol: armed ? "delete_forever" : "delete"
                tip: armed ? Translation.tr("Click again to remove") : Translation.tr("Remove from startup")
                colContent: armed ? Appearance.colors.colOnError : root.colContent
                colFill: armed ? Appearance.colors.colError : ColorUtils.transparentize(root.colContent, 0.9)
                enabled: !StartupManager.busy
                onClicked: {
                    if (!armed) {
                        armed = true;
                        disarm.restart();
                        return;
                    }
                    armed = false;
                    StartupManager.remove(root.entry);
                }
                Timer {
                    id: disarm
                    interval: 3000
                    onTriggered: removeButton.armed = false
                }
            }
        }
    }
}
