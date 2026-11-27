pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.vitals.components

/**
 * Every ii Vitals option in one place: the link and its sources as the phone reports
 * them, what the PC keeps, the profile it was given, and which other parts of the shell
 * may read the data. Writes go straight to Config or VitalsService.
 */
VitalsPage {
    id: root

    /// Two columns of sections once the page can hold them.
    readonly property bool wide: !root.compact && root.layoutWidth >= 1000
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property real contentWidth: Math.min(root.layoutWidth - root.padding * 2,
        root.wide ? 1240 : ClockStyle.sheetMaxWidth * 1.3)
    property bool confirmDelete: false

    readonly property var meta: VitalsService.meta
    readonly property var sources: root.meta?.sources ?? null
    readonly property var profile: root.meta?.profile ?? ({})
    readonly property var dates: VitalsService.dates
    readonly property int age: {
        VitalsService.meta;
        return VitalsService.age();
    }

    readonly property var stepsChoices: [
        { value: "auto", label: Translation.tr("Automatic") },
        { value: "health", label: Translation.tr("Health Connect") },
        { value: "phone", label: Translation.tr("Phone counter") }
    ]
    readonly property var retentionChoices: [
        { value: 0, label: Translation.tr("Forever") },
        { value: 365, label: Translation.tr("1 year") },
        { value: 90, label: Translation.tr("90 days") }
    ]

    readonly property var samsungText: ({
        on: Translation.tr("Reading. Each type it has comes from here first"),
        devModeOff: Translation.tr("Developer mode is off in Samsung Health, so Health Connect is used"),
        noPermission: Translation.tr("ii tools has no permission to read it"),
        notInstalled: Translation.tr("Not installed on the phone"),
        notBuiltIn: Translation.tr("This ii tools build has no Samsung reader"),
        error: Translation.tr("Could not be read; Health Connect is used")
    })
    readonly property var healthConnectText: ({
        granted: Translation.tr("Reading, with every permission"),
        partial: Translation.tr("Some permissions are missing; ii tools → Vitals lists them"),
        denied: Translation.tr("No permission; allow it in ii tools → Vitals"),
        unavailable: Translation.tr("Not available on the phone")
    })

    function linkText(): string {
        switch (VitalsService.state) {
        case "off": return Translation.tr("Off. The copy on this PC stays until you delete it");
        case "notPaired": return Translation.tr("No phone is paired with this PC");
        case "offline": return Translation.tr("The phone is not connected. The copy on this PC stays");
        case "noFeature": return Translation.tr("Sharing is off on the phone: ii tools → Vitals → Share with the PC");
        }
        if (!VitalsService.linked)
            return Translation.tr("The phone is away. The copy on this PC stays");
        return Translation.tr("Connected; new data comes over about every 10 minutes");
    }

    function dayDate(date: string): string {
        return Qt.locale().toString(new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10))), "d MMM yyyy");
    }

    component Toggle: StyledSwitch {
        checkable: false
    }

    component StatusBadge: MaterialShapeWrappedMaterialSymbol {
        property bool ok: false
        text: ok ? "check" : "remove"
        iconSize: 18
        padding: 8
        shape: MaterialShape.Shape.Cookie7Sided
        color: ok ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
        colSymbol: ok ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
        fill: 1
    }

    component Value: StyledText {
        font.pixelSize: ClockStyle.textNormal + 1
        font.weight: Font.DemiBold
        color: ClockStyle.colOnSurface
    }

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + ClockStyle.gapHuge * 3

        GridLayout {
            id: column
            x: (flick.width - width) / 2
            y: ClockStyle.gapSmall
            width: root.contentWidth
            columns: root.wide ? 2 : 1
            columnSpacing: ClockStyle.gapHuge
            rowSpacing: ClockStyle.gapHuge
            uniformCellWidths: true

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: ClockStyle.gapHuge

                // ── Sync ────────────────────────────────────────────────────
                ClockSettingsSection {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Sync")
                    symbol: "sync"

                    ClockSettingsRow {
                        first: true
                        symbol: "phonelink"
                        title: Translation.tr("Get health data from the phone")
                        description: root.linkText()
                        clickable: true
                        onClicked: Config.options.iiTools.vitals.enable = !VitalsService.enabled
                        Toggle {
                            checked: VitalsService.enabled
                            onClicked: Config.options.iiTools.vitals.enable = !VitalsService.enabled
                        }
                    }
                    ClockSettingsRow {
                        symbol: "history"
                        title: Translation.tr("Last sync")
                        description: VitalsService.syncing
                            ? (VitalsService.progress > 0 ? Translation.tr("Syncing… %1 %").arg(Math.round(VitalsService.progress * 100)) : Translation.tr("Syncing…"))
                            : VitalsService.lastSync > 0
                                ? Translation.tr("%1, at %2").arg(VitalsFormat.ago(VitalsService.lastSync, root.now)).arg(VitalsFormat.asOf(VitalsService.lastSync, null, root.now))
                                : Translation.tr("Never")
                        ClockButton {
                            enabled: VitalsService.linked && !VitalsService.syncing
                            variant: "tonal"
                            symbol: "sync"
                            label: Translation.tr("Sync now")
                            onClicked: VitalsService.syncNow()
                        }
                    }
                    ClockSettingsRow {
                        last: true
                        symbol: "keyboard"
                        title: Translation.tr("Keybind")
                        description: Translation.tr("Super+H opens and closes this app")
                    }
                }


                // ── On this PC ──────────────────────────────────────────────
                ClockSettingsSection {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("On this PC")
                    symbol: "hard_drive"

                    ClockSettingsRow {
                        first: true
                        symbol: "directions_walk"
                        title: Translation.tr("Steps from")
                        description: Translation.tr("Automatic takes Samsung Health when it counts steps, else the app Health Connect ranks first. Changing it fetches every day again")
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: stepsFlow.implicitHeight + ClockStyle.gapLarge * 2
                        color: ClockStyle.colPane
                        radius: ClockStyle.radiusSmall / 2

                        Flow {
                            id: stepsFlow
                            anchors {
                                fill: parent
                                margins: ClockStyle.gapLarge
                                leftMargin: ClockStyle.cardPadding
                            }
                            spacing: ClockStyle.gapSmall

                            Repeater {
                                model: root.stepsChoices

                                ClockFormChip {
                                    required property var modelData
                                    label: modelData.label
                                    selected: VitalsService.stepsFrom === modelData.value
                                    onTriggered: VitalsService.setStepsFrom(modelData.value)
                                }
                            }
                        }
                    }
                    ClockSettingsRow {
                        symbol: "auto_delete"
                        title: Translation.tr("Keep")
                        description: root.dates.length > 0
                            ? Translation.tr("%1 days, from %2").arg(root.dates.length).arg(root.dayDate(root.dates[0]))
                            : Translation.tr("Nothing kept yet")

                        Repeater {
                            model: root.retentionChoices

                            ClockChip {
                                required property var modelData
                                label: modelData.label
                                selected: VitalsService.retentionDays === modelData.value
                                onClicked: VitalsService.setRetention(modelData.value)
                            }
                        }
                    }
                    // Deleting is confirmed in place rather than in a dialog over the app.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: deleteColumn.implicitHeight + ClockStyle.gapLarge * 2
                        color: root.confirmDelete ? ClockStyle.colErrorContainer : ClockStyle.colPane
                        topLeftRadius: ClockStyle.radiusSmall / 2
                        topRightRadius: ClockStyle.radiusSmall / 2
                        bottomLeftRadius: ClockStyle.radiusLarge
                        bottomRightRadius: ClockStyle.radiusLarge

                        Behavior on color {
                            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                        }

                        ColumnLayout {
                            id: deleteColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: ClockStyle.gapLarge
                                leftMargin: ClockStyle.cardPadding
                            }
                            spacing: ClockStyle.gap

                            StyledText {
                                Layout.fillWidth: true
                                text: root.confirmDelete
                                    ? Translation.tr("Every day kept here is removed. The phone keeps its own data and sends it all again at the next sync.")
                                    : Translation.tr("The phone's data stays on the phone.")
                                wrapMode: Text.WordWrap
                                font.pixelSize: ClockStyle.textNormal
                                color: root.confirmDelete ? ClockStyle.colOnErrorContainer : ClockStyle.colSubtext
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: ClockStyle.gapSmall

                                ClockButton {
                                    visible: !root.confirmDelete
                                    enabled: root.dates.length > 0
                                    variant: "text"
                                    danger: true
                                    symbol: "delete"
                                    label: Translation.tr("Delete the copy on this PC")
                                    onClicked: root.confirmDelete = true
                                }
                                ClockButton {
                                    visible: root.confirmDelete
                                    variant: "text"
                                    label: Translation.tr("Cancel")
                                    onClicked: root.confirmDelete = false
                                }
                                ClockButton {
                                    visible: root.confirmDelete
                                    variant: "filled"
                                    danger: true
                                    symbol: "delete"
                                    label: Translation.tr("Delete")
                                    onClicked: {
                                        VitalsService.deleteLocalCopy();
                                        root.confirmDelete = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: ClockStyle.gapHuge

                // ── Sources ─────────────────────────────────────────────────
                ClockSettingsSection {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Sources")
                    symbol: "devices"

                    ClockSettingsRow {
                        first: true
                        visible: root.sources === null
                        symbol: "help"
                        title: Translation.tr("Not reported yet")
                        description: Translation.tr("The phone says where its data comes from at the first sync")
                    }
                    ClockSettingsRow {
                        first: true
                        visible: root.sources !== null
                        symbol: "watch"
                        title: Translation.tr("Samsung Health")
                        description: root.samsungText[root.sources?.samsung] ?? String(root.sources?.samsung ?? "")
                        StatusBadge {
                            ok: root.sources?.samsung === "on"
                        }
                    }
                    ClockSettingsRow {
                        visible: root.sources !== null
                        symbol: "health_and_safety"
                        title: Translation.tr("Health Connect")
                        description: root.healthConnectText[root.sources?.healthConnect] ?? String(root.sources?.healthConnect ?? "")
                        StatusBadge {
                            ok: root.sources?.healthConnect === "granted" || root.sources?.healthConnect === "partial"
                        }
                    }
                    ClockSettingsRow {
                        id: devicesRow
                        visible: root.sources !== null && (root.meta?.devices ?? []).length > 0
                        symbol: "devices_wearables"
                        title: Translation.tr("Devices")
                        description: (root.meta?.devices ?? []).map(d => String(d.name ?? "")).filter(n => n.length > 0).join(" · ")
                    }
                    ClockSettingsRow {
                        last: true
                        symbol: "menu_book"
                        title: Translation.tr("Watch & band sync guide")
                        description: Translation.tr("Health Connect setup, Health Sync fallback, and steps for Huawei, Xiaomi, Amazfit, Honor, OnePlus and Garmin")
                        clickable: true
                        onClicked: root.panels?.show(syncGuideSheet, {})
                        ClockButton {
                            variant: "tonal"
                            symbol: "menu_book"
                            label: Translation.tr("Open guide")
                            onClicked: root.panels?.show(syncGuideSheet, {})
                        }
                    }
                }


                // ── Profile ─────────────────────────────────────────────────
                ClockSettingsSection {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Profile")
                    symbol: "person"

                    ClockSettingsRow {
                        first: true
                        last: !sexRow.visible && !heightRow.visible
                        symbol: "cake"
                        title: Translation.tr("Age")
                        description: root.age >= 0
                            ? Translation.tr("From the phone's profile; sets the heart-rate zones")
                            : Translation.tr("The phone has not shared a birth date, so workouts have no heart-rate zones")
                        Value {
                            visible: root.age >= 0
                            text: String(root.age)
                        }
                    }
                    ClockSettingsRow {
                        id: sexRow
                        last: !heightRow.visible
                        visible: typeof root.profile.sex === "string"
                        symbol: "wc"
                        title: Translation.tr("Sex")
                        Value {
                            text: root.profile.sex === "male" ? Translation.tr("Male")
                                : root.profile.sex === "female" ? Translation.tr("Female")
                                : Translation.tr("Other")
                        }
                    }
                    ClockSettingsRow {
                        id: heightRow
                        last: true
                        visible: typeof root.profile.heightCm === "number"
                        symbol: "height"
                        title: Translation.tr("Height")
                        Value {
                            text: Translation.tr("%1 cm").arg(Math.round(root.profile.heightCm ?? 0))
                        }
                    }
                }


                // ── Elsewhere in the shell ──────────────────────────────────
                ClockSettingsSection {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Integrations")
                    symbol: "extension"

                    ClockSettingsRow {
                        first: true
                        symbol: "bedtime"
                        title: Translation.tr("Bedtime uses the watch's sleep")
                        description: Translation.tr("The Clock's Bedtime shows the nights the watch recorded, before its estimate from screen use")
                        clickable: true
                        onClicked: Config.options.vitals.bedtime.enable = !Config.options.vitals.bedtime.enable
                        Toggle {
                            checked: Config.options.vitals.bedtime.enable
                            onClicked: Config.options.vitals.bedtime.enable = !Config.options.vitals.bedtime.enable
                        }
                    }
                    ClockSettingsRow {
                        last: true
                        symbol: "neurology"
                        title: Translation.tr("Let the assistant read it")
                        description: Translation.tr("The assistant can then answer questions about your steps, sleep and heart. Those answers leave this PC for your AI provider")
                        clickable: true
                        onClicked: Config.options.vitals.assistant.enable = !Config.options.vitals.assistant.enable
                        Toggle {
                            checked: Config.options.vitals.assistant.enable
                            onClicked: Config.options.vitals.assistant.enable = !Config.options.vitals.assistant.enable
                        }
                    }
                }
            }
        }
    }

    Component {
        id: syncGuideSheet
        VitalsSyncGuideSheet {}
    }
}
