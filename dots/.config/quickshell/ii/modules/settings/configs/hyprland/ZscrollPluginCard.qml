import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The scrolloverview plugin, as Settings -> Hyprland -> Layout -> zscroll shows it.
 *
 * zscroll's overview is a Hyprland plugin (yayuuu/hyprland-scroll-overview), not something the
 * shell draws, so without it Super on a zscroll workspace falls back to the shell's overview,
 * which was not made for a vertical tape. While it is missing the card is the loudest thing in
 * the section - primary container, a large shape, one filled button. Once loaded it shrinks to
 * a status line with a Rebuild for when Hyprland is updated.
 *
 * Everything goes through scripts/hyprland/scrolloverview.sh, whose last stdout line is a
 * status JSON and whose stderr carries "step:" / "error:" lines.
 */
Rectangle {
    id: card

    /// scrolloverview.sh's status JSON; empty until the first answer.
    property var pluginState: ({})
    property bool working: false
    property string progress: ""
    property string failure: ""

    readonly property bool known: card.pluginState.hyprland !== undefined
    readonly property bool loaded: card.pluginState.loaded === true
    readonly property bool supported: card.pluginState.supported === true
    readonly property bool built: card.pluginState.built === true
    readonly property bool stale: card.built && card.pluginState.current !== true
    readonly property bool compact: card.loaded && !card.working && card.failure === ""
    /// What the one button does from here.
    readonly property string action: card.built && !card.stale ? "load" : "install"

    function run(what: string) {
        card.working = what !== "status";
        card.failure = "";
        card.progress = "";
        pluginProcess.command = ["bash", Quickshell.shellPath("scripts/hyprland/scrolloverview.sh"), what];
        pluginProcess.running = true;
    }

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + (card.compact ? 24 : 40)
    radius: Appearance.rounding.large
    color: card.compact ? Appearance.colors.colLayer2
        : (card.failure !== "" ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer)

    Behavior on color {
        animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(card)
    }
    Behavior on implicitHeight {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(card)
    }

    readonly property color contentColor: card.compact ? Appearance.colors.colOnLayer2
        : (card.failure !== "" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer)

    ColumnLayout {
        id: content

        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: card.compact ? 14 : 20
            rightMargin: card.compact ? 14 : 20
        }
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: card.compact ? 12 : 18

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignTop
                // The shape says the state: a cookie while it is missing, a soft burst while
                // it builds, a circle once it is in. It morphs between them, it never spins.
                shape: card.working ? MaterialShape.Shape.SoftBurst
                    : card.loaded ? MaterialShape.Shape.Circle
                    : card.failure !== "" ? MaterialShape.Shape.Triangle
                    : MaterialShape.Shape.Cookie9Sided
                text: card.working ? "build" : card.loaded ? "check" : card.failure !== "" ? "error" : "extension"
                iconSize: card.compact ? 18 : 30
                padding: card.compact ? 6 : 14
                color: card.failure !== "" ? Appearance.colors.colError : Appearance.colors.colPrimary
                colSymbol: card.failure !== "" ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (card.compact)
                            return Translation.tr("Overview plugin loaded");
                        if (card.working)
                            return Translation.tr("Installing the overview plugin");
                        if (card.failure !== "")
                            return Translation.tr("The overview plugin could not be installed");
                        if (card.stale)
                            return Translation.tr("Rebuild the overview plugin");
                        return Translation.tr("zscroll needs its overview plugin");
                    }
                    font.pixelSize: card.compact ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: card.contentColor
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (card.compact)
                            return Translation.tr("Tap Super on a zscroll workspace to zoom out over every workspace and its rows.");
                        if (card.working)
                            return card.progress !== "" ? card.progress : Translation.tr("Starting…");
                        if (card.failure !== "")
                            return card.failure;
                        if (!card.known)
                            return Translation.tr("Checking…");
                        if (!card.supported)
                            return Translation.tr("The plugin has no build for Hyprland %1 yet. Until it does, Super opens the shell's overview.")
                                .arg(card.pluginState.hyprland);
                        if (card.stale)
                            return Translation.tr("It was compiled for another Hyprland version and will not load on %1.")
                                .arg(card.pluginState.hyprland);
                        if (card.built)
                            return Translation.tr("It is built for Hyprland %1 but not loaded yet.").arg(card.pluginState.hyprland);
                        return Translation.tr("Tapping Super on a zscroll workspace zooms out over every workspace and its whole tape of rows. That overview is a Hyprland plugin (yayuuu/hyprland-scroll-overview): installing compiles it for Hyprland %1 in about a minute and loads it on every start. It needs git, g++ and the Hyprland headers.")
                            .arg(card.pluginState.hyprland);
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: card.contentColor
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                }
            }

            RippleButtonWithIcon {
                visible: card.compact
                Layout.alignment: Qt.AlignVCenter
                materialIcon: "refresh"
                mainText: Translation.tr("Rebuild")
                onClicked: card.run("install")
            }
        }

        StyledIndeterminateProgressBar {
            visible: card.working
            Layout.fillWidth: true
        }

        RowLayout {
            visible: !card.compact && !card.working && card.known && card.supported
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                materialIcon: card.action === "load" ? "play_arrow" : (card.stale || card.failure !== "" ? "refresh" : "download")
                mainText: card.action === "load" ? Translation.tr("Load plugin")
                    : card.failure !== "" ? Translation.tr("Try again")
                    : card.stale ? Translation.tr("Rebuild plugin") : Translation.tr("Install plugin")
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colText: Appearance.colors.colOnPrimary
                onClicked: card.run(card.action)
            }
        }
    }

    Process {
        id: pluginProcess

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                try {
                    card.pluginState = JSON.parse(lines[lines.length - 1]);
                } catch (e) {}
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.startsWith("step: "))
                    card.progress = line.slice(6);
                else if (line.startsWith("error: "))
                    card.failure = line.slice(7);
            }
        }
        onExited: card.working = false
    }

    Component.onCompleted: card.run("status")
}
