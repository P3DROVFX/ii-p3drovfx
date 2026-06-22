import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property alias contentY: page.contentY
    property url activeSubPage: ""

    function openSubPage(url) {
        root.activeSubPage = Qt.resolvedUrl(url);
    }

    function closeSubPage() {
        root.activeSubPage = "";
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.width > 0 ? (subPageOverlay.x / subPageOverlay.width) : 1
        visible: opacity > 0

        ContentSection {
            icon: "settings_suggest"
            title: Translation.tr("Core Services")

            StyledText {
                text: Translation.tr("Manage services, integrations and system behavior. Each card opens its own settings page.")
                color: Appearance.colors.colOnLayer1
                opacity: 0.75
                font.pixelSize: Appearance.font.pixelSize.small
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                Layout.bottomMargin: 8
            }

            // Group 1: Audio & Alerts
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ServiceCard {
                    cardIcon: "volume_up"
                    cardHue: 188
                    cardShape: "Cookie9Sided"
                    title: qsTr("Audio Controls")
                    description: qsTr("Earbang protection and volume limits")
                    onOpenCard: root.openSubPage("widgets/CoreAudioConfig.qml")
                }

                ServiceCard {
                    cardIcon: "notifications_active"
                    cardHue: 188
                    cardShape: "Cookie9Sided"
                    title: qsTr("Interactive Alerts")
                    description: qsTr("Battery and pomodoro sounds")
                    onOpenCard: root.openSubPage("widgets/CoreAlertsConfig.qml")
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Group 2: Power & System
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ServiceCard {
                    cardIcon: "battery_android_full"
                    cardHue: 12
                    cardShape: "Cookie12Sided"
                    title: qsTr("Power & Battery")
                    description: qsTr("Battery warnings and automatic suspend")
                    onOpenCard: root.openSubPage("widgets/CorePowerConfig.qml")
                }

                ServiceCard {
                    cardIcon: "speed"
                    cardHue: 12
                    cardShape: "Cookie12Sided"
                    title: qsTr("Network & Performance")
                    description: qsTr("User agent and resource polling")
                    onOpenCard: root.openSubPage("widgets/CoreNetworkConfig.qml")
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Group 3: Media & Communication
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ServiceCard {
                    cardIcon: "album"
                    cardHue: 312
                    cardShape: "Cookie7Sided"
                    title: qsTr("Media Integrations")
                    description: qsTr("Music player, recognition and lyrics")
                    onOpenCard: root.openSubPage("widgets/CoreMediaConfig.qml")
                }

                ServiceCard {
                    cardIcon: "language"
                    cardHue: 312
                    cardShape: "Cookie7Sided"
                    title: qsTr("Language & Translation")
                    description: qsTr("Interface language, translator and AI")
                    onOpenCard: root.openSubPage("widgets/CoreLanguageConfig.qml")
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Group 4: Environment
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ServiceCard {
                    cardIcon: "weather_mix"
                    cardHue: 205
                    cardShape: "Cookie6Sided"
                    title: qsTr("Weather Service")
                    description: qsTr("City, GPS location and units")
                    onOpenCard: root.openSubPage("widgets/CoreWeatherConfig.qml")
                }

                ServiceCard {
                    cardIcon: "nest_clock_farsight_analog"
                    cardHue: 205
                    cardShape: "Cookie6Sided"
                    title: qsTr("Time & Date")
                    description: qsTr("Clock formats and world clocks")
                    onOpenCard: root.openSubPage("widgets/CoreTimeDateConfig.qml")
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Group 5: Personalization
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ServiceCard {
                    cardIcon: "terminal"
                    cardHue: 276
                    cardShape: "Cookie4Sided"
                    title: qsTr("Terminal Settings")
                    description: qsTr("Terminal color generation props")
                    onOpenCard: root.openSubPage("widgets/CoreTerminalConfig.qml")
                }

                ServiceCard {
                    cardIcon: "build"
                    cardHue: 276
                    cardShape: "Cookie4Sided"
                    title: qsTr("Waffle Tweaks")
                    description: qsTr("Optional shell tweaks")
                    onOpenCard: root.openSubPage("widgets/CoreWaffleConfig.qml")
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Group 6: Devices & Files
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ServiceCard {
                    cardIcon: "bluetooth_connected"
                    cardHue: 142
                    cardShape: "Cookie9Sided"
                    title: qsTr("Bluetooth Device Images")
                    description: qsTr("Assign artwork to paired devices")
                    onOpenCard: root.openSubPage("widgets/BTDeviceImagesConfig.qml")
                }

                ServiceCard {
                    cardIcon: "save"
                    cardHue: 142
                    cardShape: "Cookie9Sided"
                    title: qsTr("File Paths & Transfers")
                    description: qsTr("Record paths, LocalSend and wallpapers")
                    onOpenCard: root.openSubPage("widgets/CoreFilesConfig.qml")
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Group 7: Privacy
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ServiceCard {
                    cardIcon: "policy"
                    cardHue: 48
                    cardShape: "Cookie12Sided"
                    title: qsTr("Work Safety & Policies")
                    description: qsTr("Hide suspects and manage policies icon")
                    onOpenCard: root.openSubPage("widgets/CorePoliciesConfig.qml")
                }
            }
        }
    }

    Item {
        id: subPageOverlay
        width: parent.width
        height: parent.height
        y: 0
        z: 10

        property bool isOpen: root.activeSubPage.toString() !== ""
        property bool overlayActive: isOpen

        x: isOpen ? 0 : subPageOverlay.width

        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        onXChanged: {
            if (!isOpen && x >= subPageOverlay.width - 1)
                overlayActive = false;
        }
        onIsOpenChanged: {
            if (isOpen)
                overlayActive = true;
        }

        enabled: isOpen

        Loader {
            id: subPageLoader
            anchors.fill: parent
            source: root.activeSubPage
            active: subPageOverlay.overlayActive

            onLoaded: {
                if (item.hasOwnProperty("showBackButton"))
                    item.showBackButton = true;
                if (item.hasOwnProperty("goBack")) {
                    item.goBack.connect(root.closeSubPage);
                }
            }
        }
    }
}
