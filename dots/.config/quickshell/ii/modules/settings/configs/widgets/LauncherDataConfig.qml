import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()
    property string pendingClear: ""

    function confirm(action) {
        if (root.pendingClear !== action) {
            root.pendingClear = action;
            return false;
        }
        root.pendingClear = "";
        return true;
    }

    readonly property var fallbackEntries: [
        { id: "ai", label: Translation.tr("Ask AI"), icon: "auto_awesome" },
        { id: "web", label: Translation.tr("Search the web"), icon: "travel_explore" },
        { id: "tasks", label: Translation.tr("Create a task"), icon: "task_alt" },
        { id: "calendar", label: Translation.tr("Create an event"), icon: "calendar_month" }
    ]

    function fallbackEnabled(id) {
        return Array.from(Config.options.search.fallbacks.actions ?? []).includes(id);
    }

    function setFallbackEnabled(id, enabled) {
        const current = Array.from(Config.options.search.fallbacks.actions ?? []);
        const selected = enabled ? current.concat(current.includes(id) ? [] : [id]) : current.filter(item => item !== id);
        Config.options.search.fallbacks.actions = root.fallbackEntries
            .map(entry => entry.id)
            .filter(entryId => selected.includes(entryId));
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false
        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton { implicitWidth: Appearance.sizes.elevationMargin * 4; implicitHeight: implicitWidth; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colSecondaryContainer; colBackgroundHover: Appearance.colors.colSecondaryContainerHover; colRipple: Appearance.colors.colSecondaryContainerActive; onClicked: root.goBack(); MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnSecondaryContainer } }
            StyledText { text: Translation.tr("Data & privacy"); font.pixelSize: Appearance.font.pixelSize.large; font.family: Appearance.font.family.title; color: Appearance.colors.colOnLayer0 }
        }
        ContentSection {
            icon: "monitoring"
            title: Translation.tr("Ranking and history")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "trending_up"; text: Translation.tr("Record application frequency"); checked: Config.options.search.frecencyData.trackApps; onCheckedChanged: Config.options.search.frecencyData.trackApps = checked }
                ConfigSwitch { buttonIcon: "dashboard_customize"; text: Translation.tr("Record panel frequency"); checked: Config.options.search.frecencyData.trackPanels; onCheckedChanged: Config.options.search.frecencyData.trackPanels = checked }
                ConfigSwitch { buttonIcon: "history"; text: Translation.tr("Keep recent queries"); checked: Config.options.search.history.enable; onCheckedChanged: Config.options.search.history.enable = checked }
                ConfigSpinBox { icon: "format_list_numbered"; text: Translation.tr("Recent query limit"); value: Config.options.search.history.maxItems; from: 10; to: 100; stepSize: 10; onValueChanged: Config.options.search.history.maxItems = value }
                ConfigSwitch { buttonIcon: "star"; text: Translation.tr("Enable favorites"); checked: Config.options.search.favorites.enable; onCheckedChanged: Config.options.search.favorites.enable = checked }
            }
        }
        ContentSection {
            icon: "low_priority"
            title: Translation.tr("Fallback commands")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                ConfigSwitch { buttonIcon: "low_priority"; text: Translation.tr("Show configurable fallbacks when nothing matches"); checked: Config.options.search.fallbacks.enable; onCheckedChanged: Config.options.search.fallbacks.enable = checked }
                Repeater {
                    model: root.fallbackEntries
                    delegate: ConfigSwitch {
                        required property var modelData
                        enabled: Config.options.search.fallbacks.enable
                        buttonIcon: modelData.icon
                        text: modelData.label
                        checked: root.fallbackEnabled(modelData.id)
                        onCheckedChanged: root.setFallbackEnabled(modelData.id, checked)
                    }
                }
                StyledText { Layout.fillWidth: true; text: Translation.tr("Enabled fallbacks keep this order when no regular result matches."); wrapMode: Text.Wrap; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
            }
        }
        ContentSection {
            icon: "delete_sweep"
            title: Translation.tr("Clear Search data")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                Repeater {
                    model: [
                        { id: "apps", label: Translation.tr("Clear application frequency"), icon: "trending_down" },
                        { id: "queries", label: Translation.tr("Clear recent queries"), icon: "history" },
                        { id: "emojis", label: Translation.tr("Clear recent emojis"), icon: "mood" },
                        { id: "panels", label: Translation.tr("Clear panel frequency"), icon: "dashboard_customize" },
                        { id: "favorites", label: Translation.tr("Clear favorites"), icon: "star" }
                    ]
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: clearLabel.implicitHeight + Appearance.sizes.elevationMargin * 2
                        buttonRadius: Appearance.rounding.normal
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colErrorContainer
                        colRipple: Appearance.colors.colErrorContainerActive
                        onClicked: {
                            if (!root.confirm(modelData.id))
                                return;
                            if (modelData.id === "apps") AppUsage.resetAll();
                            else if (modelData.id === "queries") Persistent.states.search.recentQueries = [];
                            else if (modelData.id === "emojis") Persistent.states.search.recentEmojis = [];
                            else if (modelData.id === "panels") Persistent.states.search.panelUsage = [];
                            else if (modelData.id === "favorites") Persistent.states.search.pinnedEntries = [];
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            spacing: Appearance.sizes.elevationMargin
                            MaterialSymbol { text: modelData.icon; iconSize: Appearance.font.pixelSize.normal; color: parent.parent.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurface }
                            StyledText { id: clearLabel; Layout.fillWidth: true; text: root.pendingClear === modelData.id ? Translation.tr("Press again to confirm") : modelData.label; color: parent.parent.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurface }
                        }
                    }
                }
            }
        }
    }
}
