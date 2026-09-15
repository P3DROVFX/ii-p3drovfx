import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.quickToggles
import qs.modules.akebono

// Host for the shared sidebar quick panels (classic / android) inside the
// Akebono control centre. It sizes to the panel's own content, keeps the
// popup's shelf surface colour behind the panel (transparent backdrop), and
// forwards every open*Dialog signal the shared system emits so the control
// centre can route them to its own pane.
Item {
    id: root

    property var panel: null
    property bool editMode: false

    signal openAudioOutputDialog
    signal openAudioInputDialog
    signal openBluetoothDialog
    signal openNightLightDialog
    signal openWifiDialog
    signal openDarkModeDialog
    signal openLocalSendDialog
    signal openVpnDialog
    signal openTailscaleDialog
    signal openDnsOverTlsDialog
    signal openIdleInhibitorDialog
    signal openScreenShaderDialog
    signal openModesDialog

    readonly property var panelInstance: holder.item

    implicitWidth: root.width
    implicitHeight: holder.item ? holder.item.implicitHeight : 0

    Loader {
        id: holder
        width: parent.width
        sourceComponent: root.panel?.style === "android" ? androidComp : classicComp
        onLoaded: {
            if (!item)
                return;
            item.editMode = Qt.binding(() => root.editMode);
            item.color = Qt.binding(() => "transparent");
            item.radius = Qt.binding(() => Appearance.rounding.windowRounding);
            if ("maxContentHeight" in item) {
                item.maxContentHeight = Qt.binding(() => {
                    const budget = root.panel?.shelf?.qsMaxH ?? 0;
                    if (budget > 0)
                        return Math.max(160, budget - 150);
                    const screen = QsWindow.window?.screen?.geometry ?? null;
                    return screen ? Math.max(240, screen.height * 0.6) : -1;
                });
            }
        }
    }

    Connections {
        target: root.panelInstance
        ignoreUnknownSignals: true
        function onOpenAudioOutputDialog() { root.openAudioOutputDialog() }
        function onOpenAudioInputDialog() { root.openAudioInputDialog() }
        function onOpenBluetoothDialog() { root.openBluetoothDialog() }
        function onOpenNightLightDialog() { root.openNightLightDialog() }
        function onOpenWifiDialog() { root.openWifiDialog() }
        function onOpenDarkModeDialog() { root.openDarkModeDialog() }
        function onOpenLocalSendDialog() { root.openLocalSendDialog() }
        function onOpenVpnDialog() { root.openVpnDialog() }
        function onOpenTailscaleDialog() { root.openTailscaleDialog() }
        function onOpenDnsOverTlsDialog() { root.openDnsOverTlsDialog() }
        function onOpenIdleInhibitorDialog() { root.openIdleInhibitorDialog() }
        function onOpenScreenShaderDialog() { root.openScreenShaderDialog() }
        function onOpenModesDialog() { root.openModesDialog() }
    }

    Component {
        id: androidComp
        AndroidQuickPanel {
            width: root.width
            layoutEntity: "shelf"
            useThreeWaySliders: Config.options.akebono.shelf.quickSettings.useThreeWaySliders
            quickSlidersConfig: Config.options.akebono.shelf.quickSliders
            spacing: 4
            // At least the badge overhang wide, so edit-mode add/remove badges
            // (which hang past the last column) stay well inside the panel and
            // the popup's outer clip.
            padding: 8
            baseCellHeight: 44
        }
    }

    Component {
        id: classicComp
        ClassicQuickPanel {
            width: root.width
            configObject: Config.options.akebono.shelf.quickSettings
        }
    }
}