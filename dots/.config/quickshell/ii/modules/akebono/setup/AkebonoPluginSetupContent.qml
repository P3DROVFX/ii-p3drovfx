pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.akebono.system
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * What the first launch says about the native pieces that are not there yet.
 *
 * Three rows, one per piece — the qs system plugin (built with cargo), the SDF
 * shaders (compiled with qsb) and the hyprbars compositor plugin (installed with
 * hyprpm). Each row carries its own state: missing, installing, installed, failed
 * — and its own button.
 */
ColumnLayout {
    id: root

    /// The qs system plugin.
    property bool qsPluginBuilt: false
    property bool qsPluginBuilding: false
    property bool qsPluginFailed: false
    property string qsPluginFailure: ""
    property string qsPluginProgressText: ""
    property int qsPluginUnits: 0
    property int qsPluginSeconds: 0
    property real qsPluginProgress: 0
    property bool cargoAvailable: true
    signal qsPluginBuildRequested()

    /// The shaders.
    property bool qsbAvailable: true
    property bool shadersBuilt: false
    property bool shadersBuilding: false
    property bool shadersFailed: false
    property string shadersDetail: ""
    property string shadersFailure: ""
    signal shadersBuildRequested()

    /// hyprbars.
    property bool hyprpmAvailable: true
    property bool hyprbarsReady: false
    property bool hyprbarsInstalling: false
    property bool hyprbarsFailed: false
    property string hyprbarsDetail: ""
    property string hyprbarsFailure: ""
    signal hyprbarsInstallRequested()

    signal dismissed()

    readonly property bool anyBuilding: root.qsPluginBuilding || root.shadersBuilding || root.hyprbarsInstalling

    readonly property bool allDone: root.qsPluginBuilt && root.shadersBuilt && root.hyprbarsReady

    readonly property bool anyFailed: root.qsPluginFailed || root.shadersFailed || root.hyprbarsFailed

    readonly property int pendingCount: (root.qsPluginBuilt ? 0 : 1)
        + (root.shadersBuilt ? 0 : 1)
        + (root.hyprbarsReady ? 0 : 1)

    spacing: 0

    // The window is a normal client, so a tiling compositor may hand it a great deal
    // more height than the content needs. Equal spacers above and below settle the block
    // near the middle at any size, while the buttons stay where a dialog's buttons go.
    Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

    MaterialSymbol {
        Layout.alignment: Qt.AlignHCenter
        text: root.allDone ? "check_circle" : (root.anyFailed ? "error" : "memory")
        iconSize: Math.round(Appearance.font.pixelSize.title * 1.3)
        fill: root.allDone ? 1 : 0
        color: root.anyFailed ? Appearance.colors.colError : Appearance.colors.colPrimary
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 10
        text: {
            if (root.allDone)
                return Translation.tr("Ready to use");
            if (root.anyBuilding)
                return Translation.tr("Installing…");
            return Translation.tr("%1 helper component%2 still to install")
                .arg(root.pendingCount)
                .arg(root.pendingCount === 1 ? "" : "s");
        }
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.title
        font.family: Appearance.font.family.title
        font.weight: 600
        color: Appearance.colors.colOnLayer0
        wrapMode: Text.WordWrap
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        text: root.allDone
            ? Translation.tr("The Akebono family's desks, panels and window decorations are all in place. Nothing else to do; this window will not come back.")
            : Translation.tr("The Akebono panel family depends on a few native pieces that ship as source. Until they are built, the task manager stays blank, the SDF shapes fall back, and windows go without their title bars — with nothing on screen saying why.")
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    AkebonoPluginSetupRow {
        Layout.fillWidth: true
        Layout.topMargin: 22
        symbol: "memory"
        title: Translation.tr("Akebono system plugin")
        description: Translation.tr("Process-table reader for the family's task manager.")
        built: root.qsPluginBuilt
        building: root.qsPluginBuilding
        failed: root.qsPluginFailed
        failureText: root.qsPluginFailure
        progressText: root.qsPluginProgressText
        unitsCompiled: root.qsPluginUnits
        elapsedSeconds: root.qsPluginSeconds
        progress: root.qsPluginProgress
        onBuildRequested: root.qsPluginBuildRequested()
    }

    AkebonoPluginSetupRow {
        Layout.fillWidth: true
        Layout.topMargin: 12
        symbol: "auto_awesome"
        title: Translation.tr("Panel family shaders")
        description: Translation.tr("The SDF shaders behind the family's shapes and wobble, compiled from source with qsb.")
        built: root.shadersBuilt
        building: root.shadersBuilding
        failed: root.shadersFailed
        failureText: root.shadersFailure
        progressText: root.shadersDetail
        showProgress: false
        onBuildRequested: root.shadersBuildRequested()
    }

    AkebonoPluginSetupRow {
        Layout.fillWidth: true
        Layout.topMargin: 12
        symbol: "window"
        title: Translation.tr("hyprbars window decorations")
        description: Translation.tr("macOS-style title bars with close, minimize and float buttons, installed into the compositor with hyprpm.")
        built: root.hyprbarsReady
        building: root.hyprbarsInstalling
        failed: root.hyprbarsFailed
        failureText: root.hyprbarsFailure
        progressText: root.hyprbarsDetail
        showProgress: false
        onBuildRequested: root.hyprbarsInstallRequested()
    }

    // Without a toolchain the button above points at a build that cannot run, which is
    // worse than saying plainly what is missing.
    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: 12
        visible: !root.cargoAvailable
        materialIcon: "info"
        text: Translation.tr("Rust and cargo are not installed, so the system plugin cannot be built here. Install the Rust toolchain, then open this again from Settings.")
    }

    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: 12
        visible: !root.qsbAvailable
        materialIcon: "info"
        text: Translation.tr("Qt 6 shader tools are not installed, so the shaders cannot be compiled here. Install qt6-shadertools, then open this again from Settings.")
    }

    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: 12
        visible: !root.hyprpmAvailable
        materialIcon: "info"
        text: Translation.tr("hyprpm is not installed, so the window decorations are not available. Install hyprpm, then open this again from Settings.")
    }

    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: 12
        visible: root.hyprbarsInstalling
        materialIcon: "schedule"
        text: Translation.tr("The first hyprbars install clones the plugin sources and compiles them into /var/cache/hyprpm, which takes several minutes. One short authorization hands the per-user cache over first, then everything runs as your user — the live lines above show where the build is. Do not close the shell while it runs.")
    }

    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: 12
        visible: root.hyprbarsFailed && root.hyprpmAvailable && !root.hyprbarsInstalling
        materialIcon: "key"
        text: Translation.tr("hyprpm refuses to run as root, so it only needs its per-user cache to be yours. The password prompt on the way is a one-time handover. Done from a terminal it is:")
            + "\ninstall -d -o $USER -g $USER /var/cache/hyprpm/$USER"
            + "\nhyprpm add https://github.com/hyprwm/hyprland-plugins && hyprpm update && hyprpm enable hyprbars"
    }

    Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        DialogButton {
            // Never disabled while a build runs. A window whose only way out is greyed
            // out for a minute is a window the user is stuck in, and a cold build takes
            // considerably longer than a minute. Closing does not stop an install: it
            // finishes, and the pieces land on their own.
            visible: !root.allDone
            buttonText: root.anyBuilding
                ? Translation.tr("Close") : Translation.tr("Do it later")
            onClicked: root.dismissed()
        }

        Item { Layout.fillWidth: true }

        RippleButtonWithIcon {
            // The finished state's only button, and the accent one: there is nothing
            // left to decide.
            visible: root.allDone
            buttonRadius: Appearance.rounding.small
            materialIcon: "done"
            mainText: Translation.tr("Done")
            colBackground: Appearance.colors.colPrimary
            colText: Appearance.m3colors.m3onPrimary
            onClicked: root.dismissed()
        }
    }
}