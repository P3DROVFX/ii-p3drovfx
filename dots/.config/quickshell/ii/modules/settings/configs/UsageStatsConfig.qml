pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: usageStatsRoot
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property var opts: Config.options.appStats

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        KeyboardShortcutBox {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            text: Translation.tr("Toggle app usage stats")
            keys: ["Super", "U"]
        }

        // ── General ───────────────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("General")
            icon: "bar_chart"
            tooltip: Translation.tr("Master statistics collection and the App usage app.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "monitoring"
                    text: Translation.tr("Collect usage statistics")
                    checked: usageStatsRoot.opts.enable
                    onCheckedChanged: {
                        Config.options.appStats.enable = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Turning this off stops the sampler but keeps the history already recorded")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "dashboard"
                    text: Translation.tr("Load the App usage app")
                    checked: usageStatsRoot.opts.overlayEnabled
                    onCheckedChanged: {
                        Config.options.appStats.overlayEnabled = checked;
                    }
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "settings"
            text: Translation.tr("Views, history and storage, and the sampler live in the App usage app itself, under Settings at the foot of its rail.")
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
