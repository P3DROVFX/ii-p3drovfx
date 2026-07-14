import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

Item {
    id: widgetsConfigRoot

    property alias contentY: page.contentY
    property url activeSubPage: ""

    property var clockWidgets: (WidgetsRegistry.allWidgets || []).filter(function(w) { return w.category === "Clock"; })
    property var mediaWidgets: (WidgetsRegistry.allWidgets || []).filter(function(w) { return w.category === "Media"; })
    property var weatherWidgets: (WidgetsRegistry.allWidgets || []).filter(function(w) { return w.category === "Weather"; })
    property var dateWidgets: (WidgetsRegistry.allWidgets || []).filter(function(w) { return w.category === "Date"; })

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.width > 0 ? (subPageOverlay.x / subPageOverlay.width) : 1
        visible: opacity > 0

        ContentSection {
            title: Translation.tr("Desktop Widgets")
            icon: "widgets"

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
        }
    }

    Component {
        id: widgetCardComponent

        Item {
            id: cardItem
            width: 220
            implicitHeight: mainColumn.implicitHeight + 12

            property bool hovered: cardMouseArea.containsMouse

            readonly property var widgetData: modelData
            readonly property bool isActive: Config.isWidgetActive(widgetData.widgetId)
            readonly property string currentLockBehavior: Config.getWidgetLockBehavior(widgetData.widgetId)

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
                    ColorAnimation { duration: 150 }
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
                        function onIsActiveChanged() { dashedBorderCanvas.requestPaint(); }
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
                            source: cardItem.widgetData.qmlPath

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

                    Rectangle {
                        id: dimOverlay
                        anchors.fill: parent
                        color: "black"
                        opacity: cardItem.hovered ? 0.35 : 0
                        radius: Appearance.rounding.normal
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation { duration: 150 }
                        }
                    }

                    Rectangle {
                        id: removeBar
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 6
                        height: 30
                        radius: Appearance.rounding.full
                        color: removeBarMouse.containsMouse ? Appearance.colors.colErrorContainerHover : Appearance.colors.colErrorContainer
                        visible: cardItem.isActive
                        opacity: cardItem.isActive ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 150 }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 100 }
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
                                text: Translation.tr("Remove")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: Appearance.colors.colOnErrorContainer
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: removeBarMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Config.removeWidgetFromDesktop(cardItem.widgetData.widgetId);
                            }
                        }
                    }

                    Rectangle {
                        id: addBar
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 6
                        height: 30
                        radius: Appearance.rounding.full
                        color: addBarMouse.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer
                        opacity: (!cardItem.isActive && cardItem.hovered) ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 150 }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 100 }
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
                                text: Translation.tr("Add")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: Appearance.colors.colOnPrimaryContainer
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: addBarMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Config.addWidgetToDesktop(cardItem.widgetData.widgetId);
                            }
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
                            ColorAnimation { duration: 100 }
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
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3
                    visible: cardItem.isActive

                    readonly property string currentBehavior: cardItem.currentLockBehavior

                    Repeater {
                        model: [
                            { value: "hide", icon: "visibility_off", tooltip: "Hidden on lock" },
                            { value: "keep", icon: "visibility", tooltip: "Keep position" },
                            { value: "center", icon: "center_focus_strong", tooltip: "Center on lock" },
                            { value: "lockOnly", icon: "lock", tooltip: "Lock only" }
                        ]

                        delegate: Rectangle {
                            width: 26
                            height: 26
                            radius: Appearance.rounding.small
                            color: parent.parent.currentBehavior === modelData.value
                                ? Appearance.colors.colPrimaryContainer
                                : Appearance.colors.colSurfaceContainerLow

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: modelData.icon
                                iconSize: 13
                                color: parent.parent.currentBehavior === modelData.value
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurfaceVariant
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

    Item {
        id: subPageOverlay
        width: parent.width
        height: parent.height
        y: 0
        z: 10

        property bool isOpen: widgetsConfigRoot.activeSubPage.toString() !== ""
        property bool overlayActive: isOpen

        onXChanged: {
            if (!isOpen && x >= subPageOverlay.width - 1)
                overlayActive = false;
        }
        onIsOpenChanged: {
            if (isOpen) overlayActive = true;
        }

        x: isOpen ? 0 : subPageOverlay.width

        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        enabled: isOpen

        Loader {
            id: subPageLoader
            anchors.fill: parent
            source: widgetsConfigRoot.activeSubPage
            active: subPageOverlay.overlayActive

            onLoaded: {
                item.goBack.connect(function() {
                    widgetsConfigRoot.activeSubPage = "";
                });
            }
        }
    }
}
