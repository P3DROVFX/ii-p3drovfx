pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Side sheet explaining how to feed wearables and companion apps into Health Connect so
 * ii tools can read them: the Health Connect prerequisite, brand-specific steps (Huawei,
 * Xiaomi, Amazfit/Zepp, Honor, OnePlus/OPPO, Garmin, Samsung), and Health Sync as a
 * bridge when a companion app does not write everything natively.
 */
ClockSheet {
    id: sheet

    title: Translation.tr("Watch & band sync guide")
    subtitle: Translation.tr("How your wearable reaches Health Connect")

    property string selectedBrand: "huawei"

    readonly property var brands: [
        {
            id: "huawei",
            label: "Huawei",
            app: "Huawei Health",
            badge: Translation.tr("Partial native · Health Sync recommended"),
            steps: [
                Translation.tr("Open Huawei Health → Me → Privacy management → Data sharing and authorization → Health Connect and turn on syncing."),
                Translation.tr("In Android Settings → Health Connect → App permissions → Huawei Health, allow write access for Steps, Sleep and Active calories."),
                Translation.tr("Native Huawei Health only writes steps, sleep and active calories (and usually only new data going forward). For heart rate, workouts, SpO2 and full history, install Health Sync from the Play Store and link Huawei Health → Health Connect.")
            ]
        },
        {
            id: "xiaomi",
            label: "Xiaomi",
            app: "Mi Fitness",
            badge: Translation.tr("Native Health Connect"),
            steps: [
                Translation.tr("Open Mi Fitness and make sure your band or watch is paired and syncing."),
                Translation.tr("Go to Profile → Third-party data → Health Connect and tap Allow all (steps, sleep, heart rate, workouts)."),
                Translation.tr("Set Mi Fitness battery usage to Unrestricted in Android settings so overnight sync is not paused.")
            ]
        },
        {
            id: "amazfit",
            label: "Amazfit / Zepp",
            app: "Zepp",
            badge: Translation.tr("Native Health Connect"),
            steps: [
                Translation.tr("Update Zepp to the latest version and sync your watch or ring."),
                Translation.tr("Go to Profile → Add accounts (or More settings → Third-party services) → Health Connect."),
                Translation.tr("Grant write permissions for steps, sleep, heart rate and workouts, and exclude Zepp from battery optimization.")
            ]
        },
        {
            id: "honor",
            label: "Honor",
            app: "Honor Health",
            badge: Translation.tr("Native Health Connect"),
            steps: [
                Translation.tr("Sign in to an Honor Account inside Honor Health (required to unlock Health Connect)."),
                Translation.tr("Open Settings → Health Connect (or Data sharing) → turn on Sync with Health Connect and allow all permissions."),
                Translation.tr("Pull down on the Honor Health home screen to force a fresh sync from your band.")
            ]
        },
        {
            id: "oneplus",
            label: "OnePlus / OPPO",
            app: "OHealth",
            badge: Translation.tr("Native · basic metrics"),
            steps: [
                Translation.tr("Open OHealth and tap your profile icon."),
                Translation.tr("Open Health Connect (or Data sharing) and allow OHealth to write steps, heart rate, workouts and sleep."),
                Translation.tr("OHealth pushes one-way and may omit detailed sleep stages or HRV; disable battery restrictions for reliable background sync.")
            ]
        },
        {
            id: "garmin",
            label: "Garmin",
            app: "Garmin Connect",
            badge: Translation.tr("Native · one-way push"),
            steps: [
                Translation.tr("Open Garmin Connect → More → Settings → Health Connect."),
                Translation.tr("Enable Health Connect and grant write permissions for steps, heart rate, sleep, calories and workouts."),
                Translation.tr("Proprietary metrics such as Body Battery, Training Readiness and HRV Status stay inside Garmin Connect.")
            ]
        },
        {
            id: "samsung",
            label: "Samsung",
            app: "Samsung Health",
            badge: Translation.tr("Native Health Connect"),
            steps: [
                Translation.tr("Open Samsung Health → Menu → Settings → Health Connect → App permissions."),
                Translation.tr("Allow Samsung Health to write all categories you want to see on your PC."),
                Translation.tr("If your ii tools build includes the Samsung Health SDK, Samsung Health can also be read directly for faster heart-rate updates and Energy Score.")
            ]
        }
    ]

    readonly property var currentBrand: {
        for (let i = 0; i < sheet.brands.length; i++)
            if (sheet.brands[i].id === sheet.selectedBrand)
                return sheet.brands[i];
        return sheet.brands[0];
    }

    // ── Prerequisite: Health Connect ────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hcRow.implicitHeight + ClockStyle.gapLarge * 2
        radius: ClockStyle.radiusNormal
        color: ClockStyle.colPrimaryContainer

        RowLayout {
            id: hcRow
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "health_and_safety"
                iconSize: 20
                padding: 9
                shape: MaterialShape.Shape.Cookie7Sided
                color: ClockStyle.colPrimary
                colSymbol: ClockStyle.colOnPrimary
                fill: 1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Health Connect is required on the phone")
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnPrimaryContainer
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Android 14+ includes Health Connect in System Settings → Security & privacy. On Android 13 or older, install Health Connect from the Play Store. Your watch app must write into Health Connect so ii tools can read it.")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnPrimaryContainer
                    opacity: 0.88
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ── Brand picker ────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Choose your watch or band")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: ClockStyle.colOnSurfaceVariant
        }

        Flow {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            Repeater {
                model: sheet.brands

                ClockFormChip {
                    required property var modelData
                    label: modelData.label
                    selected: sheet.selectedBrand === modelData.id
                    onTriggered: sheet.selectedBrand = modelData.id
                }
            }
        }
    }

    // ── Selected brand steps ────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: brandCol.implicitHeight + ClockStyle.gapLarge * 2
        radius: ClockStyle.radiusNormal
        color: ClockStyle.colField

        ColumnLayout {
            id: brandCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: `${sheet.currentBrand.label} · ${sheet.currentBrand.app}`
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurface
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                implicitWidth: badgeText.implicitWidth + 16
                implicitHeight: badgeText.implicitHeight + 8
                radius: Math.min(implicitHeight / 2, ClockStyle.radiusLarge)
                color: ClockStyle.colSecondaryContainer

                StyledText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: sheet.currentBrand.badge
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSecondaryContainer
                }
            }

            Repeater {
                model: sheet.currentBrand.steps

                RowLayout {
                    id: stepRow
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: ClockStyle.gap

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 1
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: 11
                        color: ClockStyle.colPrimaryContainer

                        StyledText {
                            anchors.centerIn: parent
                            text: String(stepRow.index + 1)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: ClockStyle.colOnPrimaryContainer
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: stepRow.modelData
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colOnSurface
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    // ── Fallback / extra metrics: Health Sync ───────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hsRow.implicitHeight + ClockStyle.gapLarge * 2
        radius: ClockStyle.radiusNormal
        color: ClockStyle.colSecondaryContainer

        RowLayout {
            id: hsRow
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "sync_alt"
                iconSize: 20
                padding: 9
                shape: MaterialShape.Shape.Clover4Leaf
                color: ClockStyle.colSurfaceHigh
                colSymbol: ClockStyle.colOnSurface
                fill: 1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Missing metrics or unsupported brand? Use Health Sync")
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSecondaryContainer
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Health Sync (Play Store) bridges apps that lack full Health Connect support — such as Huawei Health, Polar, Suunto, Coros or Fitbit — into Health Connect, including heart rate, sleep, workouts and historical sync. Once it writes to Health Connect, ii tools picks it up automatically.")
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSecondaryContainer
                    opacity: 0.88
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
