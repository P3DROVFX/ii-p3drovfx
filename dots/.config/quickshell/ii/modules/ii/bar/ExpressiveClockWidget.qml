import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    property bool showDate: Config.options.bar.verbose
    property bool isMaterial: true
    readonly property bool is12h: /a/i.test(Config.options.time.format)

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (rowLoader.item?.implicitWidth ?? 0) + 8
    implicitHeight: vertical ? (colLoader.item?.implicitHeight ?? 0) + 8 : Appearance.sizes.baseBarHeight

    width: implicitWidth
    height: implicitHeight

    // Vertical
    Loader {
        id: colLoader
        active: root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: ColumnLayout {
            id: layoutVert
            spacing: 2
            
            // Helper properties for direct formatting
            readonly property bool is12h: root.is12h
            readonly property string hours: Qt.formatDateTime(DateTime.clock.date, is12h ? "hh" : "HH")
            readonly property string minutes: Qt.formatDateTime(DateTime.clock.date, "mm")
            readonly property string ampm: is12h ? Qt.formatDateTime(DateTime.clock.date, Config.options.time.format.includes("AP") ? "AP" : "ap").trim() : ""

            readonly property bool showAMPM: is12h && ampm.length > 0

            MaterialShape {
                Layout.alignment: Qt.AlignHCenter
                shapeString: "Cookie12Sided"
                color: Appearance.colors.colPrimary
                implicitSize: Appearance.sizes.verticalBarWidth - 8
                StyledText {
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Black
                    color: Appearance.colors.colOnPrimary
                    text: layoutVert.hours
                    font.features: { "tnum": 1 }
                }
            }

            MaterialShape {
                Layout.alignment: Qt.AlignHCenter
                shapeString: "Cookie12Sided"
                color: Appearance.colors.colSecondaryContainer
                implicitSize: Appearance.sizes.verticalBarWidth - 8
                StyledText {
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Black
                    color: Appearance.colors.colPrimary
                    text: layoutVert.minutes
                    font.features: { "tnum": 1 }
                }
            }

            Rectangle {
                visible: root.showDate && DateTime.dayNameShort !== ""
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                implicitWidth: Appearance.sizes.verticalBarWidth - 8
                implicitHeight: 20
                color: Appearance.colors.colTertiaryContainer
                radius: Appearance.rounding.small
                StyledText {
                    anchors.centerIn: parent
                    text: DateTime.dayNameShort.toUpperCase()
                    font.pixelSize: 9
                    font.weight: Font.Black
                    color: Appearance.colors.colOnTertiaryContainer
                }
            }

            MaterialShape {
                visible: layoutVert.showAMPM && !root.showDate
                Layout.alignment: Qt.AlignHCenter
                shapeString: "Cookie12Sided"
                color: Appearance.colors.colTertiaryContainer
                implicitSize: Appearance.sizes.verticalBarWidth - 12
                StyledText {
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Black
                    color: Appearance.colors.colOnTertiaryContainer
                    text: layoutVert.ampm
                }
            }

            // LocalSend files attached chip
            Rectangle {
                id: attachedChipVert
                visible: LocalSend.droppedFiles.length > 0
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                implicitWidth: chipRowVert.implicitWidth + 12
                implicitHeight: 20
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimaryContainer
                border.width: 1
                border.color: Appearance.colors.colPrimary

                scale: visible ? 1.0 : 0.0
                Behavior on scale {
                    NumberAnimation { duration: 250; easing.type: Easing.OutBack }
                }

                RowLayout {
                    id: chipRowVert
                    anchors.centerIn: parent
                    spacing: 3
                    
                    MaterialSymbol {
                        text: "attach_file"
                        iconSize: 12
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    
                    StyledText {
                        text: LocalSend.droppedFiles.length
                        font.pixelSize: 10
                        font.weight: Font.Black
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }
        }
    }

    // Horizontal
    Loader {
        id: rowLoader
        active: !root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: RowLayout {
            id: layoutHoriz
            spacing: 4
            
            readonly property bool is12h: root.is12h
            readonly property string hours: Qt.formatDateTime(DateTime.clock.date, is12h ? "hh" : "HH")
            readonly property string minutes: Qt.formatDateTime(DateTime.clock.date, "mm")
            readonly property string ampm: is12h ? Qt.formatDateTime(DateTime.clock.date, Config.options.time.format.includes("AP") ? "AP" : "ap").trim() : ""

            readonly property bool showAMPM: is12h && ampm.length > 0

            MaterialShape {
                shapeString: "Cookie12Sided"
                color: Appearance.colors.colPrimary
                implicitSize: Appearance.sizes.baseBarHeight - 8
                StyledText {
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Black
                    color: Appearance.colors.colOnPrimary
                    text: layoutHoriz.hours
                    font.features: { "tnum": 1 }
                }
            }

            StyledText {
                text: ":"
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Black
                Layout.alignment: Qt.AlignVCenter
            }

            MaterialShape {
                shapeString: "Cookie12Sided"
                color: Appearance.colors.colSecondaryContainer
                implicitSize: Appearance.sizes.baseBarHeight - 8
                StyledText {
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Black
                    color: Appearance.colors.colPrimary
                    text: layoutHoriz.minutes
                    font.features: { "tnum": 1 }
                }
            }

            MaterialShape {
                visible: layoutHoriz.showAMPM
                shapeString: "Cookie12Sided"
                color: Appearance.colors.colTertiaryContainer
                implicitSize: Appearance.sizes.baseBarHeight - 16
                StyledText {
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.light
                    color: Appearance.colors.colOnTertiaryContainer
                    text: layoutHoriz.ampm
                }
            }

            // LocalSend files attached chip
            Rectangle {
                id: attachedChipHoriz
                visible: LocalSend.droppedFiles.length > 0
                implicitWidth: chipRowHoriz.implicitWidth + 12
                implicitHeight: 20
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimaryContainer
                border.width: 1
                border.color: Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 4

                scale: visible ? 1.0 : 0.0
                Behavior on scale {
                    NumberAnimation { duration: 250; easing.type: Easing.OutBack }
                }

                RowLayout {
                    id: chipRowHoriz
                    anchors.centerIn: parent
                    spacing: 3
                    
                    MaterialSymbol {
                        text: "attach_file"
                        iconSize: 12
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    
                    StyledText {
                        text: LocalSend.droppedFiles.length
                        font.pixelSize: 10
                        font.weight: Font.Black
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        ClockWidgetPopup {
            compact: Config.options.bar.tooltips.compactPopups
            hoverTarget: mouseArea
        }
    }
    DropArea {
        id: dropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (drop) => {
            if (!drop.hasUrls) return
            for (let i = 0; i < drop.urls.length; i++)
                LocalSend.addDroppedFile(drop.urls[i])
            drop.accept(Qt.CopyAction)
        }
    }

    // Drag & Drop visual overlay feedback (Layout-aware and fully responsive)
    Rectangle {
        id: dropOverlay
        anchors.fill: parent
        radius: Appearance.rounding.large // Match expressive clock pill rounding
        color: Appearance.colors.colPrimaryContainer
        border.width: 1.5
        border.color: Appearance.colors.colPrimary
        visible: opacity > 0
        opacity: dropArea.containsDrag ? 0.95 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }

        Loader {
            anchors.centerIn: parent
            sourceComponent: parent.width > parent.height ? horizDropContent : vertDropContent
        }

        Component {
            id: horizDropContent
            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: "download"
                    iconSize: 14
                    color: Appearance.colors.colOnPrimaryContainer
                    
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: dropArea.containsDrag
                        NumberAnimation { from: 1.0; to: 1.25; duration: 500; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1.25; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                    }
                }
                StyledText {
                    text: Translation.tr("Drop")
                    font.pixelSize: 10
                    font.weight: Font.Black
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        Component {
            id: vertDropContent
            ColumnLayout {
                spacing: 2
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "download"
                    iconSize: 14
                    color: Appearance.colors.colOnPrimaryContainer
                    
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: dropArea.containsDrag
                        NumberAnimation { from: 1.0; to: 1.25; duration: 500; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1.25; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drop")
                    font.pixelSize: 9
                    font.weight: Font.Black
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }
}