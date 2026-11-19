// PhoneStatsPanel.qml
// The Stats tab of the Phone tab's bottom group: the phone's own load, the reverse of
// the app's PC performance screen. Read from IiLinkService.phonePerf; the phone samples
// only while this panel is on screen (PhoneFooter watches it).

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * A memory hero (the one number, with a graph of the last minute), then storage as a
 * ring, the thermal state as a shape that changes with it, the battery's heat and power,
 * the network's rate, and the cores' clocks as bars where the phone exposes them.
 */
StyledFlickable {
    id: root

    readonly property var sample: IiLinkService.phonePerf
    readonly property bool live: sample !== null && IiLinkService.phonePerfDev !== "" && sample.dev === IiLinkService.phonePerfDev
    readonly property var axesDigits: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var axesDigitsSoft: ({ "wght": 560, "wdth": 30, "ROND": 100 })

    clip: true
    contentHeight: column.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    function gb(bytes): string {
        const v = bytes / 1073741824;
        return v >= 100 ? String(Math.round(v)) : v.toFixed(1);
    }
    function rate(bps): string {
        if (bps >= 1048576)
            return Translation.tr("%1 MB/s").arg((bps / 1048576).toFixed(1));
        if (bps >= 1024)
            return Translation.tr("%1 KB/s").arg(Math.round(bps / 1024));
        return Translation.tr("%1 B/s").arg(Math.round(bps));
    }
    function uptime(ms): string {
        const m = Math.floor(ms / 60000);
        const h = Math.floor(m / 60);
        const d = Math.floor(h / 24);
        if (d > 0)
            return Translation.tr("%1d %2h").arg(d).arg(h % 24);
        if (h > 0)
            return Translation.tr("%1h %2m").arg(h).arg(m % 60);
        return Translation.tr("%1m").arg(m);
    }
    function thermalName(status): string {
        return [Translation.tr("Cool"), Translation.tr("Light"), Translation.tr("Moderate"), Translation.tr("Severe"),
                Translation.tr("Critical"), Translation.tr("Emergency"), Translation.tr("Shutdown")][Math.max(0, Math.min(6, status))];
    }

    readonly property real ramUsed: sample?.ram ? sample.ram.total - sample.ram.avail : 0
    readonly property real ramFraction: sample?.ram ? ramUsed / sample.ram.total : 0
    readonly property int thermalStatus: sample?.thermal?.status ?? 0
    readonly property var cpuFreq: (sample?.cpu?.freq ?? []).filter(f => f > 0)
    /// What the phone adds through Shizuku, or null without it.
    readonly property var shell: sample?.shell ?? null
    readonly property var sensors: {
        const t = shell?.temps ?? {};
        const names = { skin: Translation.tr("Skin"), cpu: Translation.tr("CPU"), gpu: Translation.tr("GPU"),
                        ram: Translation.tr("RAM"), modem: Translation.tr("Modem"), usb: Translation.tr("USB") };
        return ["skin", "cpu", "gpu", "ram", "modem", "usb"].filter(k => typeof t[k] === "number").map(k => ({ label: names[k], value: t[k] }));
    }
    readonly property var storageKinds: {
        const st = shell?.storage;
        if (!st)
            return [];
        const c = Appearance.colors;
        const kinds = [
            { label: Translation.tr("Apps"), bytes: (st.apps ?? 0) + (st.appData ?? 0), color: c.colPrimary },
            { label: Translation.tr("Photos"), bytes: st.photos ?? 0, color: c.colTertiary },
            { label: Translation.tr("Videos"), bytes: st.videos ?? 0, color: c.colSecondary },
            { label: Translation.tr("Audio"), bytes: st.audio ?? 0, color: c.colPrimaryContainer },
            { label: Translation.tr("System"), bytes: st.system ?? 0, color: c.colTertiaryContainer },
            { label: Translation.tr("Other"), bytes: (st.other ?? 0) + (st.downloads ?? 0), color: c.colSecondaryContainer }
        ];
        return kinds.filter(k => k.bytes > 0);
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: 8
        opacity: root.live ? 1 : 0.6
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        // ─── Header: the phone, its Android and uptime ───
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "monitoring"
                iconSize: 20
                padding: 9
                fill: root.live ? 1 : 0
                shape: root.live ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Circle
                color: root.live ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                colSymbol: root.live ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.sample?.name || root.sample?.device?.model || Translation.tr("Phone")
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (root.sample === null)
                            return Translation.tr("Asking the phone…");
                        if (!root.live)
                            return Translation.tr("Offline · last sample at %1").arg(Qt.formatTime(new Date(root.sample.at), "hh:mm"));
                        const parts = [];
                        if (root.sample.device?.android)
                            parts.push(Translation.tr("Android %1").arg(root.sample.device.android));
                        if (root.sample.cpu?.cores)
                            parts.push(Translation.tr("%1 cores").arg(root.sample.cpu.cores));
                        if (root.sample.uptime)
                            parts.push(Translation.tr("up %1").arg(root.uptime(root.sample.uptime)));
                        return parts.join(" · ");
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        // ─── Memory: the hero ───
        Rectangle {
            Layout.fillWidth: true
            visible: root.sample?.ram != null
            implicitHeight: 104
            radius: Appearance.rounding.large
            color: root.sample?.ram?.low ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer
            readonly property color content: root.sample?.ram?.low ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer
            id: memory
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr("MEMORY")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: ColorUtils.applyAlpha(memory.content, 0.8)
                    }
                    RowLayout {
                        spacing: 3
                        StyledText {
                            text: root.gb(root.ramUsed)
                            font.family: Appearance.font.family.main
                            font.pixelSize: 44
                            font.variableAxes: root.axesDigits
                            color: memory.content
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 8
                            text: Translation.tr("/ %1 GB").arg(root.sample?.ram ? root.gb(root.sample.ram.total) : "—")
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.variableAxes: root.axesDigitsSoft
                            color: ColorUtils.applyAlpha(memory.content, 0.8)
                        }
                    }
                    StyledText {
                        text: root.sample?.ram?.low ? Translation.tr("Low memory") : Translation.tr("%1% in use").arg(Math.round(root.ramFraction * 100))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: memory.content
                    }
                }

                // The last minute of memory, newest on the right.
                Graph {
                    Layout.preferredWidth: 112
                    Layout.fillHeight: true
                    values: IiLinkService.phonePerfRam
                    points: 30
                    alignment: Graph.Alignment.Right
                    color: memory.content
                    fillOpacity: 0.18
                }
            }
        }

        // ─── Storage · Thermal · Battery · Network ───
        GridLayout {
            Layout.fillWidth: true
            visible: root.sample !== null
            columns: 2
            columnSpacing: 6
            rowSpacing: 6

            // Storage: the ring is the value.
            StatTile {
                caption: Translation.tr("Storage")
                value: root.sample?.storage ? Translation.tr("%1 GB").arg(root.gb(root.sample.storage.free)) : "—"
                detail: root.sample?.storage ? Translation.tr("free of %1 GB").arg(root.gb(root.sample.storage.total)) : ""
                lead: CircularProgress {
                    implicitSize: 30
                    lineWidth: 4
                    value: root.sample?.storage ? 1 - root.sample.storage.free / root.sample.storage.total : 0
                    colPrimary: Appearance.colors.colPrimary
                    colSecondary: Appearance.colors.colSecondaryContainer
                }
            }

            // Thermal: the shape (and the tile) changes with the state.
            StatTile {
                readonly property bool hot: root.thermalStatus >= 4
                readonly property bool warm: root.thermalStatus >= 2
                tileColor: hot ? Appearance.colors.colErrorContainer : warm ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer4
                contentColor: hot ? Appearance.colors.colOnErrorContainer : warm ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnLayer4
                caption: Translation.tr("Thermal")
                value: root.thermalName(root.thermalStatus)
                detail: root.sample?.thermal?.headroom != null
                    ? Translation.tr("%1% of the throttle point").arg(Math.max(0, Math.round(root.sample.thermal.headroom * 100)))
                    : ""
                lead: MaterialShapeWrappedMaterialSymbol {
                    text: "thermostat"
                    iconSize: 16
                    padding: 7
                    shape: [MaterialShape.Shape.Circle, MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Sunny,
                            MaterialShape.Shape.SoftBurst, MaterialShape.Shape.Burst][Math.min(4, root.thermalStatus)]
                    color: root.thermalStatus >= 4 ? Appearance.colors.colError : root.thermalStatus >= 2 ? Appearance.colors.colTertiary : Appearance.colors.colPrimaryContainer
                    colSymbol: root.thermalStatus >= 4 ? Appearance.colors.colOnError : root.thermalStatus >= 2 ? Appearance.colors.colOnTertiary : Appearance.colors.colOnPrimaryContainer
                }
            }

            // Battery: its heat, and the power going in or out.
            StatTile {
                readonly property var b: root.sample?.battery ?? null
                readonly property real watts: (b?.mv && b?.ma) ? Math.abs(b.mv * b.ma) / 1e6 : -1
                caption: Translation.tr("Battery")
                value: b?.temp != null ? `${b.temp.toFixed(1)}°` : "—"
                detail: [b?.level != null ? `${b.level}%` : "",
                         root.shell?.health != null ? Translation.tr("health %1%").arg(root.shell.health) : "",
                         watts >= 0 ? (b.charging ? Translation.tr("+%1 W").arg(watts.toFixed(1)) : Translation.tr("%1 W").arg(watts.toFixed(1))) : ""]
                    .filter(x => x.length > 0).join(" · ")
                lead: MaterialShapeWrappedMaterialSymbol {
                    text: root.sample?.battery?.charging ? "battery_charging_full" : "battery_full"
                    iconSize: 16
                    padding: 7
                    shape: MaterialShape.Shape.Cookie6Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }
            }

            // Network: down big, up under it.
            StatTile {
                caption: Translation.tr("Network")
                value: root.sample?.net ? "↓ " + root.rate(root.sample.net.rx) : "—"
                detail: root.sample?.net ? "↑ " + root.rate(root.sample.net.tx) : ""
                lead: MaterialShapeWrappedMaterialSymbol {
                    text: "swap_vert"
                    iconSize: 16
                    padding: 7
                    shape: MaterialShape.Shape.Clover4Leaf
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        // ─── CPU: one bar per core (use with Shizuku, else the clock), the GPU last ───
        Rectangle {
            id: cpuCard
            Layout.fillWidth: true
            visible: root.cpuFreq.length > 0 || root.shell?.cpu != null
            implicitHeight: 104
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer4
            readonly property bool byUse: root.shell?.cpu != null
            readonly property int cores: byUse ? root.shell.cpu.cores.length : (root.sample?.cpu?.freq?.length ?? 0)
            readonly property bool hasGpu: root.shell?.gpu != null

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                ColumnLayout {
                    Layout.fillHeight: true
                    spacing: 0
                    StyledText {
                        text: Translation.tr("CPU")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        spacing: 2
                        StyledText {
                            text: cpuCard.byUse
                                ? String(Math.round(root.shell.cpu.usage * 100))
                                : root.cpuFreq.length > 0 ? (root.cpuFreq.reduce((a, f) => a + f, 0) / root.cpuFreq.length / 1000).toFixed(2) : "—"
                            font.family: Appearance.font.family.main
                            font.pixelSize: 32
                            font.variableAxes: root.axesDigits
                            color: Appearance.colors.colOnLayer4
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 5
                            text: cpuCard.byUse ? "%" : Translation.tr("GHz")
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.variableAxes: root.axesDigitsSoft
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledText {
                        text: [cpuCard.byUse && root.cpuFreq.length > 0
                                   ? Translation.tr("%1 GHz").arg((root.cpuFreq.reduce((a, f) => a + f, 0) / root.cpuFreq.length / 1000).toFixed(1))
                                   : cpuCard.byUse ? "" : Translation.tr("average"),
                               cpuCard.hasGpu ? Translation.tr("GPU %1%").arg(Math.round(root.shell.gpu * 100)) : ""]
                            .filter(x => x.length > 0).join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                Row {
                    id: bars
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4
                    // The GPU's bar stands apart, in the second voice.
                    readonly property int count: cpuCard.cores + (cpuCard.hasGpu ? 1 : 0)
                    readonly property real barWidth: Math.max(4, (width - spacing * (count - 1) - (cpuCard.hasGpu ? 6 : 0)) / Math.max(1, count))
                    Repeater {
                        model: bars.count
                        delegate: Rectangle {
                            id: bar
                            required property int index
                            readonly property bool gpu: cpuCard.hasGpu && index === cpuCard.cores
                            readonly property real fraction: gpu ? root.shell.gpu
                                : cpuCard.byUse ? (root.shell.cpu.cores[index] ?? 0)
                                : (root.sample?.cpu?.freq?.[index] ?? 0) / Math.max(1, root.sample?.cpu?.max?.[index] ?? 0, root.sample?.cpu?.freq?.[index] ?? 0)
                            width: bars.barWidth
                            height: bars.height
                            radius: Appearance.rounding.full
                            color: gpu ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSecondaryContainer
                            transform: Translate { x: bar.gpu ? 6 : 0 }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(width, parent.height * Math.max(0, Math.min(1, bar.fraction)))
                                radius: Appearance.rounding.full
                                color: bar.gpu ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
                                Behavior on height {
                                    enabled: !Appearance.reducedMotion
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ─── Sensors: the temperatures only the shell user reads ───
        Rectangle {
            Layout.fillWidth: true
            visible: root.sensors.length > 0
            // Sized by everything inside (caption and both lines), so nothing is cut.
            implicitHeight: sensorColumn.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer

            ColumnLayout {
                id: sensorColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 6
                StyledText {
                    text: Translation.tr("SENSORS")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: ColorUtils.applyAlpha(Appearance.colors.colOnSecondaryContainer, 0.75)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: root.sensors
                        // Equal columns across the card, each centred on its own value.
                        delegate: Item {
                            id: sensor
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: sensorValue.implicitHeight + sensorLabel.implicitHeight
                            StyledText {
                                id: sensorValue
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                text: `${Math.round(sensor.modelData.value)}°`
                                font.family: Appearance.font.family.main
                                font.pixelSize: 24
                                font.variableAxes: root.axesDigits
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                id: sensorLabel
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: sensorValue.bottom
                                width: Math.min(implicitWidth, sensor.width)
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: sensor.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: ColorUtils.applyAlpha(Appearance.colors.colOnSecondaryContainer, 0.8)
                            }
                        }
                    }
                }
            }
        }

        // ─── The busiest apps right now ───
        ColumnLayout {
            Layout.fillWidth: true
            visible: (root.shell?.procs?.length ?? 0) > 0
            spacing: 2

            StyledText {
                Layout.leftMargin: 4
                Layout.bottomMargin: 2
                text: Translation.tr("BUSIEST")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colSubtext
            }
            Repeater {
                model: root.shell?.procs ?? []
                delegate: Rectangle {
                    id: procRow
                    required property var modelData
                    required property int index
                    readonly property int count: root.shell?.procs?.length ?? 0
                    readonly property real outer: Appearance.rounding.normal
                    readonly property real join: Appearance.rounding.verysmall
                    Layout.fillWidth: true
                    implicitHeight: 38
                    // One shape for the group: round outside, small joins inside.
                    topLeftRadius: index === 0 ? outer : join
                    topRightRadius: index === 0 ? outer : join
                    bottomLeftRadius: index === count - 1 ? outer : join
                    bottomRightRadius: index === count - 1 ? outer : join
                    color: Appearance.colors.colLayer4

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: procRow.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer4
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: Translation.tr("%1 MB").arg(Math.round(procRow.modelData.rssKb / 1024))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: `${(procRow.modelData.cpu * 100).toFixed(procRow.modelData.cpu < 0.1 ? 1 : 0)}%`
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.variableAxes: root.axesDigits
                            color: Appearance.colors.colOnLayer4
                        }
                    }
                }
            }
        }

        // ─── Storage by type, as one segmented bar ───
        Rectangle {
            Layout.fillWidth: true
            visible: root.storageKinds.length > 0
            implicitHeight: storageColumn.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer4

            ColumnLayout {
                id: storageColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                StyledText {
                    text: Translation.tr("STORAGE BY TYPE")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colSubtext
                }
                Row {
                    id: segments
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    spacing: 3
                    readonly property real total: root.storageKinds.reduce((a, k) => a + k.bytes, 0)
                    Repeater {
                        model: root.storageKinds
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: Math.max(4, (segments.width - segments.spacing * (root.storageKinds.length - 1)) * modelData.bytes / Math.max(1, segments.total))
                            height: 14
                            radius: Appearance.rounding.full
                            color: modelData.color
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: root.storageKinds
                        delegate: Row {
                            required property var modelData
                            spacing: 4
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.color
                            }
                            StyledText {
                                text: `${modelData.label} ${root.gb(modelData.bytes)}`
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer4
                            }
                        }
                    }
                }
            }
        }
    }

    /** A small stat: a lead (shape or ring), a caption, the value and a line under it. */
    component StatTile: Rectangle {
        id: tile
        property string caption: ""
        property string value: ""
        property string detail: ""
        property color tileColor: Appearance.colors.colLayer4
        property color contentColor: Appearance.colors.colOnLayer4
        default property alias lead: leadSlot.data

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 96
        radius: Appearance.rounding.normal
        color: tile.tileColor
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 2

            RowLayout {
                spacing: 6
                Item {
                    id: leadSlot
                    implicitWidth: childrenRect.width
                    implicitHeight: childrenRect.height
                }
                StyledText {
                    Layout.fillWidth: true
                    text: tile.caption.toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: ColorUtils.applyAlpha(tile.contentColor, 0.75)
                    elide: Text.ElideRight
                }
            }
            Item { Layout.fillHeight: true }
            StyledText {
                Layout.fillWidth: true
                text: tile.value
                font.family: Appearance.font.family.main
                font.pixelSize: 22
                font.variableAxes: root.axesDigits
                color: tile.contentColor
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: tile.detail
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: ColorUtils.applyAlpha(tile.contentColor, 0.8)
                elide: Text.ElideRight
            }
        }
    }
}
