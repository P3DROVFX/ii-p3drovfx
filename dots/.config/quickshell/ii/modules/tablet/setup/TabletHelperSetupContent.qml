pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * What the first launch says about the two helpers that are not there yet.
 *
 * One row per helper, each carrying its own state — missing, building, built, failed —
 * because the two build independently, and one succeeding while the other fails is
 * exactly the case a single shared status line would hide.
 */
ColumnLayout {
    id: root

    /// Which helpers this window is about. Latched by the owner — see TabletHelperSetup.
    property bool tracksOsk: false
    property bool tracksGestures: false

    readonly property bool oskMissing: root.tracksOsk && !OskAutoShow.binaryExists
    readonly property bool gesturesMissing: root.tracksGestures && !TouchGestureService.binaryExists

    signal dismissed()

    readonly property bool anyBuilding: OskAutoShow.building || TouchGestureService.building
    readonly property bool bothMissing: root.oskMissing && root.gesturesMissing
    readonly property bool cargoAvailable: OskAutoShow.cargoAvailable
    /// Every helper this window is about is now built.
    readonly property bool allDone: !root.anyBuilding
        && !root.oskMissing && !root.gesturesMissing
    readonly property bool anyFailed: OskAutoShow.buildResult === "failed"
        || TouchGestureService.buildResult === "failed"

    spacing: 0

    // The window is a normal client, so a tiling compositor may hand it a great deal
    // more height than the content needs. Equal spacers above and below settle the block
    // near the middle at any size, while the buttons stay where a dialog's buttons go.
    Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

    MaterialSymbol {
        Layout.alignment: Qt.AlignHCenter
        text: root.allDone ? "check_circle" : (root.anyFailed ? "error" : "handyman")
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
                return Translation.tr("Building…");
            // Counts what is actually missing right now, not what the window tracks: a
            // second row that has already been built must not be counted as work left.
            return root.bothMissing
                ? Translation.tr("Two helpers still to build")
                : Translation.tr("One helper still to build");
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
            ? Translation.tr("Tapping a text field now raises the keyboard, and edge swipes now work. Nothing else to do — this window will not come back.")
            : Translation.tr("Touch and pen support run on small native helpers that ship as source. Until they are compiled, tapping a text field will not raise the keyboard and edge gestures will not fire — with nothing on screen saying why.")
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 22
        spacing: 8

        TabletHelperSetupRow {
            Layout.fillWidth: true
            visible: root.tracksOsk
            symbol: "keyboard"
            title: Translation.tr("On-screen keyboard")
            description: Translation.tr("Raises the keyboard when a finger or pen taps a text field.")
            built: OskAutoShow.binaryExists
            building: OskAutoShow.building
            failed: OskAutoShow.buildResult === "failed"
            failureText: OskAutoShow.buildOutput
            progressText: OskAutoShow.buildProgress
            unitsCompiled: OskAutoShow.buildUnits
            elapsedSeconds: OskAutoShow.buildSeconds
            progress: OskAutoShow.buildProgressValue
            onBuildRequested: OskAutoShow.buildHelper()
        }

        TabletHelperSetupRow {
            Layout.fillWidth: true
            visible: root.tracksGestures
            symbol: "swipe"
            title: Translation.tr("Touch gestures")
            description: Translation.tr("Edge swipes for the shade, the app drawer, Back and Recents.")
            built: TouchGestureService.binaryExists
            building: TouchGestureService.building
            failed: TouchGestureService.buildResult === "failed"
            failureText: TouchGestureService.buildOutput
            progressText: TouchGestureService.buildProgress
            unitsCompiled: TouchGestureService.buildUnits
            elapsedSeconds: TouchGestureService.buildSeconds
            progress: TouchGestureService.buildProgressValue
            onBuildRequested: TouchGestureService.buildHelper()
        }
    }

    // Without a toolchain the buttons above point at a build that cannot run, which is
    // worse than saying plainly what is missing.
    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: 12
        visible: !root.cargoAvailable
        materialIcon: "info"
        text: Translation.tr("Rust and cargo are not installed, so these cannot be built here. Install the Rust toolchain, then open this again from Settings › Tablet.")
    }

    Item { Layout.fillHeight: true; Layout.preferredHeight: 1 }

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 12
        visible: root.anyBuilding
        text: Translation.tr("This takes about a minute the first time. You can close this window — the helper starts on its own when it finishes.")
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        DialogButton {
            // Never disabled while a build runs. A window whose only way out is greyed
            // out for a minute is a window the user is stuck in, and cargo on a cold
            // cache takes considerably longer than a minute. Closing does not stop the
            // build: it finishes, and the daemon starts on its own.
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

        RippleButtonWithIcon {
            visible: !root.allDone && root.cargoAvailable && root.bothMissing
            buttonRadius: Appearance.rounding.small
            materialIcon: root.anyBuilding ? "hourglass_top" : "build"
            mainText: root.anyBuilding
                ? Translation.tr("Building…") : Translation.tr("Build both")
            enabled: !root.anyBuilding
            colBackground: Appearance.colors.colPrimary
            colText: Appearance.m3colors.m3onPrimary
            onClicked: {
                if (root.oskMissing)
                    OskAutoShow.buildHelper();
                if (root.gesturesMissing)
                    TouchGestureService.buildHelper();
            }
        }
    }
}
