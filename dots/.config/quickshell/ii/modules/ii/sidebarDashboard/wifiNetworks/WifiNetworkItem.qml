import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    required property WifiAccessPoint wifiNetwork

    property bool isFirst: false
    property bool isLast: false

    // Derived state
    readonly property bool isActive: wifiNetwork?.active ?? false
    readonly property bool isAskingPassword: wifiNetwork?.askingPassword ?? false
    readonly property bool isConnecting: Network.wifiConnectTarget === root.wifiNetwork && !isActive
    readonly property bool hasError: Network.lastWifiExitCode !== 0 && Network.wifiErrorTarget === root.wifiNetwork

    onHasErrorChanged: {
        if (hasError) {
            shakeAnim.start();
        }
    }

    // Radius system
    readonly property real rFull: height / 2
    readonly property real rOuter: Appearance.rounding.large
    readonly property real rInner: Appearance.rounding.verysmall

    readonly property int activePassIdx: {
        let p = parent;
        while (p && typeof p.activePasswordIndex === "undefined") {
            p = p.parent;
        }
        return p ? p.activePasswordIndex : -1;
    }
    readonly property bool isPasswordActive: activePassIdx === index
    readonly property bool isPrevPasswordActive: activePassIdx === index + 1
    readonly property bool isNextPasswordActive: activePassIdx === index - 1

    readonly property real topLeftRadius: isPasswordActive ? rFull : (isNextPasswordActive ? rFull : (isFirst ? rOuter : rInner))
    readonly property real topRightRadius: isPasswordActive ? rFull : (isNextPasswordActive ? rFull : (isFirst ? rOuter : rInner))
    readonly property real bottomLeftRadius: isPasswordActive ? rFull : (isPrevPasswordActive ? rFull : (isLast ? rOuter : rInner))
    readonly property real bottomRightRadius: isPasswordActive ? rFull : (isPrevPasswordActive ? rFull : (isLast ? rOuter : rInner))

    onIsAskingPasswordChanged: {
        if (root.isAskingPassword) {
            if (Network.wifiErrorTarget === root.wifiNetwork) {
                Network.wifiErrorTarget = null;
                Network.lastWifiExitCode = 0;
            }
        } else {
            passwordInput.text = "";
        }
        let p = parent;
        while (p && typeof p.activePasswordIndex === "undefined") {
            p = p.parent;
        }
        if (p) {
            if (root.isAskingPassword) {
                p.activePasswordIndex = index;
            } else {
                if (p.activePasswordIndex === index) {
                    p.activePasswordIndex = -1;
                }
            }
        }
    }

    implicitHeight: 56
    height: implicitHeight
    clip: true

    // Sliding Flickable Container (Style similar to Bluetooth actions menu)
    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: flick.width * 2 + 8
        contentHeight: flick.height
        interactive: false
        clip: true

        contentX: root.isAskingPassword ? (flick.width + 8) : 0

        Behavior on contentX {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutExpo
            }
        }

        Row {
            height: flick.height
            spacing: 8

            // PAGE 1: Normal wifi network card (mainRow)
            Rectangle {
                id: mainRow
                width: flick.width
                height: flick.height
                
                topLeftRadius: root.topLeftRadius
                topRightRadius: root.topRightRadius
                bottomLeftRadius: root.bottomLeftRadius
                bottomRightRadius: root.bottomRightRadius

                color: itemMouseArea.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                       : itemMouseArea.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                       : Appearance.colors.colSurfaceContainerHighest

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }

                Behavior on topLeftRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                Behavior on topRightRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                Behavior on bottomLeftRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                Behavior on bottomRightRadius { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 20
                        rightMargin: 16
                    }
                    spacing: 10

                    Item {
                        width: 22
                        height: 22

                        MaterialSymbol {
                            anchors.centerIn: parent
                            property int strength: root.wifiNetwork?.strength ?? 0
                            text: strength > 80 ? "android_wifi_4_bar" 
                                  : strength > 60 ? "android_wifi_3_bar" 
                                  : strength > 40 ? "wifi_2_bar" 
                                  : strength > 20 ? "wifi_1_bar" 
                                  : "signal_wifi_0_bar"
                            fill: 1
                            iconSize: 22
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.wifiNetwork?.ssid ?? Translation.tr("Unknown")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                        textFormat: Text.PlainText
                    }

                    Item {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: (root.wifiNetwork?.isSecure ?? false) && !root.isConnecting
                            text: "lock"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.normal
                            color: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.3)
                        }

                        MaterialShape {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            shape: MaterialShape.Shape.Cookie7Sided
                            color: Appearance.colors.colPrimary
                            visible: root.isConnecting
                            RotationAnimator on rotation {
                                from: 0
                                to: 360
                                duration: 2000
                                loops: Animation.Infinite
                                running: root.isConnecting
                            }
                        }
                    }
                }

                MouseArea {
                    id: itemMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.isConnecting
                    onClicked: {
                        Network.connectToWifiNetwork(root.wifiNetwork);
                    }
                }

                StyledToolTip {
                    text: root.wifiNetwork.isSecure ? Translation.tr("Connect with password") : Translation.tr("Connect")
                    alternativeVisibleCondition: itemMouseArea.containsMouse
                    extraVisibleCondition: false
                }
            }

            // PAGE 2: Password entry row (passwordRow)
            RowLayout {
                id: passwordRow
                width: flick.width
                height: flick.height
                spacing: 4

                // Lock circle — left side dynamic, right side inner
                Rectangle {
                    id: lockCircle
                    width: 56
                    height: 56
                    color: root.hasError ? Appearance.colors.colError
                           : (cancelMouseArea.containsMouse ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHighest)

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    radius: root.rFull

                    transform: Translate {
                        id: shakeTranslate
                        x: 0
                    }

                    SequentialAnimation {
                        id: shakeAnim
                        loops: 1

                        NumberAnimation { target: shakeTranslate; property: "x"; from: 0; to: -8; duration: 50; easing.type: Easing.Linear }
                        NumberAnimation { target: shakeTranslate; property: "x"; from: -8; to: 8; duration: 50; easing.type: Easing.Linear }
                        NumberAnimation { target: shakeTranslate; property: "x"; from: 8; to: -8; duration: 50; easing.type: Easing.Linear }
                        NumberAnimation { target: shakeTranslate; property: "x"; from: -8; to: 8; duration: 50; easing.type: Easing.Linear }
                        NumberAnimation { target: shakeTranslate; property: "x"; from: 8; to: -4; duration: 50; easing.type: Easing.Linear }
                        NumberAnimation { target: shakeTranslate; property: "x"; from: -4; to: 4; duration: 50; easing.type: Easing.Linear }
                        NumberAnimation { target: shakeTranslate; property: "x"; from: 4; to: 0; duration: 50; easing.type: Easing.Linear }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.hasError ? "close" : (cancelMouseArea.containsMouse ? "close" : "password")
                        fill: 1
                        iconSize: 22
                        color: root.hasError ? Appearance.colors.colOnError
                               : (cancelMouseArea.containsMouse ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSurface)

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    MouseArea {
                        id: cancelMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.wifiNetwork.askingPassword = false;
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Cancel")
                        alternativeVisibleCondition: cancelMouseArea.containsMouse
                        extraVisibleCondition: false
                    }
                }

                // Password input (middle)
                Rectangle {
                    Layout.fillWidth: true
                    height: 56
                    radius: root.rInner
                    color: Appearance.colors.colSurfaceContainerHighest

                    // Material shape chars overlay (rendered first = behind)
                    StyledFlickable {
                        id: charsDisplay
                        anchors {
                            fill: parent
                            leftMargin: 16
                            rightMargin: 16
                        }
                        clip: true

                        readonly property int length: passwordInput.text.length
                        readonly property color shapeColor: Appearance.colors.colOnSurface
                        readonly property int charSize: Appearance.font.pixelSize.normal

                        contentWidth: charsRow.implicitWidth
                        contentX: Math.max(contentWidth - width, 0)
                        Behavior on contentX {
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(charsDisplay)
                        }

                        Row {
                            id: charsRow
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 0

                            Repeater {
                                model: ScriptModel {
                                    values: Array(charsDisplay.length)
                                }

                                delegate: Rectangle {
                                    id: charItem
                                    required property int index
                                    implicitWidth: charsDisplay.charSize
                                    implicitHeight: charsDisplay.charSize
                                    color: "transparent"

                                    SequentialAnimation {
                                        id: waveJumpAnim
                                        running: root.isConnecting
                                        loops: Animation.Infinite

                                        PauseAnimation {
                                            duration: charItem.index * 120
                                        }

                                        NumberAnimation {
                                            target: materialShape
                                            property: "anchors.verticalCenterOffset"
                                            from: 0
                                            to: -8
                                            duration: 350
                                            easing.type: Easing.OutQuad
                                        }

                                        NumberAnimation {
                                            target: materialShape
                                            property: "anchors.verticalCenterOffset"
                                            from: -8
                                            to: 0
                                            duration: 350
                                            easing.type: Easing.InOutQuad
                                        }

                                        PauseAnimation {
                                            duration: Math.max(0, 2000 - (charItem.index * 120) - 700)
                                        }
                                    }

                                    MaterialShape {
                                        id: materialShape
                                        anchors.centerIn: parent

                                        property list<var> charShapes: [
                                            MaterialShape.Shape.Clover4Leaf,
                                            MaterialShape.Shape.Arrow,
                                            MaterialShape.Shape.Pill,
                                            MaterialShape.Shape.SoftBurst,
                                            MaterialShape.Shape.Diamond,
                                            MaterialShape.Shape.ClamShell,
                                            MaterialShape.Shape.Pentagon
                                        ]

                                        property int randomShapeIndex: Math.floor(Math.random() * charShapes.length)
                                        shape: charShapes[randomShapeIndex]

                                        color: charsDisplay.shapeColor
                                        implicitSize: 0
                                        opacity: 0
                                        scale: 0.5

                                        Component.onCompleted: {
                                            appearAnim.start();
                                        }

                                        ParallelAnimation {
                                            id: appearAnim
                                            NumberAnimation {
                                                target: materialShape
                                                properties: "opacity"
                                                to: 1
                                                duration: 50
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                            NumberAnimation {
                                                target: materialShape
                                                properties: "scale"
                                                to: 1
                                                duration: 220
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                                            }
                                            NumberAnimation {
                                                target: materialShape
                                                properties: "implicitSize"
                                                to: charsDisplay.charSize - 2
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                                            }
                                            ColorAnimation {
                                                target: materialShape
                                                properties: "color"
                                                from: Appearance.colors.colPrimary
                                                to: charsDisplay.shapeColor
                                                duration: 1000
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Invisible TextInput for input handling (rendered on top = receives events)
                    TextInput {
                        id: passwordInput
                        anchors {
                            fill: parent
                            leftMargin: 16
                            rightMargin: 16
                        }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: "transparent"
                        cursorVisible: false
                        cursorDelegate: Component { Item {} }
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        clip: true

                        onVisibleChanged: if (visible)
                            forceActiveFocus()

                        StyledText {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Password")
                            color: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.4)
                            font.pixelSize: Appearance.font.pixelSize.small
                            visible: passwordInput.text.length === 0
                        }

                        onAccepted: {
                            Network.connectWithPassword(root.wifiNetwork.ssid, passwordInput.text);
                        }
                    }

                    // IBeam cursor for text input area
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.NoButton // pass-through clicks to TextInput
                    }
                }

                // Confirm/status circle — always rFull on the right side
                Rectangle {
                    id: confirmCircle
                    width: 56
                    height: 56
                    color: root.isConnecting ? Appearance.colors.colPrimaryContainer : (Network.lastWifiExitCode !== 0 && Network.wifiConnectTarget === root.wifiNetwork) ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    radius: root.rFull

                    // Checkmark
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: (Network.lastWifiExitCode !== 0 && Network.wifiConnectTarget === root.wifiNetwork) ? "close" : "check"
                        fill: 1
                        iconSize: 22
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: root.isConnecting ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    // Spinner
                    MaterialShape {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        shape: MaterialShape.Shape.Cookie7Sided
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: root.isConnecting ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 2000
                            loops: Animation.Infinite
                            running: root.isConnecting
                        }
                    }

                    MouseArea {
                        id: confirmMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.isConnecting
                        onClicked: {
                            Network.connectWithPassword(root.wifiNetwork.ssid, passwordInput.text);
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Connect")
                        alternativeVisibleCondition: confirmMouseArea.containsMouse
                        extraVisibleCondition: false
                    }
                }
            }
        }
    }
}
