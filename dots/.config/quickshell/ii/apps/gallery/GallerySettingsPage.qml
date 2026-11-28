pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Gallery Settings page (lazy-loaded via Loader).
 * Two-column M3 Expressive layout matching the prototype:
 *   Left: Grid size cards (P=7, M=5, G=3) + Order & playback switches.
 *   Right: Timeline source folders (grouped rows with switches, counts, remove) + Library summary.
 */
Flickable {
    id: root

    required property var store

    contentHeight: mainCol.implicitHeight + 140
    clip: true
    flickDeceleration: 2200
    maximumFlickVelocity: 7200

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse
        onWheel: event => {
            if (event.angleDelta.y === 0)
                return;
            const step = -event.angleDelta.y * 0.85;
            const maxY = Math.max(0, root.contentHeight - root.height);
            root.contentY = Math.max(0, Math.min(maxY, root.contentY + step));
            event.accepted = true;
        }
    }

    readonly property var rowShapes: [
        MaterialShape.Shape.Cookie9Sided,
        MaterialShape.Shape.Clover4Leaf,
        MaterialShape.Shape.Flower,
        MaterialShape.Shape.SoftBurst,
        MaterialShape.Shape.Cookie6Sided,
        MaterialShape.Shape.Cookie12Sided
    ]

    readonly property int libPhotoCount: store.libraryItems.filter(i => i.type === "photo").length
    readonly property int libVideoCount: store.libraryItems.filter(i => i.type === "video").length
    readonly property int libFavCount: store.libraryItems.filter(i => store.isFav(i.path)).length

    component SettingToggleRow: Rectangle {
        id: rowRoot
        required property string icon
        required property string title
        required property string help
        required property bool checked
        required property int shapeEnum
        property bool isFirst: false
        property bool isLast: false
        signal toggled()

        Layout.fillWidth: true
        implicitHeight: 70
        color: checked
            ? (rowMouse.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
            : (rowMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

        topLeftRadius: (isFirst || checked) ? Appearance.rounding.large : Appearance.rounding.verysmall
        topRightRadius: (isFirst || checked) ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomLeftRadius: (isLast || checked) ? Appearance.rounding.large : Appearance.rounding.verysmall
        bottomRightRadius: (isLast || checked) ? Appearance.rounding.large : Appearance.rounding.verysmall

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on topLeftRadius { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Behavior on topRightRadius { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Behavior on bottomLeftRadius { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Behavior on bottomRightRadius { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 14

            MaterialShape {
                implicitWidth: 40
                implicitHeight: 40
                shape: rowRoot.shapeEnum
                color: rowRoot.checked
                    ? Appearance.m3colors.m3tertiaryContainer
                    : Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: rowRoot.icon
                    iconSize: 20
                    fill: rowRoot.checked ? 1 : 0
                    color: rowRoot.checked
                        ? Appearance.m3colors.m3onTertiaryContainer
                        : Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    text: rowRoot.title
                    font.pixelSize: 15
                    font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
                    color: rowRoot.checked
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                StyledText {
                    text: rowRoot.help
                    font.pixelSize: 13
                    color: rowRoot.checked
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colSubtext
                    opacity: rowRoot.checked ? 0.8 : 1
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            StyledSwitch {
                checked: rowRoot.checked
                onClicked: rowRoot.toggled()
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            z: -1
            onClicked: rowRoot.toggled()
        }
    }

    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 28
        spacing: 28

        // Header
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                text: Translation.tr("CUSTOMIZE YOUR GALLERY")
                font.pixelSize: 12
                font.letterSpacing: 0.9
                font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 60 })
                color: Appearance.colors.colOnSurfaceVariant
            }

            RowLayout {
                spacing: 12
                StyledText {
                    text: Translation.tr("Settings")
                    font.pixelSize: 64
                    lineHeight: 0.88
                    font.variableAxes: ({ "wght": 720, "wdth": 40, "ROND": 100 })
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 6
                    text: Translation.tr("your way")
                    font.pixelSize: 28
                    font.italic: true
                    color: Appearance.colors.colPrimary
                }
            }
        }

        // Expressive 1-click Default Linux Photo Viewer card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: defaultCardRow.implicitHeight + 36
            radius: Appearance.rounding.verylarge
            color: store.isDefaultViewer
                ? Appearance.m3colors.m3tertiaryContainer
                : Appearance.colors.colPrimaryContainer

            Behavior on color { ColorAnimation { duration: 220 } }

            RowLayout {
                id: defaultCardRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 22
                spacing: 18

                MaterialShape {
                    implicitWidth: 56
                    implicitHeight: 56
                    shape: store.isDefaultViewer ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie9Sided
                    color: store.isDefaultViewer
                        ? Appearance.m3colors.m3tertiary
                        : Appearance.colors.colPrimary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: store.isDefaultViewer ? "verified" : "photo_library"
                        fill: 1
                        iconSize: 26
                        color: store.isDefaultViewer
                            ? Appearance.m3colors.m3onTertiary
                            : Appearance.colors.colOnPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        spacing: 8
                        StyledText {
                            text: Translation.tr("Default Linux photo viewer")
                            font.family: Appearance.font.family.main
                            font.pixelSize: 18
                            font.variableAxes: ({ "wght": 660, "wdth": 106, "ROND": 100 })
                            color: store.isDefaultViewer
                                ? Appearance.m3colors.m3onTertiaryContainer
                                : Appearance.colors.colOnPrimaryContainer
                        }
                        Rectangle {
                            visible: store.isDefaultViewer
                            implicitWidth: activePillText.implicitWidth + 16
                            implicitHeight: 22
                            radius: 11
                            color: Appearance.m3colors.m3tertiary
                            StyledText {
                                id: activePillText
                                anchors.centerIn: parent
                                text: Translation.tr("Active")
                                font.family: Appearance.font.family.main
                                font.pixelSize: 11
                                font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                                color: Appearance.m3colors.m3onTertiary
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: store.isDefaultViewer
                            ? Translation.tr("Images opened from your file manager open directly in Gallery. You can restore your previous viewer anytime with one click.")
                            : Translation.tr("Register Gallery as your system default photo viewer (PNG, JPEG, WebP, GIF, AVIF, HEIC) so file managers open images directly here.")
                        font.family: Appearance.font.family.main
                        font.pixelSize: 13
                        color: store.isDefaultViewer
                            ? Appearance.m3colors.m3onTertiaryContainer
                            : Appearance.colors.colOnPrimaryContainer
                        opacity: 0.85
                        wrapMode: Text.Wrap
                    }
                }

                RippleButton {
                    enabled: !store.defaultViewerBusy
                    implicitHeight: 44
                    leftPadding: 20
                    rightPadding: 20
                    buttonRadius: hovered ? 14 : 22
                    colBackground: store.isDefaultViewer
                        ? Appearance.m3colors.m3surfaceContainerLowest
                        : Appearance.colors.colPrimary
                    colBackgroundHover: store.isDefaultViewer
                        ? Appearance.colors.colLayer2Hover
                        : Appearance.colors.colPrimaryHover
                    Behavior on buttonRadius { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    onClicked: store.setDefaultViewer(!store.isDefaultViewer)

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: store.defaultViewerBusy
                                ? "hourglass_top"
                                : (store.isDefaultViewer ? "link_off" : "check_circle")
                            iconSize: 18
                            color: store.isDefaultViewer
                                ? Appearance.colors.colOnSurface
                                : Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: store.defaultViewerBusy
                                ? Translation.tr("Updating…")
                                : (store.isDefaultViewer ? Translation.tr("Remove as default") : Translation.tr("Set as default"))
                            font.family: Appearance.font.family.main
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: store.isDefaultViewer
                                ? Appearance.colors.colOnSurface
                                : Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }

        // Responsive 2-column layout (stacks on narrow windows)
        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 880 ? 1 : 2
            columnSpacing: 24
            rowSpacing: 24

            // ── Left column: Grid size + Order & playback ───────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 26

                // Grid size section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        textFormat: Text.RichText
                        text: Translation.tr("Grid <span style='color:%1; font-style:italic'>size</span>").arg(Appearance.colors.colPrimary)
                        font.pixelSize: 24
                        font.variableAxes: ({ "wght": 580, "wdth": 110, "ROND": 100 })
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("How many thumbnails fit per row on Home and in Albums.")
                        font.pixelSize: 14
                        color: Appearance.colors.colOnSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { id: "P", cols: 7, cells: 14, label: Translation.tr("Small") },
                                { id: "M", cols: 5, cells: 10, label: Translation.tr("Medium") },
                                { id: "G", cols: 3, cells: 6,  label: Translation.tr("Large") }
                            ]

                            delegate: Rectangle {
                                id: szCard
                                required property var modelData
                                readonly property bool selected: store.gridSize === modelData.id

                                Layout.fillWidth: true
                                implicitHeight: 184
                                radius: selected ? 32 : (szMouse.containsMouse ? Appearance.rounding.verylarge : Appearance.rounding.large)
                                color: selected
                                    ? Appearance.colors.colSecondaryContainer
                                    : (szMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

                                Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 150 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 6

                                    // Mini grid preview (bounded height so 3-col never overflows!)
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 46
                                        clip: true

                                        Grid {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            columns: szCard.modelData.cols
                                            spacing: 3

                                            Repeater {
                                                model: szCard.modelData.cells
                                                delegate: Rectangle {
                                                    readonly property real fitW: Math.floor((szCard.width - 32 - (szCard.modelData.cols - 1) * 3) / szCard.modelData.cols)
                                                    width: Math.max(8, Math.min(20, fitW))
                                                    height: width
                                                    radius: 4
                                                    color: szCard.selected
                                                        ? Appearance.colors.colOnSecondaryContainer
                                                        : Appearance.colors.colOnSurface
                                                    opacity: szCard.selected ? 0.72 : 0.25
                                                }
                                            }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }

                                    StyledText {
                                        text: String(szCard.modelData.cols)
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: 52
                                        lineHeight: 0.84
                                        font.variableAxes: ({ "wght": 760, "wdth": 36, "ROND": 100 })
                                        color: szCard.selected
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colOnSurface
                                    }

                                    StyledText {
                                        text: szCard.modelData.label
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: 14
                                        font.variableAxes: ({ "wght": 660, "wdth": 104, "ROND": 100 })
                                        color: szCard.selected
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colOnSurfaceVariant
                                    }
                                }

                                MouseArea {
                                    id: szMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        store.setGridSize(szCard.modelData.id);
                                        store.showSnack(
                                            Translation.tr("%1 grid · %2 per row")
                                                .arg(szCard.modelData.label)
                                                .arg(szCard.modelData.cols),
                                            "", null
                                        );
                                    }
                                }
                            }
                        }
                    }
                }

                // Order & Playback section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        textFormat: Text.RichText
                        text: Translation.tr("Order & <span style='color:%1; font-style:italic'>playback</span>").arg(Appearance.colors.colPrimary)
                        font.pixelSize: 24
                        font.variableAxes: ({ "wght": 580, "wdth": 110, "ROND": 100 })
                        color: Appearance.colors.colOnSurface
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { id: "desc", label: Translation.tr("Newest first") },
                                { id: "asc",  label: Translation.tr("Oldest first") }
                            ]

                            delegate: RippleButton {
                                id: ordChip
                                required property var modelData
                                readonly property bool selected: store.sortOrder === modelData.id

                                implicitHeight: 38
                                leftPadding: 14
                                rightPadding: 16
                                buttonRadius: selected ? 19 : Appearance.rounding.small
                                colBackground: selected ? Appearance.colors.colSecondaryContainer : "transparent"
                                colBackgroundHover: selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                                onClicked: store.setSortOrder(modelData.id)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.buttonRadius
                                    color: "transparent"
                                    border.width: ordChip.selected ? 0 : 1
                                    border.color: Appearance.colors.colOutlineVariant
                                }

                                contentItem: RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        visible: ordChip.selected
                                        text: "check"
                                        iconSize: 17
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    StyledText {
                                        text: ordChip.modelData.label
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        color: ordChip.selected
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        SettingToggleRow {
                            isFirst: true
                            icon: "movie"
                            title: Translation.tr("Show videos")
                            help: Translation.tr("In the timeline and in albums")
                            checked: store.showVideos
                            shapeEnum: root.rowShapes[0]
                            onToggled: store.togglePref("showVideos")
                        }
                        SettingToggleRow {
                            icon: "play_circle"
                            title: Translation.tr("Autoplay videos on open")
                            help: Translation.tr("Start playing automatically in the viewer")
                            checked: store.autoplay
                            shapeEnum: root.rowShapes[1]
                            onToggled: store.togglePref("autoplay")
                        }
                        SettingToggleRow {
                            isLast: true
                            icon: "volume_off"
                            title: Translation.tr("Start muted")
                            help: Translation.tr("Useful in quiet environments")
                            checked: store.startMuted
                            shapeEnum: root.rowShapes[2]
                            onToggled: store.togglePref("startMuted")
                        }
                    }
                }
            }

            // ── Right column: Timeline folders + Library summary ────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 26

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        textFormat: Text.RichText
                        text: Translation.tr("Timeline <span style='color:%1; font-style:italic'>folders</span>").arg(Appearance.colors.colPrimary)
                        font.pixelSize: 24
                        font.variableAxes: ({ "wght": 580, "wdth": 110, "ROND": 100 })
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Choose where Home photos and videos come from. Albums always show all folders.")
                        font.pixelSize: 14
                        color: Appearance.colors.colOnSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Repeater {
                            model: store.folders

                            delegate: Rectangle {
                                id: fRow
                                required property var modelData
                                required property int index
                                readonly property bool isOn: modelData.on === true
                                readonly property int count: Number(store.folderCounts[modelData.name] ?? 0)

                                Layout.fillWidth: true
                                implicitHeight: 70
                                color: isOn
                                    ? (fMouse.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                                    : (fMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

                                topLeftRadius: (index === 0 || isOn) ? Appearance.rounding.large : Appearance.rounding.verysmall
                                topRightRadius: (index === 0 || isOn) ? Appearance.rounding.large : Appearance.rounding.verysmall
                                bottomLeftRadius: isOn ? Appearance.rounding.large : Appearance.rounding.verysmall
                                bottomRightRadius: isOn ? Appearance.rounding.large : Appearance.rounding.verysmall

                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    spacing: 12

                                    MaterialShape {
                                        implicitWidth: 40
                                        implicitHeight: 40
                                        shape: root.rowShapes[fRow.index % root.rowShapes.length]
                                        color: fRow.isOn
                                            ? Appearance.m3colors.m3tertiaryContainer
                                            : Appearance.colors.colPrimaryContainer

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: store.folderIcon(fRow.modelData.name)
                                            iconSize: 20
                                            fill: fRow.isOn ? 1 : 0
                                            color: fRow.isOn
                                                ? Appearance.m3colors.m3onTertiaryContainer
                                                : Appearance.colors.colOnPrimaryContainer
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        StyledText {
                                            text: fRow.modelData.name
                                            font.pixelSize: 15
                                            font.weight: Font.DemiBold
                                            color: fRow.isOn
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnSurface
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        StyledText {
                                            text: fRow.modelData.path
                                            font.pixelSize: 13
                                            color: fRow.isOn
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colSubtext
                                            opacity: fRow.isOn ? 0.8 : 1
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    StyledText {
                                        text: store.pad2(fRow.count)
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: 28
                                        font.variableAxes: ({ "wght": 760, "wdth": 38, "ROND": 100 })
                                        color: fRow.isOn
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colOnSurfaceVariant
                                    }

                                    RippleButton {
                                        visible: !fRow.modelData.base
                                        implicitWidth: 34
                                        implicitHeight: 34
                                        buttonRadius: 17
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.m3colors.m3errorContainer
                                        onClicked: store.removeFolder(fRow.modelData.name)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"
                                            iconSize: 18
                                            color: parent.hovered
                                                ? Appearance.m3colors.m3onErrorContainer
                                                : Appearance.colors.colOnSurfaceVariant
                                        }
                                        StyledToolTip { text: Translation.tr("Remove folder") }
                                    }

                                    StyledSwitch {
                                        checked: fRow.isOn
                                        onClicked: store.toggleFolder(fRow.modelData.name)
                                    }
                                }

                                MouseArea {
                                    id: fMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    z: -1
                                    onClicked: store.toggleFolder(fRow.modelData.name)
                                }
                            }
                        }

                        SettingToggleRow {
                            isLast: true
                            icon: "account_tree"
                            title: Translation.tr("Include subfolders")
                            help: Translation.tr("e.g. Pictures › Wallpapers, Downloads › Phone")
                            checked: store.includeSub
                            shapeEnum: root.rowShapes[4]
                            onToggled: store.togglePref("includeSub")
                        }
                    }

                    RippleButton {
                        Layout.topMargin: 4
                        implicitHeight: 44
                        leftPadding: 18
                        rightPadding: 20
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: store.addSheetOpen = true

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.buttonRadius
                            color: "transparent"
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                        }

                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                text: "add"
                                iconSize: 20
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                text: Translation.tr("Add folder")
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }

                // Library summary card
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        textFormat: Text.RichText
                        text: Translation.tr("In your <span style='color:%1; font-style:italic'>library</span>").arg(Appearance.colors.colPrimary)
                        font.pixelSize: 24
                        font.variableAxes: ({ "wght": 580, "wdth": 110, "ROND": 100 })
                        color: Appearance.colors.colOnSurface
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: storeCardCol.implicitHeight + 40
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer2

                        ColumnLayout {
                            id: storeCardCol
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 14

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 16

                                StyledText {
                                    text: store.pad2(store.libraryItems.length)
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 72
                                    lineHeight: 0.84
                                    font.variableAxes: ({ "wght": 760, "wdth": 36, "ROND": 100 })
                                    color: Appearance.colors.colPrimary
                                }

                                ColumnLayout {
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 6
                                    spacing: 2
                                    StyledText {
                                        text: Translation.tr("items across %1 folders").arg(store.folders.length)
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnSurface
                                    }
                                    StyledText {
                                        text: Translation.tr("Preferences saved in gallery.json")
                                        font.pixelSize: 13
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            // Segmented bar
                            RowLayout {
                                Layout.fillWidth: true
                                implicitHeight: 16
                                spacing: 4

                                Rectangle {
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: Math.max(1, root.libPhotoCount)
                                    radius: 5
                                    color: Appearance.colors.colPrimary
                                }
                                Rectangle {
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: Math.max(0.1, root.libVideoCount)
                                    visible: root.libVideoCount > 0
                                    radius: 5
                                    color: Appearance.m3colors.m3tertiary
                                }
                                Rectangle {
                                    Layout.fillHeight: true
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: Math.max(0.1, root.libFavCount)
                                    visible: root.libFavCount > 0
                                    radius: 5
                                    color: Appearance.m3colors.m3surfaceContainerHighest
                                }
                            }

                            // Legend
                            Flow {
                                Layout.fillWidth: true
                                spacing: 18

                                Repeater {
                                    model: [
                                        { c: Appearance.colors.colPrimary, txt: Translation.tr("%1 photos").arg(root.libPhotoCount) },
                                        { c: Appearance.m3colors.m3tertiary, txt: Translation.tr("%1 videos").arg(root.libVideoCount) },
                                        { c: Appearance.m3colors.m3surfaceContainerHighest, txt: Translation.tr("%1 favorites").arg(root.libFavCount) }
                                    ]
                                    delegate: RowLayout {
                                        required property var modelData
                                        spacing: 6
                                        Rectangle { width: 10; height: 10; radius: 3; color: parent.modelData.c }
                                        StyledText {
                                            text: parent.modelData.txt
                                            font.pixelSize: 13
                                            color: Appearance.colors.colOnSurfaceVariant
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
}
