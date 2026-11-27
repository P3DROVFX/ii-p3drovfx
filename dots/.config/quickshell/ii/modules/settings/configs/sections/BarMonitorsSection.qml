import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ContentSection {
    icon: "monitor"
    title: Translation.tr("Monitors")

    ConfigSwitch {
        buttonIcon: "desktop_windows"
        text: Translation.tr("Only show bar on single monitor")
        checked: Config.options.bar.onlyShowOnSingleMonitor
        onCheckedChanged: {
            Config.options.bar.onlyShowOnSingleMonitor = checked;
            if (checked && Config.options.bar.singleMonitorName === "" && Quickshell.screens.length > 0)
                Config.options.bar.singleMonitorName = Quickshell.screens[0].name;
        }
        StyledToolTip {
            text: Translation.tr("Display the bar on only one chosen monitor instead of all monitors. Rendering the bar on multiple monitors duplicates all widgets and consumes significantly more RAM.")
        }
    }

    ContentSubsection {
        title: Translation.tr("Selected Monitor")
        icon: "settings_input_hdmi"
        visible: Config.options.bar.onlyShowOnSingleMonitor

        MonitorPicker {
            currentValue: Config.options.bar.singleMonitorName
            onSelected: newValue => Config.options.bar.singleMonitorName = newValue
        }
    }
}
