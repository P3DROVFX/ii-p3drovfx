import QtQuick
import QtQuick.Layouts
import "./widgets"
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

Item {
    id: widgetsConfigRoot

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage
    // When non-empty, opens the extension config schema sub-page for this extId
    property string extensionConfigExtId: ""

    property var clockWidgets: (WidgetsRegistry.allWidgets || []).filter(function (w) {
        return w.category === "Clock";
    })
    property var mediaWidgets: (WidgetsRegistry.allWidgets || []).filter(function (w) {
        return w.category === "Media";
    })
    property var weatherWidgets: (WidgetsRegistry.allWidgets || []).filter(function (w) {
        return w.category === "Weather";
    })
    property var dateWidgets: (WidgetsRegistry.allWidgets || []).filter(function (w) {
        return w.category === "Date";
    })
    property var photoWidgets: (WidgetsRegistry.allWidgets || []).filter(function (w) {
        return w.category === "Photo";
    })
    property var bluetoothWidgets: (WidgetsRegistry.allWidgets || []).filter(function (w) {
        return w.category === "Devices" || w.category === "Bluetooth";
    })
    property var utilityWidgets: (WidgetsRegistry.allWidgets || []).filter(function (w) {
        return w.category === "Utility";
    })

    property var _previewQueue: []
    property bool _previewStaggerActive: false

    function _enqueuePreview(card) {
        _previewQueue.push(card);
        if (!_previewStaggerActive) {
            _previewStaggerActive = true;
            _previewStaggerTimer.start();
        }
    }

    Timer {
        id: _previewStaggerTimer
        interval: 30
        repeat: true
        onTriggered: {
            if (widgetsConfigRoot._previewQueue.length > 0) {
                var card = widgetsConfigRoot._previewQueue.shift();
                if (card)
                    card._previewActive = true;
            } else {
                widgetsConfigRoot._previewStaggerActive = false;
                stop();
            }
        }
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        ContentSection {
            title: Translation.tr("Desktop Widgets")
            icon: "widgets"

            ShortcutBox {
                Layout.fillWidth: true
                value: Translation.tr("Lock screen widget settings")
                targetPageId: "lockScreen"
                targetSectionTitle: Translation.tr("Lockscreen widget")
                materialIcon: "lock"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "grid_on"
                    text: Translation.tr("Enable alignment grid (10px)")
                    checked: Config.options.background.widgets.enableGrid ?? false
                    onCheckedChanged: {
                        Config.options.background.widgets.enableGrid = checked;
                    }
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "align_horizontal_center"
                    text: Translation.tr("Enable layout snap alignment")
                    checked: Config.options.background.widgets.enableSnap ?? false
                    onCheckedChanged: {
                        Config.options.background.widgets.enableSnap = checked;
                    }
                }

                ConfigSlider {
                    Layout.fillWidth: true
                    text: Translation.tr("Global widget scale")
                    value: Config.options.background.widgets.widgetsScale ?? 1.0
                    from: 0.5
                    to: 2.0
                    stepSize: 0.05
                    onValueChanged: {
                        Config.options.background.widgets.widgetsScale = value;
                    }
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "lock"
                    text: Translation.tr("Lock widget positions")
                    checked: Config.options.background.widgets.lockWidgetPositions ?? false
                    onCheckedChanged: {
                        Config.options.background.widgets.lockWidgetPositions = checked;
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Widget Color Scheme")
                    icon: "palette"
                    Layout.fillWidth: true

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: schemeGrid.implicitHeight + 24
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.normal
                        border.color: Appearance.colors.colLayer0Border
                        border.width: 1

                        GridLayout {
                            id: schemeGrid
                            anchors.fill: parent
                            anchors.margins: 12
                            columns: 3
                            rowSpacing: 8
                            columnSpacing: 8

                            Repeater {
                                model: WidgetColorScheme.availableSchemes

                                delegate: ColorPreviewButton {
                                    Layout.fillWidth: true
                                    isWidgetScheme: true
                                    colorScheme: modelData
                                    colorSchemeDisplayName: WidgetColorScheme.schemes[modelData] ? WidgetColorScheme.schemes[modelData].name : modelData
                                    widgetSchemeToggled: WidgetColorScheme.currentScheme === modelData
                                    usePreviewColors: true
                                    previewPrimary: WidgetColorScheme.getCardBgColor(modelData)
                                    previewSecondary: WidgetColorScheme.getTextColorOnBg(modelData)
                                    previewTertiary: WidgetColorScheme.getAccentColor(modelData)

                                    onClicked: {
                                        Config.options.background.widgets.colorScheme = modelData;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Clocks")
                icon: "schedule"
                Layout.fillWidth: true

                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: widgetsConfigRoot.clockWidgets
                        delegate: widgetCardComponent
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Media Players")
                icon: "play_circle"
                Layout.fillWidth: true

                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: widgetsConfigRoot.mediaWidgets
                        delegate: widgetCardComponent
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Weather")
                icon: "cloud"
                Layout.fillWidth: true

                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: widgetsConfigRoot.weatherWidgets
                        delegate: widgetCardComponent
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Date & Calendar")
                icon: "calendar_today"
                Layout.fillWidth: true

                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: widgetsConfigRoot.dateWidgets
                        delegate: widgetCardComponent
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Photo")
                icon: "image"
                Layout.fillWidth: true

                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: widgetsConfigRoot.photoWidgets
                        delegate: widgetCardComponent
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Devices & Bluetooth")
                icon: "earbuds"
                Layout.fillWidth: true

                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: widgetsConfigRoot.bluetoothWidgets
                        delegate: widgetCardComponent
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Utility")
                icon: "build"
                Layout.fillWidth: true

                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: widgetsConfigRoot.utilityWidgets
                        delegate: widgetCardComponent
                    }
                }
            }
        }

        // ── Widget Extensions ────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Widget Extensions")
            icon: "extension"

            // Install input row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ToolbarTextField {
                    id: extInstallInput
                    Layout.fillWidth: true
                    implicitHeight: 40
                    placeholderText: Translation.tr("GitHub URL or local absolute path...")
                    font.pixelSize: Appearance.font.pixelSize.normal
                }

                RippleButton {
                    implicitWidth: 90
                    implicitHeight: 40
                    topLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    colRipple: Appearance.colors.colPrimaryContainerActive
                    enabled: !WidgetExtensionManager.loading && extInstallInput.text.trim().length > 0

                    onClicked: {
                        WidgetExtensionManager.installWidget(extInstallInput.text.trim());
                        extInstallInput.text = "";
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: WidgetExtensionManager.loading ? "hourglass_top" : "download"
                            iconSize: 16
                            color: Appearance.colors.colOnPrimaryContainer
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: WidgetExtensionManager.loading ? Translation.tr("Installing...") : Translation.tr("Install")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnPrimaryContainer
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Error notice
            StyledText {
                Layout.fillWidth: true
                visible: WidgetExtensionManager.lastError !== ""
                text: WidgetExtensionManager.lastError
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }

            // Installed extension cards
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: WidgetExtensionManager.ready && Object.keys(WidgetExtensionManager.installedWidgets).length > 0

                Repeater {
                    model: {
                        // Re-evaluate when signal fires
                        var _r = WidgetExtensionManager.ready;
                        var keys = Object.keys(WidgetExtensionManager.installedWidgets);
                        return keys.map(function (k) {
                            return Object.assign({
                                _extId: k
                            }, WidgetExtensionManager.installedWidgets[k]);
                        });
                    }

                    delegate: Rectangle {
                        id: extCard
                        Layout.fillWidth: true
                        implicitHeight: extCardCol.implicitHeight + 24
                        color: Appearance.colors.colLayer2
                        radius: Appearance.rounding.large

                        required property var modelData
                        required property int index

                        readonly property string extId: modelData._extId || ""
                        readonly property bool isEnabled: modelData.enabled ?? true
                        readonly property var wj: modelData.widgetJson || ({})
                        readonly property bool isWidgetActive: {
                            let list = Config.options.background.activeWidgets || [];
                            for (let i = 0; i < list.length; i++) {
                                if (list[i].widgetId === "ext:" + extCard.extId)
                                    return true;
                            }
                            return false;
                        }

                        ColumnLayout {
                            id: extCardCol
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 12
                            }
                            spacing: 8

                            // Header: icon + name + toggle
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                MaterialSymbol {
                                    text: extCard.wj.icon || "extension"
                                    iconSize: 20
                                    color: Appearance.colors.colPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name || extCard.extId
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.bold: true
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            var parts = [];
                                            if (modelData.author)
                                                parts.push("@" + modelData.author);
                                            if (modelData.version)
                                                parts.push("v" + modelData.version);
                                            if (modelData.isLocal)
                                                parts.push(Translation.tr("local"));
                                            return parts.join(" · ");
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnSurfaceVariant
                                        visible: text !== ""
                                        elide: Text.ElideRight
                                    }
                                }

                                // Enable/disable toggle
                                StyledSwitch {
                                    id: toggleBtn
                                    checked: extCard.isEnabled
                                    onToggled: WidgetExtensionManager.toggleWidget(extCard.extId, checked)
                                }
                            }

                            // Description
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.description || ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.WordWrap
                                visible: text !== ""
                            }

                            // Action buttons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // Add/Remove toggle
                                Rectangle {
                                    height: 28
                                    implicitWidth: toggleRow.implicitWidth + 16
                                    radius: Appearance.rounding.full
                                    color: extCard.isWidgetActive ? (toggleBtnMouse.containsMouse ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer) : (toggleBtnMouse.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
                                    opacity: extCard.isEnabled ? 1.0 : 0.4
                                    enabled: extCard.isEnabled

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }

                                    Row {
                                        id: toggleRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        MaterialSymbol {
                                            text: extCard.isWidgetActive ? "delete" : "add"
                                            iconSize: 13
                                            color: extCard.isWidgetActive ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: extCard.isWidgetActive ? Translation.tr("Remove") : Translation.tr("Add to Desktop")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.bold: true
                                            color: extCard.isWidgetActive ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: toggleBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (extCard.isWidgetActive) {
                                                Config.removeWidgetFromDesktop("ext:" + extCard.extId);
                                            } else {
                                                Config.addWidgetToDesktop("ext:" + extCard.extId);
                                            }
                                        }
                                    }
                                }

                                // Settings (schema-driven)
                                Rectangle {
                                    height: 28
                                    width: 28
                                    radius: Appearance.rounding.full
                                    color: settingsBtnMouse.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                                    visible: Object.keys(extCard.wj.configSchema || {}).length > 0

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "settings"
                                        iconSize: 14
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }

                                    MouseArea {
                                        id: settingsBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: widgetsConfigRoot.extensionConfigExtId = extCard.extId
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                // Reload (local only)
                                Rectangle {
                                    height: 28
                                    width: 28
                                    radius: Appearance.rounding.full
                                    color: reloadBtnMouse.containsMouse ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colTertiaryContainer
                                    visible: modelData.isLocal ?? false

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "refresh"
                                        iconSize: 14
                                        color: Appearance.colors.colOnTertiaryContainer
                                    }

                                    MouseArea {
                                        id: reloadBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WidgetExtensionManager.reloadLocalWidget(extCard.extId)
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Reload widget")
                                        visible: reloadBtnMouse.containsMouse
                                    }
                                }

                                // Update (git only)
                                Rectangle {
                                    height: 28
                                    width: 28
                                    radius: Appearance.rounding.full
                                    color: updateBtnMouse.containsMouse ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colTertiaryContainer
                                    visible: !(modelData.isLocal ?? false)

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "system_update_alt"
                                        iconSize: 14
                                        color: Appearance.colors.colOnTertiaryContainer
                                    }

                                    MouseArea {
                                        id: updateBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WidgetExtensionManager.updateWidget(extCard.extId)
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Update widget")
                                        visible: updateBtnMouse.containsMouse
                                    }
                                }

                                // Uninstall
                                Rectangle {
                                    height: 28
                                    width: 28
                                    radius: Appearance.rounding.full
                                    color: uninstallBtnMouse.containsMouse ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 100
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "delete"
                                        iconSize: 14
                                        color: Appearance.colors.colOnErrorContainer
                                    }

                                    MouseArea {
                                        id: uninstallBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WidgetExtensionManager.uninstallWidget(extCard.extId)
                                    }

                                    StyledToolTip {
                                        text: Translation.tr("Uninstall widget")
                                        visible: uninstallBtnMouse.containsMouse
                                    }
                                }
                            }

                            // Lock behavior options (only when active)
                            RowLayout {
                                Layout.fillWidth: true
                                visible: extCard.isWidgetActive
                                spacing: 8

                                StyledText {
                                    text: Translation.tr("Lock Behavior:")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnSurfaceVariant
                                }

                                Row {
                                    spacing: 4

                                    readonly property string currentBehavior: {
                                        let list = Config.options.background.activeWidgets || [];
                                        for (let i = 0; i < list.length; i++) {
                                            if (list[i].widgetId === "ext:" + extCard.extId)
                                                return list[i].lockBehavior || "hide";
                                        }
                                        return "hide";
                                    }

                                    Repeater {
                                        model: [
                                            {
                                                value: "hide",
                                                icon: "visibility_off",
                                                tooltip: "Hidden on lock"
                                            },
                                            {
                                                value: "keep",
                                                icon: "visibility",
                                                tooltip: "Show fixed on lock"
                                            },
                                            {
                                                value: "center",
                                                icon: "center_focus_strong",
                                                tooltip: "Center on lock"
                                            },
                                            {
                                                value: "lockOnly",
                                                icon: "lock",
                                                tooltip: "Lock only"
                                            }
                                        ]

                                        delegate: Rectangle {
                                            width: 24
                                            height: 24
                                            radius: Appearance.rounding.small
                                            color: parent.currentBehavior === modelData.value ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerLow

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 150
                                                }
                                            }

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: modelData.icon
                                                iconSize: 12
                                                color: parent.parent.currentBehavior === modelData.value ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                                            }

                                            MouseArea {
                                                id: lockBtnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Config.setWidgetLockBehavior("ext:" + extCard.extId, modelData.value);
                                                }
                                            }

                                            StyledToolTip {
                                                text: Translation.tr(modelData.tooltip)
                                                visible: lockBtnMouse.containsMouse
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty state
            Item {
                Layout.fillWidth: true
                implicitHeight: 64
                visible: !(WidgetExtensionManager.ready && Object.keys(WidgetExtensionManager.installedWidgets).length > 0)

                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("No extensions installed. Paste a GitHub URL or local path above.")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    width: parent.width - 32
                }
            }
        }

        // ── Browse Community Widgets ──────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Browse Community Widgets")
            icon: "travel_explore"

            // Auto-fetch on first show
            Component.onCompleted: {
                if (WidgetExtensionManager.communityWidgets.length === 0 && !WidgetExtensionManager.discoverLoading) {
                    WidgetExtensionManager.discoverWidgets();
                }
            }

            // Header row: refresh button + status
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: WidgetExtensionManager.discoverLoading ? Translation.tr("Fetching community widgets from GitHub…") : WidgetExtensionManager.discoverError !== "" ? WidgetExtensionManager.discoverError : Translation.tr("%1 widget(s) found on GitHub").arg(WidgetExtensionManager.communityWidgets.length)
                    color: WidgetExtensionManager.discoverError !== "" ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                }

                RippleButton {
                    implicitWidth: refreshBtnRow.implicitWidth + 20
                    implicitHeight: 32
                    topLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    enabled: !WidgetExtensionManager.discoverLoading
                    onClicked: WidgetExtensionManager.discoverWidgets()

                    Row {
                        id: refreshBtnRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: WidgetExtensionManager.discoverLoading ? "hourglass_top" : "refresh"
                            iconSize: 14
                            color: Appearance.colors.colOnSecondaryContainer
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: WidgetExtensionManager.discoverLoading ? Translation.tr("Refreshing…") : Translation.tr("Refresh")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnSecondaryContainer
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Community widget grid
            Flow {
                id: communityFlow
                Layout.fillWidth: true
                spacing: 12

                Repeater {
                    model: WidgetExtensionManager.communityWidgets

                    delegate: Rectangle {
                        id: communityCard
                        required property var modelData
                        required property int index

                        readonly property string extId: {
                            let name = modelData.fullName || modelData.name || "";
                            return name.split("/").pop().replace(/[^a-zA-Z0-9_\-]/g, "-");
                        }
                        readonly property bool alreadyInstalled: WidgetExtensionManager.installedWidgets[communityCard.extId] !== undefined

                        width: 240
                        implicitHeight: communityCardCol.implicitHeight + 24
                        color: Appearance.colors.colLayer2Base
                        radius: Appearance.rounding.large

                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }

                        ColumnLayout {
                            id: communityCardCol
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 12
                            }
                            spacing: 6

                            // Repo name + stars row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                MaterialSymbol {
                                    text: "extension"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colPrimary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: communityCard.modelData.name || ""
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer2
                                    elide: Text.ElideRight
                                }

                                MaterialSymbol {
                                    text: "star"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colTertiary
                                }

                                StyledText {
                                    text: communityCard.modelData.stars || "0"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colTertiary
                                }
                            }

                            // Author
                            StyledText {
                                Layout.fillWidth: true
                                text: "@" + (communityCard.modelData.author || "")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }

                            // Description
                            StyledText {
                                Layout.fillWidth: true
                                text: communityCard.modelData.description || Translation.tr("No description")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            // Install / Installed button
                            RippleButton {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                topLeftRadius: Appearance.rounding.full
                                topRightRadius: Appearance.rounding.full
                                bottomLeftRadius: Appearance.rounding.full
                                bottomRightRadius: Appearance.rounding.full
                                colBackground: communityCard.alreadyInstalled ? Appearance.colors.colSurfaceContainerLow : Appearance.colors.colPrimaryContainer
                                colBackgroundHover: communityCard.alreadyInstalled ? Appearance.colors.colSurfaceContainerLow : Appearance.colors.colPrimaryContainerHover
                                colRipple: Appearance.colors.colPrimaryContainerActive
                                enabled: !communityCard.alreadyInstalled && !WidgetExtensionManager.loading
                                onClicked: {
                                    if (!communityCard.alreadyInstalled)
                                        WidgetExtensionManager.installWidget(communityCard.modelData.cloneUrl);
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        text: communityCard.alreadyInstalled ? "check_circle" : "download"
                                        iconSize: 13
                                        color: communityCard.alreadyInstalled ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnPrimaryContainer
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: communityCard.alreadyInstalled ? Translation.tr("Installed") : WidgetExtensionManager.loading ? Translation.tr("Installing…") : Translation.tr("Install")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.bold: true
                                        color: communityCard.alreadyInstalled ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnPrimaryContainer
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty/loading state
                Item {
                    visible: WidgetExtensionManager.communityWidgets.length === 0
                    width: communityFlow.width
                    height: 64

                    StyledText {
                        anchors.centerIn: parent
                        text: WidgetExtensionManager.discoverLoading ? Translation.tr("Loading…") : WidgetExtensionManager.discoverError !== "" ? Translation.tr("Could not load community widgets. Check network and retry.") : Translation.tr("No community widgets found.")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        width: parent.width - 32
                    }
                }
            }
        }
    }

    Component {
        id: widgetCardComponent

        Item {
            id: cardItem
            width: 220
            implicitHeight: mainColumn.implicitHeight + 12

            property bool _previewActive: false
            property bool hovered: cardMouseArea.containsMouse

            Component.onCompleted: widgetsConfigRoot._enqueuePreview(cardItem)

            readonly property var widgetData: modelData
            readonly property var _activeWidgets: Config.options.background.activeWidgets
            readonly property bool isActive: {
                let list = _activeWidgets || [];
                for (let i = 0; i < list.length; i++) {
                    if (list[i].widgetId === widgetData.widgetId)
                        return true;
                }
                return false;
            }
            readonly property string currentLockBehavior: {
                let list = _activeWidgets || [];
                for (let i = 0; i < list.length; i++) {
                    if (list[i].widgetId === widgetData.widgetId)
                        return list[i].lockBehavior || "hide";
                }
                return "hide";
            }

            MouseArea {
                id: cardMouseArea
                anchors.fill: parent
                hoverEnabled: true
                z: 0
            }

            Rectangle {
                id: backgroundRect
                anchors.fill: parent
                color: cardItem.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                radius: Appearance.rounding.large

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                Canvas {
                    id: dashedBorderCanvas
                    anchors.fill: parent
                    visible: cardItem.isActive
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = Appearance.colors.colPrimary;
                        ctx.lineWidth = 2;
                        ctx.setLineDash([6, 4]);
                        var r = Appearance.rounding.large;
                        var w = width;
                        var h = height;
                        ctx.beginPath();
                        ctx.moveTo(r, 0);
                        ctx.lineTo(w - r, 0);
                        ctx.arcTo(w, 0, w, r, r);
                        ctx.lineTo(w, h - r);
                        ctx.arcTo(w, h, w - r, h, r);
                        ctx.lineTo(r, h);
                        ctx.arcTo(0, h, 0, h - r, r);
                        ctx.lineTo(0, r);
                        ctx.arcTo(0, 0, r, 0, r);
                        ctx.closePath();
                        ctx.stroke();
                    }
                    Component.onCompleted: requestPaint()
                    Connections {
                        target: cardItem
                        function onIsActiveChanged() {
                            dashedBorderCanvas.requestPaint();
                        }
                    }
                }
            }

            ColumnLayout {
                id: mainColumn
                anchors.top: parent.top
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                Item {
                    id: previewContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: 155
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colLayer0
                        radius: Appearance.rounding.normal
                    }

                    Item {
                        id: previewScaler
                        width: widgetPreviewLoader.item ? Math.max(100, widgetPreviewLoader.item.implicitWidth || widgetPreviewLoader.item.width) : 200
                        height: widgetPreviewLoader.item ? Math.max(100, widgetPreviewLoader.item.implicitHeight || widgetPreviewLoader.item.height) : 200
                        scale: Math.min((previewContainer.width - 8) / width, (previewContainer.height - 8) / height)
                        transformOrigin: Item.Center
                        anchors.centerIn: parent

                        Loader {
                            id: widgetPreviewLoader
                            anchors.fill: parent
                            active: cardItem._previewActive
                            source: cardItem._previewActive ? cardItem.widgetData.qmlPath : ""

                            Binding {
                                target: widgetPreviewLoader.item
                                property: "isPreview"
                                value: true
                            }
                            Binding {
                                target: widgetPreviewLoader.item
                                property: "screenWidth"
                                value: 1920
                            }
                            Binding {
                                target: widgetPreviewLoader.item
                                property: "screenHeight"
                                value: 1080
                            }
                            Binding {
                                target: widgetPreviewLoader.item
                                property: "scaledScreenWidth"
                                value: 1920
                            }
                            Binding {
                                target: widgetPreviewLoader.item
                                property: "scaledScreenHeight"
                                value: 1080
                            }
                            Binding {
                                target: widgetPreviewLoader.item
                                property: "wallpaperScale"
                                value: 1.0
                            }
                            Binding {
                                target: widgetPreviewLoader.item
                                property: "styleOverride"
                                value: cardItem.widgetData.styleOverride || ""
                            }
                        }
                    }
                }

                Rectangle {
                    id: addBtn
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    Layout.preferredHeight: 30
                    radius: Appearance.rounding.full
                    color: addBtnMouse.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer
                    visible: !cardItem.isActive

                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "add"
                            iconSize: 14
                            color: Appearance.colors.colOnPrimaryContainer
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: Translation.tr("Add to Desktop")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnPrimaryContainer
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: addBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Config.addWidgetToDesktop(cardItem.widgetData.widgetId);
                        }
                    }
                }

                Rectangle {
                    id: removeBtn
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    Layout.preferredHeight: 30
                    radius: Appearance.rounding.full
                    color: removeBtnMouse.containsMouse ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer
                    visible: cardItem.isActive

                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "delete"
                            iconSize: 14
                            color: Appearance.colors.colOnErrorContainer
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: Translation.tr("Remove from Desktop")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.bold: true
                            color: Appearance.colors.colOnErrorContainer
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: removeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Config.removeWidgetFromDesktop(cardItem.widgetData.widgetId);
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        text: cardItem.widgetData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: settingsBtn
                        visible: cardItem.widgetData.configPage !== undefined && cardItem.widgetData.configPage !== ""
                        width: 26
                        height: 26
                        radius: Appearance.rounding.full
                        color: settingsBtnMouse.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "settings"
                            iconSize: 13
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        MouseArea {
                            id: settingsBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                widgetsConfigRoot.activeSubPage = Qt.resolvedUrl(cardItem.widgetData.configPage);
                            }
                        }
                    }
                }

                Row {
                    id: lockBehaviorRow
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3
                    visible: cardItem.isActive

                    readonly property string currentBehavior: cardItem.currentLockBehavior

                    Repeater {
                        model: [
                            {
                                value: "hide",
                                icon: "visibility_off",
                                tooltip: "Hidden on lock"
                            },
                            {
                                value: "keep",
                                icon: "visibility",
                                tooltip: "Show fixed on lock"
                            },
                            {
                                value: "center",
                                icon: "center_focus_strong",
                                tooltip: "Center on lock"
                            },
                            {
                                value: "lockOnly",
                                icon: "lock",
                                tooltip: "Lock only"
                            }
                        ]

                        delegate: Rectangle {
                            width: 26
                            height: 26
                            radius: Appearance.rounding.small
                            color: lockBehaviorRow.currentBehavior === modelData.value ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerLow

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: modelData.icon
                                iconSize: 13
                                color: lockBehaviorRow.currentBehavior === modelData.value ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                            }

                            MouseArea {
                                id: lockBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Config.setWidgetLockBehavior(cardItem.widgetData.widgetId, modelData.value);
                                }
                            }

                            StyledToolTip {
                                text: modelData.tooltip
                                visible: lockBtnMouse.containsMouse
                            }
                        }
                    }
                }
            }
        }
    }

    // Extension config schema sub-page overlay
    Item {
        id: extConfigOverlay
        width: parent.width
        height: parent.height
        y: 0
        z: 11

        property bool isOpen: widgetsConfigRoot.extensionConfigExtId !== ""
        property bool overlayActive: isOpen

        onXChanged: {
            if (!isOpen && x >= extConfigOverlay.width - 1)
                overlayActive = false;
        }
        onIsOpenChanged: {
            if (isOpen)
                overlayActive = true;
        }

        x: isOpen ? 0 : extConfigOverlay.width

        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        enabled: isOpen

        // Inline config schema renderer
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            visible: extConfigOverlay.overlayActive

            ColumnLayout {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: 16
                }
                spacing: 0

                // Header row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 12

                    RippleButton {
                        implicitWidth: implicitHeight
                        implicitHeight: 40
                        topLeftRadius: Appearance.rounding.full
                        topRightRadius: Appearance.rounding.full
                        bottomLeftRadius: Appearance.rounding.full
                        bottomRightRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: widgetsConfigRoot.extensionConfigExtId = ""

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    StyledText {
                        text: {
                            let extId = widgetsConfigRoot.extensionConfigExtId;
                            if (!extId)
                                return "";
                            let entry = WidgetExtensionManager.installedWidgets[extId];
                            return entry ? (entry.name + " — " + Translation.tr("Settings")) : Translation.tr("Settings");
                        }
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.family: Appearance.font.family.title
                        color: Appearance.colors.colOnLayer0
                    }
                }

                Item {
                    implicitHeight: 16
                }

                // Schema-driven controls via ExtensionWidgetSettingsRenderer
                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, extConfigOverlay.height - 120)
                    contentHeight: schemaSection.implicitHeight
                    clip: true

                    ContentSection {
                        id: schemaSection
                        width: parent.width
                        title: Translation.tr("Configuration")
                        icon: "tune"

                        ExtensionWidgetSettingsRenderer {
                            id: schemaRenderer
                            width: parent.width
                            extId: widgetsConfigRoot.extensionConfigExtId
                            schema: {
                                let eId = widgetsConfigRoot.extensionConfigExtId;
                                if (!eId)
                                    return ({});
                                let entry = WidgetExtensionManager.installedWidgets[eId];
                                if (!entry)
                                    return ({});
                                return (entry.widgetJson || {}).configSchema || ({});
                            }
                        }
                    }
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
