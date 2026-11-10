pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * What the app shows before `health_watch` exists.
 *
 * The helper ships as source and is compiled on the machine that runs it, so a fresh
 * install has the window and nothing to fill it. The build is a button (the same
 * machinery as the keyboard and gesture helpers); without a Rust toolchain it is the
 * two commands instead. The page swaps itself for the real ones the moment the binary
 * appears — no restart.
 */
Item {
    id: root

    property bool compact: false
    readonly property string pageSubtitle: Translation.tr("One-time setup")
    readonly property var build: HealthService.helperBuild
    readonly property string commands: `yay -S --needed rust
${Directories.rustHelpersScriptPath} build health_watch`

    // A build finishing in a terminal beside the window is picked up without a click.
    Timer {
        interval: 4000
        repeat: true
        running: !HealthService.binaryPresent && !root.build.building
        onTriggered: HealthService.checkBinary()
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - ClockStyle.gapHuge * 2, 560)
        spacing: ClockStyle.gapLarge

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.build.building ? "construction" : "monitor_heart"
            iconSize: 54
            padding: 34
            shape: root.build.building ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie12Sided
            color: ClockStyle.colPrimaryContainer
            colSymbol: ClockStyle.colOnPrimaryContainer
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Build the System Health helper")
            font.family: ClockStyle.fontTitle
            font.variableAxes: ClockStyle.axesTitle
            font.pixelSize: ClockStyle.textTitle
            color: ClockStyle.colOnSurface
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("A small program watches services, crashes, the journal, drives and firmware as you, without root. It is compiled here from its source, once, in about a minute.")
            wrapMode: Text.Wrap
            font.pixelSize: ClockStyle.textNormal + 1
            color: ClockStyle.colSubtext
        }

        ClockButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.build.cargoAvailable
            enabled: !root.build.building
            variant: "filled"
            symbol: "build"
            label: root.build.building ? Translation.tr("Building…") : Translation.tr("Build now")
            onClicked: root.build.build()
        }

        StyledProgressBar {
            Layout.fillWidth: true
            visible: root.build.building
            value: root.build.progress
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: root.build.building || root.build.buildResult === "failed"
            text: root.build.building ? root.build.progressText : Translation.tr("The build failed. The last lines cargo printed:")
            wrapMode: Text.Wrap
            font.pixelSize: ClockStyle.textSmall
            color: root.build.buildResult === "failed" ? ClockStyle.colError : ClockStyle.colSubtext
        }

        HealthLogBoxLite {
            visible: root.build.buildResult === "failed"
            text: root.build.buildOutput.split("\n").slice(-12).join("\n")
        }

        // Without cargo: the commands, copyable.
        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.build.cargoAvailable
            spacing: ClockStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Rust is not installed. Run these, then come back:")
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnSurface
            }

            HealthLogBoxLite {
                text: root.commands
            }

            ClockButton {
                Layout.alignment: Qt.AlignHCenter
                symbol: "content_copy"
                label: Translation.tr("Copy the commands")
                onClicked: Quickshell.clipboardText = root.commands
            }
        }
    }

    component HealthLogBoxLite: Rectangle {
        property alias text: logText.text
        Layout.fillWidth: true
        implicitHeight: logText.implicitHeight + ClockStyle.gap * 2
        radius: ClockStyle.radiusNormal
        color: ClockStyle.colPane

        TextEdit {
            id: logText
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: ClockStyle.gap
            }
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            font.family: Appearance.font.family.monospace
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colOnSurfaceVariant
        }
    }
}
