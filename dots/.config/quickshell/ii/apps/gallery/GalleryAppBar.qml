pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Top app bar for the standalone Gallery app.
 * Matches the M3 Expressive prototype: Cookie9Sided->Cookie12Sided brand mark,
 * animated subtitle, centered pill search field with `/` hint, and right-aligned actions.
 */
Item {
    id: root

    required property var store
    required property var phoneBridge
    signal closeWindowRequested()
    signal toggleMaximizeRequested()
    property bool isMaximized: false

    implicitHeight: 68

    function focusSearch(): void {
        searchInput.forceActiveFocus();
    }

    readonly property string subtitleText: {
        if (store.activeTab === "albums") {
            if (store.activeAlbum) {
                const segs = store.activeAlbum.split("/");
                return segs[segs.length - 1];
            }
            return Translation.tr("Albums");
        }
        if (store.activeTab === "phone")
            return phoneBridge.deviceName ? phoneBridge.deviceName : Translation.tr("Phone gallery");
        if (store.activeTab === "settings")
            return Translation.tr("Settings");
        return Translation.tr("Timeline");
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 16
        spacing: 16

        // Left: Brand mark + title/subtitle
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 12

            MouseArea {
                id: brandHover
                implicitWidth: 40
                implicitHeight: 40
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    store.activeTab = "home";
                    store.activeAlbum = "";
                }

                MaterialShape {
                    anchors.fill: parent
                    shape: brandHover.containsMouse
                        ? MaterialShape.Shape.Cookie12Sided
                        : MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "photo_library"
                        fill: 1
                        iconSize: 21
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }

            ColumnLayout {
                spacing: 0
                StyledText {
                    text: Translation.tr("Gallery")
                    font.family: Appearance.font.family.main
                    font.pixelSize: 20
                    font.variableAxes: ({ "wght": 680, "wdth": 115, "ROND": 100 })
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    text: root.subtitleText
                    font.family: Appearance.font.family.main
                    font.pixelSize: 13
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    Layout.maximumWidth: 220
                }
            }

            Item { Layout.fillWidth: true }
        }

        // Center: Pill Search Bar
        Rectangle {
            Layout.preferredWidth: Math.min(500, Math.max(240, root.width * 0.36))
            Layout.preferredHeight: 44
            radius: Appearance.rounding.full
            color: searchInput.activeFocus
                ? Appearance.m3colors.m3surfaceContainerHighest
                : (searchHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

            Behavior on color {
                ColorAnimation { duration: 160 }
            }

            HoverHandler {
                id: searchHover
                cursorShape: Qt.IBeamCursor
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 8
                spacing: 10

                MaterialSymbol {
                    text: "search"
                    iconSize: 20
                    color: Appearance.colors.colOnSurfaceVariant
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Appearance.font.family.main
                    font.pixelSize: 15
                    color: Appearance.colors.colOnSurface
                    selectionColor: Appearance.colors.colPrimaryContainer
                    selectedTextColor: Appearance.colors.colOnPrimaryContainer
                    clip: true
                    text: store.query

                    onTextChanged: {
                        if (store.query !== text) {
                            store.query = text;
                            if (text.length > 0 && store.activeTab !== "home")
                                store.activeTab = "home";
                        }
                    }

                    Keys.onEscapePressed: {
                        if (text.length > 0) {
                            text = "";
                            store.query = "";
                        } else {
                            focus = false;
                        }
                    }

                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: searchInput.text.length === 0
                        text: Translation.tr("Search photos, folders, months…")
                        font.pixelSize: 15
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                // Keyboard shortcut hint `/`
                Rectangle {
                    visible: !searchInput.activeFocus && searchInput.text.length === 0
                    implicitWidth: 24
                    implicitHeight: 24
                    radius: 8
                    color: Appearance.m3colors.m3surfaceContainerHighest
                    StyledText {
                        anchors.centerIn: parent
                        text: "/"
                        font.pixelSize: 12
                        color: Appearance.colors.colSubtext
                    }
                }

                // Clear search button
                RippleButton {
                    visible: searchInput.text.length > 0
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: {
                        searchInput.text = "";
                        store.query = "";
                        searchInput.forceActiveFocus();
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }

        // Right: Phone quick pill + refresh + window buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 4

            Item { Layout.fillWidth: true }

            // Phone status pill (when connected via ii tools)
            RippleButton {
                visible: phoneBridge.connected
                implicitHeight: 36
                leftPadding: 10
                rightPadding: 12
                buttonRadius: Appearance.rounding.full
                colBackground: store.activeTab === "phone"
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer2
                colBackgroundHover: store.activeTab === "phone"
                    ? Appearance.colors.colPrimaryContainerHover
                    : Appearance.colors.colLayer2Hover
                onClicked: store.activeTab = "phone"
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "smartphone"
                        iconSize: 16
                        fill: 1
                        color: store.activeTab === "phone"
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: phoneBridge.deviceName || Translation.tr("Phone")
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: store.activeTab === "phone"
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                        Layout.maximumWidth: 110
                    }
                }
                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Open phone gallery via ii tools")
                }
            }

            // Refresh library button
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: hovered ? 13 : 20
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: {
                    if (store.activeTab === "phone")
                        phoneBridge.refresh();
                    else
                        store.rescan();
                }
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 20
                    color: Appearance.colors.colOnSurfaceVariant
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 900
                        loops: Animation.Infinite
                        running: store.scanning || (store.activeTab === "phone" && phoneBridge.loading)
                    }
                }
                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Refresh")
                }
            }

            // Fullscreen / Maximize adaptive toggle
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: hovered ? 13 : 20
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.toggleMaximizeRequested()
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isMaximized ? "fullscreen_exit" : "fullscreen"
                    iconSize: 21
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledToolTip {
                    requireOverlay: false
                    text: root.isMaximized ? Translation.tr("Exit fullscreen") : Translation.tr("Fullscreen")
                }
            }

            // Close window
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: hovered ? 13 : 20
                colBackground: "transparent"
                colBackgroundHover: Appearance.m3colors.m3errorContainer
                onClicked: root.closeWindowRequested()
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 20
                    color: parent.hovered ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnSurfaceVariant
                }
                StyledToolTip {
                    requireOverlay: false
                    text: Translation.tr("Close")
                }
            }
        }
    }
}
