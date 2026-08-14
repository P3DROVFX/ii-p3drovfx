pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

Item {
    id: root

    property bool editMode: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    property int pageIndex: 0
    property int gridColumns: 4
    property bool isUnused: false
    property var panel: null
    property var gridRef: null
    property int entranceTrigger: -1

    required property int index
    required property var modelData

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

    readonly property string toggleType: (root.modelData && root.modelData.type) ? root.modelData.type : ""

    // Layout properties for GridLayout
    Layout.row: (root.modelData && root.modelData.gridRow !== undefined) ? root.modelData.gridRow : -1
    Layout.column: (root.modelData && root.modelData.gridCol !== undefined) ? root.modelData.gridCol : -1
    Layout.columnSpan: toggleLoader.item ? (toggleLoader.item.effectiveSizeW ?? 1) : (root.modelData?.sizeW ?? root.modelData?.size ?? 1)
    Layout.rowSpan: toggleLoader.item ? (toggleLoader.item.effectiveSizeH ?? 1) : (root.modelData?.sizeH ?? 1)
    Layout.preferredWidth: toggleLoader.item ? toggleLoader.item.implicitWidth : (root.baseCellWidth * (root.modelData?.sizeW ?? 1) + root.spacing * ((root.modelData?.sizeW ?? 1) - 1))
    Layout.preferredHeight: toggleLoader.item ? toggleLoader.item.implicitHeight : (root.baseCellHeight * (root.modelData?.sizeH ?? 1) + root.spacing * ((root.modelData?.sizeH ?? 1) - 1))
    Layout.fillWidth: false
    Layout.fillHeight: false

    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight

    Behavior on x {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on y {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Loader {
        id: toggleLoader
        anchors.fill: parent
        sourceComponent: {
            switch (root.toggleType) {
                case "screenShader": return screenShaderComp;
                case "antiFlashbang": return antiFlashbangComp;
                case "audio": return audioComp;
                case "bluetooth": return bluetoothComp;
                case "cloudflareWarp": return cloudflareWarpComp;
                case "colorPicker": return colorPickerComp;
                case "videoEditor": return videoEditorComp;
                case "darkMode": return darkModeComp;
                case "easyEffects": return easyEffectsComp;
                case "gameMode": return gameModeComp;
                case "idleInhibitor": return idleInhibitorComp;
                case "mic": return micComp;
                case "musicRecognition": return musicRecognitionComp;
                case "network": return networkComp;
                case "nightLight": return nightLightComp;
                case "notifications": return notificationComp;
                case "autoDnd": return autoDndComp;
                case "onScreenKeyboard": return onScreenKeyboardComp;
                case "powerProfile": return powerProfileComp;
                case "screenRecord": return screenRecordComp;
                case "screenSnip": return screenSnipComp;
                case "systemSounds": return systemSoundsComp;
                case "soundcoreAnc": return soundcoreAncComp;
                case "localSend": return localSendComp;
                case "mediaWidget": return mediaWidgetComp;
                case "volumeSlider": return volumeSliderComp;
                case "micSlider": return micSliderComp;
                case "brightnessSlider": return brightnessSliderComp;
                case "gammaSlider": return gammaSliderComp;
                case "vpn": return vpnComp;
                case "tailscale": return tailscaleComp;
                case "dnsOverTls": return dnsOverTlsComp;
                default: return null;
            }
        }
    }

    Component {
        id: screenShaderComp
        AndroidScreenShaderToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openScreenShaderDialog()
        }
    }

    Component {
        id: antiFlashbangComp
        AndroidAntiFlashbangToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openNightLightDialog()
        }
    }

    Component {
        id: audioComp
        AndroidAudioToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openAudioOutputDialog()
        }
    }

    Component {
        id: bluetoothComp
        AndroidBluetoothToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openBluetoothDialog()
        }
    }

    Component {
        id: cloudflareWarpComp
        AndroidCloudflareWarpToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: colorPickerComp
        AndroidColorPickerToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: videoEditorComp
        AndroidVideoEditorToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: darkModeComp
        AndroidDarkModeToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openDarkModeDialog()
        }
    }

    Component {
        id: easyEffectsComp
        AndroidEasyEffectsToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: gameModeComp
        AndroidGameModeToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: idleInhibitorComp
        AndroidIdleInhibitorToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openIdleInhibitorDialog()
        }
    }

    Component {
        id: micComp
        AndroidMicToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openAudioInputDialog()
        }
    }

    Component {
        id: musicRecognitionComp
        AndroidMusicRecognition {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: networkComp
        AndroidNetworkToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openWifiDialog()
        }
    }

    Component {
        id: nightLightComp
        AndroidNightLightToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openNightLightDialog()
        }
    }

    Component {
        id: notificationComp
        AndroidNotificationToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: autoDndComp
        AndroidAutoDndToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: onScreenKeyboardComp
        AndroidOnScreenKeyboardToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: powerProfileComp
        AndroidPowerProfileToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: screenRecordComp
        AndroidScreenRecordToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: screenSnipComp
        AndroidScreenSnipToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: systemSoundsComp
        AndroidSystemSoundsToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
        }
    }

    Component {
        id: soundcoreAncComp
        AndroidSoundcoreAncToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: localSendComp
        AndroidLocalSendToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openLocalSendDialog()
        }
    }

    Component {
        id: mediaWidgetComp
        AndroidMediaWidgetToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: volumeSliderComp
        AndroidVolumeSliderToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openAudioOutputDialog()
        }
    }

    Component {
        id: micSliderComp
        AndroidMicSliderToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openAudioInputDialog()
        }
    }

    Component {
        id: brightnessSliderComp
        AndroidBrightnessSliderToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: gammaSliderComp
        AndroidGammaSliderToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    Component {
        id: vpnComp
        AndroidVpnToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openVpnDialog()
        }
    }

    Component {
        id: tailscaleComp
        AndroidTailscaleToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openTailscaleDialog()
        }
    }

    Component {
        id: dnsOverTlsComp
        AndroidDnsOverTlsToggle {
            buttonIndex: root.index
            isUnused: root.isUnused
            buttonData: root.modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: root.modelData?.size ?? 1
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: root.openDnsOverTlsDialog()
        }
    }
}
