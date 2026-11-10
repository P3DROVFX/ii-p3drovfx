pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.dynamicIsland.core

/**
 * Settings → Features → Teleprompter.
 *
 * The page leads with the thing itself: the live preview — the island's real
 * faces, demo-reading until a real session takes over — then the script and
 * its transport, then the layout the island is measured by. Every control
 * writes the configuration the service reads, so the preview, the island and
 * this page are three views of one truth.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    readonly property var cfg: Config.options.dynamicIsland.widgets.teleprompter
    readonly property bool islandOn: IslandPolicy.enabled
    readonly property bool sessionOn: Teleprompter.running

    readonly property string statusText: {
        if (!root.sessionOn)
            return Translation.tr("Idle");
        if (Teleprompter.phase === "ready")
            return Translation.tr("Ready");
        if (Teleprompter.phase === "countdown")
            return Translation.tr("Starting in") + " " + Teleprompter.countdownLeft;
        if (Teleprompter.phase === "finished")
            return Translation.tr("Script complete");
        if (Teleprompter.paused)
            return Translation.tr("Paused");
        const s = Math.max(0, Math.round(Teleprompter.remainingSeconds));
        return Translation.tr("Reading · %1 left").arg(Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"));
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Teleprompter")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── The thing itself, live ──────────────────────────────────────────
        TeleprompterPreview {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: !root.islandOn
            materialIcon: "info"
            text: Translation.tr("The Dynamic Island is off: the teleprompter has nowhere to read. Turn the island on and every control here comes alive.")

            RelatedChip {
                pageId: "dynamicIsland"
                label: Translation.tr("Dynamic Island")
            }
        }

        // ── Script and transport ────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: pane.implicitHeight + 40
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: pane
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "subtitles"
                        iconSize: 24
                        padding: 12
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: Translation.tr("Script")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: root.statusText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: 28
                        implicitWidth: statusChipRow.implicitWidth + 20
                        radius: Appearance.rounding.full
                        color: root.sessionOn ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                        RowLayout {
                            id: statusChipRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: root.sessionOn ? ((Teleprompter.phase === "scrolling" || Teleprompter.phase === "countdown") && !Teleprompter.paused ? "pause" : "play_arrow") : "hourglass_empty"
                                iconSize: 14
                                fill: 1
                                color: root.sessionOn ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: root.statusText
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: root.sessionOn ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                MaterialTextArea {
                    Layout.fillWidth: true
                    implicitHeight: 150
                    enabled: root.islandOn
                    placeholderText: Translation.tr("Paste or type what you want to read…")
                    text: root.cfg.text
                    wrapMode: TextEdit.Wrap
                    onTextChanged: Qt.callLater(() => {
                        if (root.cfg.text !== text)
                            root.cfg.text = text;
                    })
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        implicitHeight: 42
                        implicitWidth: startRow.implicitWidth + 32
                        buttonRadius: Appearance.rounding.full
                        enabled: root.islandOn && (root.cfg.text.trim().length > 0 || root.sessionOn)
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colBackgroundActive: Appearance.colors.colPrimaryActive
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        onClicked: root.sessionOn ? Teleprompter.stop() : Teleprompter.start()

                        contentItem: RowLayout {
                            id: startRow
                            spacing: 6
                            MaterialSymbol {
                                text: root.sessionOn ? "stop" : "play_arrow"
                                iconSize: 18
                                fill: 1
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: root.sessionOn ? Translation.tr("Stop") : Translation.tr("Start reading")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }

                    RippleButton {
                        visible: root.sessionOn
                        implicitHeight: 42
                        implicitWidth: 42
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: Teleprompter.togglePause()

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: Teleprompter.paused || Teleprompter.phase === "finished" || Teleprompter.phase === "ready" ? "play_arrow" : "pause"
                            iconSize: 18
                            fill: 1
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledToolTip {
                            text: Teleprompter.phase === "finished" ? Translation.tr("Read again")
                                : Teleprompter.phase === "ready" ? Translation.tr("Start reading")
                                : Teleprompter.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                        }
                    }

                    RippleButton {
                        visible: root.sessionOn
                        implicitHeight: 42
                        implicitWidth: 42
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: Teleprompter.restart()

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "restart_alt"
                            iconSize: 18
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledToolTip {
                            text: Translation.tr("Restart")
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }

        ContentSection {
            icon: "straighten"
            title: Translation.tr("Layout")
            tooltip: Translation.tr("How much of the island the script takes")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Lines on the island")
                    icon: "format_align_left"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: root.cfg.lines
                        onSelected: newValue => root.cfg.lines = newValue
                        options: [
                            { displayName: Translation.tr("1 line"), icon: "looks_one", value: 1 },
                            { displayName: Translation.tr("2 lines"), icon: "looks_two", value: 2 },
                            { displayName: Translation.tr("3 lines"), icon: "looks_3", value: 3 },
                            { displayName: Translation.tr("4 lines"), icon: "looks_4", value: 4 }
                        ]
                    }
                }

                ConfigSlider {
                    buttonIcon: "unfold_more_double"
                    text: Translation.tr("Lines in the hover card")
                    from: 2
                    to: 8
                    stepSize: 1
                    value: root.cfg.expandedLines
                    usePercentTooltip: false
                    onValueChanged: {
                        if (value !== root.cfg.expandedLines)
                            root.cfg.expandedLines = value;
                    }
                }

                ConfigSlider {
                    buttonIcon: "straighten"
                    text: Translation.tr("Island width")
                    from: 360
                    to: 960
                    stepSize: 10
                    value: root.cfg.width
                    usePercentTooltip: false
                    onValueChanged: {
                        if (value !== root.cfg.width)
                            root.cfg.width = value;
                    }
                }

                ConfigSlider {
                    buttonIcon: "format_size"
                    text: Translation.tr("Text size")
                    from: 14
                    to: 48
                    stepSize: 1
                    value: root.cfg.fontSize
                    usePercentTooltip: false
                    onValueChanged: {
                        if (value !== root.cfg.fontSize)
                            root.cfg.fontSize = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "format_bold"
                    text: Translation.tr("Bold, expressive text")
                    checked: root.cfg.bold
                    onCheckedChanged: {
                        if (checked !== root.cfg.bold)
                            root.cfg.bold = checked;
                    }
                }
            }
        }

        // ── How the reading moves ───────────────────────────────────────────
        ContentSection {
            icon: "speed"
            title: Translation.tr("Reading")
            tooltip: Translation.tr("Speed, countdown and the tricks that help on camera")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSlider {
                    buttonIcon: "speed"
                    text: Translation.tr("Scroll speed")
                    from: Teleprompter.speedMin
                    to: Teleprompter.speedMax
                    stepSize: 5
                    value: root.cfg.speed
                    usePercentTooltip: false
                    onValueChanged: {
                        if (value !== root.cfg.speed)
                            root.cfg.speed = value;
                    }
                    StyledToolTip {
                        text: Translation.tr("Pixels per second; the hover card also steps it by five")
                    }
                }

                ConfigSpinBox {
                    icon: "hourglass_top"
                    text: Translation.tr("Countdown before reading")
                    from: 0
                    to: 10
                    stepSize: 1
                    value: root.cfg.countdownSeconds
                    onValueChanged: {
                        if (value !== root.cfg.countdownSeconds)
                            root.cfg.countdownSeconds = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "repeat"
                    text: Translation.tr("Loop the script")
                    checked: root.cfg.loop
                    onCheckedChanged: {
                        if (checked !== root.cfg.loop)
                            root.cfg.loop = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Back to the top when the last line passes, instead of finishing")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "swap_horiz"
                    text: Translation.tr("Mirror the text")
                    checked: root.cfg.mirror
                    onCheckedChanged: {
                        if (checked !== root.cfg.mirror)
                            root.cfg.mirror = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("For teleprompter glass rigs: the script reads correctly in the reflection")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "graphic_eq"
                    text: Translation.tr("Progress line")
                    checked: root.cfg.showProgress
                    onCheckedChanged: {
                        if (checked !== root.cfg.showProgress)
                            root.cfg.showProgress = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Stay on screen while reading")
                    checked: root.cfg.holdVisible
                    onCheckedChanged: {
                        if (checked !== root.cfg.holdVisible)
                            root.cfg.holdVisible = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Overrides auto-hide and the fullscreen hide for as long as a session runs")
                    }
                }
            }
        }
    }
}
