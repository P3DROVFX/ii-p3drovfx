import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/**
 * Power & Battery → Framework Laptop. What framework_tool offers beyond the fans: the EC's
 * charge limit, the fingerprint reader's light, and read-only status (privacy sliders,
 * expansion bay, firmware). framework_tool needs root, so ii-fand runs it and reports the
 * values in its status; this page sends changes through `FanControl.applyFramework`.
 */
ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    Component.onCompleted: FanControl.watchers += 1
    Component.onDestruction: FanControl.watchers -= 1

    readonly property var fw: FanControl.frameworkStatus
    readonly property bool live: root.fw !== null
    readonly property bool canApply: FanControl.daemonInstalled && FanControl.frameworkToolInstalled && !FanControl.busy
    readonly property int chargeLimit: root.fw?.chargeLimit ?? (Battery.chargeLimitActive ? Battery.chargeLimit : 100)
    readonly property string fpLevel: root.fw?.fp?.level ?? FanControl.frameworkConfig.fpLevel ?? ""
    readonly property var versions: root.fw?.versions ?? null
    readonly property var bay: root.fw?.bay ?? null
    readonly property string unknown: Translation.tr("Unknown")

    // ── header ──
    RowLayout {
        visible: root.showBackButton
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Framework Laptop")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── hero: the machine, its firmware, the privacy sliders ──
    Rectangle {
        id: hero
        Layout.fillWidth: true
        readonly property bool wide: width >= 620
        implicitHeight: heroGrid.implicitHeight + 40
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        GridLayout {
            id: heroGrid
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 20
            }
            columns: hero.wide ? 2 : 1
            columnSpacing: 24
            rowSpacing: 16

            ColumnLayout {
                // wrapped text claims the whole row otherwise, pushing the sliders off the card
                Layout.preferredWidth: hero.wide ? (heroGrid.width - heroGrid.columnSpacing) / 2 : -1
                Layout.fillWidth: !hero.wide
                Layout.alignment: Qt.AlignTop
                spacing: 4

                StyledText {
                    text: Translation.tr("Framework").toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.versions?.board ?? FanControl.caps?.product ?? Translation.tr("Laptop")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.versions
                        ? Translation.tr("BIOS %1 · EC %2").arg(root.versions.bios ?? "?").arg(root.versions.ec ?? "?")
                        : (FanControl.daemonRunning ? Translation.tr("Reading the EC…")
                                                    : Translation.tr("Firmware details appear once the thermal service runs."))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }

            ColumnLayout {
                Layout.preferredWidth: hero.wide ? (heroGrid.width - heroGrid.columnSpacing) / 2 : -1
                Layout.fillWidth: !hero.wide
                Layout.alignment: Qt.AlignTop
                spacing: 6

                PrivacyRow {
                    symbol: "mic"
                    symbolOff: "mic_off"
                    label: Translation.tr("Microphone")
                    connected: root.fw?.privacy?.microphone
                }
                PrivacyRow {
                    symbol: "videocam"
                    symbolOff: "videocam_off"
                    label: Translation.tr("Camera")
                    connected: root.fw?.privacy?.camera
                }
            }
        }
    }

    FrameworkRequirements {
        Layout.fillWidth: true
        visible: FanControl.ready && !FanControl.frameworkReady
    }

    // ── the service is missing: one line and the button ──
    Rectangle {
        Layout.fillWidth: true
        visible: FanControl.ready && FanControl.frameworkToolInstalled && !FanControl.daemonInstalled
        implicitHeight: installRow.implicitHeight + 32
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        RowLayout {
            id: installRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: 16
                leftMargin: 20
            }
            spacing: 16

            StyledText {
                Layout.fillWidth: true
                text: FanControl.lastError.length > 0 ? FanControl.lastError
                    : Translation.tr("framework_tool needs root. The thermal service runs it for this page.")
                color: FanControl.lastError.length > 0 ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                wrapMode: Text.WordWrap
            }
            RippleButton {
                implicitHeight: 40
                implicitWidth: installLabel.implicitWidth + 32
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.small
                enabled: !FanControl.busy
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: FanControl.install()
                contentItem: Item {
                    StyledText {
                        id: installLabel
                        anchors.centerIn: parent
                        text: FanControl.busy ? Translation.tr("Installing…") : Translation.tr("Install")
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // ── battery ──
    AppSettingsSection {
        Layout.topMargin: 12
        title: Translation.tr("Battery")
        symbol: "battery_profile"
        description: Translation.tr("The EC stops charging at the limit, even while the laptop is off.")

        ColorsFeatureTile {
            id: chargeTile
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            enabled: root.canApply
            symbol: "battery_charging_80"
            shapeOn: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Charge limit")
            checked: root.chargeLimit < 100
            summary: checked
                ? Translation.tr("Stops at %1 %. A pack kept below full wears more slowly.").arg(root.chargeLimit)
                : Translation.tr("Off. Charges to 100 %.")
            onToggled: value => FanControl.applyFramework({ "chargeLimit": value ? 80 : 100 })

            readonly property color colContent: checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

            Repeater {
                model: [60, 70, 80, 90]
                delegate: ColorsChip {
                    required property int modelData
                    label: `${modelData} %`
                    enabled: root.canApply
                    chosen: root.chargeLimit === modelData
                    colContent: chargeTile.colContent
                    colChosen: Appearance.colors.colPrimary
                    colOnChosen: Appearance.colors.colOnPrimary
                    onClicked: FanControl.applyFramework({ "chargeLimit": modelData })
                }
            }
        }

        AppStepperRow {
            symbol: "tune"
            title: Translation.tr("Exact limit (%)")
            description: Translation.tr("framework_tool refuses limits under 25 %")
            enabled: root.canApply
            value: root.chargeLimit
            from: 25
            to: 100
            onMoved: v => FanControl.applyFramework({ "chargeLimit": v })
        }
    }

    // ── fingerprint reader light ──
    AppSettingsSection {
        Layout.topMargin: 12
        title: Translation.tr("Fingerprint reader light")
        symbol: "fingerprint"
        description: root.fw?.fp?.pct !== undefined && root.fw?.fp?.pct !== null
            ? Translation.tr("The ring around the power button. Now at %1 % brightness.").arg(root.fw.fp.pct)
            : Translation.tr("The ring around the power button.")

        ConfigSelectionArray {
            enabled: root.canApply
            currentValue: root.fpLevel
            onSelected: newValue => FanControl.applyFramework({ "fpLevel": String(newValue) })
            options: [
                { displayName: Translation.tr("Auto"),      icon: "brightness_auto", value: "auto" },
                { displayName: Translation.tr("High"),      icon: "brightness_7",    value: "high" },
                { displayName: Translation.tr("Medium"),    icon: "brightness_6",    value: "medium" },
                { displayName: Translation.tr("Low"),       icon: "brightness_5",    value: "low" },
                { displayName: Translation.tr("Ultra low"), icon: "brightness_4",    value: "ultra-low" }
            ]
        }
    }

    // ── expansion bay (Laptop 16) ──
    AppSettingsSection {
        Layout.topMargin: 12
        visible: root.bay !== null
        title: Translation.tr("Expansion bay")
        symbol: "developer_board"

        AppSettingRow {
            symbol: "view_module"
            title: Translation.tr("Module")
            description: [root.bay?.board, root.bay?.vendor].filter(v => !!v).join(" · ") || root.unknown
        }
        AppSettingRow {
            symbol: "cable"
            title: Translation.tr("Interface")
            description: root.bay?.config ?? root.unknown
        }
        AppSettingRow {
            symbol: root.bay?.doorClosed ? "lock" : "lock_open"
            title: Translation.tr("Door")
            description: root.bay?.doorClosed ? Translation.tr("Closed") : Translation.tr("Open")
            StyledText {
                text: root.bay?.enabled ? Translation.tr("Enabled") : Translation.tr("Disabled")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.bay?.enabled ? Appearance.colors.colSubtext : Appearance.colors.colError
            }
        }
    }

    // ── firmware ──
    AppSettingsSection {
        Layout.topMargin: 12
        visible: root.versions !== null
        title: Translation.tr("Firmware")
        symbol: "memory"

        AppSettingRow {
            symbol: "settings_applications"
            title: Translation.tr("BIOS")
            description: [root.versions?.bios, root.versions?.biosDate].filter(v => !!v).join(" · ") || root.unknown
        }
        AppSettingRow {
            symbol: "developer_board"
            title: Translation.tr("Embedded controller")
            description: root.versions?.ec ?? root.unknown
            StyledText {
                visible: !!root.versions?.ecImage
                text: Translation.tr("Image %1").arg(root.versions?.ecImage ?? "")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        AppSettingRow {
            symbol: "terminal"
            title: Translation.tr("framework_tool")
            description: root.versions?.tool ?? root.unknown
        }
    }

    component PrivacyRow: Rectangle {
        id: privacy
        property string symbol
        property string symbolOff
        property string label
        property var connected   // true / false / undefined (not read yet)
        readonly property bool known: privacy.connected === true || privacy.connected === false

        Layout.fillWidth: true
        implicitHeight: 56
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 16
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: privacy.connected === false ? privacy.symbolOff : privacy.symbol
                iconSize: 18
                padding: 8
                shape: privacy.connected === false ? MaterialShape.Shape.Circle : MaterialShape.Shape.Cookie6Sided
                color: privacy.connected === false ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                colSymbol: privacy.connected === false ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: privacy.label
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }
            StyledText {
                text: !privacy.known ? "—"
                    : privacy.connected ? Translation.tr("On") : Translation.tr("Cut off by the slider")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: privacy.connected === false ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
        }
    }
}
