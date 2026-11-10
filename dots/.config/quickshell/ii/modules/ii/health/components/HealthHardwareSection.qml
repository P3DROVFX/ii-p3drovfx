pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The Hardware page's own cards, under the filesystems and drives: the battery's
 * wear, peripherals' charge, the processor, each GPU, memory, fans, and the
 * kernel's hardware complaints this boot. One big number per card, its facts,
 * and its 30-day trend from the helper's daily rows. A part the machine does not
 * have is left out rather than shown empty; a card with a finding behind it is
 * tinted and opens that finding.
 */
ColumnLayout {
    id: root

    /// Opens a finding's sheet (the page's own toggle).
    property var openFinding: null
    property real layoutWidth: width

    readonly property var hw: HealthService.hardware
    readonly property var events: root.hw?.events?.counts ?? ({})
    readonly property var details: root.hw?.events?.details ?? ({})
    /// Wider than the System page's cards: these carry a row of facts each.
    readonly property int cardMinWidth: 320
    readonly property int columns: Math.max(1, Math.floor((root.layoutWidth + ClockStyle.paneGap) / (root.cardMinWidth + ClockStyle.paneGap)))
    readonly property real cardWidth: Math.floor((root.width - ClockStyle.paneGap * (root.columns - 1)) / root.columns)

    function count(kind): int {
        return Number(root.events[kind] ?? 0);
    }
    function detailText(kind): string {
        return Object.entries(root.details[kind] ?? {}).map(([k, n]) => n > 1 ? `${k} ×${n}` : k).join(", ");
    }

    readonly property var cards: {
        const S = MaterialShape.Shape;
        const out = [];
        const hw = root.hw;
        if (!hw)
            return out;
        for (const b of Array.from(hw.batteries ?? [])) {
            const f = HealthService.finding(`battery:${b.name}`);
            const h = Number(b.healthPct ?? NaN);
            out.push({
                key: `battery:${b.name}`, symbol: "battery_horiz_075", shape: S.Cookie9Sided, finding: f?.id ?? "", attention: !!f,
                title: Translation.tr("Battery"),
                big: isNaN(h) ? "—" : `${Math.round(Math.min(100, h))}`, unit: isNaN(h) ? "" : Translation.tr("% of its design capacity"),
                note: h > 100 ? Translation.tr("Reads %1 %, above its design: normal for a newer pack.").arg(h.toFixed(1))
                    : f ? HealthText.detail(f, Date.now()) : "",
                facts: [
                    [Translation.tr("Charge cycles"), b.cycles ? String(Math.round(b.cycles)) : "—"],
                    [Translation.tr("Now"), b.capacity !== null && b.capacity !== undefined ? `${Math.round(b.capacity)} % · ${b.status ?? ""}` : "—"],
                    [Translation.tr("Model"), [b.manufacturer, b.model].filter(s => s).join(" ") || "—"]
                ],
                trend: HealthService.historySeries("batteryHealthPct", true), trendBars: false
            });
        }
        const peripherals = Array.from(hw.peripherals ?? []);
        if (peripherals.length > 0) {
            const low = peripherals.map(p => HealthService.finding(`peripheral:${p.name}`)).find(f => f) ?? null;
            out.push({
                key: "peripherals", symbol: "mouse", shape: S.Clover4Leaf, finding: low?.id ?? "", attention: !!low,
                title: HealthText.plural(peripherals.length, Translation.tr("%1 wireless device"), Translation.tr("%1 wireless devices")),
                big: "", unit: "",
                facts: peripherals.map(p => [p.model || p.name, p.capacity !== null && p.capacity !== undefined ? `${Math.round(p.capacity)} %` : "—"])
            });
        }
        const cpu = hw.cpu ?? {};
        const mce = HealthService.finding("mce");
        const overheat = HealthService.finding("overheat");
        out.push({
            key: "cpu", symbol: "memory", shape: S.Sunny, finding: (mce ?? overheat)?.id ?? "", attention: !!(mce || overheat),
            title: Translation.tr("Processor"),
            big: cpu.tempC !== null && cpu.tempC !== undefined ? `${Math.round(cpu.tempC)}` : "—", unit: "°C",
            note: mce ? HealthText.title(mce) : overheat ? HealthText.title(overheat) : "",
            facts: [
                [Translation.tr("Machine-check errors"), String(root.count("mce"))],
                [Translation.tr("Throttled since boot"), Translation.tr("%1 times").arg(cpu.throttleTotal ?? 0)]
            ],
            trend: HealthService.historySeries("cpuTempPeak", true), trendBars: false, trendLabel: Translation.tr("Daily peak")
        });
        const resets = HealthService.finding("gpu:resets");
        for (const g of Array.from(hw.gpus ?? [])) {
            out.push({
                key: `gpu:${g.card}`, symbol: "developer_board", shape: S.Cookie12Sided, finding: resets?.id ?? "", attention: !!resets,
                title: g.model || [g.vendor, Translation.tr("graphics")].join(" "),
                big: String(root.count("gpu")), unit: Translation.tr("resets this boot"),
                note: resets ? HealthText.detail(resets, Date.now()) : "",
                facts: [
                    [Translation.tr("Driver"), g.driver ?? "—"],
                    g.tempC !== null && g.tempC !== undefined ? [Translation.tr("Temperature"), `${Math.round(g.tempC)} °C`] : null,
                    g.busyPct !== null && g.busyPct !== undefined ? [Translation.tr("Busy"), `${Math.round(g.busyPct)} %`] : null
                ].filter(r => r),
                trend: HealthService.historySeries("gpuResets", false), trendBars: true
            });
        }
        const mem = hw.memory ?? {};
        const oom = HealthService.finding("oom");
        const edac = HealthService.finding("edac");
        const swapUsed = Number(mem.swapTotal ?? 0) - Number(mem.swapFree ?? 0);
        out.push({
            key: "memory", symbol: "memory_alt", shape: S.Puffy, finding: (edac?.sev === "critical" ? edac : oom ?? edac)?.id ?? "", attention: !!(oom || edac?.sev === "critical"),
            title: Translation.tr("Memory"),
            big: String(root.count("oom")), unit: Translation.tr("programs killed for memory this boot"),
            note: oom ? root.detailText("oom") : "",
            facts: [
                [mem.zram ? Translation.tr("Compressed swap (zram)") : Translation.tr("Swap"),
                    Number(mem.swapTotal ?? 0) > 0 ? Translation.tr("%1 of %2").arg(HealthText.bytes(swapUsed)).arg(HealthText.bytes(mem.swapTotal)) : Translation.tr("None")],
                [Translation.tr("Error correction"), mem.edac ? Translation.tr("%1 corrected, %2 not").arg(mem.edac.ce).arg(mem.edac.ue) : Translation.tr("Not available (no ECC)")]
            ],
            trend: HealthService.historySeries("oomKills", false), trendBars: true
        });
        const fans = Array.from(hw.fans ?? []);
        if (fans.length > 0) {
            const stopped = HealthService.finding("fan:stopped");
            out.push({
                key: "fans", symbol: "mode_fan", shape: S.Cookie7Sided, finding: stopped?.id ?? "", attention: !!stopped,
                title: Translation.tr("Fans"), big: "", unit: "",
                note: stopped ? HealthText.title(stopped) : "",
                facts: fans.map(f => [f.label, Translation.tr("%1 RPM").arg(Math.round(f.rpm))])
            });
        }
        const radios = HealthService.findingsOfKind("radioFw");
        const usb = HealthService.findingsOfKind("usb");
        const pcie = HealthService.findingsOfKind("aer");
        const worst = pcie.find(f => f.sev === "critical") ?? radios[0] ?? usb[0] ?? pcie[0] ?? null;
        out.push({
            key: "buses", symbol: "cable", shape: S.SoftBurst, finding: worst?.id ?? "", attention: !!worst && worst.sev !== "info",
            title: Translation.tr("Devices and buses"), big: "", unit: "",
            note: worst ? HealthText.title(worst) : Translation.tr("No firmware crashes or bus errors this boot."),
            facts: [
                [Translation.tr("Wi-Fi and Bluetooth firmware crashes"), String(root.count("radioFw"))],
                [Translation.tr("USB errors"), root.count("usb") > 0 ? `${root.count("usb")} (${root.detailText("usb")})` : "0"],
                [Translation.tr("PCIe errors"), Translation.tr("%1 corrected, %2 not").arg(root.count("aer")).arg(root.count("aerFatal"))]
            ]
        });
        return out;
    }

    spacing: ClockStyle.gapSmall
    visible: root.hw !== null && root.cards.length > 0

    StyledText {
        Layout.leftMargin: ClockStyle.gapTiny
        Layout.topMargin: ClockStyle.gapSmall
        text: Translation.tr("The rest of the machine")
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.Black
        font.letterSpacing: 1.0
        font.capitalization: Font.AllUppercase
        color: ClockStyle.colSubtext
    }

    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.paneGap

        Repeater {
            // Rebuilt on every hardware message: matched by key, so cards update in
            // place instead of re-entering.
            model: ScriptModel {
                values: root.cards
                objectProp: "key"
            }

            HwCard {
                required property var modelData
                required property int index
                width: root.cardWidth
                card: modelData
                entranceIndex: index
            }
        }
    }

    component HwCard: Rectangle {
        id: hc

        property var card: null
        property int entranceIndex: 0
        readonly property bool attention: hc.card?.attention === true
        readonly property bool clickable: String(hc.card?.finding ?? "").length > 0

        implicitHeight: hcColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusLarge
        color: hcMouse.containsMouse && hc.clickable ? ClockStyle.colIdleCardHover : ClockStyle.colPane

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        StaggeredEntrance {
            index: hc.entranceIndex
            active: !ClockStyle.reducedMotion
        }

        MouseArea {
            id: hcMouse
            anchors.fill: parent
            hoverEnabled: hc.clickable
            enabled: hc.clickable
            cursorShape: hc.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (typeof root.openFinding === "function")
                    root.openFinding(hc.card.finding);
            }
        }

        ColumnLayout {
            id: hcColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.cardPadding
            }
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                MaterialShapeWrappedMaterialSymbol {
                    text: hc.card?.symbol ?? "info"
                    iconSize: 20
                    padding: 10
                    shape: hc.attention ? ClockStyle.morphOf(hc.card?.shape) : hc.card?.shape
                    color: hc.attention ? ClockStyle.colTertiaryContainer : ClockStyle.colPrimaryContainer
                    colSymbol: hc.attention ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnPrimaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: hc.card?.title ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colOnSurface
                }
            }

            // The one number.
            RowLayout {
                visible: String(hc.card?.big ?? "").length > 0
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: hc.card?.big ?? ""
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ({ "wght": 720, "wdth": 45, "ROND": 100 })
                    font.pixelSize: 40
                    color: hc.attention ? ClockStyle.colTertiary : ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: hc.card?.unit ?? ""
                    wrapMode: Text.Wrap
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: hc.card?.note ?? ""
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textSmall + 1
                color: hc.attention ? ClockStyle.colOnSurface : ClockStyle.colSubtext
            }

            Repeater {
                model: hc.card?.facts ?? []
                RowLayout {
                    id: fact
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    StyledText {
                        Layout.fillWidth: true
                        text: fact.modelData[0]
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }
                    StyledText {
                        Layout.maximumWidth: hc.width * 0.55
                        text: fact.modelData[1]
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: ClockStyle.textSmall
                        font.features: { "tnum": 1 }
                        color: ClockStyle.colOnSurface
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapTiny
                visible: (hc.card?.trend ?? []).some(v => v !== null && v !== undefined && v > 0)
                spacing: 2

                HealthSparkline {
                    Layout.fillWidth: true
                    values: hc.card?.trend ?? []
                    bars: hc.card?.trendBars === true
                    color: hc.attention ? ClockStyle.colTertiary : ClockStyle.colPrimary
                }
                StyledText {
                    text: hc.card?.trendLabel ?? Translation.tr("Last 30 days")
                    font.pixelSize: ClockStyle.textSmall - 1
                    color: ClockStyle.colSubtext
                }
            }
        }
    }
}
