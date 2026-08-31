pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal

    property bool showBackButton: true
    signal goBack()

    // Sub-page entrance animation
    opacity: 0
    transform: Translate { id: pageTranslate; y: 16 }

    Component.onCompleted: {
        pageEntranceAnim.start()
        if (PhoneScrcpyService.appModeSupported && (!PhoneScrcpyService.apps || PhoneScrcpyService.apps.length === 0)) {
            PhoneScrcpyService.refreshApps()
        }
    }

    SequentialAnimation {
        id: pageEntranceAnim
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                from: 0
                to: 1
                duration: 280
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: pageTranslate
                property: "y"
                from: 16
                to: 0
                duration: 360
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
        }
    }

    // Pulling icons off the phone is slow enough that it only happens when the
    // user refreshes the list, never on its own. The results are cached, so it
    // is a one-off rather than something that repeats on every reconnect.
    QtObject {
        id: iconHarvest
        property bool armed: false
    }

    Timer {
        id: harvestWindow
        interval: 10000
        onTriggered: iconHarvest.armed = false
    }

    Connections {
        target: PhoneScrcpyService
        enabled: iconHarvest.armed
        function onAppsChanged() {
            iconHarvest.armed = false
            harvestWindow.stop()
            PhoneAppIconService.fetchMissing((PhoneScrcpyService.apps || []).map(a => a.package))
        }
    }

    // Launcher icon pulled off the phone, falling back to a generic glyph while
    // it has not been fetched or cannot be resolved.
    component AppIcon: Item {
        id: appIcon

        required property string packageName
        property real symbolSize: 20
        property real symbolPadding: 8
        property color shapeColor: Appearance.colors.colSecondaryContainer
        property color symbolColor: Appearance.colors.colOnSecondaryContainer

        readonly property string iconPath: PhoneAppIconService.iconFor(packageName)

        implicitWidth: symbolSize + symbolPadding * 2
        implicitHeight: implicitWidth

        MaterialShapeWrappedMaterialSymbol {
            anchors.centerIn: parent
            visible: launcherIcon.status !== Image.Ready
            text: "android"
            iconSize: appIcon.symbolSize
            padding: appIcon.symbolPadding
            fill: 1.0
            color: appIcon.shapeColor
            colSymbol: appIcon.symbolColor
            shape: MaterialShape.Shape.Cookie9Sided
        }

        Image {
            id: launcherIcon
            anchors.fill: parent
            source: appIcon.iconPath ? ("file://" + appIcon.iconPath) : ""
            sourceSize.width: appIcon.implicitWidth * 2
            sourceSize.height: appIcon.implicitHeight * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready

            layer.enabled: visible
            layer.effect: OpacityMask {
                maskSource: AndroidIconMask {
                    width: launcherIcon.width
                    height: launcherIcon.height
                    shapeName: Config.options?.phone?.scrcpy?.appMode?.iconShape ?? "oneui"
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // ─── Header Bar ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                id: backBtn
                visible: root.showBackButton
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer3
                }
                onClicked: root.goBack()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Android Apps")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (!PhoneScrcpyService.appModeSupported) return Translation.tr("Requires scrcpy 4.0+")
                        if (PhoneScrcpyService.appsLoading) return Translation.tr("Loading apps…")
                        if (PhoneAppIconService.fetching) {
                            return Translation.tr("Fetching icons… %1/%2")
                                .arg(String(PhoneAppIconService.fetched))
                                .arg(String(PhoneAppIconService.batchSize))
                        }
                        return Translation.tr("%1 apps").arg(String(PhoneScrcpyService.filteredApps.length))
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                }
            }

            RippleButton {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer3
                }
                onClicked: {
                    iconHarvest.armed = PhoneAppIconService.enabled
                    if (iconHarvest.armed) harvestWindow.restart()
                    PhoneScrcpyService.refreshApps()
                }
                StyledToolTip {
                    text: PhoneAppIconService.enabled
                          ? Translation.tr("Refresh app list and fetch missing icons")
                          : Translation.tr("Refresh app list")
                }
            }
        }

        // ─── Search Field ─────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialSymbol {
                    text: "search"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }

                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search Android apps…")
                    placeholderTextColor: Appearance.colors.colSubtext
                    color: Appearance.colors.colOnLayer3
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    background: null
                    padding: 0
                    verticalAlignment: TextInput.AlignVCenter

                    onTextChanged: PhoneScrcpyService.setSearchQuery(text)

                    StyledTextContextMenu {
                        id: searchContextMenu
                        targetField: searchInput
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.RightButton
                        onPressed: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                searchInput.forceActiveFocus();
                                searchContextMenu.popup(mouse.x, mouse.y);
                            }
                        }
                    }
                }

                RippleButton {
                    visible: searchInput.text.length > 0
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 16
                        color: Appearance.colors.colSubtext
                    }
                    onClicked: {
                        searchInput.text = ""
                        PhoneScrcpyService.setSearchQuery("")
                    }
                }
            }
        }

        // ─── Active Running Sessions Section ────────────────────────
        Item {
            id: runningSection
            Layout.fillWidth: true
            implicitHeight: runningLayout.implicitHeight
            visible: runningRepeater.count > 0

            ColumnLayout {
                id: runningLayout
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        text: Translation.tr("Active Sessions (%1)").arg(String(runningRepeater.count))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                        opacity: 0.85
                    }
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        Layout.preferredHeight: 24
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Stop All")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colError
                        }
                        onClicked: PhoneScrcpyService.stopAllApps()
                    }
                }

                Repeater {
                    id: runningRepeater
                    model: (PhoneScrcpyService.sessions || []).filter(s => s.type === "app")

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colPrimaryContainer

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 10
                                Layout.preferredHeight: 10
                                radius: 5
                                color: Appearance.colors.colSuccess ?? "#4CAF50"
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.package ? modelData.package.split(".").pop() : modelData.id
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimaryContainer
                                elide: Text.ElideRight
                            }

                            RippleButton {
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: 60
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover

                                contentItem: StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Focus")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnPrimary
                                }
                                onClicked: PhoneScrcpyService.focusApp(modelData.package)
                            }

                            RippleButton {
                                Layout.preferredHeight: 32
                                Layout.preferredWidth: 32
                                buttonRadius: Appearance.rounding.full
                                colBackground: Appearance.colors.colErrorContainer
                                colBackgroundHover: Appearance.colors.colErrorContainerHover

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 16
                                    color: Appearance.colors.colOnErrorContainer
                                }
                                onClicked: PhoneScrcpyService.stopApp(modelData.package)
                                StyledToolTip {
                                    text: Translation.tr("Close session")
                                }
                            }
                        }
                    }
                }
            }
        }

        // ─── Favorites Section ──────────────────────────────────
        Item {
            id: favoritesRow
            Layout.fillWidth: true
            implicitHeight: favLayout.implicitHeight
            visible: favRepeater.count > 0

            ColumnLayout {
                id: favLayout
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                StyledText {
                    text: Translation.tr("Favorite Apps")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                    opacity: 0.85
                }

                Flickable {
                    id: favFlickable
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    contentWidth: favRow.implicitWidth
                    contentHeight: height
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.DragOverBounds
                    maximumFlickVelocity: 3500

                    WheelHandler {
                        enabled: Config?.options.interactions.scrolling.fasterTouchpadScroll ?? false
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            // Mouse wheels emit multiples of ±120 on one axis; touchpads emit
                            // small continuous deltas, so each gets its own amplification factor.
                            const raw = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                            const threshold = Config.options.interactions.scrolling.mouseScrollDeltaThreshold;
                            const scrollFactor = Math.abs(raw) >= threshold ? Config.options.interactions.scrolling.mouseScrollFactor : Config.options.interactions.scrolling.touchpadScrollFactor;
                            const maxX = Math.max(0, favFlickable.contentWidth - favFlickable.width);
                            favFlickable.contentX = Math.max(0, Math.min(favFlickable.contentX - (raw / threshold) * scrollFactor, maxX));
                        }
                    }

                    Row {
                        id: favRow
                        spacing: 8

                        Repeater {
                            id: favRepeater
                            model: (PhoneScrcpyService.apps || []).filter(a => PhoneScrcpyService.isAppFavorite(a.package))

                            delegate: RippleButton {
                                required property var modelData
                                width: 130
                                height: 50
                                buttonRadius: Appearance.rounding.normal
                                colBackground: PhoneScrcpyService.isAppRunning(modelData.package)
                                               ? Appearance.colors.colPrimaryContainer
                                               : Appearance.colors.colLayer3
                                colBackgroundHover: Appearance.colors.colLayer3Hover

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    AppIcon {
                                        Layout.alignment: Qt.AlignVCenter
                                        packageName: modelData.package
                                        symbolSize: 16
                                        symbolPadding: 6
                                        shapeColor: Appearance.colors.colPrimary
                                        symbolColor: Appearance.colors.colOnPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name || modelData.package.split(".").pop()
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer2
                                        elide: Text.ElideRight
                                    }
                                }

                                onClicked: PhoneScrcpyService.launchApp(modelData.package)
                            }
                        }
                    }
                }
            }
        }

        // ─── Apps List ────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: appsList
                anchors.fill: parent
                model: PhoneScrcpyService.filteredApps
                clip: true
                spacing: 6
                animateAppearance: false // Model is search-filtered: no pop-in on every keystroke

                delegate: Rectangle {
                    id: appItem
                    required property var modelData
                    required property int index

                    width: appsList.width
                    height: 56
                    radius: Appearance.rounding.normal
                    color: isRunning ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3

                    readonly property bool isRunning: PhoneScrcpyService.isAppRunning(modelData.package)

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                        }
                    }

                    RippleButton {
                        anchors.fill: parent
                        buttonRadius: Appearance.rounding.normal
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer3Hover

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            // App Icon / Glyph
                            AppIcon {
                                Layout.alignment: Qt.AlignVCenter
                                packageName: modelData.package
                                shapeColor: appItem.isRunning ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                symbolColor: appItem.isRunning ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: -2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.name || modelData.package.split(".").pop()
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.DemiBold
                                    color: appItem.isRunning ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.package
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    opacity: 0.8
                                    elide: Text.ElideRight
                                }
                            }

                            // Favorite Star Toggle
                            RippleButton {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer3Hover

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: PhoneScrcpyService.isAppFavorite(modelData.package) ? "star" : "star_outline"
                                    iconSize: 18
                                    fill: PhoneScrcpyService.isAppFavorite(modelData.package) ? 1.0 : 0.0
                                    color: PhoneScrcpyService.isAppFavorite(modelData.package)
                                           ? Appearance.colors.colPrimary
                                           : Appearance.colors.colSubtext
                                    animateChange: true
                                }
                                onClicked: PhoneScrcpyService.toggleAppFavorite(modelData.package)
                                StyledToolTip {
                                    text: PhoneScrcpyService.isAppFavorite(modelData.package)
                                          ? Translation.tr("Remove from favorites")
                                          : Translation.tr("Add to favorites")
                                }
                            }

                            // Launch / Focus Action Icon
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: appItem.isRunning ? "open_in_new" : "play_arrow"
                                iconSize: 20
                                color: appItem.isRunning ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                        }

                        onClicked: PhoneScrcpyService.launchApp(modelData.package)
                    }
                }
            }

            // Empty State
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                visible: !PhoneScrcpyService.appModeSupported || PhoneScrcpyService.filteredApps.length === 0

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: !PhoneScrcpyService.appModeSupported ? "warning" : "apps"
                    iconSize: 48
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: parent.width * 0.85
                    text: !PhoneScrcpyService.appModeSupported
                          ? Translation.tr("App Mode requires scrcpy 4.0+ with --flex-display support.")
                          : (searchInput.text.length > 0
                             ? Translation.tr("No apps matching search")
                             : (PhoneScrcpyService.appsLoading ? Translation.tr("Loading apps from phone…") : Translation.tr("No Android apps found.")))
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
