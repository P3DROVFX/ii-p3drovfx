import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    readonly property int index: 0
    property bool register: parent.register ?? false
    forceWidth: true

    property bool allowHeavyLoad: false
    Component.onCompleted: Qt.callLater(() => page.allowHeavyLoad = true)

    Process {
        id: randomWallProc
        property string status: ""
        property string scriptPath: `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`
        command: ["bash", "-c", FileUtils.trimFileProtocol(randomWallProc.scriptPath)]
        stdout: SplitParser {
            onRead: data => {
                randomWallProc.status = data.trim();
            }
        }
    }

    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property bool dark
        property color colText: enabled ? toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2 : Appearance.colors.colOnLayer3
        padding: 5
        Layout.fillWidth: true
        toggled: Appearance.m3colors.darkmode === dark
        colBackground: Appearance.colors.colLayer2
        onClicked: {
            Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
        }
        StyledToolTip {
            extraVisibleCondition: !smallLightDarkPreferenceButton.enabled
            text: Translation.tr("Custom color scheme has been selected")
        }
        contentItem: Item {
            anchors.centerIn: parent
            RowLayout {
                anchors.centerIn: parent
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: dark ? "dark_mode" : "light_mode"
                    fill: toggled ? 1 : 0
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: dark ? Translation.tr("Dark") : Translation.tr("Light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
            }
        }
    }

    // Wallpaper selection
    ContentSection {
        icon: "format_paint"
        title: Translation.tr("Wallpaper & Colors")
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true

            Item {
                implicitWidth: 360
                implicitHeight: 220

                StyledImage {
                    id: wallpaperPreview
                    anchors.fill: parent
                    sourceSize.width: parent.implicitWidth
                    sourceSize.height: parent.implicitHeight
                    fillMode: Image.PreserveAspectCrop
                    source: Config.options.background.wallpaperPath !== "" ? Config.options.background.wallpaperPath : `${Directories.assetsPath}/images/default_wallpaper.png`
                    cache: false
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: 360
                            height: 200
                            radius: Appearance.rounding.normal
                        }
                    }
                }

                RippleButton {
                    anchors.fill: parent
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.85)
                    colRipple: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.5)
                    onClicked: {
                        Quickshell.execDetached(`${Directories.wallpaperSwitchScriptPath}`);
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "hourglass_top"
                    color: Appearance.colors.colPrimary
                    iconSize: 40
                    z: -1
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                        margins: 10
                    }

                    implicitWidth: Math.min(text.implicitWidth + 20, parent.width - 20)
                    implicitHeight: text.implicitHeight + 5
                    color: Appearance.colors.colPrimary
                    radius: Appearance.rounding.full

                    StyledText {
                        id: text
                        anchors.centerIn: parent
                        property string fileName: {
                            const path = Config.options.background.wallpaperPath;
                            if (path === "") return "Click to select wallpaper";
                            const parts = path.split("/");
                            return parts[parts.length - 1];
                        }
                        text: fileName.length > 30 ? fileName.slice(0, 27) + "..." : fileName
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    uniformCellSizes: true

                    SmallLightDarkPreferenceButton {
                        Layout.preferredHeight: 60
                        dark: false
                    }
                    SmallLightDarkPreferenceButton {
                        Layout.preferredHeight: 60
                        dark: true
                    }
                }

                Item {
                    id: colorGridItem
                    z: 1
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    StyledFlickable {
                        id: flickable
                        anchors.fill: parent
                        contentHeight: contentLayout.implicitHeight
                        contentWidth: width
                        clip: true

                        ColumnLayout {
                            id: contentLayout
                            width: flickable.width

                            Repeater {
                                model: [
                                    {
                                        customTheme: false,
                                        builtInTheme: false
                                    },
                                    {
                                        customTheme: false,
                                        builtInTheme: true
                                    },
                                    {
                                        customTheme: true,
                                        builtInTheme: false
                                    }
                                ]

                                delegate: ColorPreviewGrid {
                                    customTheme: modelData.customTheme
                                    builtInTheme: modelData.builtInTheme
                                }
                            }
                        }
                    }
                }
            }
        }

        ConfigRow {
            uniform: true
            Layout.fillWidth: true

            RippleButtonWithIcon {
                enabled: !randomWallProc.running
                visible: Config.options.policies.weeb === 1
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.small
                materialIcon: "ifl"
                mainText: randomWallProc.running ? Translation.tr("Be patient...") : Translation.tr("Random: Konachan")
                onClicked: {
                    randomWallProc.scriptPath = `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`;
                    randomWallProc.running = true;
                }
                StyledToolTip {
                    text: Translation.tr("Random SFW Anime wallpaper from Konachan\nImage is saved to ~/Pictures/Wallpapers")
                }
            }
            RippleButtonWithIcon {
                enabled: !randomWallProc.running
                visible: Config.options.policies.weeb === 1
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.small
                materialIcon: "ifl"
                mainText: randomWallProc.running ? Translation.tr("Be patient...") : Translation.tr("Random: osu! seasonal")
                onClicked: {
                    randomWallProc.scriptPath = `${Directories.scriptPath}/colors/random/random_osu_wall.sh`;
                    randomWallProc.running = true;
                }
                StyledToolTip {
                    text: Translation.tr("Random osu! seasonal background\nImage is saved to ~/Pictures/Wallpapers")
                }
            }
        }
    }

    ContentSection {
        icon: "screenshot_monitor"
        title: Translation.tr("Bar & screen")
        Layout.topMargin: -25

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Bar style")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        },
                        {
                            displayName: Translation.tr("Dynamic Island"),
                            icon: "water_drop",
                            value: 3
                        }
                    ]
                }
            }
        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Screen round corner")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.fakeScreenRounding
                    onSelected: newValue => {
                        Config.options.appearance.fakeScreenRounding = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("When not fullscreen"),
                            icon: "fullscreen_exit",
                            value: 2
                        },
                        {
                            displayName: Translation.tr("Wrapped"),
                            icon: "capture",
                            value: 3
                        },
                        {
                            displayName: Translation.tr("Edge"),
                            icon: "border_bottom",
                            value: 4
                        }
                    ]
                }
            }
        }

        ConfigSpinBox {
            visible: Config.options.appearance.fakeScreenRounding === 3
            icon: "line_weight"
            text: Translation.tr("Wrapped frame thickness")
            value: Config.options.appearance.wrappedFrameThickness
            from: 5
            to: 25
            stepSize: 1
            onValueChanged: {
                Config.options.appearance.wrappedFrameThickness = value;
            }
        }

        ColumnLayout {
            ContentSubsection {
                title: Translation.tr("Bar background style")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.barBackgroundStyle
                    onSelected: newValue => {
                        Config.options.bar.barBackgroundStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Visible"),
                            icon: "visibility",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Adaptive"),
                            icon: "masked_transitions",
                            value: 2
                        },
                        {
                            displayName: Translation.tr("Transparent"),
                            icon: "opacity",
                            value: 0
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Hyprland layout")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: {
                        if (Persistent.states.hyprland.layout !== "scrolling")
                            return "default";
                        else
                            return "scrolling";
                    }
                    onSelected: newValue => {
                        console.log(newValue);
                        if (newValue === "scrolling") {
                            HyprlandSettings.setLayout("scrolling");
                        } else {
                            const defaultLayout = Config.options.hyprland.defaultHyprlandLayout;
                            HyprlandSettings.setLayout(defaultLayout);
                        }
                    }
                    options: [
                        {
                            displayName: Translation.tr("Default"),
                            icon: "mobile_layout",
                            value: "default"
                        },
                        {
                            displayName: Translation.tr("Scrolling"),
                            icon: "view_carousel",
                            value: "scrolling"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Rounding style")
                tooltip: Translation.tr("Sharp mode is experimental")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.globalRounding
                    onSelected: newValue => {
                        Config.options.appearance.globalRounding = newValue;
                        Config.options.appearance.sharpMode = (newValue === "sharp");
                    }
                    options: [
                        {
                            displayName: Translation.tr("Sharp"),
                            icon: "square",
                            value: "sharp"
                        },
                        {
                            displayName: Translation.tr("Normal"),
                            icon: "rounded_corner",
                            value: "normal"
                        },
                        {
                            displayName: Translation.tr("Large"),
                            icon: "lens_blur",
                            value: "large"
                        },
                        {
                            displayName: Translation.tr("V. Large"),
                            icon: "circle",
                            value: "verylarge"
                        }
                    ]
                }
            }
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: -20
        text: Translation.tr('Not all options are available in this app. You should also check the config file by hitting the "Config file" button on the topleft corner or opening ~/.config/illogical-impulse/config.json manually.')

        RippleButtonWithIcon {
            id: copyPathButton
            property bool justCopied: false
            buttonRadius: Appearance.rounding.small
            materialIcon: justCopied ? "check" : "content_copy"
            mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy path")
            onClicked: {
                copyPathButton.justCopied = true;
                Quickshell.clipboardText = FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                revertTextTimer.restart();
            }
            colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive

            Timer {
                id: revertTextTimer
                interval: 1500
                onTriggered: {
                    copyPathButton.justCopied = false;
                }
            }
        }
    }

    Connections {
        target: Config.options.appearance.palette
        function onTypeChanged() {
            page.showRestartFab = true;
        }
    }

    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            page.showRestartFab = true;
        }
    }

    property bool showRestartFab: false

    FloatingActionButton {
        id: restartFab
        parent: page.parent
        anchors {
            right: parent?.right
            bottom: parent?.bottom
            margins: 30
        }
        z: 100
        iconText: "restart_alt"
        buttonText: Translation.tr("Restart Shell")
        expanded: false
        visible: opacity > 0
        opacity: page.showRestartFab ? 1 : 0
        scale: opacity

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        colBackground: Appearance.colors.colTertiaryContainer
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colRipple: Appearance.colors.colTertiaryContainerActive
        colOnBackground: Appearance.colors.colOnTertiaryContainer

        onClicked: {
            Quickshell.execDetached(["bash", "-c", "qs kill -c ii && qs -c ii &"]);
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: restartFab.expanded = true
            onExited: restartFab.expanded = false
        }
    }
}
