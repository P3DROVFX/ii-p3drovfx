import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.island
import qs.modules.settings.configs.lockscreen

/**
 * The workspace compactor in one card: what it does, acted out; how to build and
 * call it; and, with Auto-Compact on, when it runs by itself.
 */
Rectangle {
    id: root

    readonly property var cfg: Config.options.bar.workspaces

    readonly property real padding: 20
    readonly property real stageHeight: 76
    readonly property int delayFrom: 100
    readonly property int delayTo: 5000
    readonly property int delayStep: 100

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                text: "compress"
                iconSize: 22
                padding: 11
                fill: 1
                shape: root.cfg.autoCompact ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie9Sided
                color: root.cfg.autoCompact ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
                colSymbol: root.cfg.autoCompact ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Workspace Compactor")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.cfg.autoCompact
                        ? Translation.tr("Auto-Compact closes gaps %1 ms after they appear").arg(root.cfg.autoCompactDelay)
                        : Translation.tr("Closes the gaps when you press the keybind")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            StyledText {
                text: Translation.tr("Auto-Compact")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledSwitch {
                id: autoSwitch
                checked: root.cfg.autoCompact
                onToggled: {
                    root.cfg.autoCompact = autoSwitch.checked;
                    autoSwitch.checked = Qt.binding(() => root.cfg.autoCompact);
                }
                StyledToolTip {
                    text: Translation.tr("Compact automatically whenever closing or moving a window leaves a gap on the focused monitor. The keybind keeps working either way.")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.stageHeight
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            WorkspacesCompactorDiagram {
                anchors.centerIn: parent
                running: root.visible
            }
        }

        HelperCodeBox {
            Layout.fillWidth: true
            icon: "terminal"
            title: Translation.tr("Build it once")
            text: Translation.tr("Pulls the focused monitor's occupied workspaces down to 1..N with no gaps. The workspaces themselves are renumbered, so every window keeps its exact place. Rust is the only requirement.")
            codeSnippet: `${Directories.rustHelpersScriptPath.replace(FileUtils.trimFileProtocol(Directories.home), "~")} build workspace_compactor`
            snippetWrapMode: Text.Wrap
        }

        KeyboardShortcutBox {
            Layout.fillWidth: true
            text: Translation.tr("Compact workspaces into 1..N")
            keys: ["Ctrl", "Super", "C"]
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.cfg.autoCompact
            spacing: 14

            LockSliderRow {
                Layout.fillWidth: true
                symbol: "timer"
                label: Translation.tr("Auto-Compact delay")
                activeShape: MaterialShape.Shape.Cookie12Sided
                from: root.delayFrom
                to: root.delayTo
                stepSize: root.delayStep
                value: root.cfg.autoCompactDelay
                format: v => Translation.tr("%1 ms").arg(Math.round(v))
                onMoved: v => root.cfg.autoCompactDelay = Math.round(v)
            }

            StyledText {
                text: Translation.tr("When the gap is the current workspace")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            IslandSegmentedToggle {
                Layout.fillWidth: true
                labelMinWidth: 120
                currentValue: root.cfg.autoCompactCurrentGap
                options: [
                    { "value": "onswitch", "label": Translation.tr("Compact on switch"), "icon": "move_group", "shape": "Cookie9Sided" },
                    { "value": "immediate", "label": Translation.tr("Immediately"), "icon": "bolt", "shape": "SoftBurst" },
                    { "value": "never", "label": Translation.tr("Never"), "icon": "block", "shape": "Circle" }
                ]
                onSelected: value => root.cfg.autoCompactCurrentGap = value
            }
        }
    }
}
