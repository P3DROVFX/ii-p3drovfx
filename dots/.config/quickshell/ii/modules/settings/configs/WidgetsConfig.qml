import QtQuick
import QtQuick.Layouts
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

    // Every gallery card re-runs mapToItem() when this changes. Quantising the
    // scroll position keeps that off the per-pixel path: the load/unload
    // margins below are an order of magnitude larger than one step.
    readonly property int scrollStep: Math.floor(widgetsConfigRoot.contentY / 120)
    // When non-empty, opens the extension config schema sub-page for this extId
    property string extensionConfigExtId: ""

    // Build all category models in one pass. Each individual filter used to
    // walk the complete registry again whenever an extension changed.
    readonly property var widgetCategories: {
        const categories = {
            Clock: [],
            Media: [],
            Weather: [],
            Date: [],
            Photo: [],
            Bluetooth: [],
            Utility: [],
            Resources: [],
            System: []
        };
        const allWidgets = WidgetsRegistry.allWidgets || [];
        for (let i = 0; i < allWidgets.length; i++) {
            const widget = allWidgets[i];
            if (widget.category === "Devices" || widget.category === "Bluetooth")
                categories.Bluetooth.push(widget);
            else if (categories[widget.category] !== undefined)
                categories[widget.category].push(widget);
        }
        return categories;
    }

    readonly property var clockWidgets: widgetCategories.Clock
    readonly property var mediaWidgets: widgetCategories.Media
    readonly property var weatherWidgets: widgetCategories.Weather
    readonly property var dateWidgets: widgetCategories.Date
    readonly property var photoWidgets: widgetCategories.Photo
    readonly property var bluetoothWidgets: widgetCategories.Bluetooth
    readonly property var utilityWidgets: widgetCategories.Utility
    readonly property var resourceWidgets: widgetCategories.Resources
    readonly property var systemWidgets: widgetCategories.System

    // Accordion collapse state per category. Default: all categories collapsed.
    // When collapsed, widget preview Loaders are not active → no GPU/memory cost.
    property bool clockExpanded: false
    property bool mediaExpanded: false
    property bool weatherExpanded: false
    property bool dateExpanded: false
    property bool photoExpanded: false
    property bool bluetoothExpanded: false
    property bool utilityExpanded: false
    property bool resourceExpanded: false
    property bool systemExpanded: false

    // Rich catalog sections are opt-in. This keeps the first page pass limited
    // to the small Desktop Widgets controls and avoids starting network work.
    property bool colorSchemeActive: false
    property bool extensionsExpanded: false
    property bool communityExpanded: false

    property var _previewQueue: []
    property bool _previewStaggerActive: false

    function _enqueuePreview(card) {
        if (!card || card._previewActive || card._previewQueued || !card.previewNearViewport)
            return;

        card._previewQueued = true;
        _previewQueue.push(card);
        if (!_previewStaggerActive) {
            _previewStaggerActive = true;
            _previewStaggerTimer.start();
        }
    }

    function _removePreview(card) {
        const index = _previewQueue.indexOf(card);
        if (index >= 0)
            _previewQueue.splice(index, 1);
    }

    Timer {
        id: _previewStaggerTimer
        interval: 30
        repeat: true
        onTriggered: {
            if (widgetsConfigRoot._previewQueue.length > 0) {
                var card = widgetsConfigRoot._previewQueue.shift();
                if (card) {
                    card._previewQueued = false;
                    if (card.previewNearViewport)
                        card._previewActive = true;
                }
            } else {
                widgetsConfigRoot._previewStaggerActive = false;
                stop();
            }
        }
    }

    Timer {
        id: colorSchemeLoadTimer
        interval: 0
        repeat: false
        onTriggered: widgetsConfigRoot.colorSchemeActive = true
    }

    Component.onCompleted: colorSchemeLoadTimer.start()

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

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("Hold Ctrl while dragging a widget to temporarily disable the alignment grid and snap for pixel-perfect placement")
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

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Show widgets only in one monitor")
                    checked: Config.options.background.widgets.showOnlyOnSingleMonitor ?? false
                    onCheckedChanged: {
                        Config.options.background.widgets.showOnlyOnSingleMonitor = checked;
                    }
                }

                MonitorPicker {
                    Layout.fillWidth: true
                    visible: Config.options.background.widgets.showOnlyOnSingleMonitor ?? false
                    currentValue: Config.options.background.widgets.targetMonitor ?? ""
                    onSelected: newValue => {
                        Config.options.background.widgets.targetMonitor = newValue;
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                    active: widgetsConfigRoot.colorSchemeActive
                    asynchronous: true
                    sourceComponent: ContentSubsection {
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
                                        required property var modelData

                                        Layout.fillWidth: true
                                        isWidgetScheme: true
                                        colorScheme: modelData
                                        colorSchemeDisplayName: WidgetColorScheme.schemes[modelData] ? WidgetColorScheme.schemes[modelData].name : modelData
                                        widgetSchemeToggled: WidgetColorScheme.currentScheme === modelData
                                        usePreviewColors: true
                                        previewPrimary: WidgetColorScheme.getCardBgColor(modelData)
                                        previewSecondary: WidgetColorScheme.getTextColorOnBg(modelData)
                                        previewTertiary: WidgetColorScheme.getAccentColor(modelData)

                                        onClicked: Config.options.background.widgets.colorScheme = modelData
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
                collapsible: true
                expanded: widgetsConfigRoot.clockExpanded
                onExpandedChanged: widgetsConfigRoot.clockExpanded = expanded

                // GPU: Loader prevents Flow+Repeater+cards from being created when collapsed
                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.clockExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.clockWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Media Players")
                icon: "play_circle"
                Layout.fillWidth: true
                collapsible: true
                expanded: widgetsConfigRoot.mediaExpanded
                onExpandedChanged: widgetsConfigRoot.mediaExpanded = expanded

                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.mediaExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.mediaWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Weather")
                icon: "cloud"
                Layout.fillWidth: true
                collapsible: true
                expanded: widgetsConfigRoot.weatherExpanded
                onExpandedChanged: widgetsConfigRoot.weatherExpanded = expanded

                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.weatherExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.weatherWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Date & Calendar")
                icon: "calendar_today"
                Layout.fillWidth: true
                collapsible: true
                expanded: widgetsConfigRoot.dateExpanded
                onExpandedChanged: widgetsConfigRoot.dateExpanded = expanded

                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.dateExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.dateWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Photo")
                icon: "image"
                Layout.fillWidth: true
                collapsible: true
                expanded: widgetsConfigRoot.photoExpanded
                onExpandedChanged: widgetsConfigRoot.photoExpanded = expanded

                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.photoExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.photoWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Devices & Bluetooth")
                icon: "earbuds"
                Layout.fillWidth: true
                collapsible: true
                expanded: widgetsConfigRoot.bluetoothExpanded
                onExpandedChanged: widgetsConfigRoot.bluetoothExpanded = expanded

                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.bluetoothExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.bluetoothWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Utility")
                icon: "build"
                Layout.fillWidth: true
                collapsible: true
                expanded: widgetsConfigRoot.utilityExpanded
                onExpandedChanged: widgetsConfigRoot.utilityExpanded = expanded

                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.utilityExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.utilityWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("System")
                icon: "tune"
                Layout.fillWidth: true
                collapsible: true
                expanded: widgetsConfigRoot.systemExpanded
                onExpandedChanged: widgetsConfigRoot.systemExpanded = expanded

                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.systemExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.systemWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Resources")
                icon: "monitor_heart"
                Layout.fillWidth: true
                collapsible: true
                expanded: widgetsConfigRoot.resourceExpanded
                onExpandedChanged: widgetsConfigRoot.resourceExpanded = expanded

                Loader {
                    Layout.fillWidth: true
                    active: widgetsConfigRoot.resourceExpanded
                    asynchronous: true
                    sourceComponent: Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: widgetsConfigRoot.resourceWidgets
                            delegate: widgetCardComponent
                        }
                    }
                }
            }
        }

        // ── Widget Extensions ────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Widget Extensions")
            icon: "extension"
            collapsible: true
            expanded: widgetsConfigRoot.extensionsExpanded
            onExpandedChanged: widgetsConfigRoot.extensionsExpanded = expanded

            Loader {
                id: extensionsContentLoader
                Layout.fillWidth: true
                Layout.preferredHeight: item ? item.implicitHeight : 0
                active: widgetsConfigRoot.extensionsExpanded
                asynchronous: true
                source: Qt.resolvedUrl("widgets/WidgetExtensionsContent.qml")
            }

            Connections {
                target: extensionsContentLoader.item
                function onExtensionConfigRequested(extId) {
                    widgetsConfigRoot.extensionConfigExtId = extId;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Browse Community Widgets")
            icon: "travel_explore"
            collapsible: true
            expanded: widgetsConfigRoot.communityExpanded
            onExpandedChanged: widgetsConfigRoot.communityExpanded = expanded

            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: item ? item.implicitHeight : 0
                active: widgetsConfigRoot.communityExpanded
                asynchronous: true
                source: Qt.resolvedUrl("widgets/WidgetCommunityContent.qml")
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
            property bool _previewQueued: false
            property bool hovered: cardMouseArea.containsMouse

            // How far outside the viewport this card sits, in pixels; 0 while
            // any part of it is on screen. One mapToItem() feeds both the load
            // and the unload decision.
            readonly property real viewportDistance: {
                // Explicit dependencies: mapToItem is not reactive in QML.
                widgetsConfigRoot.scrollStep;
                widgetsConfigRoot.width;
                widgetsConfigRoot.height;
                cardItem.x;
                cardItem.y;
                cardItem.height;

                if (!cardItem.visible || widgetsConfigRoot.height <= 0)
                    return Number.MAX_VALUE;

                const point = cardItem.mapToItem(widgetsConfigRoot, 0, 0);
                if (point.y > widgetsConfigRoot.height)
                    return point.y - widgetsConfigRoot.height;
                if (point.y + cardItem.height < 0)
                    return -(point.y + cardItem.height);
                return 0;
            }

            readonly property real previewLoadMargin: Math.max(cardItem.height, widgetsConfigRoot.height * 0.25)
            readonly property bool previewNearViewport: cardItem.viewportDistance < cardItem.previewLoadMargin
            // Unloading uses a wider margin than loading so a card sitting near
            // the edge cannot thrash between the two states while scrolling.
            readonly property bool previewFarFromViewport: cardItem.viewportDistance > widgetsConfigRoot.height * 1.5

            function requestPreviewIfVisible() {
                if (previewNearViewport)
                    widgetsConfigRoot._enqueuePreview(cardItem);
            }

            // A preview is a live instance of the real widget. Without this the
            // gallery kept every card the user ever scrolled past running for
            // the rest of the session.
            function releasePreview() {
                widgetsConfigRoot._removePreview(cardItem);
                cardItem._previewQueued = false;
                cardItem._previewActive = false;
            }

            Component.onCompleted: Qt.callLater(requestPreviewIfVisible)
            Component.onDestruction: widgetsConfigRoot._removePreview(cardItem)
            onPreviewNearViewportChanged: requestPreviewIfVisible()
            onPreviewFarFromViewportChanged: {
                if (cardItem.previewFarFromViewport)
                    cardItem.releasePreview();
            }

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
                            asynchronous: true
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

                        Loader {
                            id: schemaRenderer
                            Layout.fillWidth: true
                            asynchronous: true
                            active: extConfigOverlay.overlayActive
                            source: Qt.resolvedUrl("widgets/ExtensionWidgetSettingsRenderer.qml")
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                        }

                        Binding {
                            target: schemaRenderer.item
                            property: "extId"
                            value: widgetsConfigRoot.extensionConfigExtId
                            when: schemaRenderer.item !== null
                        }

                        Binding {
                            target: schemaRenderer.item
                            property: "schema"
                            value: {
                                let eId = widgetsConfigRoot.extensionConfigExtId;
                                if (!eId)
                                    return ({});
                                let entry = WidgetExtensionManager.installedWidgets[eId];
                                if (!entry)
                                    return ({});
                                return (entry.widgetJson || {}).configSchema || ({});
                            }
                            when: schemaRenderer.item !== null
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
