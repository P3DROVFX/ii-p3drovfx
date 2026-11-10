import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

ColumnLayout {
    id: root
    signal extensionConfigRequested(string extId)

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
                                onClicked: root.extensionConfigRequested(extCard.extId)
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
                                        value: "custom",
                                        icon: "open_with",
                                        tooltip: "Own position on lock"
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
