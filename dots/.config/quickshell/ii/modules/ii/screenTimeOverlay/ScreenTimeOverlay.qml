pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.usage.limits
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The block screen: shown when a spent limit or a running focus schedule finds one of
 * its apps open. A scrim takes the input over the whole output and a centred card offers
 * the only ways on — close the app, lock the screen, or take more time (behind the PIN
 * when the rule is strict). Built only while ScreenTimeLimits names a block.
 */
Scope {
    id: root

    readonly property var block: ScreenTimeLimits.activeBlock

    LazyLoader {
        active: root.block !== null && !GlobalStates.screenLocked

        component: PanelWindow {
            id: window

            readonly property var block: root.block ?? ({})
            readonly property string blockId: root.block ? root.block.ruleId + "|" + root.block.key : ""
            readonly property var rule: window.block.rule ?? null
            readonly property string kind: window.block.kind ?? "limit"
            readonly property bool isSchedule: window.kind === "schedule"
            readonly property bool isTotal: window.kind === "total"
            readonly property string appKey: window.block.key ?? ""
            readonly property string appName: window.appKey.length > 0 ? AppStats.displayName(window.appKey) : ""
            readonly property bool strict: window.rule?.strict === true && ScreenTimeLimits.hasPin
            readonly property real used: window.isSchedule ? 0 : ScreenTimeLimits.usedFor(window.rule)
            readonly property real budget: window.isSchedule ? 0 : ScreenTimeLimits.budgetFor(window.rule)

            readonly property color colHero: window.isSchedule ? Appearance.colors.colTertiaryContainer : Appearance.colors.colErrorContainer
            readonly property color colOnHero: window.isSchedule ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnErrorContainer
            readonly property color colAccent: window.isSchedule ? Appearance.colors.colTertiary : Appearance.colors.colError
            readonly property color colOnAccent: window.isSchedule ? Appearance.colors.colOnTertiary : Appearance.colors.colOnError

            /// The extra-time choice waiting on the PIN, or 0.
            property int pendingMinutes: 0
            property bool pinWrong: false
            property int secondsLeft: ScreenTimeLimits.autoCloseSeconds
            property bool shown: false

            readonly property var grants: window.isSchedule
                ? [
                    { minutes: 15, label: Translation.tr("15 min"), symbol: "timer" },
                    { minutes: 60, label: Translation.tr("1 hour"), symbol: "hourglass_top" },
                    { minutes: -1, label: Translation.tr("Rest of today"), symbol: "event_available" }
                ]
                : [
                    { minutes: 1, label: Translation.tr("1 min"), symbol: "timer" },
                    { minutes: 15, label: Translation.tr("15 min"), symbol: "more_time" },
                    { minutes: -1, label: Translation.tr("Rest of today"), symbol: "event_available" }
                ]

            function titleText(): string {
                if (window.isSchedule)
                    return Translation.tr("%1 is on").arg(String(window.rule?.name ?? "").length > 0 ? window.rule.name : Translation.tr("Focus time"));
                return window.isTotal ? Translation.tr("Screen time is up") : Translation.tr("Time's up");
            }

            function bodyText(): string {
                if (window.isSchedule)
                    return Translation.tr("%1 is paused until %2.").arg(window.appName).arg(window.rule?.end ?? "");
                if (window.isTotal)
                    return Translation.tr("You reached today's limit of %1. %2 is covered until tomorrow.").arg(ScreenTimeLimits.formatMinutes(window.rule?.minutes ?? 0)).arg(window.appName);
                if ((window.rule?.keys ?? []).length > 1)
                    return Translation.tr("%1 shares the %2 limit of %3, which is used up for today.").arg(window.appName).arg(ScreenTimeLimits.ruleName(window.rule)).arg(ScreenTimeLimits.formatMinutes(window.rule?.minutes ?? 0));
                return Translation.tr("%1 reached its daily limit of %2.").arg(window.appName).arg(ScreenTimeLimits.formatMinutes(window.rule?.minutes ?? 0));
            }

            function requestGrant(minutes: int): void {
                if (window.strict) {
                    window.pendingMinutes = minutes;
                    window.pinWrong = false;
                    Qt.callLater(() => pinField.focusInput());
                    return;
                }
                ScreenTimeLimits.grant(window.block.ruleId, minutes, "");
            }

            function confirmPin(): void {
                if (!ScreenTimeLimits.grant(window.block.ruleId, window.pendingMinutes, pinField.text)) {
                    pinField.text = "";
                    window.pinWrong = true;
                    pinField.focusInput();
                }
            }

            onBlockIdChanged: {
                window.pendingMinutes = 0;
                window.pinWrong = false;
                window.secondsLeft = ScreenTimeLimits.autoCloseSeconds;
            }

            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:screenTime"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Component.onCompleted: Qt.callLater(() => window.shown = true)

            // Counts down while nobody is typing the PIN, then closes the app itself.
            Timer {
                interval: 1000
                repeat: true
                running: ScreenTimeLimits.autoCloseSeconds > 0 && window.blockId.length > 0 && window.pendingMinutes === 0
                onTriggered: {
                    window.secondsLeft -= 1;
                    if (window.secondsLeft <= 0)
                        ScreenTimeLimits.closeApp(window.appKey);
                }
            }

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.35)
                opacity: window.shown ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // Swallows every click: the app behind is not to be used from here.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onWheel: wheel => wheel.accepted = true
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                anchors.verticalCenterOffset: window.shown || ClockStyle.reducedMotion ? 0 : ClockStyle.enterOffset
                width: Math.min(540, (window.screen?.width ?? 1200) - 64)
                implicitHeight: cardColumn.implicitHeight + 24
                radius: Appearance.rounding.verylarge
                color: Appearance.m3colors.m3surfaceContainerHigh
                opacity: window.shown ? 1 : 0
                focus: true

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.verticalCenterOffset {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                Keys.onEscapePressed: event => {
                    if (window.pendingMinutes !== 0) {
                        window.pendingMinutes = 0;
                        card.forceActiveFocus();
                    }
                    event.accepted = true;
                }

                ColumnLayout {
                    id: cardColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 12

                    // ── Hero ────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: heroColumn.implicitHeight + 48
                        radius: Appearance.rounding.large
                        color: window.colHero

                        ColumnLayout {
                            id: heroColumn
                            anchors.centerIn: parent
                            width: parent.width - 48
                            spacing: 14

                            // The app on a big scalloped shape; a draining ring when the
                            // block screen will close the app on its own.
                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 148
                                implicitHeight: 148

                                ClockProgressRing {
                                    anchors.fill: parent
                                    visible: ScreenTimeLimits.autoCloseSeconds > 0
                                    value: ScreenTimeLimits.autoCloseSeconds > 0 ? window.secondsLeft / ScreenTimeLimits.autoCloseSeconds : 0
                                    tickDuration: 1000
                                    thickness: 8
                                    wavy: window.pendingMinutes === 0
                                    animateWave: true
                                    colIndicator: window.colAccent
                                    colTrack: ColorUtils.applyAlpha(window.colOnHero, 0.14)
                                }

                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: 116
                                    shapeString: window.isSchedule ? "Cookie9Sided" : "Cookie12Sided"
                                    color: window.colAccent
                                    rotation: window.shown ? 0 : -30
                                    Behavior on rotation {
                                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                    }
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 72
                                    height: 72
                                    radius: 36
                                    color: window.colHero

                                    LimitsAppIcon {
                                        anchors.centerIn: parent
                                        size: 48
                                        appKey: window.appKey
                                        fallbackSymbol: window.isTotal ? "devices" : "apps"
                                        colFallback: window.colOnHero
                                    }
                                }

                                MaterialShapeWrappedMaterialSymbol {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 6
                                    text: window.isSchedule ? "bedtime" : "hourglass_bottom"
                                    iconSize: 18
                                    padding: 8
                                    shape: MaterialShape.Shape.Cookie7Sided
                                    color: window.colOnHero
                                    colSymbol: window.colHero
                                    fill: 1
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: window.titleText()
                                wrapMode: Text.WordWrap
                                font.family: ClockStyle.fontTitle
                                font.variableAxes: ClockStyle.axesTitle
                                font.pixelSize: 34
                                color: window.colOnHero
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: window.bodyText()
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: window.colOnHero
                                opacity: 0.9
                            }

                            // Today's figures in the clock's condensed digits.
                            RowLayout {
                                visible: !window.isSchedule
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 10

                                Repeater {
                                    model: window.isSchedule ? [] : [
                                        { value: ScreenTimeLimits.formatSeconds(window.used), label: Translation.tr("used today") },
                                        { value: ScreenTimeLimits.formatSeconds(window.budget), label: Translation.tr("allowed") },
                                        { value: String(ScreenTimeLimits.dayState.ignores ?? 0), label: Translation.tr("extensions") }
                                    ]

                                    Rectangle {
                                        id: figure
                                        required property var modelData
                                        implicitWidth: figureColumn.implicitWidth + 28
                                        implicitHeight: figureColumn.implicitHeight + 16
                                        radius: Appearance.rounding.normal
                                        color: ColorUtils.applyAlpha(window.colOnHero, 0.1)

                                        ColumnLayout {
                                            id: figureColumn
                                            anchors.centerIn: parent
                                            spacing: 0

                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: figure.modelData.value
                                                font.family: ClockStyle.fontMain
                                                font.variableAxes: ClockStyle.axesDigitsBold
                                                font.pixelSize: 24
                                                color: window.colOnHero
                                            }
                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: figure.modelData.label
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: window.colOnHero
                                                opacity: 0.8
                                            }
                                        }
                                    }
                                }
                            }

                            StyledText {
                                visible: ScreenTimeLimits.autoCloseSeconds > 0
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: window.pendingMinutes !== 0 ? Translation.tr("Countdown paused")
                                    : Translation.tr("Closing in %1 s").arg(String(Math.max(0, window.secondsLeft)))
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: window.colOnHero
                            }
                        }
                    }

                    // ── The way out ─────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 8

                        LimitsTintButton {
                            Layout.fillWidth: true
                            height_: 56
                            solid: true
                            colContent: window.colAccent
                            colSolidContent: window.colOnAccent
                            symbol: "close"
                            label: window.appName.length > 0 ? Translation.tr("Close %1").arg(window.appName) : Translation.tr("Close app")
                            onClicked: ScreenTimeLimits.closeApp(window.appKey)
                        }

                        LimitsTintButton {
                            visible: window.isTotal || (window.isSchedule && window.rule?.allApps === true)
                            Layout.fillWidth: true
                            height_: 52
                            colContent: Appearance.colors.colOnSurface
                            symbol: "lock"
                            label: Translation.tr("Lock screen")
                            onClicked: ScreenTimeLimits.lockScreen()
                        }
                    }

                    StyledText {
                        Layout.leftMargin: 12
                        Layout.topMargin: 4
                        text: window.isSchedule ? Translation.tr("Need it now?") : Translation.tr("Need more time?")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 8

                        Repeater {
                            model: window.grants

                            RippleButton {
                                id: grantButton
                                required property var modelData
                                readonly property bool pending: window.pendingMinutes === grantButton.modelData.minutes
                                Layout.fillWidth: true
                                implicitHeight: 48
                                buttonRadius: grantButton.pending ? Appearance.rounding.small : Appearance.rounding.full
                                buttonRadiusPressed: Appearance.rounding.small
                                colBackground: grantButton.pending ? Appearance.colors.colSecondaryContainer : Appearance.m3colors.m3surfaceContainerHighest
                                colBackgroundHover: grantButton.pending ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                onClicked: window.requestGrant(grantButton.modelData.minutes)

                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        MaterialSymbol {
                                            text: window.strict ? "lock" : grantButton.modelData.symbol
                                            iconSize: Appearance.font.pixelSize.normal
                                            fill: window.strict ? 1 : 0
                                            color: grantButton.pending ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                                        }
                                        StyledText {
                                            text: grantButton.modelData.label
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: grantButton.pending ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The PIN, only once a strict rule was asked for more time.
                    RowLayout {
                        visible: window.pendingMinutes !== 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 8

                        ClockFormField {
                            id: pinField
                            Layout.fillWidth: true
                            symbol: window.pinWrong ? "lock_reset" : "password"
                            shapeKind: MaterialShape.Shape.Cookie4Sided
                            caption: window.pinWrong ? Translation.tr("Wrong PIN, try again") : Translation.tr("PIN")
                            placeholder: Translation.tr("Enter your PIN")
                            input.echoMode: TextInput.Password
                            onAccepted: window.confirmPin()
                            onTextChanged: if (text.length > 0) window.pinWrong = false
                        }

                        LimitsTintButton {
                            height_: 56
                            solid: true
                            colContent: Appearance.colors.colPrimary
                            colSolidContent: Appearance.colors.colOnPrimary
                            symbol: "check"
                            label: Translation.tr("Confirm")
                            enabled: pinField.text.length > 0
                            onClicked: window.confirmPin()
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Daily limits · change them in App usage")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
