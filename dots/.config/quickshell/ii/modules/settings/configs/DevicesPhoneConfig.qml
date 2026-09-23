import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage
    property int loadStage: 0

    Component.onCompleted: Qt.callLater(() => root.loadStage = 1)

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        // Fade the parent content while the KDE Connect sub-page slides in so
        // its switches cannot remain visible behind the loaded page.
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            isLast: true
            materialIcon: "mobile_share"
            text: Translation.tr("Ways to share files with your phone:\n\n• KDE Connect: Drag files into the Phone tab in Sidebar Policies, drop files onto the Dynamic Island, use the 'Send file' toggle inside Phone in Sidebar Policies, or use More Actions in Search (Ctrl+K).\n\n• LocalSend: Use More Actions in Search (Ctrl+K), drop files onto the Dynamic Island, use the LocalSend Quick Toggle, or drag files onto the Clock widget in the bar.")
        }

    ContentSection {
        icon: "smartphone"
        title: Translation.tr("Phone & scrcpy Integration")
        visible: Config.options.policies.phone !== 0

        ContentSubsectionLabel { text: Translation.tr("Display") }

        ConfigSwitch {
            buttonIcon: "view_in_ar"
            text: Translation.tr("Show Mirror / Webcam / Microphone cards")
            checked: Config.options.phone.showPeripheralCards
            onCheckedChanged: {
                Config.options.phone.showPeripheralCards = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "smart_display"
            text: Translation.tr("Mirror the phone inside the sidebar")
            checked: Config.options.phone.scrcpy.embed.enabled
            onCheckedChanged: {
                Config.options.phone.scrcpy.embed.enabled = checked;
            }
            StyledToolTip {
                text: Translation.tr("On, the mirror opens as a page in the Phone tab with the phone's screen drawn inside it, touch and keyboard included. Off, it opens as a separate scrcpy window like it always did.")
            }
        }

        ConfigSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Enable KDE Connect Service")
            checked: Config.options.phone.kdeconnectEnabled
            configPage: Qt.resolvedUrl("widgets/KdeConnectConfig.qml")
            onCheckedChanged: {
                Config.options.phone.kdeconnectEnabled = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show phone notifications with desktop ones")
            checked: Config.options.phone.mirrorNotificationsToDesktop
            enabled: Config.options.phone.kdeconnectEnabled
            onCheckedChanged: {
                Config.options.phone.mirrorNotificationsToDesktop = checked;
            }
            StyledToolTip {
                text: Translation.tr("On, phone notifications pop up and stay in the sidebar list like any other, and also show in the Phone tab. Off, they only show in the Phone tab while your phone is connected.")
            }
        }

        ContentSubsectionLabel { text: Translation.tr("Contacts") }

        ConfigSwitch {
            buttonIcon: "contacts"
            text: Translation.tr("Sync contacts from phone")
            checked: Config.options.phone.contacts.enabled
            onCheckedChanged: {
                Config.options.phone.contacts.enabled = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "filter_alt"
            text: Translation.tr("Hide contacts without a name")
            checked: Config.options.phone.contacts.hideUnnamed
            enabled: Config.options.phone.contacts.enabled
            onCheckedChanged: {
                Config.options.phone.contacts.hideUnnamed = checked;
            }
            StyledToolTip {
                text: Translation.tr("Your phone exports every number known to any app, including spam lists and SIM imports. These arrive with no name and show up as bare numbers. Favorites are never hidden.")
            }
        }
    }

    ProgressiveSectionLoader {
        source: Qt.resolvedUrl("sections/PhoneBluetoothImagesSection.qml")
        active: root.loadStage >= 1
        estimatedHeight: 620
        showSkeleton: true
        sectionTitle: Translation.tr("Bluetooth Device Images")
        prioritizeOnViewport: true
        prioritizeOnSearch: true
    }

    ContentSection {
        icon: "share"
        title: Translation.tr("LocalSend")

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            materialIcon: LocalSend.available ? "verified" : "download"
            text: LocalSend.available
                ? Translation.tr("Backend: official localsend-cli %1 (Rust, from github.com/localsend/localsend). Sending and receiving are driven through a pseudo-terminal bridge (services/localsend_bridge.py) that only reads the CLI's screen and writes keystrokes — it never touches file bytes itself, so file integrity always comes straight from the official implementation.").arg(LocalSend.cliVersion || "?")
                : Translation.tr("The official localsend-cli was not found. It replaced a now-deprecated, unaffiliated third-party Python package that corrupted received files once LocalSend moved to protocol v2.2. The official binary is a prebuilt download from localsend/localsend's GitHub releases — no Rust toolchain needed on x86_64/aarch64 Linux or macOS.")

            RippleButtonWithIcon {
                visible: !LocalSend.available && !LocalSend.installing
                materialIcon: "download"
                mainText: Translation.tr("Install")
                colBackground: Appearance.colors.colTertiary
                colText: Appearance.colors.colOnTertiary
                onClicked: LocalSend.installOfficialCli()
            }

            RowLayout {
                visible: LocalSend.installing
                spacing: 8
                MaterialLoadingIndicator {
                    loading: true
                    implicitSize: 20
                }
                StyledText {
                    text: Translation.tr("Installing\u2026")
                    color: Appearance.colors.colOnTertiaryContainer
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: LocalSend.installError !== ""
            materialIcon: "error"
            text: LocalSend.installError
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: LocalSend.installLog !== ""
            icon: "terminal"
            title: Translation.tr("Install log")
            codeSnippet: LocalSend.installLog.trim()
            snippetWrapMode: Text.Wrap
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: !LocalSend.available
            icon: "terminal"
            title: Translation.tr("Or install manually")
            text: Translation.tr("Downloads the prebuilt binary matching your architecture from GitHub releases; prints cargo build instructions instead if none is published yet for it.")
            codeSnippet: "bash ~/.config/quickshell/ii/scripts/localsend/install_localsend_cli.sh"
            snippetWrapMode: Text.WrapAnywhere
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: LocalSend.available && LocalSend.pyteChecked && !LocalSend.pyteAvailable
            icon: "warning"
            title: Translation.tr("Missing Python package: pyte")
            text: Translation.tr("Only needed to send files: it reads the CLI's on-screen device list to pick a target. Receiving already works without it.")
            codeSnippet: "pip install --user pyte"
            snippetWrapMode: Text.WrapAnywhere
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Auto-start")
            checked: Config.options.localsend.autoStart
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.autoStart = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show notifications")
            checked: Config.options.localsend.showNotifications
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.showNotifications = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "branding_watermark"
            text: Translation.tr("Prefer popup over notification")
            checked: Config.options.localsend.preferPopupOverNotification
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.preferPopupOverNotification = checked;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Download path")
            text: Config.options.localsend.downloadPath
            wrapMode: TextEdit.Wrap
            enabled: LocalSend.available
            onTextChanged: {
                Config.options.localsend.downloadPath = text;
            }
        }
    }

    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }

}
