pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.health.components

/**
 * System: the chores an update leaves behind and the platform underneath, as a checklist.
 *
 * Each card's badge is a Material shape that morphs into its relative when the card
 * needs you, and back when the chore is done — the state is the shape, not a spinner or
 * a tick. Platform security is the one card with a meter: fwupd's four HSI levels.
 */
Item {
    id: root

    property double now: Date.now()
    property bool compact: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null
    property HealthAssistant assistant: null

    readonly property var sys: HealthService.system
    readonly property var fw: root.sys?.fwupd ?? null
    readonly property var firmware: HealthService.findingsOfKind("firmware")
    readonly property int columns: Math.max(1, Math.floor((root.layoutWidth + ClockStyle.paneGap) / (HealthStyle.systemCardMinWidth + ClockStyle.paneGap)))
    readonly property real cardWidth: Math.floor((root.width - ClockStyle.paneGap * (root.columns - 1)) / root.columns)

    readonly property var lastBoot: HealthService.boots.length > 0 ? HealthService.boots[HealthService.boots.length - 1] : null

    readonly property var cards: {
        const S = MaterialShape.Shape;
        const out = [];
        // Packages built here that an update broke; Quickshell among them can keep
        // the shell from starting, so this comes first.
        const rebuild = HealthService.finding("rebuild");
        if (HealthService.packageManager === "pacman") {
            out.push({
                symbol: "construction", shape: S.Cookie12Sided, attention: !!rebuild, finding: rebuild?.id ?? "",
                title: rebuild ? HealthText.title(rebuild) : Translation.tr("No package needs a rebuild"),
                body: [rebuild ? Array.from(rebuild.data?.packages ?? []).map(p => `${p.name}: ${HealthText.rebuildReason(p)}`).join("\n")
                    : Translation.tr("Programs built on this computer still find their libraries, and Quickshell matches Qt."),
                    HealthService.rebuildScanText()].filter(s => s.length > 0).join("\n\n")
            });
        }
        // The shell itself: its settings file, its helpers, its memory and errors.
        const config = HealthService.finding("config");
        const helpers = HealthService.findingsOfKind("shellHelper");
        const memory = HealthService.finding("shellMemory");
        const errors = HealthService.finding("shellErrors");
        const shellIssue = (config?.sev === "critical" ? config : null) ?? helpers[0] ?? memory ?? errors ?? null;
        const rss = Number(HealthService.vitals?.shellRss ?? 0);
        const watchingLog = Config.options?.health?.sources?.shellLog === true;
        out.push({
            symbol: "deployed_code", shape: S.Cookie9Sided, attention: !!shellIssue, finding: shellIssue?.id ?? "",
            title: shellIssue ? HealthText.title(shellIssue)
                : helpers.length > 1 ? HealthText.plural(helpers.length, Translation.tr("%1 helper out of date"), Translation.tr("%1 helpers out of date"))
                : Translation.tr("The shell is in shape"),
            body: [
                rss > 0 ? Translation.tr("Using %1 of memory.").arg(HealthText.bytes(rss)) : "",
                helpers.length > 0 ? Translation.tr("Out of date: %1.").arg(helpers.map(h => h.data?.name).join(", ")) : Translation.tr("Its helpers match their sources."),
                errors ? HealthText.detail(errors, root.now)
                    : watchingLog ? Translation.tr("No QML errors in the last hour.") : Translation.tr("QML errors are not watched (Settings).")
            ].filter(s => s.length > 0).join(" ")
        });
        // How long the last boot took, phase by phase, and what slowed it.
        const slow = HealthService.finding("slowBoot");
        const b = root.lastBoot;
        if (b) {
            const top = Array.from(b.top ?? []).slice(0, 3);
            out.push({
                symbol: "timer", shape: S.Puffy, attention: !!slow, finding: slow?.id ?? "",
                title: Translation.tr("Started in %1").arg(HealthText.seconds(b.total)),
                body: (slow ? HealthText.detail(slow, root.now) + ". " : "")
                    + (top.length > 0 ? Translation.tr("Slowest: %1.").arg(top.map(u => `${u.unit} ${HealthText.seconds(u.ms)}`).join(", ")) : ""),
                phases: [
                    { label: Translation.tr("Firmware"), ms: Number(b.firmware ?? 0) },
                    { label: Translation.tr("Loader"), ms: Number(b.loader ?? 0) },
                    { label: Translation.tr("Kernel"), ms: Number(b.kernel ?? 0) },
                    { label: Translation.tr("Initrd"), ms: Number(b.initrd ?? 0) },
                    { label: Translation.tr("System"), ms: Number(b.userspace ?? 0) },
                    { label: Translation.tr("Session"), ms: Number(b.user ?? 0) }
                ].filter(p => p.ms > 0)
            });
        }
        const k = root.sys?.kernel;
        const reboot = HealthService.finding("reboot:kernel");
        out.push({
            symbol: "restart_alt", shape: S.Sunny, attention: !!reboot, finding: reboot?.id ?? "",
            title: reboot ? Translation.tr("Restart to finish the update") : Translation.tr("No restart needed"),
            body: reboot ? Translation.tr("The running kernel %1 lost its modules in the update. New hardware may not work until you restart.").arg(k?.running ?? "")
                : Translation.tr("The running kernel %1 still has its modules on disk.").arg(k?.running ?? "—")
        });
        out.push({
            symbol: "memory", shape: S.Cookie9Sided, attention: root.firmware.length > 0, finding: root.firmware[0]?.id ?? "",
            title: root.fw?.available === false ? Translation.tr("Firmware updates need fwupd")
                : root.firmware.length > 0 ? HealthText.plural(root.firmware.length, Translation.tr("%1 firmware update"), Translation.tr("%1 firmware updates"))
                : Translation.tr("Firmware up to date"),
            body: root.fw?.available === false ? Translation.tr("Install fwupd to get BIOS and device firmware from the vendors.")
                : root.firmware.length > 0 ? root.firmware.map(f => f.data?.name ?? "").join(", ")
                : Translation.tr("fwupd reports no pending upgrades.")
        });
        const hsiLevel = Number(root.fw?.hsiLevel ?? 0);
        const security = HealthService.finding("security:hsi");
        out.push({
            symbol: "shield", shape: S.Clover4Leaf, attention: !!security, finding: security?.id ?? "", meter: root.fw?.available !== false,
            title: root.fw?.available === false ? Translation.tr("Platform security unknown") : Translation.tr("Platform security: level %1").arg(hsiLevel),
            body: root.fw?.runtimeIssue ? Translation.tr("fwupd flags a runtime issue. Open for the checks that fail.")
                : hsiLevel >= 2 ? Translation.tr("The firmware protections fwupd checks are in place.")
                : Translation.tr("Some firmware protections are off. Most are BIOS settings.")
        });
        const pacnew = HealthService.finding("pacnew");
        out.push({
            symbol: "description", shape: S.Cookie7Sided, attention: !!pacnew, finding: pacnew?.id ?? "",
            title: pacnew ? HealthText.title(pacnew) : (HealthService.packageManager === "dnf" ? Translation.tr("No .rpmnew files") : Translation.tr("No .pacnew files")),
            body: pacnew ? Translation.tr("The packages ship new versions of config files you changed. Merge them so updates keep working.")
                : Translation.tr("Config files match what the packages ship.")
        });
        const time = HealthService.finding("timesync");
        out.push({
            symbol: "schedule", shape: S.Puffy, attention: !!time, finding: time?.id ?? "",
            title: time ? Translation.tr("Clock not synchronised") : Translation.tr("Clock synchronised"),
            body: time ? Translation.tr("Logins, TLS and two-factor codes can fail with a wrong clock.") : Translation.tr("Network time keeps it right.")
        });
        const libs = HealthService.finding("deletedLibs");
        out.push({
            symbol: "sync_problem", shape: S.SoftBurst, attention: !!libs, finding: libs?.id ?? "",
            title: libs ? HealthText.title(libs) : Translation.tr("Every program runs current code"),
            body: libs ? Translation.tr("Updated libraries load only when these restart: %1.").arg(HealthText.detail(libs, root.now))
                : Translation.tr("No program still uses a library an update replaced.")
        });
        const last = Number(root.sys?.packages?.lastUpgrade ?? 0);
        if (last > 0) {
            const days = Math.floor((root.now - last) / 86400000);
            out.push({
                symbol: "system_update_alt", shape: S.Cookie12Sided, attention: days >= 30, finding: "",
                title: days === 0 ? Translation.tr("Updated today") : Translation.tr("Last update %1 ago").arg(HealthText.age(last, root.now)),
                body: days >= 30 ? Translation.tr("A month without updates leaves security fixes waiting.") : Translation.tr("Packages are recent.")
            });
        }
        return out;
    }

    readonly property int attentionCards: root.cards.filter(c => c.attention).length
    readonly property string pageSubtitle: root.attentionCards === 0 ? Translation.tr("Nothing to do")
        : HealthText.plural(root.attentionCards, Translation.tr("%1 thing to review"), Translation.tr("%1 things to review"))

    function showFinding(id): void {
        root.panels?.show(findingSheet, { findingId: id, assistant: root.assistant });
    }

    readonly property string openId: root.panels?.open ? String(root.panels.current?.findingId ?? "") : ""

    /// A card's click: the open card's second click closes its sheet.
    function toggle(id): void {
        if (root.openId === id)
            root.panels.close();
        else
            root.showFinding(id);
    }

    Component {
        id: findingSheet
        FindingSheet {}
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: flow.implicitHeight + ClockStyle.gapHuge * 2
        clip: true

        Flow {
            id: flow
            width: Math.max(flick.width, root.layoutWidth)
            spacing: ClockStyle.paneGap

            move: Transition {
                enabled: !ClockStyle.reducedMotion
                NumberAnimation {
                    properties: "x,y"
                    duration: ClockStyle.motionDefault.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                }
            }

            Repeater {
                // Rebuilt every vitals tick (the Shell card reads the shell's memory):
                // matched by symbol, so cards update in place instead of re-entering.
                model: ScriptModel {
                    values: root.cards
                    objectProp: "symbol"
                }

                CheckCard {
                    required property var modelData
                    required property int index
                    width: root.cardWidth
                    card: modelData
                    entranceIndex: index
                }
            }
        }
    }

    component CheckCard: Rectangle {
        id: cc

        property var card: null
        property int entranceIndex: 0
        readonly property bool attention: cc.card?.attention === true
        readonly property bool clickable: String(cc.card?.finding ?? "").length > 0

        implicitHeight: Math.max(160, ccColumn.implicitHeight + ClockStyle.cardPadding * 2)
        radius: ClockStyle.radiusLarge
        color: ccMouse.containsMouse && cc.clickable ? ClockStyle.colIdleCardHover : ClockStyle.colPane

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        StaggeredEntrance {
            index: cc.entranceIndex
            active: !ClockStyle.reducedMotion
        }

        MouseArea {
            id: ccMouse
            anchors.fill: parent
            hoverEnabled: cc.clickable
            enabled: cc.clickable
            cursorShape: cc.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.toggle(cc.card.finding)
        }

        ColumnLayout {
            id: ccColumn
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
                    text: cc.card?.symbol ?? "info"
                    iconSize: 20
                    padding: 10
                    shape: cc.attention ? ClockStyle.morphOf(cc.card?.shape) : cc.card?.shape
                    color: cc.attention ? ClockStyle.colTertiaryContainer : ClockStyle.colPrimaryContainer
                    colSymbol: cc.attention ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnPrimaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: cc.card?.title ?? ""
                    wrapMode: Text.Wrap
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: ClockStyle.colOnSurface
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: cc.card?.body ?? ""
                wrapMode: Text.Wrap
                font.pixelSize: ClockStyle.textSmall + 1
                color: ClockStyle.colSubtext
            }

            // A boot's phases as one bar, each as wide as it took, named under it.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapSmall
                visible: (cc.card?.phases ?? []).length > 0
                spacing: 6

                readonly property var phases: cc.card?.phases ?? []
                readonly property real total: Math.max(1, phases.reduce((n, p) => n + p.ms, 0))

                Row {
                    id: phaseBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    spacing: 2

                    Repeater {
                        model: parent.parent.phases
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property int n: phaseBar.parent.phases.length
                            width: Math.max(4, (phaseBar.width - 2 * (n - 1)) * modelData.ms / phaseBar.parent.total)
                            height: 14
                            topLeftRadius: index === 0 ? 7 : 2
                            bottomLeftRadius: index === 0 ? 7 : 2
                            topRightRadius: index === n - 1 ? 7 : 2
                            bottomRightRadius: index === n - 1 ? 7 : 2
                            color: Qt.rgba(ClockStyle.colPrimary.r, ClockStyle.colPrimary.g, ClockStyle.colPrimary.b, 1 - index * 0.14)
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap
                    Repeater {
                        model: parent.parent.phases
                        StyledText {
                            required property var modelData
                            text: `${modelData.label} ${HealthText.seconds(modelData.ms)}`
                            font.pixelSize: ClockStyle.textSmall
                            font.features: { "tnum": 1 }
                            color: ClockStyle.colSubtext
                        }
                    }
                }
            }

            // fwupd's four HSI levels, the reached ones filled.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapSmall
                visible: cc.card?.meter === true
                spacing: 4

                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        readonly property bool reached: index < Number(root.fw?.hsiLevel ?? 0)
                        Layout.fillWidth: true
                        implicitHeight: 30
                        topLeftRadius: index === 0 ? 15 : 6
                        bottomLeftRadius: index === 0 ? 15 : 6
                        topRightRadius: index === 3 ? 15 : 6
                        bottomRightRadius: index === 3 ? 15 : 6
                        color: reached ? ClockStyle.colTertiary : ClockStyle.colRailRow

                        StyledText {
                            anchors.centerIn: parent
                            text: String(index + 1)
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Black
                            color: parent.reached ? ClockStyle.colOnTertiary : ClockStyle.colSubtext
                        }
                    }
                }
            }
        }
    }
}
