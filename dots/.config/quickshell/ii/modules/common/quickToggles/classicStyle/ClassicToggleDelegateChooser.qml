pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell

// Maps a classic toggle type onto its widget. Kept as a DelegateChooser so
// every toggle stays a direct child of the grid - a Loader wrapper would hide
// the buttons from GroupButton's parent lookup and kill the press bounce.
DelegateChooser {
    id: root
    property bool editMode: false
    property bool isUnused: false
    property bool draggable: false

    signal openBluetoothDialog
    signal openWifiDialog
    signal openVpnDialog
    signal openTailscaleDialog
    signal openIdleInhibitorDialog
    signal openModesDialog
    signal editRequested(string type)

    role: "toggleType"

    DelegateChoice {
        roleValue: "network"
        NetworkToggle {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "network"
            draggable: root.draggable
            onEditClicked: root.editRequested("network")
            altAction: () => {
                root.openWifiDialog();
            }
        }
    }
    DelegateChoice {
        roleValue: "bluetooth"
        BluetoothToggle {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "bluetooth"
            draggable: root.draggable
            onEditClicked: root.editRequested("bluetooth")
            altAction: () => {
                root.openBluetoothDialog();
            }
        }
    }
    DelegateChoice {
        roleValue: "vpn"
        VpnToggle {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "vpn"
            draggable: root.draggable
            onEditClicked: root.editRequested("vpn")
            altAction: () => {
                root.openVpnDialog();
            }
        }
    }
    DelegateChoice {
        roleValue: "tailscale"
        TailscaleToggle {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "tailscale"
            draggable: root.draggable
            onEditClicked: root.editRequested("tailscale")
            altAction: () => {
                root.openTailscaleDialog();
            }
        }
    }
    DelegateChoice {
        roleValue: "nightLight"
        NightLight {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "nightLight"
            draggable: root.draggable
            onEditClicked: root.editRequested("nightLight")
        }
    }
    DelegateChoice {
        roleValue: "gameMode"
        GameMode {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "gameMode"
            draggable: root.draggable
            onEditClicked: root.editRequested("gameMode")
        }
    }
    DelegateChoice {
        roleValue: "keypressDisplay"
        KeystrokeDisplay {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "keypressDisplay"
            draggable: root.draggable
            onEditClicked: root.editRequested("keypressDisplay")
        }
    }
    DelegateChoice {
        roleValue: "idleInhibitor"
        IdleInhibitor {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "idleInhibitor"
            draggable: root.draggable
            onEditClicked: root.editRequested("idleInhibitor")
            altAction: () => {
                root.openIdleInhibitorDialog();
            }
        }
    }
    DelegateChoice {
        roleValue: "modes"
        ModesQuickToggle {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "modes"
            draggable: root.draggable
            onEditClicked: root.editRequested("modes")
            altAction: () => {
                root.openModesDialog();
            }
        }
    }
    DelegateChoice {
        roleValue: "easyEffects"
        EasyEffectsToggle {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "easyEffects"
            draggable: root.draggable
            onEditClicked: root.editRequested("easyEffects")
        }
    }
    DelegateChoice {
        roleValue: "cloudflareWarp"
        CloudflareWarp {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "cloudflareWarp"
            draggable: root.draggable
            onEditClicked: root.editRequested("cloudflareWarp")
        }
    }
    DelegateChoice {
        roleValue: "keyboardBacklight"
        KeyboardBacklight {
            editMode: root.editMode
            isUnused: root.isUnused
            toggleType: "keyboardBacklight"
            draggable: root.draggable
            onEditClicked: root.editRequested("keyboardBacklight")
        }
    }
}
