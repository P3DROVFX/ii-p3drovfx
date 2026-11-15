pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Settings → Devices & Phone: the ii tools banner. A full-width primary-container
 * surface that promotes the released Android app (download, source) and doubles
 * as the service card (switch, paired phone, modules, Configure).
 */
Item {
    id: card

    property bool active: false
    property bool connected: false
    property bool switchEnabled: true
    property string statusText: ""

    signal toggled(bool wantActive)
    signal configureRequested()

    readonly property string releaseUrl: "https://github.com/P3DROVFX/ii-tools/releases/latest"
    readonly property string repoUrl: "https://github.com/P3DROVFX/ii-tools"
    readonly property bool wide: width >= 640

    readonly property color colSurface: Appearance.colors.colPrimaryContainer
    readonly property color colOn: Appearance.colors.colOnPrimaryContainer
    readonly property color colOnSoft: ColorUtils.applyAlpha(Appearance.colors.colOnPrimaryContainer, 0.78)

    readonly property var features: [
        { icon: "notifications_active", label: Translation.tr("Live updates") },
        { icon: "videocam", label: Translation.tr("Webcam") },
        { icon: "mic", label: Translation.tr("Microphone") },
        { icon: "desktop_windows", label: Translation.tr("Second screen") },
        { icon: "grid_view", label: Translation.tr("Stream deck") },
        { icon: "co_present", label: Translation.tr("Presenter") },
        { icon: "touch_app", label: Translation.tr("Touchpad") },
        { icon: "call", label: Translation.tr("Calls") },
        { icon: "content_paste", label: Translation.tr("Clipboard") },
        { icon: "music_note", label: Translation.tr("Media") }
    ]

    implicitHeight: bannerCol.implicitHeight + 48

    // ── Surface: rounded mask over a tonal fill and two morphing shapes ──
    Rectangle {
        id: bannerMask
        width: bannerSurface.width
        height: bannerSurface.height
        radius: Appearance.rounding.verylarge
        visible: false
        layer.enabled: true
    }

    Item {
        id: bannerSurface
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: bannerMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Rectangle {
            anchors.fill: parent
            color: card.colSurface
        }

        // The whole banner opens Configure; buttons sit above it and keep
        // their own clicks. Inside the masked surface so the ripple is clipped.
        RippleButton {
            anchors.fill: parent
            buttonRadius: 0
            colBackground: "transparent"
            colBackgroundHover: ColorUtils.applyAlpha(card.colOn, 0.05)
            colRipple: ColorUtils.applyAlpha(card.colOn, 0.12)
            onClicked: card.configureRequested()
        }

        MaterialShape {
            implicitSize: Math.max(card.height * 1.25, 320)
            x: card.width - implicitSize * (card.wide ? 0.5 : 0.42)
            y: -implicitSize * 0.34
            shape: card.connected
                ? MaterialShape.Shape.Sunny
                : (card.active ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.SoftBurst)
            color: Appearance.colors.colPrimary
            opacity: 0.14
        }

        MaterialShape {
            implicitSize: 150
            x: card.width - implicitSize * (card.wide ? 1.55 : 0.8)
            y: card.height - implicitSize * 0.52
            shape: card.active ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Pill
            color: Appearance.colors.colTertiary
            opacity: 0.16
        }
    }

    ColumnLayout {
        id: bannerCol
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18

        // ── Header: app tile + name + switch ─────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            Item {
                id: appTile
                implicitWidth: card.wide ? 92 : 72
                implicitHeight: implicitWidth
                Layout.alignment: Qt.AlignTop

                Rectangle {
                    id: tileMask
                    anchors.fill: parent
                    radius: width * 0.3
                    visible: false
                    layer.enabled: true
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: tileMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colPrimary
                    }

                    Image {
                        id: appGlyph
                        anchors.fill: parent
                        source: Qt.resolvedUrl(Quickshell.shellPath("assets/icons/ii-tools-symbolic.svg"))
                        sourceSize: Qt.size(width * 2, height * 2)
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: appGlyph
                        source: appGlyph
                        brightness: 1.0
                        colorization: 1.0
                        colorizationColor: Appearance.colors.colOnPrimary
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                Rectangle {
                    implicitWidth: newBadgeRow.implicitWidth + 18
                    implicitHeight: 24
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colTertiary

                    RowLayout {
                        id: newBadgeRow
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            text: "new_releases"
                            iconSize: 14
                            fill: 1
                            color: Appearance.colors.colOnTertiary
                        }
                        StyledText {
                            text: Translation.tr("OUT NOW · ANDROID 12+")
                            font.pixelSize: Appearance.font.pixelSize.smaller - 1
                            font.variableAxes: ({ "wght": 800, "wdth": 115, "ROND": 0 })
                            font.letterSpacing: 1.2
                            color: Appearance.colors.colOnTertiary
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("ii tools")
                    font.pixelSize: card.wide ? 40 : 32
                    font.variableAxes: ({ "wght": 850, "wdth": 112, "ROND": 30 })
                    color: card.colOn
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("The Android companion for the ii shell")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 0 })
                    color: card.colOn
                }
            }

            // Pairing status where the switch used to be; the selector above
            // owns turning the service on and off.
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: statusRow.implicitWidth + 24
                implicitHeight: 34
                radius: Appearance.rounding.full
                color: card.connected
                    ? Appearance.colors.colPrimary
                    : (card.active ? Appearance.colors.colSurfaceContainerHighest : ColorUtils.applyAlpha(card.colOn, 0.1))

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 7

                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: card.connected
                            ? Appearance.colors.colOnPrimary
                            : (card.active ? Appearance.colors.colPrimary : card.colOnSoft)
                    }
                    StyledText {
                        text: card.statusText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: card.connected
                            ? Appearance.colors.colOnPrimary
                            : (card.active ? Appearance.colors.colOnSurface : card.colOn)
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            lineHeight: 1.25
            font.pixelSize: Appearance.font.pixelSize.small
            color: card.colOnSoft
            text: Translation.tr("In place of KDE Connect: the phone talks to the shell over its own encrypted link, on your network or Tailscale, with nothing else to install on either side. Live updates on the lock screen, the phone as webcam, microphone, second screen and stream deck, and the PC on the phone's home.")
        }

        // ── What it brings ───────────────────────────────────────────────
        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: card.features

                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    implicitWidth: chipRow.implicitWidth + 22
                    implicitHeight: 34
                    radius: Appearance.rounding.full
                    color: ColorUtils.applyAlpha(card.colOn, 0.09)

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: chip.modelData.icon
                            iconSize: 17
                            fill: 1
                            color: card.colOn
                        }
                        StyledText {
                            text: chip.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: card.colOn
                        }
                    }
                }
            }
        }

        // ── Actions: get the app on the left, Configure on the right ─────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 10

            RippleButtonWithIcon {
                implicitHeight: 48
                horizontalPadding: 20
                materialIcon: "download"
                mainText: card.wide ? Translation.tr("Download for Android") : Translation.tr("Download")
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colText: Appearance.colors.colOnPrimary
                onClicked: Qt.openUrlExternally(card.releaseUrl)
            }

            RippleButtonWithIcon {
                implicitHeight: 48
                horizontalPadding: 20
                materialIcon: "code"
                mainText: card.wide ? Translation.tr("Source on GitHub") : Translation.tr("GitHub")
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.applyAlpha(card.colOn, 0.1)
                colBackgroundHover: ColorUtils.applyAlpha(card.colOn, 0.16)
                colText: card.colOn
                onClicked: Qt.openUrlExternally(card.repoUrl)
            }

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                implicitHeight: 48
                horizontalPadding: 28
                materialIcon: card.active ? "tune" : "power_settings_new"
                mainText: card.active ? Translation.tr("Configure") : Translation.tr("Use ii tools")
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colText: Appearance.colors.colOnLayer1
                enabled: card.active || card.switchEnabled
                onClicked: {
                    if (card.active)
                        card.configureRequested();
                    else
                        card.toggled(true);
                }
            }
        }
    }
}
