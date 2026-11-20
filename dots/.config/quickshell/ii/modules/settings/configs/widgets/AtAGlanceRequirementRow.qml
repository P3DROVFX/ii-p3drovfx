import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * One At a Glance requirement (Smartspacer's Requirements): its summary, an
 * invert switch, a delete key, and the fields its type needs.
 */
Rectangle {
    id: root

    property var requirement: ({})
    signal changed(var requirement)
    signal removed

    readonly property var info: AtAGlanceService.typeInfo("requirement", root.requirement.type)

    property bool armed: false
    Component.onCompleted: Qt.callLater(() => root.armed = true)

    function set(key, value) {
        if (!root.armed)
            return;
        const current = root.requirement[key] ?? (key === "invert" ? false : undefined);
        if (JSON.stringify(current) === JSON.stringify(value))
            return;
        const copy = AtAGlanceService.plain(root.requirement);
        copy[key] = value;
        // After the handler returns, or the rebuild re-enters this binding.
        Qt.callLater(() => root.changed(copy));
    }

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialSymbol {
                text: root.info.icon
                iconSize: 20
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: root.info.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: AtAGlanceService.requirementSummary(root.requirement)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
            RippleButton {
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: 17
                colBackground: "transparent"
                onClicked: root.removed()
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "delete"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: Translation.tr("Remove requirement")
                }
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "swap_horiz"
            text: Translation.tr("Invert this requirement")
            checked: root.requirement.invert === true
            onCheckedChanged: root.set("invert", checked)
            StyledToolTip {
                text: Translation.tr("Show only when this condition is NOT met")
            }
        }

        // ── Time & Date ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: root.requirement.type === "time"
            spacing: 6
            ConfigTextField {
                Layout.fillWidth: true
                icon: "schedule"
                text: Translation.tr("Start Time")
                placeholderText: "09:00"
                inputText: root.requirement.start ?? "09:00"
                textField.onEditingFinished: if (/^\d{1,2}:\d{2}$/.test(textField.text)) root.set("start", textField.text)
            }
            ConfigTextField {
                Layout.fillWidth: true
                icon: "schedule"
                text: Translation.tr("End Time")
                placeholderText: "17:00"
                inputText: root.requirement.end ?? "17:00"
                textField.onEditingFinished: if (/^\d{1,2}:\d{2}$/.test(textField.text)) root.set("end", textField.text)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.requirement.type === "time"
            spacing: 4
            Repeater {
                model: [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat")]
                delegate: RippleButton {
                    id: day
                    required property string modelData
                    required property int index
                    readonly property var days: Array.from(root.requirement.days ?? [true, true, true, true, true, true, true])
                    readonly property bool on: day.days[day.index] !== false
                    Layout.fillWidth: true
                    implicitHeight: 34
                    buttonRadius: day.on ? Appearance.rounding.small : 17
                    colBackground: day.on ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: day.on ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    onClicked: {
                        const next = day.days.slice();
                        next[day.index] = !day.on;
                        // Smartspacer needs at least one day.
                        if (next.some(d => d !== false))
                            root.set("days", next);
                    }
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: day.modelData
                        color: day.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }

        // ── Text parameter for the other types ─────────────────────────────────
        ConfigTextField {
            Layout.fillWidth: true
            readonly property string key: ({ wifi: "ssid", bluetooth: "device", app: "appClass", focusedApp: "appClass", location: "city" })[root.requirement.type] ?? ""
            visible: key !== ""
            icon: root.info.icon
            text: ({
                wifi: Translation.tr("Network Name (SSID)"),
                bluetooth: Translation.tr("Device name"),
                app: Translation.tr("App class"),
                focusedApp: Translation.tr("App class"),
                location: Translation.tr("City")
            })[root.requirement.type] ?? ""
            placeholderText: ({
                wifi: NetworkState.wifiNetworkName || Translation.tr("Any network"),
                bluetooth: Translation.tr("Any device"),
                app: "firefox",
                focusedApp: "code",
                location: Weather.data?.city ?? ""
            })[root.requirement.type] ?? ""
            tooltip: root.requirement.type === "location"
                ? Translation.tr("Matched against the city your weather location resolves to")
                : root.requirement.type === "app" || root.requirement.type === "focusedApp"
                    ? Translation.tr("Window class, as shown by hyprctl clients; partial names match")
                    : ""
            inputText: key !== "" ? String(root.requirement[key] ?? "") : ""
            textField.onEditingFinished: if (key !== "") root.set(key, textField.text.trim())
        }
    }
}
