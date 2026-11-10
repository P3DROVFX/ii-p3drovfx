pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    readonly property int panelWidth: Config.options.search.appearance.panelWidth

    implicitWidth: root.panelWidth
    implicitHeight: scaffold.implicitHeight

    focus: true

    function focusInput() {
        inputSink.forceActiveFocus();
        return true;
    }

    function handleEscape() {
        if (SpeedTestService.running) {
            SpeedTestService.cancelTest();
            return true;
        }
        return false;
    }

    function toggleRunning() {
        if (SpeedTestService.running) {
            SpeedTestService.cancelTest();
        } else {
            SpeedTestService.startTest(SpeedTestService.testDuration, SpeedTestService.testMode);
        }
    }

    function retest() {
        SpeedTestService.cancelTest();
        SpeedTestService.startTest(SpeedTestService.testDuration, SpeedTestService.testMode);
    }

    function cycleMode() {
        if (SpeedTestService.testMode === "both") {
            SpeedTestService.testMode = "download";
        } else if (SpeedTestService.testMode === "download") {
            SpeedTestService.testMode = "upload";
        } else {
            SpeedTestService.testMode = "both";
        }
        if (Config.options?.search?.speedTest) {
            Config.options.search.speedTest.mode = SpeedTestService.testMode;
        }
    }

    function toggleUnit() {
        SpeedTestService.speedUnit = SpeedTestService.speedUnit === "mbps" ? "mBps" : "mbps";
        if (Config.options?.search?.speedTest) {
            Config.options.search.speedTest.unit = SpeedTestService.speedUnit;
        }
    }

    function setDuration(dur) {
        SpeedTestService.testDuration = dur;
        if (Config.options?.search?.speedTest) {
            Config.options.search.speedTest.duration = dur;
        }
    }

    function handleKeyPress(event): bool {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.toggleRunning();
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_R) {
            root.retest();
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_C) {
            SpeedTestService.clearHistory();
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_M) {
            root.cycleMode();
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_U) {
            root.toggleUnit();
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_1) {
            root.setDuration(5);
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_2) {
            root.setDuration(10);
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_3) {
            root.setDuration(15);
            event.accepted = true;
            return true;
        }
        if (event.key === Qt.Key_Escape) {
            if (root.handleEscape()) {
                event.accepted = true;
                return true;
            }
        }
        return false;
    }

    Keys.onPressed: event => {
        root.handleKeyPress(event);
    }

    Component.onCompleted: {
        Qt.callLater(root.focusInput);
    }

    // Hidden TextInput that acts as a focus sink so all key events are captured
    TextInput {
        id: inputSink
        width: 1
        height: 1
        opacity: 0
        focus: true
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        Keys.onPressed: event => root.handleKeyPress(event)
    }

    // Clicking anywhere in the panel re-focuses the input sink
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.focusInput()
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        showHeader: false
        showStatus: true
        statusText: SpeedTestService.statusMessage
        minimumContentHeight: Math.max(Config.options.search.appearance.panelBodyHeight, 530)
        primaryHint: SpeedTestService.running
            ? ({ label: Translation.tr("Stop"), keys: ["Space"] })
            : (SpeedTestService.phase === "complete"
                ? ({ label: Translation.tr("Retest"), keys: ["Space"] })
                : ({ label: Translation.tr("Start test"), keys: ["Space"] }))
        hints: [
            { label: Translation.tr("Retest"), keys: ["R"] },
            { label: Translation.tr("Mode"), keys: ["M"] },
            { label: Translation.tr("Unit"), keys: ["U"] },
            { label: Translation.tr("5s/10s/15s"), keys: ["1-3"] },
            { label: Translation.tr("Clear"), keys: ["C"] },
            { label: Translation.tr("Back"), keys: ["Esc"] }
        ]

        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            spacing: Appearance.sizes.elevationMargin

            // 1. Header Toolbar with Controls & Toggles
            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin

                // Title & Server Badge
                RowLayout {
                    spacing: Appearance.sizes.elevationMargin / 2
                    MaterialSymbol {
                        text: "speed"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("Speed Test")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }
                    Rectangle {
                        implicitHeight: Appearance.font.pixelSize.large + 2
                        implicitWidth: serverText.implicitWidth + Appearance.sizes.elevationMargin
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSurfaceContainerHigh

                        StyledText {
                            id: serverText
                            anchors.centerIn: parent
                            text: "Cloudflare Anycast"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Toggles Row
                RowLayout {
                    spacing: Appearance.sizes.elevationMargin / 2

                    // Duration Chips
                    RowLayout {
                        spacing: 2
                        Repeater {
                            model: [5, 10, 15]
                            delegate: RippleButton {
                                id: durButton
                                required property int modelData
                                implicitHeight: 28
                                implicitWidth: 36
                                buttonRadius: Appearance.rounding.small
                                toggled: SpeedTestService.testDuration === modelData
                                colBackground: toggled ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                                colBackgroundHover: toggled ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
                                colRipple: Appearance.colors.colPrimaryActive
                                onClicked: {
                                    root.setDuration(durButton.modelData);
                                    root.focusInput();
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: durButton.modelData + "s"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: durButton.toggled ? Font.Bold : Font.Normal
                                    color: durButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                                }
                            }
                        }
                    }

                    Rectangle {
                        implicitWidth: 1
                        implicitHeight: 18
                        color: Appearance.colors.colOutlineVariant
                    }

                    // Mode Toggle Chip
                    RippleButton {
                        implicitHeight: 28
                        implicitWidth: modeLabel.implicitWidth + Appearance.sizes.elevationMargin * 1.5
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: {
                            root.cycleMode();
                            root.focusInput();
                        }

                        RowLayout {
                            id: modeLabel
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: SpeedTestService.testMode === "both" ? "sync_alt" : (SpeedTestService.testMode === "download" ? "download" : "upload")
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: SpeedTestService.testMode === "both" ? Translation.tr("Both") : (SpeedTestService.testMode === "download" ? Translation.tr("Down") : Translation.tr("Up"))
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }

                    // Unit Toggle Chip
                    RippleButton {
                        implicitHeight: 28
                        implicitWidth: 50
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: {
                            root.toggleUnit();
                            root.focusInput();
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: SpeedTestService.unitLabel()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }
                    }

                    // Action Button (Start / Stop / Retest)
                    RippleButton {
                        implicitHeight: 32
                        implicitWidth: actionContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                        buttonRadius: Appearance.rounding.full
                        colBackground: {
                            if (SpeedTestService.running) return Appearance.colors.colError;
                            if (SpeedTestService.phase === "complete") return Appearance.colors.colPrimary;
                            return Appearance.colors.colPrimary;
                        }
                        colBackgroundHover: {
                            if (SpeedTestService.running) return Appearance.colors.colErrorHover;
                            return Appearance.colors.colPrimaryHover;
                        }
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: {
                            root.toggleRunning();
                            root.focusInput();
                        }

                        RowLayout {
                            id: actionContent
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                text: {
                                    if (SpeedTestService.running) return "stop";
                                    if (SpeedTestService.phase === "complete") return "refresh";
                                    return "play_arrow";
                                }
                                iconSize: Appearance.font.pixelSize.normal
                                color: SpeedTestService.running ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: {
                                    if (SpeedTestService.running) return Translation.tr("Stop");
                                    if (SpeedTestService.phase === "complete") return Translation.tr("Retest");
                                    return Translation.tr("Start");
                                }
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: SpeedTestService.running ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }

            // 2. Hero Speed Display Section (with Finished & Error states, plus integrated progress track)
            Rectangle {
                id: heroCard
                Layout.fillWidth: true
                implicitHeight: 124
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerLow

                // Normal / Finished View
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: SpeedTestService.phase !== "error"

                    // Phase & Status Indicator Pill
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: phaseRow.implicitWidth + 16
                            radius: Appearance.rounding.full
                            color: {
                                if (SpeedTestService.phase === "download") return Appearance.colors.colPrimaryContainer;
                                if (SpeedTestService.phase === "upload") return Appearance.colors.colTertiaryContainer;
                                if (SpeedTestService.phase === "complete") return ColorUtils.transparentize(Appearance.colors.colPrimary, 0.25);
                                return Appearance.colors.colSurfaceContainerHigh;
                            }

                            RowLayout {
                                id: phaseRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: {
                                        if (SpeedTestService.phase === "download") return "download";
                                        if (SpeedTestService.phase === "upload") return "upload";
                                        if (SpeedTestService.phase === "complete") return "check_circle";
                                        if (SpeedTestService.phase === "ping") return "network_ping";
                                        return "bolt";
                                    }
                                    iconSize: 14
                                    color: {
                                        if (SpeedTestService.phase === "download") return Appearance.colors.colOnPrimaryContainer;
                                        if (SpeedTestService.phase === "upload") return Appearance.colors.colOnTertiaryContainer;
                                        if (SpeedTestService.phase === "complete") return Appearance.colors.colOnPrimary;
                                        return Appearance.colors.colOnSurfaceVariant;
                                    }
                                }
                                StyledText {
                                    text: {
                                        if (SpeedTestService.phase === "download") return Translation.tr("Testing Download");
                                        if (SpeedTestService.phase === "upload") return Translation.tr("Testing Upload");
                                        if (SpeedTestService.phase === "ping") return Translation.tr("Measuring Latency");
                                        if (SpeedTestService.phase === "complete") return Translation.tr("Test Complete");
                                        if (SpeedTestService.lastResult) return Translation.tr("Last Result");
                                        return Translation.tr("Ready to Test");
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: {
                                        if (SpeedTestService.phase === "download") return Appearance.colors.colOnPrimaryContainer;
                                        if (SpeedTestService.phase === "upload") return Appearance.colors.colOnTertiaryContainer;
                                        if (SpeedTestService.phase === "complete") return Appearance.colors.colOnPrimary;
                                        return Appearance.colors.colOnSurfaceVariant;
                                    }
                                }
                            }
                        }

                        // Finished State Rating Pill
                        Rectangle {
                            visible: SpeedTestService.phase === "complete" && SpeedTestService.downloadSpeed > 0
                            implicitHeight: 24
                            implicitWidth: ratingRow.implicitWidth + 14
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colSurfaceContainerHigh

                            RowLayout {
                                id: ratingRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: SpeedTestService.downloadSpeed >= 100 ? "rocket_launch" : (SpeedTestService.downloadSpeed >= 35 ? "bolt" : "wifi")
                                    iconSize: 13
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: SpeedTestService.downloadSpeed >= 100
                                        ? Translation.tr("Ultra Fast")
                                        : (SpeedTestService.downloadSpeed >= 35 ? Translation.tr("Fast Connection") : Translation.tr("Standard Connection"))
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                        }

                        // Ping snippet
                        StyledText {
                            visible: SpeedTestService.ping > 0
                            text: `Ping: ${Math.round(SpeedTestService.ping)} ms`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    // Main Big Speed Typography
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6

                        StyledText {
                            id: bigNumber
                            text: {
                                if (SpeedTestService.running) {
                                    return SpeedTestService.speedValue(SpeedTestService.currentSpeed).toFixed(1);
                                }
                                if (SpeedTestService.phase === "complete" || SpeedTestService.lastResult) {
                                    const res = SpeedTestService.lastResult;
                                    const avg = res?.downloadAvg || SpeedTestService.downloadSpeed;
                                    return SpeedTestService.speedValue(avg).toFixed(1);
                                }
                                return "0.0";
                            }
                            font.pixelSize: 46
                            font.weight: Font.Black
                            font.family: Appearance.font.family.monospace
                            color: {
                                if (SpeedTestService.phase === "upload") return Appearance.colors.colTertiary;
                                return Appearance.colors.colPrimary;
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 8
                            text: SpeedTestService.unitLabel()
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    // Floating Integrated Progress Bar (Only visible during running)
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 320
                        implicitHeight: 6
                        opacity: SpeedTestService.running ? 1.0 : 0.0

                        Behavior on opacity {
                            NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: Appearance.colors.colSurfaceContainerHighest

                            Rectangle {
                                height: parent.height
                                width: parent.width * Math.max(0.0, Math.min(1.0, SpeedTestService.progress))
                                radius: 3
                                color: SpeedTestService.phase === "upload" ? Appearance.colors.colTertiary : Appearance.colors.colPrimary

                                Behavior on width {
                                    enabled: !root.animationsDisabled && SpeedTestService.running
                                    NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                                }
                            }
                        }
                    }
                }

                // Error State View (No Internet / Disconnected)
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: SpeedTestService.phase === "error"

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        Rectangle {
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: 17
                            color: Appearance.colors.colErrorContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: SpeedTestService.errorType === "offline" ? "wifi_off" : "error"
                                iconSize: 20
                                color: Appearance.colors.colOnErrorContainer
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                text: SpeedTestService.errorType === "offline"
                                    ? Translation.tr("No Internet Connection Detected")
                                    : Translation.tr("Connection Error")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: Appearance.colors.colError
                            }
                            StyledText {
                                text: SpeedTestService.errorType === "offline"
                                    ? Translation.tr("Please check your Wi-Fi or ethernet cable and try again.")
                                    : SpeedTestService.errorText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        RippleButton {
                            implicitHeight: 30
                            implicitWidth: retryLabel.implicitWidth + 20
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colError
                            colBackgroundHover: Appearance.colors.colErrorHover
                            colRipple: Appearance.colors.colOnError
                            onClicked: {
                                root.retest();
                                root.focusInput();
                            }

                            RowLayout {
                                id: retryLabel
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: "refresh"
                                    iconSize: 14
                                    color: Appearance.colors.colOnError
                                }
                                StyledText {
                                    text: Translation.tr("Try Again (R)")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnError
                                }
                            }
                        }
                    }
                }
            }

            // 3. Live Chart Section (Dual Curve with Rounded Corners & Expanded Margins)
            Rectangle {
                id: chartBox
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 160
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerLow
                clip: true

                // Chart Legend Top Right
                RowLayout {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 10
                    anchors.rightMargin: 16
                    spacing: 12
                    z: 2

                    RowLayout {
                        spacing: 4
                        Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: Appearance.colors.colPrimary }
                        StyledText {
                            text: Translation.tr("Download")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    RowLayout {
                        spacing: 4
                        Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: Appearance.colors.colTertiary }
                        StyledText {
                            text: Translation.tr("Upload")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                // Grid scale indicator labels with generous margins
                ColumnLayout {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 26
                    anchors.leftMargin: 12
                    anchors.bottomMargin: 32
                    width: 30
                    spacing: 0
                    z: 2

                    StyledText {
                        text: `${Math.round(SpeedTestService.speedValue(speedChartCanvas.maxPeak))}`
                        font.pixelSize: 10
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignRight
                    }
                    Item { Layout.fillHeight: true }
                    StyledText {
                        text: `${Math.round(SpeedTestService.speedValue(speedChartCanvas.maxPeak * 0.5))}`
                        font.pixelSize: 10
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignRight
                    }
                    Item { Layout.fillHeight: true }
                    StyledText {
                        text: "0"
                        font.pixelSize: 10
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignRight
                    }
                }

                // Empty state text when no test has run yet
                StyledText {
                    anchors.centerIn: parent
                    visible: SpeedTestService.downloadSamples.length === 0 && SpeedTestService.uploadSamples.length === 0 && SpeedTestService.phase !== "error"
                    text: Translation.tr("Press Space or click Start to begin the 10-second speed test")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    z: 2
                }

                // Canvas Graph with Rounded Corners Clip & Generous Inner Padding
                Canvas {
                    id: speedChartCanvas
                    anchors.fill: parent
                    anchors.leftMargin: 48
                    anchors.rightMargin: 20
                    anchors.topMargin: 28
                    anchors.bottomMargin: 30

                    readonly property var downList: SpeedTestService.downloadSamples
                    readonly property var upList: SpeedTestService.uploadSamples

                    readonly property real maxPeak: {
                        let peak = 50.0;
                        for (let i = 0; i < downList.length; i++) peak = Math.max(peak, downList[i]);
                        for (let i = 0; i < upList.length; i++) peak = Math.max(peak, upList[i]);
                        return peak * 1.15;
                    }

                    onDownListChanged: requestPaint()
                    onUpListChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);

                        ctx.save();

                        // Clip canvas content to smooth rounded corners matching container
                        const r = 12;
                        ctx.beginPath();
                        ctx.moveTo(r, 0);
                        ctx.lineTo(width - r, 0);
                        ctx.arcTo(width, 0, width, r, r);
                        ctx.lineTo(width, height - r);
                        ctx.arcTo(width, height, width - r, height, r);
                        ctx.lineTo(r, height);
                        ctx.arcTo(0, height, 0, height - r, r);
                        ctx.lineTo(0, r);
                        ctx.arcTo(0, 0, r, 0, r);
                        ctx.closePath();
                        ctx.clip();

                        // Horizontal subtle grid lines
                        ctx.strokeStyle = ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5);
                        ctx.lineWidth = 1;
                        ctx.setLineDash([4, 4]);

                        // 100% line
                        ctx.beginPath();
                        ctx.moveTo(0, 4);
                        ctx.lineTo(width, 4);
                        ctx.stroke();

                        // 50% line
                        ctx.beginPath();
                        ctx.moveTo(0, height / 2);
                        ctx.lineTo(width, height / 2);
                        ctx.stroke();

                        // Base line
                        ctx.beginPath();
                        ctx.moveTo(0, height - 2);
                        ctx.lineTo(width, height - 2);
                        ctx.stroke();
                        ctx.setLineDash([]);

                        const peak = maxPeak;
                        const baselineY = height - 4;
                        const usableHeight = height - 12;

                        // Function to draw curve with gradient fill
                        function drawSeries(samples, strokeColor, fillColor) {
                            if (!samples || samples.length < 2) return;

                            const stepX = width / Math.max(samples.length - 1, 1);

                            ctx.beginPath();
                            ctx.moveTo(0, baselineY - (samples[0] / peak) * usableHeight);

                            for (let i = 1; i < samples.length; i++) {
                                const prevX = (i - 1) * stepX;
                                const prevY = baselineY - (samples[i - 1] / peak) * usableHeight;
                                const curX = i * stepX;
                                const curY = baselineY - (samples[i] / peak) * usableHeight;
                                const cpX = (prevX + curX) / 2;

                                ctx.bezierCurveTo(cpX, prevY, cpX, curY, curX, curY);
                            }

                            // Stroke line
                            ctx.strokeStyle = strokeColor;
                            ctx.lineWidth = 2.5;
                            ctx.stroke();

                            // Area fill
                            ctx.lineTo((samples.length - 1) * stepX, height);
                            ctx.lineTo(0, height);
                            ctx.closePath();

                            const gradient = ctx.createLinearGradient(0, 0, 0, height);
                            gradient.addColorStop(0, ColorUtils.transparentize(fillColor, 0.35));
                            gradient.addColorStop(1, ColorUtils.transparentize(fillColor, 0.02));
                            ctx.fillStyle = gradient;
                            ctx.fill();
                        }

                        // Draw Download Series
                        drawSeries(downList, Appearance.colors.colPrimary, Appearance.colors.colPrimary);

                        // Draw Upload Series
                        drawSeries(upList, Appearance.colors.colTertiary, Appearance.colors.colTertiary);

                        ctx.restore();
                    }
                }

                // Time axis labels along bottom with proper separation
                RowLayout {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 48
                    anchors.rightMargin: 20
                    anchors.bottomMargin: 8
                    spacing: 0

                    StyledText { text: "0s"; font.pixelSize: 10; font.family: Appearance.font.family.monospace; color: Appearance.colors.colSubtext }
                    Item { Layout.fillWidth: true }
                    StyledText { text: `${Math.round(SpeedTestService.testDuration * 0.25)}s`; font.pixelSize: 10; font.family: Appearance.font.family.monospace; color: Appearance.colors.colSubtext }
                    Item { Layout.fillWidth: true }
                    StyledText { text: `${Math.round(SpeedTestService.testDuration * 0.5)}s`; font.pixelSize: 10; font.family: Appearance.font.family.monospace; color: Appearance.colors.colSubtext }
                    Item { Layout.fillWidth: true }
                    StyledText { text: `${Math.round(SpeedTestService.testDuration * 0.75)}s`; font.pixelSize: 10; font.family: Appearance.font.family.monospace; color: Appearance.colors.colSubtext }
                    Item { Layout.fillWidth: true }
                    StyledText { text: `${SpeedTestService.testDuration}s`; font.pixelSize: 10; font.family: Appearance.font.family.monospace; color: Appearance.colors.colSubtext }
                }
            }

            // 4. Detailed Summary Metric Cards
            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin

                // Card 1: Download
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 74
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerLow

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Rectangle {
                            implicitWidth: 38
                            implicitHeight: 38
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "download"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                text: Translation.tr("Download")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                text: SpeedTestService.formatSpeed(SpeedTestService.downloadSpeed)
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Bold
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                text: Translation.tr("Peak: %1").arg(SpeedTestService.formatSpeed(SpeedTestService.downloadPeak))
                                font.pixelSize: 10
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                // Card 2: Upload
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 74
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerLow

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Rectangle {
                            implicitWidth: 38
                            implicitHeight: 38
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colTertiaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "upload"
                                iconSize: 20
                                color: Appearance.colors.colOnTertiaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                text: Translation.tr("Upload")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                text: SpeedTestService.formatSpeed(SpeedTestService.uploadSpeed)
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Bold
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colTertiary
                            }

                            StyledText {
                                text: Translation.tr("Peak: %1").arg(SpeedTestService.formatSpeed(SpeedTestService.uploadPeak))
                                font.pixelSize: 10
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                // Card 3: Ping / Latency
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 74
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerLow

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Rectangle {
                            implicitWidth: 38
                            implicitHeight: 38
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colSecondaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "network_ping"
                                iconSize: 20
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                text: Translation.tr("Latency & Jitter")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                text: SpeedTestService.ping > 0 ? `${Math.round(SpeedTestService.ping)} ms` : "--"
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Bold
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colSecondary
                            }

                            StyledText {
                                text: SpeedTestService.jitter > 0 ? `Jitter: ${SpeedTestService.jitter.toFixed(1)} ms` : "Jitter: --"
                                font.pixelSize: 10
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
