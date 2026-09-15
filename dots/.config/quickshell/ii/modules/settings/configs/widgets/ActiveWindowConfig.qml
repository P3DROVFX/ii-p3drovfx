import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

    // ── Back button row ───────────────────────────────────────────────────
    RowLayout {
        spacing: 12

        RippleButton {
            id: backButton
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Active Window")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Settings ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "ad"
        title: Translation.tr("Active Window")

        TipBox {
            Layout.fillWidth: true
            isFirst: true
            text: Translation.tr(
                "When off: the bar on the monitor you are using shows the focused window; bars on other monitors show the largest window on that workspace (or Workspace when empty). "
                + "When on: every bar shows the same globally focused window.")
        }

        ConfigSwitch {
            buttonIcon: "desktop_windows"
            text: Translation.tr("Show focused window on every monitor")
            checked: Config.options.bar.activeWindow.showOnAllMonitors
            onCheckedChanged: {
                Config.options.bar.activeWindow.showOnAllMonitors = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "crop_free"
            text: Translation.tr("Use fixed size")
            checked: Config.options.bar.activeWindow.fixedSize
            onCheckedChanged: {
                Config.options.bar.activeWindow.fixedSize = checked;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.bar.activeWindow.fixedSize
            icon: "height"
            text: Translation.tr("Custom size")
            value: Config.options.bar.activeWindow.customSize
            from: 100
            to: 500
            stepSize: 25
            onValueChanged: {
                Config.options.bar.activeWindow.customSize = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Animate title change")
            checked: Config.options.bar.activeWindow.animateTransition ?? true
            onCheckedChanged: {
                Config.options.bar.activeWindow.animateTransition = checked;
            }
        }
    }
}
