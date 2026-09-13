import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: screenCaptureRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Selection ─────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Selection")
            icon: "highlight_alt"
            tooltip: Translation.tr("Region snapping and display behavior for screenshot selection.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "monitor"
                    text: Translation.tr("Show only on focused monitor")
                    checked: Config.options.regionSelector.showOnlyOnFocusedMonitor
                    onCheckedChanged: {
                        Config.options.regionSelector.showOnlyOnFocusedMonitor = checked;
                    }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Hint target regions")
                }

                // Multi-select tiles for target region hints (Windows · Layers · Content)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // 1. Windows
                    RippleButton {
                        id: btnWindows
                        Layout.fillWidth: true
                        implicitHeight: 46
                        buttonRadius: Appearance.rounding.normal
                        property bool active: Config.options.regionSelector.targetRegions.windows
                        colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                        colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                        onClicked: Config.options.regionSelector.targetRegions.windows = !active

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            MaterialSymbol {
                                text: "desktop_windows"
                                iconSize: 20
                                fill: btnWindows.active ? 1 : 0
                                color: btnWindows.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Windows")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: btnWindows.active
                                color: btnWindows.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }

                            MaterialSymbol {
                                text: btnWindows.active ? "check_circle" : "radio_button_unchecked"
                                iconSize: 18
                                fill: btnWindows.active ? 1 : 0
                                color: btnWindows.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Enable region snapping for Hyprland app windows")
                        }
                    }

                    // 2. Layers
                    RippleButton {
                        id: btnLayers
                        Layout.fillWidth: true
                        implicitHeight: 46
                        buttonRadius: Appearance.rounding.normal
                        property bool active: Config.options.regionSelector.targetRegions.layers
                        colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                        colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                        onClicked: Config.options.regionSelector.targetRegions.layers = !active

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            MaterialSymbol {
                                text: "layers"
                                iconSize: 20
                                fill: btnLayers.active ? 1 : 0
                                color: btnLayers.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Layers")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: btnLayers.active
                                color: btnLayers.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }

                            MaterialSymbol {
                                text: btnLayers.active ? "check_circle" : "radio_button_unchecked"
                                iconSize: 18
                                fill: btnLayers.active ? 1 : 0
                                color: btnLayers.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Enable region snapping for Wayland layer surfaces (bars, docks, popups)")
                        }
                    }

                    // 3. Content
                    RippleButton {
                        id: btnContent
                        Layout.fillWidth: true
                        implicitHeight: 46
                        buttonRadius: Appearance.rounding.normal
                        property bool active: Config.options.regionSelector.targetRegions.content
                        colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                        colRipple: active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                        onClicked: Config.options.regionSelector.targetRegions.content = !active

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            MaterialSymbol {
                                text: "article"
                                iconSize: 20
                                fill: btnContent.active ? 1 : 0
                                color: btnContent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Content")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: btnContent.active
                                color: btnContent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }

                            MaterialSymbol {
                                text: btnContent.active ? "check_circle" : "radio_button_unchecked"
                                iconSize: 18
                                fill: btnContent.active ? 1 : 0
                                color: btnContent.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Enable region snapping for detected on-screen visual content boxes")
                        }
                    }
                }
            }
        }

        // ── Editor & Screenshots ──────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Editor & Screenshots")
            icon: "transform"
            tooltip: Translation.tr("Screenshot preview overlay, notifications and storage location.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "edit"
                    text: Translation.tr("Enable built-in right click screenshot editor")
                    checked: Config.options.regionSelector.annotation.enableInlineEditor
                    onCheckedChanged: {
                        Config.options.regionSelector.annotation.enableInlineEditor = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Enable this if you want to use the built-in screenshot editor when using right click to select area, replacing swappy.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "photo_library"
                    text: Translation.tr("Show screenshot preview overlay")
                    checked: Config.options.regionSelector.enableOverlay
                    onCheckedChanged: {
                        Config.options.regionSelector.enableOverlay = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Shows a Pixel-style preview overlay at the bottom-left after taking a screenshot, with quick actions to save, edit, or delete.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "notifications"
                    text: Translation.tr("Show copy notifications")
                    checked: Config.options.regionSelector.copyNotification
                    onCheckedChanged: {
                        Config.options.regionSelector.copyNotification = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Shows a system notification when a screenshot is copied to the clipboard.")
                    }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Screenshot path")
                }

                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Screenshot path")
                    text: Config.options.screenSnip.savePath
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.screenSnip.savePath = text;
                    }
                }
            }
        }

        // ── Navigation to Recording & Google Lens ─────────────────────────────
        ContentSection {
            title: Translation.tr("Recording & Visual Search")
            tooltip: Translation.tr("Configure screen recording options and visual search tools.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSubpageRow {
                    buttonIcon: "screen_record"
                    title: Translation.tr("Screen Recording")
                    description: Translation.tr("Recorder provider (OBS / wf-recorder), video quality, and post-recording actions")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/ScreenRecordingConfig.qml"))
                }

                ConfigSubpageRow {
                    buttonIcon: "search"
                    title: Translation.tr("Google Lens & Visual Search")
                    description: Translation.tr("Circle to search, rectangular mode, stroke width and aim lines")
                    summary: Config.options.search.imageSearch.useCircleSelection ? Translation.tr("Circle to Search") : Translation.tr("Rectangular")
                    onClicked: subPageOverlay.open(Qt.resolvedUrl("widgets/ScreenCaptureLensConfig.qml"))
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
