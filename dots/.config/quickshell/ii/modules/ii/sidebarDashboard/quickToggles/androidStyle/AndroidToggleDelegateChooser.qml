pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

DelegateChooser {
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
    signal openAudioOutputDialog
    signal openAudioInputDialog
    signal openBluetoothDialog
    signal openNightLightDialog
    signal openWifiDialog
    signal openDarkModeDialog
    signal openLocalSendDialog

    role: "type"

    DelegateChoice {
        roleValue: "antiFlashbang"
        AndroidAntiFlashbangToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openNightLightDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "audio"
        AndroidAudioToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openAudioOutputDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "bluetooth"
        AndroidBluetoothToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openBluetoothDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "cloudflareWarp"
        AndroidCloudflareWarpToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "colorPicker"
        AndroidColorPickerToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "videoEditor"
        AndroidVideoEditorToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "darkMode"
        AndroidDarkModeToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openDarkModeDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "easyEffects"
        AndroidEasyEffectsToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "gameMode"
        AndroidGameModeToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "idleInhibitor"
        AndroidIdleInhibitorToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "mic"
        AndroidMicToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openAudioInputDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "musicRecognition"
        AndroidMusicRecognition {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "network"
        AndroidNetworkToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openWifiDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "nightLight"
        AndroidNightLightToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openNightLightDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "notifications"
        AndroidNotificationToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "onScreenKeyboard"
        AndroidOnScreenKeyboardToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "powerProfile"
        AndroidPowerProfileToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "screenRecord"
        AndroidScreenRecordToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "screenSnip"
        AndroidScreenSnipToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "systemSounds"
        AndroidSystemSoundsToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
        }
    }

    DelegateChoice {
        roleValue: "soundcoreAnc"
        AndroidSoundcoreAncToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "localSend"
        AndroidLocalSendToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openLocalSendDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "mediaWidget"
        AndroidMediaWidgetToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }
    DelegateChoice {
        roleValue: "volumeSlider"
        AndroidVolumeSliderToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openAudioOutputDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "micSlider"
        AndroidMicSliderToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
            onOpenMenu: {
                root.openAudioInputDialog();
            }
        }
    }

    DelegateChoice {
        roleValue: "brightnessSlider"
        AndroidBrightnessSliderToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "gammaSlider"
        AndroidGammaSliderToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }

    DelegateChoice {
        roleValue: "keyboardBacklight"
        AndroidKeyboardBacklightToggle {
            required property int index
            required property var modelData
            buttonIndex: index
            isUnused: root.isUnused
            buttonData: modelData
            editMode: root.editMode
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
            gridColumns: root.gridColumns
            panel: root.panel
            gridRef: root.gridRef
            entranceTrigger: root.entranceTrigger
        }
    }
}
