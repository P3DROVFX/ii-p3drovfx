import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt5Compat.GraphicalEffects

StyledFlickable {
    id: root

    property int activePasswordIndex: -1

    // With a cable plugged in, a missing Wi-Fi list is not "no connection":
    // the Wi-Fi state then sits inline under its own header instead of the
    // full-page placeholder, so it cannot read as the Ethernet's state.
    property bool wiredOnline: Network.ethernet
    property bool wifiOff: Network.wifiStatus === "disabled"
    property bool wifiScanning: Network.wifiScanning
    property int wifiCount: repeaterAvailable.count
    readonly property bool wifiListEmpty: !root.wifiOff && root.wifiCount === 0
    readonly property bool inlineWifiState: root.wiredOnline && (root.wifiOff || root.wifiListEmpty)

    Layout.fillWidth: true
    Layout.fillHeight: true

    contentHeight: mainLayout.implicitHeight + 36
    // A page hugs this whole height, slack included: given any less the body can
    // still scroll, and the bottom fade greys out the last row.
    readonly property real naturalHeight: mainLayout.y + root.contentHeight
    clip: true

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Item {
            id: maskRoot
            width: root.width
            height: root.height

            property color topFadeColor: root.atYBeginning ? "white" : "transparent"
            property color bottomFadeColor: root.atYEnd ? "white" : "transparent"

            Behavior on topFadeColor {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }
            Behavior on bottomFadeColor {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            Column {
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: Math.min(46, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: maskRoot.topFadeColor
                        }
                        GradientStop {
                            position: 1.0
                            color: "white"
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Math.max(0, parent.height - Math.min(46, parent.height / 2) - Math.min(56, parent.height / 2))
                    color: "white"
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(56, parent.height / 2)
                    color: "transparent"
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: "white"
                        }
                        GradientStop {
                            position: 1.0
                            color: maskRoot.bottomFadeColor
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        width: root.width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 4
        spacing: 6

        // ── Scanning bar ──────────────────────────────────
        StyledIndeterminateProgressBar {
            visible: Network.wifiScanning
            Layout.fillWidth: true
            Layout.topMargin: 0
            Layout.bottomMargin: 12
        }

        WiredConnectionSection {
            Layout.bottomMargin: 10
            wiredConnected: root.wiredOnline
        }

        // ── Section: connected ────────────────────────────
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            visible: Network.active !== null
            text: Translation.tr("Connected Wi-Fi")
        }

        // Connected network row
        Item {
            Layout.fillWidth: true
            implicitHeight: 56
            height: implicitHeight
            visible: Network.active !== null

            Flickable {
                id: connectedFlick
                anchors.fill: parent
                contentWidth: connectedFlick.width * 2 + 8
                contentHeight: connectedFlick.height
                interactive: false
                clip: true

                x: 0

                NumberAnimation {
                    id: slideInAnim
                    target: connectedFlick
                    property: "x"
                    from: -connectedFlick.width
                    to: 0
                    duration: 500
                    easing.type: Easing.OutExpo
                }

                Connections {
                    target: Network
                    function onActiveChanged() {
                        if (Network.active !== null) {
                            slideInAnim.start();
                        }
                    }
                }

                property bool showActions: false
                contentX: showActions ? (connectedFlick.width + 8) : 0

                Behavior on contentX {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutExpo
                    }
                }

                Row {
                    height: connectedFlick.height
                    spacing: 8

                    // PAGE 1: Connected Info & Action toggle
                    RowLayout {
                        width: connectedFlick.width
                        height: connectedFlick.height
                        spacing: 8

                        // Connected pill (wide)
                        Rectangle {
                            id: connectedRect
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: height / 2
                            color: Appearance.colors.colPrimary

                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 20
                                    rightMargin: 16
                                }
                                spacing: 10

                                Item {
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22

                                    property int strength: Network.active?.strength ?? 0
                                    readonly property string fullWifiIcon: "wifi"

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: parent.fullWifiIcon
                                        iconSize: 22
                                        opacity: 0.3
                                        color: Appearance.colors.colOnPrimary
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: parent.strength > 80 ? "android_wifi_4_bar"
                                            : parent.strength > 60 ? "android_wifi_3_bar"
                                            : parent.strength > 40 ? "wifi_2_bar"
                                            : parent.strength > 20 ? "wifi_1_bar"
                                            : "signal_wifi_0_bar"
                                        fill: 1
                                        iconSize: 22
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: Network.active?.ssid ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: true
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }

                        // Action Button (Slide to Quick Settings, or Cancel if connecting)
                        Rectangle {
                            id: wifiActionBtn
                            Layout.preferredWidth: 56
                            Layout.fillHeight: true
                            radius: height / 2
                            color: wifiActionMouse.containsPress ? Appearance.colors.colPrimaryActive
                                   : wifiActionMouse.containsMouse ? Appearance.colors.colPrimaryHover
                                   : Appearance.colors.colPrimary

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            MouseArea {
                                id: wifiActionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Network.active !== null) {
                                        connectedFlick.showActions = true;
                                    } else {
                                        Network.disconnectWifiNetwork();
                                    }
                                }
                            }

                            StyledToolTip {
                                text: Network.active !== null ? Translation.tr("Quick Actions") : Translation.tr("Cancel Connection")
                                alternativeVisibleCondition: wifiActionMouse.containsMouse
                                extraVisibleCondition: false
                            }

                            Item {
                                anchors.centerIn: parent
                                width: 24
                                height: 24

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "check"
                                    iconSize: 22
                                    color: Appearance.colors.colOnPrimary
                                    opacity: (Network.active !== null && !wifiActionMouse.containsMouse) ? 1 : 0
                                    scale: (Network.active !== null && !wifiActionMouse.containsMouse) ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "arrow_back"
                                    iconSize: 22
                                    color: Appearance.colors.colOnPrimary
                                    opacity: (Network.active !== null && wifiActionMouse.containsMouse) ? 1 : 0
                                    scale: (Network.active !== null && wifiActionMouse.containsMouse) ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                }

                                MaterialShape {
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    shape: MaterialShape.Shape.Cookie7Sided
                                    color: Appearance.colors.colOnPrimary
                                    opacity: (Network.active === null && !wifiActionMouse.containsMouse) ? 1 : 0
                                    scale: (Network.active === null && !wifiActionMouse.containsMouse) ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    RotationAnimator on rotation {
                                        from: 0
                                        to: 360
                                        duration: 2000
                                        loops: Animation.Infinite
                                        running: (Network.active === null && !wifiActionMouse.containsMouse)
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 22
                                    color: Appearance.colors.colOnPrimary
                                    opacity: (Network.active === null && wifiActionMouse.containsMouse) ? 1 : 0
                                    scale: (Network.active === null && wifiActionMouse.containsMouse) ? 1 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                }
                            }
                        }
                    }

                    // PAGE 2: Quick Settings buttons
                    RowLayout {
                        width: connectedFlick.width
                        height: connectedFlick.height
                        spacing: 8

                        // Back Button (arrow_forward)
                        Rectangle {
                            id: wifiBackBtn
                            Layout.preferredWidth: 56
                            Layout.fillHeight: true
                            radius: height / 2
                            color: wifiBackMouse.containsPress ? Appearance.colors.colPrimaryActive
                                   : wifiBackMouse.containsMouse ? Appearance.colors.colPrimaryHover
                                   : Appearance.colors.colPrimary

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            MouseArea {
                                id: wifiBackMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: connectedFlick.showActions = false
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "arrow_forward"
                                iconSize: 24
                                color: Appearance.colors.colOnPrimary
                            }
                        }

                        // Disconnect Button (outline / border and no fill)
                        Rectangle {
                            id: wifiDisconnectBtn
                            Layout.fillWidth: true
                            Layout.preferredWidth: wifiDisconnectRow.implicitWidth + 32
                            Layout.fillHeight: true
                            radius: height / 2
                            color: "transparent"
                            
                            border.width: 2
                            border.color: wifiDisconnectMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOutline

                            Behavior on border.color {
                                ColorAnimation { duration: 150 }
                            }

                            MouseArea {
                                id: wifiDisconnectMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Network.disconnectWifiNetwork();
                                    connectedFlick.showActions = false;
                                }
                            }

                            RowLayout {
                                id: wifiDisconnectRow
                                anchors.centerIn: parent
                                spacing: 6
                                
                                MaterialSymbol {
                                    text: "wifi_off"
                                    iconSize: 18
                                    color: wifiDisconnectMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                
                                StyledText {
                                    text: Translation.tr("Disconnect")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: true
                                    color: wifiDisconnectMouse.containsMouse ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                            }
                        }

                        // Forget Button (filled colErrorContainer)
                        Rectangle {
                            id: wifiForgetBtn
                            Layout.fillWidth: true
                            Layout.preferredWidth: wifiForgetRow.implicitWidth + 32
                            Layout.fillHeight: true
                            radius: height / 2
                            
                            color: wifiForgetMouse.containsPress ? Appearance.colors.colErrorContainerActive
                                   : wifiForgetMouse.containsMouse ? Appearance.colors.colErrorContainerHover
                                   : Appearance.colors.colErrorContainer

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            MouseArea {
                                id: wifiForgetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Network.active) {
                                        Network.forgetWifiNetwork(Network.active.ssid);
                                    }
                                    connectedFlick.showActions = false;
                                }
                            }

                            RowLayout {
                                id: wifiForgetRow
                                anchors.centerIn: parent
                                spacing: 6
                                
                                MaterialSymbol {
                                    text: "delete"
                                    iconSize: 18
                                    color: Appearance.colors.colOnErrorContainer
                                }
                                
                                StyledText {
                                    text: Translation.tr("Forget")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.bold: true
                                    color: Appearance.colors.colOnErrorContainer
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Section: available ────────────────────────────
        // Drive both the header/list visibility and the empty placeholder from
        // the repeater count (already O(1)): the list itself filters out the
        // active AP, so a scan that only knows the connected network would
        // otherwise leave this section blank with no empty state.
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 16
            font.pixelSize: Appearance.font.pixelSize.normal
            font.bold: true
            color: Appearance.colors.colSubtext
            visible: root.inlineWifiState || (!root.wifiOff && root.wifiCount > 0)
            text: !root.wifiOff && root.wifiCount > 0 ? Translation.tr("Available Wi-Fi") : Translation.tr("Wi-Fi")
        }

        // Available list with dynamic radius
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: !root.wifiOff && root.wifiCount > 0

            Repeater {
                id: repeaterAvailable
                model: ScriptModel {
                    values: Network.friendlyWifiNetworks.filter(n => !n.active)
                }
                delegate: WifiNetworkItem {
                    Layout.fillWidth: true
                    required property WifiAccessPoint modelData
                    required property int index
                    wifiNetwork: modelData
                    isFirst: index === 0
                    isLast: index === (repeaterAvailable.count - 1)
                }

            }
        }

        // Wi-Fi off / empty while Ethernet carries the connection.
        Rectangle {
            id: inlineWifiCard

            readonly property string wifiState: root.wifiOff ? "off"
                : root.wifiScanning ? "scanning" : "empty"

            Layout.fillWidth: true
            visible: root.inlineWifiState
            implicitHeight: inlineWifiRow.implicitHeight + 24
            radius: Appearance.rounding.large
            // Outlined, not filled: an empty Wi-Fi list is a quiet state next
            // to the Ethernet card, and the tonal icon and action read on it.
            color: "transparent"
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            RowLayout {
                id: inlineWifiRow

                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 12
                }
                spacing: 12

                MaterialShapeWrappedMaterialSymbol {
                    text: inlineWifiCard.wifiState === "off" ? "wifi_off" : "wifi_find"
                    iconSize: 22
                    padding: 10
                    shape: inlineWifiCard.wifiState === "off" ? MaterialShape.Shape.Cookie7Sided
                        : MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colSecondaryContainer
                    colSymbol: Appearance.colors.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: inlineWifiCard.wifiState === "off" ? Translation.tr("Wi-Fi is off")
                            : inlineWifiCard.wifiState === "scanning" ? Translation.tr("Searching for Wi-Fi…")
                            : Translation.tr("No Wi-Fi networks nearby")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("You're online through Ethernet")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    id: inlineWifiAction

                    visible: inlineWifiCard.wifiState !== "scanning"
                    implicitHeight: 36
                    implicitWidth: inlineWifiActionRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: {
                        if (inlineWifiCard.wifiState === "off")
                            Network.enableWifi();
                        else
                            Network.rescanWifi();
                    }

                    contentItem: RowLayout {
                        id: inlineWifiActionRow

                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: inlineWifiCard.wifiState === "off" ? "power_settings_new" : "refresh"
                            iconSize: 18
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            text: inlineWifiCard.wifiState === "off" ? Translation.tr("Turn on") : Translation.tr("Scan")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }

        // Off / empty placeholders when nothing else is connected. Sized by the
        // layout: filling the parent would centre them over the whole column.
        PagePlaceholder {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            fillParent: false
            icon: "wifi_off"
            title: Translation.tr("Wi-Fi is off")
            description: Translation.tr("Turn on Wi-Fi to see networks")
            shape: MaterialShape.Shape.Cookie7Sided
            shown: !root.wiredOnline && root.wifiOff
        }

        PagePlaceholder {
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            fillParent: false
            icon: "wifi_find"
            title: Translation.tr("No Wi-Fi networks found")
            shape: MaterialShape.Shape.Cookie7Sided
            shown: !root.wiredOnline && root.wifiListEmpty && !root.wifiScanning
        }

        NetworkConnectionInfoGrid {}
    }
}
