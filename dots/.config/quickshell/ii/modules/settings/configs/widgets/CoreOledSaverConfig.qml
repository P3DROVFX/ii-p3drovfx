import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    RowLayout {
        spacing: 12

        RippleButton {
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
            text: Translation.tr("Always On Display")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }
    ContentSection {
        icon: "brightness_1"
        title: Translation.tr("Timing")

        StyledText {
            text: Translation.tr("Super + R turns the focused monitor into an Always On Display: pure black, with the lock screen's widgets in grey, where the lock screen places them. A click, a key or the same shortcut wakes it. On the lock screen it also comes on by itself after the timeout below.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            Layout.bottomMargin: 8
        }

        ConfigSpinBox {
            icon: "mouse"
            text: Translation.tr("Cursor hide delay (seconds)")
            value: Config.options.oledSaver.cursorHideDelay
            from: 1
            to: 60
            stepSize: 1
            onValueChanged: {
                Config.options.oledSaver.cursorHideDelay = value;
            }
            StyledToolTip {
                text: Translation.tr("How long after you stop moving the mouse before the cursor hides again")
            }
        }

        ConfigSpinBox {
            icon: "lock_clock"
            text: Translation.tr("Lock screen timeout (minutes)")
            value: Config.options.oledSaver.lockTimeout
            from: 0
            to: 60
            stepSize: 1
            onValueChanged: {
                Config.options.oledSaver.lockTimeout = value;
            }
            StyledToolTip {
                text: Translation.tr("Minutes without input on the lock screen before it turns into the Always On Display. 0 turns the timer off; the shortcut still works")
            }
        }
    }
}
