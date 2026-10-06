import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Every chosen tool as a labelled button, three to a row. A tool that is on
 * (recording, keyboard open, mic live) sits in primary; the recorder's stop
 * in error. A click closes the panel first, so captures never include it.
 */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var tools: panel.tile?.tools ?? []

    spacing: 8

    GridLayout {
        Layout.fillWidth: true
        visible: panel.tools.length > 0
        columns: 3
        rowSpacing: 6
        columnSpacing: 6

        Repeater {
            model: panel.tools
            delegate: RippleButton {
                id: toolButton
                required property var modelData
                readonly property bool stop: modelData.id === "screenRecord" && modelData.active
                readonly property color ink: toolButton.stop ? ClockStyle.colOnErrorContainer
                    : modelData.active ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 84
                buttonRadius: ClockStyle.radiusLarge
                buttonRadiusPressed: ClockStyle.radiusNormal
                colBackground: toolButton.stop ? ClockStyle.colErrorContainer
                    : modelData.active ? ClockStyle.colPrimaryContainer : ClockStyle.colField
                colBackgroundHover: toolButton.stop ? ClockStyle.colErrorContainerHover
                    : modelData.active ? ClockStyle.colPrimaryContainerHover : ClockStyle.colFieldHover
                colRipple: ColorUtils.applyAlpha(toolButton.ink, 0.2)
                onClicked: panel.tile?.run(modelData.id, false)
                altAction: () => panel.tile?.run(modelData.id, true)
                contentItem: ColumnLayout {
                    spacing: 4
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: toolButton.modelData.symbol
                        iconSize: 26
                        fill: toolButton.modelData.active ? 1 : 0
                        color: toolButton.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: toolButton.modelData.title
                        color: toolButton.ink
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 12
        visible: panel.tools.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: Translation.tr("No tools chosen. Pick them in the widget's settings.")
        color: ClockStyle.colSubtext
    }

    RippleButton {
        Layout.fillWidth: true
        implicitHeight: 40
        buttonRadius: ClockStyle.radiusFull
        colBackground: "transparent"
        colBackgroundHover: ClockStyle.colSurfaceHover
        onClicked: {
            panel.host?.closePanel();
            GlobalStates.openSettingsPage("dock", "widgets/DockUtilitiesConfig.qml");
        }
        contentItem: RowLayout {
            spacing: 6
            Item { Layout.fillWidth: true }
            MaterialSymbol {
                text: "tune"
                iconSize: 18
                color: ClockStyle.colOnSurfaceVariant
            }
            StyledText {
                text: Translation.tr("Choose tools")
                color: ClockStyle.colOnSurfaceVariant
            }
            Item { Layout.fillWidth: true }
        }
    }
}
