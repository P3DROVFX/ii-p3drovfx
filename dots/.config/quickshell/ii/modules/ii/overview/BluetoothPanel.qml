pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Bluetooth

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property string searchQuery: ""

    readonly property int panelWidth: Config.options.search.clipboard.panelWidth ?? 860
    readonly property real listColumnRatio: 0.40
    readonly property int listColumnWidth: Math.round(panelWidth * listColumnRatio)
    readonly property int detailColumnWidth: panelWidth - listColumnWidth

    implicitWidth: panelWidth
    implicitHeight: 520

    readonly property bool btAvailable: BluetoothStatus.available
    readonly property bool btEnabled: BluetoothStatus.enabled

    property var connectingDevices: ({})
    property var disconnectingDevices: ({})
    property bool isEnabling: false

    onBtEnabledChanged: {
        if (btEnabled) {
            isEnabling = false;
        }
    }

    Timer {
        id: enablingTimeout
        interval: 4000
        repeat: false
        onTriggered: root.isEnabling = false
    }

    Timer {
        id: connectionTimeoutTimer
        interval: 1000
        repeat: true
        running: Object.keys(root.connectingDevices).length > 0 || Object.keys(root.disconnectingDevices).length > 0
        onTriggered: {
            const now = Date.now();
            let changed = false;
            let tempCon = Object.assign({}, root.connectingDevices);
            let tempDis = Object.assign({}, root.disconnectingDevices);

            for (const addr in tempCon) {
                if (tempCon[addr] === true) {
                    // Initialize timestamp
                    tempCon[addr] = now;
                } else if (now - tempCon[addr] > 12000) { // 12s timeout
                    delete tempCon[addr];
                    changed = true;
                }
            }

            for (const addr in tempDis) {
                if (tempDis[addr] === true) {
                    tempDis[addr] = now;
                } else if (now - tempDis[addr] > 12000) {
                    delete tempDis[addr];
                    changed = true;
                }
            }

            if (changed) {
                root.connectingDevices = tempCon;
                root.disconnectingDevices = tempDis;
            }
        }
    }

    Connections {
        target: BluetoothStatus
        ignoreUnknownSignals: true
        function onDeviceConnected(device) {
            if (device && device.address) {
                let tempCon = Object.assign({}, root.connectingDevices);
                if (tempCon[device.address]) {
                    delete tempCon[device.address];
                    root.connectingDevices = tempCon;
                }
            }
        }
        function onDeviceDisconnected(device) {
            if (device && device.address) {
                let tempDis = Object.assign({}, root.disconnectingDevices);
                if (tempDis[device.address]) {
                    delete tempDis[device.address];
                    root.disconnectingDevices = tempDis;
                }
            }
        }
    }

    onDeviceListChanged: {
        if (selectedIndex >= deviceList.length && deviceList.length > 0)
            selectedIndex = deviceList.length - 1;
    }

    property var deviceList: {
        const q = root.searchQuery.toLowerCase();
        let all = Array.from(BluetoothStatus.friendlyDeviceList);
        if (q) {
            all = all.filter(d => (d.name || "").toLowerCase().includes(q) || (d.address || "").toLowerCase().includes(q));
        }

        // Sort: paired devices first, then unpaired
        all.sort((a, b) => {
            if (a.paired && !b.paired)
                return -1;
            if (!a.paired && b.paired)
                return 1;
            return 0;
        });

        return all;
    }

    property int selectedIndex: 0
    property int selectedActionIndex: -1

    readonly property var selectedDevice: deviceList.length > 0 && selectedIndex >= 0 ? deviceList[Math.min(selectedIndex, deviceList.length - 1)] : null
    property bool isScanning: false

    // Random shape and custom image properties
    property list<int> detailShapes: [MaterialShape.Shape.Cookie7Sided, MaterialShape.Shape.SoftBurst, MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Pentagon, MaterialShape.Shape.Sunny, MaterialShape.Shape.Cookie4Sided, MaterialShape.Shape.Arch, MaterialShape.Shape.Fan, MaterialShape.Shape.SemiCircle]
    property int currentRandomShape: MaterialShape.Shape.Cookie7Sided
    onSelectedDeviceChanged: {
        if (selectedDevice) {
            currentRandomShape = detailShapes[Math.floor(Math.random() * detailShapes.length)];
        }
    }

    function getDeviceImageSource(device) {
        if (!device)
            return "";
        let custom = Config.options.bluetoothDeviceImages.find(d => d.mac === device.address);
        if (custom) {
            return "file://" + Directories.shellConfig + "/bluetooth_images/" + custom.image;
        }
        return "";
    }
    readonly property string deviceImageSource: getDeviceImageSource(selectedDevice)
    readonly property bool hasCustomImage: deviceImageSource !== ""

    Timer {
        id: scanTimer
        interval: 12000
        repeat: false
        onTriggered: root.isScanning = false
    }

    function startScan() {
        if (!root.btEnabled)
            return;
        root.isScanning = true;
        scanTimer.restart();
        Quickshell.execDetached(["bash", "-c", "bluetoothctl scan on &"]);
    }

    function stopScan() {
        root.isScanning = false;
        scanTimer.stop();
        Quickshell.execDetached(["bash", "-c", "bluetoothctl scan off"]);
    }

    function toggleBluetooth() {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return;
        if (!adapter.enabled) {
            root.isEnabling = true;
            enablingTimeout.restart();
        } else {
            root.isEnabling = false;
        }
        adapter.enabled = !adapter.enabled;
    }

    function navigateUp() {
        selectedActionIndex = -1;
        if (selectedIndex > 0) {
            selectedIndex--;
            deviceListView.positionViewAtIndex(selectedIndex, ListView.Contain);
        } else if (selectedIndex === 0) {
            selectedIndex = -1; // Go to Scan button
        } else if (selectedIndex === -1) {
            selectedIndex = -2; // Go to Power button
        }
    }

    function navigateDown() {
        selectedActionIndex = -1;
        if (selectedIndex === -2) {
            selectedIndex = -1; // Go to Scan button
        } else if (selectedIndex === -1) {
            selectedIndex = deviceList.length > 0 ? 0 : -1; // Go to first item or stay
        } else if (selectedIndex < deviceList.length - 1) {
            selectedIndex++;
            deviceListView.positionViewAtIndex(selectedIndex, ListView.Contain);
        }
    }

    function navigateLeft() {
        if (selectedIndex === -1) {
            selectedIndex = -2; // Go from Scan to Power button
        } else if (selectedActionIndex > -1) {
            selectedActionIndex--;
        }
    }

    function navigateRight() {
        if (selectedIndex === -2) {
            selectedIndex = -1; // Go from Power to Scan button
        } else if (selectedIndex >= 0) {
            const maxIdx = (selectedDevice?.paired ? 1 : 0) + 1; // Connect (0), Forget (1 if paired), Copy MAC (1 or 2)
            if (selectedActionIndex < maxIdx)
                selectedActionIndex++;
        }
    }

    function activateSelected() {
        if (selectedIndex === -1) {
            if (root.isScanning)
                root.stopScan();
            else
                root.startScan();
            return;
        }
        if (selectedIndex === -2) {
            root.toggleBluetooth();
            return;
        }
        if (!selectedDevice)
            return;
        if (selectedActionIndex <= 0) {
            if (selectedDevice.connected) {
                let temp = Object.assign({}, root.disconnectingDevices);
                temp[selectedDevice.address] = true;
                root.disconnectingDevices = temp;
                selectedDevice.disconnect();
            } else {
                root.stopScan();
                let temp = Object.assign({}, root.connectingDevices);
                temp[selectedDevice.address] = true;
                root.connectingDevices = temp;
                selectedDevice.connect();
            }
        } else if (selectedActionIndex === 1) {
            if (selectedDevice.paired)
                selectedDevice.forget();
            else
                Quickshell.clipboardText = selectedDevice.address; // Copy MAC as second action if unpaired
        } else if (selectedActionIndex === 2) {
            Quickshell.clipboardText = selectedDevice.address; // Copy MAC as third action if paired
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Up) {
            navigateUp();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            navigateDown();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            navigateLeft();
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            navigateRight();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            activateSelected();
            event.accepted = true;
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: listColumn
            Layout.preferredWidth: root.listColumnWidth
            Layout.fillHeight: true
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 8
                    Layout.bottomMargin: 4
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        text: root.deviceList.length + " " + (root.deviceList.length === 1 ? Translation.tr("device") : Translation.tr("devices"))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    RippleButton {
                        id: scanBtn
                        implicitWidth: 84
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: (root.selectedIndex === -1 || scanBtn.hovered) ? Appearance.colors.colSurfaceContainerHighest : (root.isScanning ? Appearance.colors.colPrimaryContainer : "transparent")
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        PointingHandInteraction {}

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.buttonRadius
                            color: "transparent"
                            border.width: 1
                            border.color: root.isScanning ? Appearance.colors.colPrimaryContainer : Appearance.colors.colOutlineVariant
                        }

                        onClicked: {
                            root.selectedIndex = -1;
                            if (root.isScanning)
                                root.stopScan();
                            else
                                root.startScan();
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "refresh"
                                iconSize: 16
                                color: (root.selectedIndex === -1 || scanBtn.hovered || root.isScanning) ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant

                                RotationAnimator on rotation {
                                    from: 0
                                    to: 360
                                    duration: 1200
                                    loops: Animation.Infinite
                                    running: root.isScanning
                                }
                            }

                            StyledText {
                                text: Translation.tr("Scan")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: (root.selectedIndex === -1 || scanBtn.hovered || root.isScanning) ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        StyledToolTip {
                            text: root.isScanning ? Translation.tr("Stop scanning") : Translation.tr("Scan for devices")
                        }
                    }

                    // Premium inline toggle switch
                    RippleButton {
                        id: powerBtn
                        implicitWidth: 100
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        colBackground: (root.selectedIndex === -2 || powerBtn.hovered) ? Appearance.colors.colSurfaceContainerHighest : "transparent"
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        PointingHandInteraction {}
                        onClicked: {
                            root.selectedIndex = -2;
                            root.toggleBluetooth();
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            StyledText {
                                text: root.btEnabled ? Translation.tr("On") : Translation.tr("Off")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: (root.selectedIndex === -2 || powerBtn.hovered) ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                            }

                            // Toggle track
                            Rectangle {
                                width: 40
                                height: 20
                                radius: 10
                                color: root.btEnabled ? ((root.selectedIndex === -2 || powerBtn.hovered) ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimary) : ((root.selectedIndex === -2 || powerBtn.hovered) ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colSurfaceContainerHigh)
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 200
                                    }
                                }

                                // Toggle thumb
                                Rectangle {
                                    id: thumb
                                    y: 2
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: root.btEnabled ? Appearance.colors.colOnPrimary : ((root.selectedIndex === -2 || powerBtn.hovered) ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant)
                                    x: root.btEnabled ? 22 : 2

                                    Behavior on x {
                                        NumberAnimation {
                                            duration: 200
                                            easing.type: Easing.OutQuint
                                        }
                                    }
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 200
                                        }
                                    }
                                }
                            }
                        }

                        StyledToolTip {
                            text: root.btEnabled ? Translation.tr("Disable Bluetooth") : Translation.tr("Enable Bluetooth")
                        }
                    }
                }

                Loader {
                    active: root.isScanning
                    visible: active
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    Layout.bottomMargin: 4

                    sourceComponent: StyledProgressBar {
                        Layout.fillWidth: true
                        valueBarHeight: 3
                        indeterminate: true
                        highlightColor: Appearance.colors.colPrimary
                        trackColor: Appearance.colors.colSurfaceContainerHigh
                    }
                }

                Loader {
                    active: !root.btAvailable || !root.btEnabled || root.isEnabling
                    visible: active
                    Layout.fillWidth: true
                    Layout.margins: 12

                    sourceComponent: ColumnLayout {
                        spacing: 12

                        Item {
                            Layout.fillHeight: true
                            visible: root.isEnabling
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: {
                                if (!root.btAvailable)
                                    return "bluetooth_searching";
                                if (root.isEnabling)
                                    return "bluetooth_searching";
                                return "bluetooth_disabled";
                            }
                            iconSize: 48
                            color: Appearance.colors.colPrimary
                            opacity: 0.8

                            RotationAnimator on rotation {
                                from: 0
                                to: 360
                                duration: 2000
                                loops: Animation.Infinite
                                running: root.isEnabling
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: {
                                if (!root.btAvailable)
                                    return Translation.tr("No Bluetooth adapter");
                                if (root.isEnabling)
                                    return Translation.tr("Enabling Bluetooth...");
                                return Translation.tr("Bluetooth is off");
                            }
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !root.isEnabling && root.btAvailable
                            text: Translation.tr("Toggle Bluetooth at the top to search")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.6
                        }

                        Item {
                            Layout.fillHeight: true
                            visible: root.isEnabling
                        }
                    }
                }

                Loader {
                    active: root.btAvailable && root.btEnabled && !root.isEnabling && root.deviceList.length === 0
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 12

                    sourceComponent: ColumnLayout {
                        spacing: 12

                        Item {
                            Layout.fillHeight: true
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "bluetooth"
                            iconSize: 48
                            color: Appearance.colors.colPrimary
                            opacity: 0.8

                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 1.0
                                    to: 1.15
                                    duration: 1000
                                    easing.type: Easing.InOutQuad
                                }
                                NumberAnimation {
                                    from: 1.15
                                    to: 1.0
                                    duration: 1000
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Searching for devices...")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Make sure your device is in pairing mode.")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.7
                        }

                        Item {
                            Layout.fillHeight: true
                        }
                    }
                }

                ListView {
                    id: deviceListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    topMargin: 4
                    bottomMargin: 4
                    spacing: 2
                    visible: root.btAvailable && root.btEnabled && !root.isEnabling && root.deviceList.length > 0

                    model: root.deviceList

                    currentIndex: root.selectedIndex
                    highlightMoveDuration: 80

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Item {
                            id: maskRoot
                            width: deviceListView.width
                            height: deviceListView.height

                            property color topFadeColor: !deviceListView.atYBeginning ? "transparent" : "white"
                            property color bottomFadeColor: !deviceListView.atYEnd ? "transparent" : "white"

                            Behavior on topFadeColor {
                                ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
                            }
                            Behavior on bottomFadeColor {
                                ColorAnimation { duration: 200; easing.type: Easing.OutQuad }
                            }

                            Column {
                                anchors.fill: parent
                                spacing: 0

                                Rectangle {
                                    width: parent.width
                                    height: Math.min(36, parent.height / 2)
                                    color: "transparent"
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: maskRoot.topFadeColor }
                                        GradientStop { position: 1.0; color: "white" }
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: Math.max(0, parent.height - Math.min(36, parent.height / 2) * 2)
                                    color: "white"
                                }

                                Rectangle {
                                    width: parent.width
                                    height: Math.min(36, parent.height / 2)
                                    color: "transparent"
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "white" }
                                        GradientStop { position: 1.0; color: maskRoot.bottomFadeColor }
                                    }
                                }
                            }
                        }
                    }

                    ScrollBar.vertical: StyledScrollBar {}

                    delegate: Column {
                        id: delegateContainer
                        required property var modelData
                        required property int index

                        width: deviceListView.width
                        spacing: 0

                        readonly property var dev: modelData
                        readonly property bool isFirstUnpaired: !dev.paired && (index === 0 || (deviceListView.model[index - 1] && deviceListView.model[index - 1].paired))

                        opacity: 0
                        transform: Translate {
                            id: devSlide
                            y: -10
                        }

                        Component.onCompleted: {
                            devRevealOp.start();
                            devRevealSlide.start();
                        }

                        NumberAnimation {
                            id: devRevealOp
                            target: delegateContainer
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 320
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            id: devRevealSlide
                            target: devSlide
                            property: "y"
                            from: -10
                            to: 0
                            duration: 320
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }

                        // Discover Section Header with line and spacing
                        Item {
                            width: parent.width
                            height: 64
                            visible: delegateContainer.isFirstUnpaired

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.topMargin: 30
                                spacing: 8

                                MaterialSymbol {
                                    text: "search"
                                    iconSize: 16
                                    color: Appearance.colors.colPrimary
                                }

                                StyledText {
                                    text: Translation.tr("DISCOVER")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.5
                                    color: Appearance.colors.colPrimary
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Appearance.colors.colOutlineVariant
                                    opacity: 0.4
                                }
                            }
                        }

                        RippleButton {
                            id: deviceDelegate
                            width: parent.width
                            implicitHeight: 56
                            buttonRadius: 0

                            readonly property var dev: delegateContainer.dev
                            readonly property bool isDevConnected: dev ? dev.connected : false
                            onIsDevConnectedChanged: {
                                if (dev && dev.address) {
                                    let tempCon = Object.assign({}, root.connectingDevices);
                                    let tempDis = Object.assign({}, root.disconnectingDevices);
                                    let changed = false;
                                    if (tempCon[dev.address]) {
                                        delete tempCon[dev.address];
                                        changed = true;
                                    }
                                    if (tempDis[dev.address]) {
                                        delete tempDis[dev.address];
                                        changed = true;
                                    }
                                    if (changed) {
                                        root.connectingDevices = tempCon;
                                        root.disconnectingDevices = tempDis;
                                    }
                                }
                            }
                            readonly property bool isSelected: delegateContainer.index === root.selectedIndex
                            readonly property bool isFirst: delegateContainer.index === 0
                            readonly property bool isLast: delegateContainer.index === deviceListView.count - 1
                            readonly property bool isAboveSelected: root.selectedIndex === delegateContainer.index + 1
                            readonly property bool isBelowSelected: root.selectedIndex === delegateContainer.index - 1
                            readonly property real pillRadius: Math.min(implicitHeight / 2, Appearance.rounding.large)

                            colBackground: isSelected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                            colBackgroundHover: isSelected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighest
                            colRipple: Appearance.colors.colPrimaryContainerActive

                            background: Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                color: deviceDelegate.colBackground
                                antialiasing: true
                                topLeftRadius: deviceDelegate.isFirst ? Appearance.rounding.large : (deviceDelegate.isSelected || deviceDelegate.isBelowSelected ? deviceDelegate.pillRadius : Appearance.rounding.small)
                                topRightRadius: topLeftRadius
                                bottomLeftRadius: deviceDelegate.isLast ? Appearance.rounding.large : (deviceDelegate.isSelected || deviceDelegate.isAboveSelected ? deviceDelegate.pillRadius : Appearance.rounding.small)
                                bottomRightRadius: bottomLeftRadius

                                Behavior on topLeftRadius {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Behavior on topRightRadius {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Behavior on bottomLeftRadius {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Behavior on bottomRightRadius {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }

                            onClicked: root.selectedIndex = delegateContainer.index
                            onDoubleClicked: {
                                root.selectedIndex = delegateContainer.index;
                                root.activateSelected();
                            }

                            PointingHandInteraction {}

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                Item {
                                    id: iconContainer
                                    implicitWidth: 32
                                    implicitHeight: 32

                                    readonly property bool isProcessing: deviceDelegate.dev ? (deviceDelegate.dev.state === 3 || deviceDelegate.dev.state === 2 || !!root.connectingDevices[deviceDelegate.dev.address] || !!root.disconnectingDevices[deviceDelegate.dev.address]) : false

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: Icons.getBluetoothDeviceMaterialSymbol(deviceDelegate.dev?.icon || "")
                                        iconSize: 20
                                        color: deviceDelegate.isSelected ? (deviceDelegate.dev?.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer) : (deviceDelegate.dev?.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant)
                                        visible: !iconContainer.isProcessing
                                    }

                                    MaterialShape {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        shape: MaterialShape.Shape.Cookie7Sided
                                        color: deviceDelegate.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colPrimary
                                        visible: iconContainer.isProcessing

                                        RotationAnimator on rotation {
                                            from: 0
                                            to: 360
                                            duration: 2000
                                            loops: Animation.Infinite
                                            running: iconContainer.isProcessing
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: deviceDelegate.dev?.name || Translation.tr("Unknown device")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.Medium
                                        color: deviceDelegate.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const dev = deviceDelegate.dev;
                                            if (!dev)
                                                return "";
                                            if (dev.connected)
                                                return Translation.tr("Connected");
                                            if (dev.address && (dev.state === 3 || root.connectingDevices[dev.address]))
                                                return Translation.tr("Connecting...");
                                            if (dev.address && (dev.state === 2 || root.disconnectingDevices[dev.address]))
                                                return Translation.tr("Disconnecting...");
                                            if (dev.paired)
                                                return Translation.tr("Paired");
                                            return Translation.tr("Available");
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: {
                                            const dev = deviceDelegate.dev;
                                            if (!dev)
                                                return Appearance.colors.colSubtext;
                                            if (dev.connected)
                                                return deviceDelegate.isSelected ? Appearance.colors.colPrimary : Appearance.colors.colPrimary;
                                            return deviceDelegate.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext;
                                        }
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                        opacity: 0.85
                                    }
                                }

                                Loader {
                                    active: deviceDelegate.dev?.batteryAvailable ?? false
                                    visible: active
                                    Layout.preferredWidth: active ? 28 : 0

                                    sourceComponent: RowLayout {
                                        spacing: 2

                                        MaterialSymbol {
                                            text: {
                                                const b = deviceDelegate.dev?.battery ?? 0;
                                                if (b <= 0.15)
                                                    return "battery_1_bar";
                                                if (b <= 0.35)
                                                    return "battery_3_bar";
                                                if (b <= 0.60)
                                                    return "battery_5_bar";
                                                if (b <= 0.85)
                                                    return "battery_6_bar";
                                                return "battery_full";
                                            }
                                            iconSize: 14
                                            color: {
                                                const b = deviceDelegate.dev?.battery ?? 0;
                                                if (b <= 0.15)
                                                    return Appearance.m3colors.m3error;
                                                return deviceDelegate.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: detailColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Loader {
                    active: root.selectedDevice !== null
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Connections {
                        target: root
                        function onSelectedIndexChanged() {
                            detailReloadTimer.restart();
                        }
                    }

                    Timer {
                        id: detailReloadTimer
                        interval: 16
                        onTriggered: {}
                    }

                    sourceComponent: ColumnLayout {
                        width: parent.width
                        spacing: 0

                        opacity: 0
                        transform: Translate {
                            id: detailSlide
                            y: -8
                        }
                        NumberAnimation on opacity {
                            from: 0
                            to: 1
                            duration: 320
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: detailSlide
                            property: "y"
                            running: true
                            from: -8
                            to: 0
                            duration: 320
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            Layout.alignment: Qt.AlignHCenter

                            MaterialShape {
                                id: backdropShape
                                anchors.centerIn: parent
                                width: 120
                                height: 120
                                shape: root.currentRandomShape
                                color: root.selectedDevice?.connected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(backdropShape)
                                }

                                Loader {
                                    anchors.centerIn: parent
                                    active: root.hasCustomImage
                                    visible: active
                                    sourceComponent: Image {
                                        source: root.deviceImageSource
                                        width: 80
                                        height: 80
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }
                                }

                                Loader {
                                    anchors.centerIn: parent
                                    active: !root.hasCustomImage
                                    visible: active
                                    sourceComponent: MaterialSymbol {
                                        text: Icons.getBluetoothDeviceMaterialSymbol(root.selectedDevice?.icon || "")
                                        iconSize: 48
                                        color: root.selectedDevice?.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.selectedDevice?.name || Translation.tr("Unknown device")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            color: Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            horizontalAlignment: Text.AlignHCenter
                            Layout.topMargin: 4
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.selectedDevice?.address || ""
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                            opacity: 0.8
                        }

                        Item {
                            height: 12
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: deviceInfoColumn.implicitHeight + 20
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colSurfaceContainerHigh

                            ColumnLayout {
                                id: deviceInfoColumn
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "bluetooth"
                                        iconSize: 16
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }

                                    StyledText {
                                        text: Translation.tr("Status")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnSurfaceVariant
                                        Layout.fillWidth: true
                                    }

                                    StyledText {
                                        text: {
                                            const dev = root.selectedDevice;
                                            if (!dev)
                                                return "";
                                            if (dev.connected)
                                                return Translation.tr("Connected");
                                            if (dev.paired)
                                                return Translation.tr("Paired");
                                            return Translation.tr("Available");
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        color: root.selectedDevice?.connected ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                                    }
                                }

                                Loader {
                                    active: (root.selectedDevice?.batteryAvailable ?? false) && root.selectedDevice?.connected
                                    visible: active
                                    Layout.fillWidth: true

                                    sourceComponent: ColumnLayout {
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            MaterialSymbol {
                                                text: "battery_charging_full"
                                                iconSize: 16
                                                color: Appearance.colors.colOnSurfaceVariant
                                            }

                                            StyledText {
                                                text: Translation.tr("Battery")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: Appearance.colors.colOnSurfaceVariant
                                                Layout.fillWidth: true
                                            }

                                            StyledText {
                                                text: Math.round((root.selectedDevice?.battery ?? 0) * 100) + "%"
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.Medium
                                                color: {
                                                    const b = root.selectedDevice?.battery ?? 0;
                                                    if (b <= 0.15)
                                                        return Appearance.m3colors.m3error;
                                                    return Appearance.m3colors.m3onSurface;
                                                }
                                            }
                                        }

                                        StyledProgressBar {
                                            Layout.fillWidth: true
                                            valueBarHeight: 6
                                            value: root.selectedDevice?.battery ?? 0
                                            highlightColor: {
                                                const b = root.selectedDevice?.battery ?? 0;
                                                if (b <= 0.15)
                                                    return Appearance.m3colors.m3error;
                                                return Appearance.colors.colPrimary;
                                            }
                                            trackColor: Appearance.colors.colSurfaceContainerHighest
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: root.selectedDevice?.paired ?? false

                                    MaterialSymbol {
                                        text: "verified"
                                        iconSize: 16
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }

                                    StyledText {
                                        text: Translation.tr("Paired")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnSurfaceVariant
                                        Layout.fillWidth: true
                                    }

                                    MaterialSymbol {
                                        text: "check"
                                        iconSize: 16
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            RippleButton {
                                id: connectActionBtn
                                Layout.fillWidth: true
                                implicitHeight: 40
                                buttonRadius: Appearance.rounding.large
                                colBackground: {
                                    if (connectActionBtn.isActionSelected || connectActionBtn.hovered) {
                                        return root.selectedDevice?.connected ? Appearance.m3colors.m3error : Appearance.colors.colPrimary;
                                    }
                                    return root.selectedDevice?.connected ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer;
                                }
                                colBackgroundHover: colBackground
                                colRipple: Appearance.colors.colPrimaryContainerActive

                                property bool isActionSelected: root.selectedActionIndex === 0
                                readonly property bool isProcessing: root.selectedDevice ? (root.selectedDevice.state === 3 || root.selectedDevice.state === 2 || !!root.connectingDevices[root.selectedDevice.address] || !!root.disconnectingDevices[root.selectedDevice.address]) : false

                                PointingHandInteraction {}
                                onClicked: {
                                    root.selectedActionIndex = 0;
                                    if (!root.selectedDevice)
                                        return;
                                    if (root.selectedDevice.connected) {
                                        let temp = Object.assign({}, root.disconnectingDevices);
                                        temp[root.selectedDevice.address] = true;
                                        root.disconnectingDevices = temp;
                                        root.selectedDevice.disconnect();
                                    } else {
                                        root.stopScan();
                                        let temp = Object.assign({}, root.connectingDevices);
                                        temp[root.selectedDevice.address] = true;
                                        root.connectingDevices = temp;
                                        root.selectedDevice.connect();
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    MaterialSymbol {
                                        text: root.selectedDevice?.connected ? "bluetooth_disabled" : "bluetooth_connected"
                                        iconSize: 16
                                        color: (connectActionBtn.isActionSelected || connectActionBtn.hovered) ? (root.selectedDevice?.connected ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary) : (root.selectedDevice?.connected ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnPrimaryContainer)
                                        visible: !connectActionBtn.isProcessing
                                    }

                                    MaterialShape {
                                        width: 16
                                        height: 16
                                        shape: MaterialShape.Shape.Cookie7Sided
                                        color: (connectActionBtn.isActionSelected || connectActionBtn.hovered) ? (root.selectedDevice?.connected ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary) : (root.selectedDevice?.connected ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnPrimaryContainer)
                                        visible: connectActionBtn.isProcessing

                                        RotationAnimator on rotation {
                                            from: 0
                                            to: 360
                                            duration: 2000
                                            loops: Animation.Infinite
                                            running: connectActionBtn.isProcessing
                                        }
                                    }

                                    StyledText {
                                        text: {
                                            if (root.selectedDevice?.connected) {
                                                if (root.selectedDevice.address && (root.selectedDevice.state === 2 || root.disconnectingDevices[root.selectedDevice.address])) {
                                                    return Translation.tr("Disconnecting...");
                                                }
                                                return Translation.tr("Disconnect");
                                            } else {
                                                if (root.selectedDevice?.address && (root.selectedDevice.state === 3 || root.connectingDevices[root.selectedDevice.address])) {
                                                    return Translation.tr("Connecting...");
                                                }
                                                return Translation.tr("Connect");
                                            }
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        color: (connectActionBtn.isActionSelected || connectActionBtn.hovered) ? (root.selectedDevice?.connected ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary) : (root.selectedDevice?.connected ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnPrimaryContainer)
                                    }
                                }
                            }

                            Loader {
                                active: root.selectedDevice?.paired ?? false
                                visible: active
                                Layout.fillWidth: active

                                sourceComponent: RippleButton {
                                    id: forgetActionBtn
                                    Layout.fillWidth: true
                                    implicitHeight: 40
                                    buttonRadius: Appearance.rounding.large
                                    colBackground: (forgetActionBtn.isActionSelected || forgetActionBtn.hovered) ? Appearance.m3colors.m3error : Appearance.colors.colSurfaceContainerHighest
                                    colBackgroundHover: colBackground
                                    colRipple: Appearance.colors.colErrorContainerActive

                                    property bool isActionSelected: root.selectedActionIndex === 1

                                    PointingHandInteraction {}
                                    onClicked: {
                                        root.selectedActionIndex = 1;
                                        root.selectedDevice?.forget();
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        MaterialSymbol {
                                            text: "link_off"
                                            iconSize: 16
                                            color: (forgetActionBtn.isActionSelected || forgetActionBtn.hovered) ? Appearance.m3colors.m3onError : Appearance.m3colors.m3error
                                        }

                                        StyledText {
                                            text: Translation.tr("Forget")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.Medium
                                            color: (forgetActionBtn.isActionSelected || forgetActionBtn.hovered) ? Appearance.m3colors.m3onError : Appearance.m3colors.m3error
                                        }
                                    }
                                }
                            }

                            // Copy MAC quick action button
                            RippleButton {
                                id: copyMacActionBtn
                                Layout.fillWidth: true
                                implicitHeight: 40
                                buttonRadius: Appearance.rounding.large
                                colBackground: (copyMacActionBtn.isActionSelected || copyMacActionBtn.hovered) ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                colBackgroundHover: colBackground
                                colRipple: Appearance.colors.colPrimaryContainerActive

                                // Action index is 2 if paired (after forgetBtn), 1 if unpaired (after connectBtn)
                                readonly property int btnIndex: root.selectedDevice?.paired ? 2 : 1
                                property bool isActionSelected: root.selectedActionIndex === btnIndex

                                PointingHandInteraction {}
                                onClicked: {
                                    root.selectedActionIndex = btnIndex;
                                    Quickshell.clipboardText = root.selectedDevice?.address || "";
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "content_copy"
                                        iconSize: 16
                                        color: (copyMacActionBtn.isActionSelected || copyMacActionBtn.hovered) ? Appearance.colors.colOnPrimary : Appearance.m3colors.m3onSurface
                                    }

                                    StyledText {
                                        text: Translation.tr("Copy MAC")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Medium
                                        color: (copyMacActionBtn.isActionSelected || copyMacActionBtn.hovered) ? Appearance.colors.colOnPrimary : Appearance.m3colors.m3onSurface
                                    }
                                }
                            }
                        }
                    }
                }

                Loader {
                    active: root.selectedDevice === null
                    visible: active
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    sourceComponent: ColumnLayout {
                        anchors.fill: parent
                        spacing: 12

                        Item {
                            Layout.fillHeight: true
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "bluetooth_searching"
                            iconSize: 56
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.4
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.btEnabled ? Translation.tr("No devices found") : Translation.tr("Enable Bluetooth to see devices")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.6
                        }

                        Item {
                            Layout.fillHeight: true
                        }
                    }
                }
            }
        }
    }
}
