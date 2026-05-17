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
    required property int startingIndex
    property int pageIndex: 0
    signal openAudioOutputDialog
    signal openAudioInputDialog
    signal openBluetoothDialog
    signal openNightLightDialog
    signal openWifiDialog
    signal openDarkModeDialog

    role: "type"

    DelegateChoice {
        roleValue: "antiFlashbang"
        AndroidAntiFlashbangToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
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
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
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
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
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
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "colorPicker"
        AndroidColorPickerToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "darkMode"
        AndroidDarkModeToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
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
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "gameMode"
        AndroidGameModeToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "idleInhibitor"
        AndroidIdleInhibitorToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "mic"
        AndroidMicToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
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
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "network"
        AndroidNetworkToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
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
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
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
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "onScreenKeyboard"
        AndroidOnScreenKeyboardToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "powerProfile"
        AndroidPowerProfileToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "screenSnip"
        AndroidScreenSnipToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }

    DelegateChoice {
        roleValue: "soundcoreAnc"
        AndroidSoundcoreAncToggle {
            required property int index
            required property var modelData
            buttonIndex: root.startingIndex + index
            buttonData: modelData
            editMode: root.editMode
            expandedSize: modelData.size > 1
            baseCellWidth: root.baseCellWidth
            baseCellHeight: root.baseCellHeight
            cellSpacing: root.spacing
            cellSize: modelData.size
            pageIndex: root.pageIndex
        }
    }
}
