import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * An expressive Material 3 card configuring the Always On Display (OLED Saver).
 * Includes an interactive header with keybind hint (Super + R), master toggle,
 * anti burn-in pixel shift toggle, and sliders for idle timeout and cursor hide delay.
 */
Rectangle {
    id: root

    readonly property bool enabledAod: Config.options.oledSaver?.enable ?? true
    readonly property bool antiBurnIn: Config.options.oledSaver?.antiBurnIn ?? true
    readonly property int lockTimeout: Config.options.oledSaver?.lockTimeout ?? 10
    readonly property int cursorHideDelay: Config.options.oledSaver?.cursorHideDelay ?? 5

    readonly property int padding: 20
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    implicitHeight: mainColumn.implicitHeight + root.padding * 2

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    ColumnLayout {
        id: mainColumn
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12

        // ── Card Header ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: "dark_mode"
                iconSize: 22
                padding: 11
                fill: root.enabledAod ? 1 : 0
                shape: root.enabledAod ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: root.enabledAod ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                colSymbol: root.enabledAod ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Always On Display")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: !root.enabledAod
                        ? Translation.tr("Disabled")
                        : (root.lockTimeout > 0
                            ? Translation.tr("Active · Idle timeout %1m · Grayscale widgets").arg(root.lockTimeout)
                            : Translation.tr("Active · Shortcut only · Grayscale widgets"))
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            // Keybind Hint Pill
            Rectangle {
                id: keybindBadge
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 36
                implicitWidth: keybindRow.implicitWidth + 24
                radius: height / 2
                color: keybindMouseArea.containsMouse
                    ? Appearance.colors.colSecondaryContainerHover
                    : Appearance.colors.colSecondaryContainer
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: keybindRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "keyboard"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    KeyboardKey {
                        key: "Super"
                        pixelSize: Appearance.font.pixelSize.smallest
                        horizontalPadding: 6
                        verticalPadding: 2
                        borderRadius: 4
                    }

                    StyledText {
                        text: "+"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    KeyboardKey {
                        key: "R"
                        pixelSize: Appearance.font.pixelSize.smallest
                        horizontalPadding: 6
                        verticalPadding: 2
                        borderRadius: 4
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Super + R toggles Always On Display immediately on the focused monitor")
                }

                MouseArea {
                    id: keybindMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const name = Hyprland.focusedMonitor?.name ?? Quickshell.primaryScreen?.name;
                        if (!name) return;
                        const monitors = GlobalStates.oledSaverMonitors ?? [];
                        GlobalStates.oledSaverMonitors = monitors.includes(name)
                            ? monitors.filter(n => n !== name)
                            : [...monitors, name];
                    }
                }
            }

            // Master Switch
            StyledSwitch {
                id: masterSwitch
                Layout.alignment: Qt.AlignVCenter
                sizeScale: 0.9
                checked: root.enabledAod
                activeColor: Appearance.colors.colPrimary
                activeThumbColor: Appearance.colors.colOnPrimary
                inactiveColor: Appearance.colors.colSurfaceContainerHighest

                Binding {
                    target: masterSwitch
                    property: "checked"
                    value: root.enabledAod
                }

                onToggled: {
                    if (Config.ready && Config.options.oledSaver) {
                        Config.options.oledSaver.enable = checked;
                        if (!checked)
                            GlobalStates.oledSaverMonitors = [];
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Enable or disable Always On Display")
                }
            }
        }

        // ── Sub-controls ─────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            opacity: root.enabledAod ? 1.0 : 0.45
            enabled: root.enabledAod

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Anti Burn-in (Pixel shift) Row
            Rectangle {
                id: burnInRow
                Layout.fillWidth: true
                implicitHeight: Math.max(64, burnInLayout.implicitHeight + 24)
                radius: Appearance.rounding.large
                color: burnInHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                HoverHandler {
                    id: burnInHover
                    cursorShape: root.enabledAod ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                TapHandler {
                    enabled: root.enabledAod
                    onTapped: {
                        if (Config.ready && Config.options.oledSaver) {
                            Config.options.oledSaver.antiBurnIn = !Config.options.oledSaver.antiBurnIn;
                        }
                    }
                }

                RowLayout {
                    id: burnInLayout
                    anchors {
                        fill: parent
                        leftMargin: 16
                        rightMargin: 16
                        topMargin: 12
                        bottomMargin: 12
                    }
                    spacing: 14

                    MaterialShapeWrappedMaterialSymbol {
                        text: "motion_photos_on"
                        iconSize: 20
                        padding: 8
                        fill: root.antiBurnIn ? 1 : 0
                        shape: root.antiBurnIn ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Circle
                        color: root.antiBurnIn ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                        colSymbol: root.antiBurnIn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            spacing: 8
                            StyledText {
                                text: Translation.tr("Anti burn-in pixel shift")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                            }

                            Rectangle {
                                visible: root.antiBurnIn
                                implicitHeight: 20
                                implicitWidth: intervalText.implicitWidth + 12
                                radius: height / 2
                                color: Appearance.colors.colPrimaryContainer

                                StyledText {
                                    id: intervalText
                                    anchors.centerIn: parent
                                    text: Translation.tr("Every 1m")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Periodically shifts widgets every minute to prevent OLED screen burn-in")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledSwitch {
                        id: burnInSwitch
                        Layout.alignment: Qt.AlignVCenter
                        sizeScale: 0.85
                        checked: root.antiBurnIn
                        enabled: false
                        activeColor: Appearance.colors.colPrimary
                        activeThumbColor: Appearance.colors.colOnPrimary
                        inactiveColor: Appearance.colors.colSurfaceContainerHighest

                        Binding {
                            target: burnInSwitch
                            property: "checked"
                            value: root.antiBurnIn
                        }

                        StyledToolTip {
                            text: Translation.tr("Periodically shifts widgets every minute to prevent OLED screen burn-in")
                        }
                    }
                }
            }

            // Lock screen idle timeout
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: timeoutColumn.implicitHeight + 24
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: timeoutColumn
                    anchors {
                        fill: parent
                        leftMargin: 16
                        rightMargin: 16
                        topMargin: 12
                        bottomMargin: 12
                    }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        MaterialShapeWrappedMaterialSymbol {
                            text: "lock_clock"
                            iconSize: 20
                            padding: 8
                            fill: root.lockTimeout > 0 ? 1 : 0
                            shape: root.lockTimeout > 0 ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Circle
                            color: root.lockTimeout > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                            colSymbol: root.lockTimeout > 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Lock screen idle timeout")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Inactivity on the lock screen before turning into Always On Display")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }

                        StyledText {
                            text: root.lockTimeout === 0
                                ? Translation.tr("Never")
                                : (root.lockTimeout === 1 ? Translation.tr("1 minute") : Translation.tr("%1 minutes").arg(root.lockTimeout))
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: root.lockTimeout > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                    }

                    StyledSlider {
                        id: timeoutSlider
                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.M
                        from: 0
                        to: 30
                        stepSize: 1
                        value: root.lockTimeout
                        usePercentTooltip: false
                        tooltipContent: Math.round(value) === 0
                            ? Translation.tr("Never (shortcut only)")
                            : (Math.round(value) === 1 ? Translation.tr("1 minute") : Translation.tr("%1 minutes").arg(Math.round(value)))
                        onMoved: {
                            if (Config.ready && Config.options.oledSaver) {
                                Config.options.oledSaver.lockTimeout = Math.round(value);
                            }
                        }
                    }
                }
            }

            // Cursor hide delay
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cursorColumn.implicitHeight + 24
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: cursorColumn
                    anchors {
                        fill: parent
                        leftMargin: 16
                        rightMargin: 16
                        topMargin: 12
                        bottomMargin: 12
                    }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        MaterialShapeWrappedMaterialSymbol {
                            text: "mouse"
                            iconSize: 20
                            padding: 8
                            fill: 1
                            shape: MaterialShape.Shape.Flower
                            color: Appearance.colors.colSecondaryContainer
                            colSymbol: Appearance.colors.colOnSecondaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Cursor hide delay")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Seconds of mouse inactivity before cursor hides on AOD")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }

                        StyledText {
                            text: Translation.tr("%1 s").arg(root.cursorHideDelay)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colPrimary
                        }
                    }

                    StyledSlider {
                        id: cursorSlider
                        Layout.fillWidth: true
                        configuration: StyledSlider.Configuration.M
                        from: 1
                        to: 30
                        stepSize: 1
                        value: root.cursorHideDelay
                        usePercentTooltip: false
                        tooltipContent: Translation.tr("%1 seconds").arg(Math.round(value))
                        onMoved: {
                            if (Config.ready && Config.options.oledSaver) {
                                Config.options.oledSaver.cursorHideDelay = Math.round(value);
                            }
                        }
                    }
                }
            }
        }
    }
}
