import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * Power & Battery → Thermals & fans. Live sensors as the hero, the fan curve as the main
 * pane, turbo and TCC offset as tiles. Everything is applied by ii-fand (root daemon,
 * scripts/thermal/); this page only reads its status and asks it through pkexec.
 */
ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    Component.onCompleted: FanControl.watchers += 1
    Component.onDestruction: {
        FanControl.watchers -= 1;
        if (root.hostWindow && root.hostWindow.leaveGuard === root)
            root.hostWindow.leaveGuard = null;
        // Left without the dialog (Settings closed, a search result…): the draft survives in
        // FanControl, so say where it is instead of letting it sit there unnoticed.
        if (FanControl.curveDirty && !root.leaveAllowed)
            Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "dialog-warning",
                Translation.tr("Fan curve not applied"),
                Translation.tr("Your edited curve is kept. Open Settings → Power & Battery → Thermals & fans to apply or revert it.")]);
    }

    // ── leave guard: SettingsWindow asks before navigating away ──
    readonly property var hostWindow: root.QsWindow.window
    onHostWindowChanged: if (root.hostWindow && root.hostWindow.leaveGuard !== undefined) root.hostWindow.leaveGuard = root
    property bool leaveAllowed: false
    property var pendingLeave: null

    function interceptLeave(proceed): bool {
        if (!FanControl.curveDirty || root.leaveAllowed)
            return false;
        root.pendingLeave = proceed;
        leaveDialog.show = true;
        return true;
    }

    function finishLeave(save: bool) {
        if (save)
            FanControl.applyDraft();
        else
            FanControl.discardDraft();
        leaveDialog.show = false;
        root.leaveAllowed = true;
        const proceed = root.pendingLeave;
        root.pendingLeave = null;
        if (proceed)
            proceed();
        // navigation that did not take this page down: guard the next edit again
        Qt.callLater(() => root.leaveAllowed = false);
    }

    readonly property bool canApply: FanControl.daemonInstalled && !FanControl.busy

    function applyWith(changes) {
        FanControl.apply(Object.assign({}, FanControl.config, changes));
    }

    // ── header ──
    RowLayout {
        visible: root.showBackButton
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: {
                if (!root.interceptLeave(() => root.goBack()))
                    root.goBack();
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Thermals & fans")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── install invitation (only until the daemon exists) ──
    Rectangle {
        Layout.fillWidth: true
        visible: FanControl.ready && !FanControl.daemonInstalled
        implicitHeight: inviteRow.implicitHeight + 40
        radius: Appearance.rounding.verylarge
        color: inviteHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

        HoverHandler { id: inviteHover }

        RowLayout {
            id: inviteRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 20
            }
            spacing: 16

            MaterialShapeWrappedMaterialSymbol {
                text: "download"
                iconSize: 24
                padding: 12
                shape: inviteHover.hovered ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie7Sided
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: Translation.tr("Install the thermal service")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Fans, turbo and TCC need root. ii-fand runs as a system service and this page talks to it; installing replaces g15-fancurve and keeps its curve.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: FanControl.lastError.length > 0
                    text: FanControl.lastError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                    wrapMode: Text.WordWrap
                }
            }

            RippleButton {
                implicitHeight: 40
                implicitWidth: installRow.implicitWidth + 32
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.small
                enabled: !FanControl.busy
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: FanControl.install()
                contentItem: Item {
                    RowLayout {
                        id: installRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol { text: "admin_panel_settings"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnPrimary }
                        StyledText { text: FanControl.busy ? Translation.tr("Installing…") : Translation.tr("Install"); font.weight: Font.DemiBold; color: Appearance.colors.colOnPrimary }
                    }
                }
            }
        }
    }

    // ── a Framework missing a requirement: say which one instead of the generic hint ──
    FrameworkRequirements {
        Layout.fillWidth: true
        visible: FanControl.ready && FanControl.isFramework && !FanControl.frameworkReady
    }

    ThermalHero {
        Layout.fillWidth: true
    }

    FanCurvePane {
        Layout.fillWidth: true
        visible: FanControl.controllable
    }

    // ── processor ──
    AppSettingsSection {
        Layout.topMargin: 12
        visible: FanControl.turboAvailable || FanControl.tccAvailable
        title: Translation.tr("Processor")
        symbol: "memory"
        description: Translation.tr("Both apply at once, without a reboot, and the service keeps them across suspend and restarts.")

        GridLayout {
            id: tiles
            Layout.fillWidth: true
            readonly property int tileHeight: 200
            readonly property int count: (FanControl.turboAvailable ? 1 : 0) + (FanControl.tccAvailable ? 1 : 0)
            columns: width >= 600 ? Math.max(1, count) : 1
            columnSpacing: 12
            rowSpacing: 12

            ColorsFeatureTile {
                Layout.fillWidth: true
                Layout.preferredHeight: tiles.tileHeight
                visible: FanControl.turboAvailable
                enabled: root.canApply
                symbol: "speed"
                shapeOn: MaterialShape.Shape.SoftBurst
                title: Translation.tr("Turbo Boost")
                checked: FanControl.turboEnabled
                summary: FanControl.turboEnabled
                    ? (FanControl.config.turbo === null
                        ? Translation.tr("On, left to the firmware. Turn off to cap the CPU at its base clock: cooler and quieter, slower in bursts.")
                        : Translation.tr("On. Cores boost above their base clock when there is thermal headroom."))
                    : Translation.tr("Off. The CPU stays at its base clock: lower temperatures and fan noise.")
                onToggled: value => root.applyWith({ "turbo": value })

                StyledText {
                    visible: FanControl.config.turbo !== null
                    text: Translation.tr("Use firmware default")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.underline: resetTurboHover.hovered
                    color: FanControl.turboEnabled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    HoverHandler { id: resetTurboHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.applyWith({ "turbo": null }) }
                }
            }

            ColorsFeatureTile {
                id: tccTile
                Layout.fillWidth: true
                Layout.preferredHeight: tiles.tileHeight
                visible: FanControl.tccAvailable
                enabled: root.canApply
                symbol: "thermostat"
                shapeOn: MaterialShape.Shape.Flower
                title: Translation.tr("TCC offset")
                checked: FanControl.tccOffset > 0
                summary: FanControl.tccOffset > 0
                    ? Translation.tr("Throttles at %1 °C instead of %2 °C (offset %3).").arg(FanControl.tjMax - FanControl.tccOffset).arg(FanControl.tjMax).arg(FanControl.tccOffset)
                    : Translation.tr("Off. The CPU runs up to its %1 °C limit before throttling.").arg(FanControl.tjMax)
                onToggled: value => root.applyWith({ "tccOffset": value ? 10 : 0 })

                readonly property color colContent: tccTile.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

                StepButton {
                    symbol: "remove"
                    enabled: root.canApply && FanControl.tccOffset > 0
                    onClicked: root.applyWith({ "tccOffset": Math.max(0, FanControl.tccOffset - 1) })
                }
                StyledText {
                    Layout.minimumWidth: 52
                    horizontalAlignment: Text.AlignHCenter
                    text: `${FanControl.tjMax - FanControl.tccOffset}°`
                    font.family: Appearance.font.family.main
                    font.variableAxes: ({ "wght": 760, "wdth": 50, "ROND": 100 })
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: tccTile.colContent
                }
                StepButton {
                    symbol: "add"
                    enabled: root.canApply && FanControl.tccOffset < FanControl.tccMax
                    onClicked: root.applyWith({ "tccOffset": Math.min(FanControl.tccMax, FanControl.tccOffset + 1) })
                }

            }
        }
    }

    // ── advanced ──
    AppSettingsSection {
        Layout.topMargin: 12
        visible: FanControl.controllable
        title: Translation.tr("Curve behaviour")
        symbol: "tune"

        AppStepperRow {
            symbol: "swap_vert"
            title: Translation.tr("Hysteresis (°C)")
            description: Translation.tr("Fans slow down only after the temperature drops this far, so they don't hunt up and down")
            enabled: root.canApply
            value: FanControl.config.hysteresis
            from: 0
            to: 15
            onMoved: v => root.applyWith({ "hysteresis": v })
        }
        AppStepperRow {
            symbol: "timer"
            title: Translation.tr("Update interval (s)")
            enabled: root.canApply
            value: FanControl.config.interval
            from: 1
            to: 10
            onMoved: v => root.applyWith({ "interval": v })
        }
        AppSettingRow {
            symbol: "developer_board"
            title: Translation.tr("Control method")
            description: FanControl.backend === "alienware_wmi"
                ? Translation.tr("alienware-wmi fan boost (kernel driver)")
                : FanControl.backend === "hwmon_pwm"
                    ? Translation.tr("hwmon PWM, manual mode")
                    : FanControl.backend === "framework_ec"
                        ? Translation.tr("Framework EC duty through framework_tool")
                        : Translation.tr("None: the firmware keeps the fans")
            StyledText {
                text: FanControl.daemonRunning ? Translation.tr("Service running") : Translation.tr("Service stopped")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ── no control at all ──
    StyledText {
        Layout.fillWidth: true
        visible: FanControl.ready && !FanControl.controllable && !FanControl.isFramework
        text: Translation.tr("No writable fan interface was found. Desktop boards usually need their Super I/O driver (nct6775, it87); ThinkPads need thinkpad_acpi with fan_control=1; other laptops may only offer the power profiles in Quick Settings.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.WordWrap
    }

    // ── Revert / Apply: FABs in the corner, only while the curve has unapplied edits ──
    // Parented to the sub-page loader so they stay put while the page scrolls.
    Item {
        id: fabHost
        parent: root.parent ?? root
        anchors.fill: parent
        z: 50

        FadeLoader {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 25
            shown: FanControl.curveDirty

            sourceComponent: RowLayout {
                spacing: 12

                FloatingActionButton {
                    iconText: "undo"
                    buttonText: Translation.tr("Revert")
                    expanded: hovered
                    enabled: !FanControl.busy
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    colOnBackground: Appearance.colors.colOnSurface
                    onClicked: FanControl.discardDraft()

                    StyledToolTip {
                        text: Translation.tr("Go back to the curve the service is running")
                    }
                }

                FloatingActionButton {
                    iconText: FanControl.busy ? "hourglass_top" : "check"
                    buttonText: Translation.tr("Apply curve")
                    expanded: true
                    enabled: !FanControl.busy && FanControl.daemonInstalled
                    onClicked: FanControl.applyDraft()

                    StyledToolTip {
                        text: Translation.tr("Send the curve to ii-fand; it takes effect on the next reading")
                    }
                }
            }
        }
    }

    WindowDialog {
        id: leaveDialog
        parent: root.parent ?? root
        anchors.fill: parent
        show: false
        backgroundWidth: 400
        z: 100
        onDismiss: {
            show = false;
            root.pendingLeave = null;
        }

        WindowDialogTitle {
            text: Translation.tr("Apply the fan curve?")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            text: Translation.tr("The curve you edited hasn't been applied yet. The fans keep following the previous one until you apply it.")
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: Translation.tr("Keep editing")
                onClicked: leaveDialog.dismiss()
            }
            Item {
                Layout.fillWidth: true
            }
            DialogButton {
                buttonText: Translation.tr("Discard")
                onClicked: root.finishLeave(false)
            }
            DialogButton {
                buttonText: Translation.tr("Apply")
                enabled: FanControl.daemonInstalled && !FanControl.busy
                onClicked: root.finishLeave(true)
            }
        }
    }

    component StepButton: RippleButton {
        id: stepButton
        property string symbol
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: height / 2
        buttonRadiusPressed: Appearance.rounding.small
        opacity: enabled ? 1 : 0.4
        colBackground: ColorUtils.applyAlpha(tccTile.colContent, 0.1)
        colBackgroundHover: ColorUtils.applyAlpha(tccTile.colContent, 0.18)
        colRipple: ColorUtils.applyAlpha(tccTile.colContent, 0.26)
        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: stepButton.symbol
                iconSize: Appearance.font.pixelSize.large
                color: tccTile.colContent
            }
        }
    }
}
