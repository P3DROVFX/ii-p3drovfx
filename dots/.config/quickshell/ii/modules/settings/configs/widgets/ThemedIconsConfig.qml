import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Themed Icons")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Themed Icons Configuration")
            icon: "category"

            ConfigSwitch {
                buttonIcon: "magic_button"
                text: Translation.tr("Enable themed icons")
                checked: Config.options.appearance.icons.enableThemed
                onCheckedChanged: IconThemes.setThemed(checked)

                StyledToolTip {
                    text: Translation.tr("When enabled, uses the dynamic Matugen generated icon pack. Fallbacks to Tint Icons.")
                }
            }

            ContentSubsection {
                visible: Config.options.appearance.icons.enableThemed
                title: Translation.tr("Base icon theme")
                icon: "palette"
                Layout.fillWidth: true
                tooltip: Translation.tr("Select the base icon theme to be recolored by Matugen.\nRequires generating colors again to apply.")

                ConfigSelectionArray {
                    currentValue: Config.options.appearance.iconTheme
                    onSelected: (newValue) => {
                        Config.options.appearance.iconTheme = newValue;
                    }
                    options: IconThemes.availableThemes.map((theme) => {
                        return ({
                            "displayName": theme,
                            "value": theme,
                            "icon": "category"
                        });
                    })
                }
            }

            RippleButtonWithIcon {
                visible: Config.options.appearance.icons.enableThemed
                materialIcon: "magic_button"
                mainText: Translation.tr("Apply Theme")
                useDynamicRadius: true
                implicitHeight: 48
                Layout.fillWidth: true
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: {
                    IconThemes.applyTheme(false);
                }
            }

            ConfigSwitch {
                buttonIcon: "restart_alt"
                text: Translation.tr("Auto restart Quickshell on theme change")
                checked: Config.options.appearance.wallpaperTheming.autoRestartQuickshell
                onCheckedChanged: {
                    Config.options.appearance.wallpaperTheming.autoRestartQuickshell = checked;
                }
            }
        }

        ContentSection {
            id: packSection
            title: Translation.tr("ii-icon-pack")
            icon: "interests"
            tooltip: Translation.tr("The Material You icon pack made for this shell. Installed from GitHub, kept up to date from here, and redrawn in any shape.")

            readonly property var packOptions: Config.options.appearance.icons.iiPack

            /// What the icons will look like on the desktop: recolored to the palette when themed
            /// icons are on, in the pack's own colors otherwise.
            readonly property color previewPlate: IconThemes.themed ? Appearance.colors.colPrimaryContainer : "#1a2636"
            readonly property color previewGlyph: IconThemes.themed ? Appearance.colors.colOnPrimaryContainer : "#7dd3fc"

            function refreshPreviews() {
                previewDebounce.restart();
            }

            onPreviewPlateChanged: packSection.refreshPreviews()
            onPreviewGlyphChanged: packSection.refreshPreviews()

            Timer {
                id: previewDebounce
                interval: 150
                onTriggered: IiIconPack.refreshPreviews(packSection.previewPlate, packSection.previewGlyph)
            }

            Connections {
                target: IiIconPack
                function onSourcePresentChanged() {
                    packSection.refreshPreviews();
                }
            }

            Component.onCompleted: {
                IiIconPack.refresh(true);
                if (IiIconPack.sourcePresent) packSection.refreshPreviews();
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: !IiIconPack.statusReady ? "hourglass_empty"
                    : !IiIconPack.installed ? "download"
                    : IiIconPack.updateAvailable ? "system_update"
                    : "verified"
                text: {
                    if (!IiIconPack.statusReady)
                        return Translation.tr("Looking for ii-icon-pack…");
                    if (!IiIconPack.installed)
                        return Translation.tr("Not installed. Download it from GitHub and draw every app icon in the shape you pick.");
                    if (!IiIconPack.managed)
                        return Translation.tr("Installed by hand. Install it from here to reshape it and receive updates.");
                    const parts = [Translation.tr("Installed · %1").arg(IiIconPack.shapeName(String(IiIconPack.installedOptions.shape ?? "circle")))];
                    if (IiIconPack.installedCommit !== "")
                        parts.push(Translation.tr("version %1").arg(IiIconPack.installedCommit.slice(0, 7)));
                    if (IiIconPack.checkingRemote)
                        parts.push(Translation.tr("checking for updates…"));
                    else if (IiIconPack.updateAvailable)
                        parts.push(Translation.tr("an update is available"));
                    else if (IiIconPack.remoteCommit !== "")
                        parts.push(Translation.tr("up to date"));
                    return parts.join(" · ");
                }

                RippleButtonWithIcon {
                    visible: IiIconPack.statusReady && (!IiIconPack.installed || !IiIconPack.managed || IiIconPack.updateAvailable)
                    enabled: !IiIconPack.busy
                    materialIcon: IiIconPack.installed && IiIconPack.managed ? "system_update" : "download"
                    mainText: IiIconPack.installed && IiIconPack.managed ? Translation.tr("Update") : Translation.tr("Install")
                    buttonRadius: Appearance.rounding.full
                    implicitHeight: 40
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    colText: Appearance.colors.colOnPrimary
                    onClicked: IiIconPack.installed && IiIconPack.managed ? IiIconPack.update() : IiIconPack.install()
                }

                RippleButton {
                    visible: IiIconPack.installed && IiIconPack.managed
                    enabled: !IiIconPack.busy && !IiIconPack.checkingRemote
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: IiIconPack.refresh(true)
                    Accessible.name: Translation.tr("Check for updates")

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledToolTip {
                        text: Translation.tr("Check for updates")
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                visible: IiIconPack.busy
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: IiIconPack.message
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    value: IiIconPack.progress
                    wavy: true
                    animateWave: IiIconPack.busy
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                visible: IiIconPack.lastError !== "" && !IiIconPack.busy
                text: IiIconPack.lastError
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colError
            }

            RippleButtonWithIcon {
                visible: IiIconPack.installed && IconThemes.currentPack !== IiIconPack.themeName
                enabled: !IconThemes.applying
                materialIcon: "check_circle"
                mainText: IconThemes.themed ? Translation.tr("Recolor ii-icon-pack as the themed icons base")
                    : Translation.tr("Use ii-icon-pack as the icon theme")
                useDynamicRadius: true
                implicitHeight: 48
                Layout.fillWidth: true
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                colText: Appearance.colors.colOnPrimaryContainer
                onClicked: IiIconPack.useAsIconTheme()
            }

            ContentSubsection {
                visible: IiIconPack.sourcePresent && IiIconPack.shapes.length > 0
                title: Translation.tr("Icon shape")
                icon: "interests"
                Layout.fillWidth: true
                tooltip: Translation.tr("The plate every app icon sits on. Circle, squircle and teardrop are the Android launcher masks; the rest are Material 3 Expressive shapes.")

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: IiIconPack.shapes

                        delegate: ShapeTile {
                            required property var modelData
                            shape: modelData
                        }
                    }
                }
            }

            ConfigSlider {
                visible: IiIconPack.sourcePresent && IiIconPack.shapes.length > 0
                buttonIcon: "photo_size_select_small"
                text: Translation.tr("Icon size (%)")
                usePercentTooltip: false
                from: 60
                to: 108
                stepSize: 1
                value: Math.round(packSection.packOptions.plateScale * 100)
                onValueChanged: {
                    const scale = value / 100;
                    if (Math.abs(scale - packSection.packOptions.plateScale) < 0.001) return;
                    packSection.packOptions.plateScale = scale;
                    packSection.refreshPreviews();
                    IiIconPack.applyOptions();
                }
            }

            ConfigSlider {
                visible: IiIconPack.sourcePresent && IiIconPack.shapes.length > 0
                buttonIcon: "zoom_in"
                text: Translation.tr("Logo size (%)")
                usePercentTooltip: false
                from: 50
                to: 150
                stepSize: 1
                value: Math.round(packSection.packOptions.glyphScale * 100)
                onValueChanged: {
                    const scale = value / 100;
                    if (Math.abs(scale - packSection.packOptions.glyphScale) < 0.001) return;
                    packSection.packOptions.glyphScale = scale;
                    packSection.refreshPreviews();
                    IiIconPack.applyOptions();
                }
            }

            RippleButtonWithIcon {
                visible: IiIconPack.optionsPending && !IiIconPack.busy
                materialIcon: "format_paint"
                mainText: Translation.tr("Apply shape")
                useDynamicRadius: true
                implicitHeight: 48
                Layout.fillWidth: true
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                colText: Appearance.colors.colOnSecondaryContainer
                onClicked: IiIconPack.applyOptions()
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                text: Translation.tr("Outside this shell, install.sh in the ii-icon-pack repository takes the same options, e.g. --shape squircle --set-theme.")
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    /// One shape of the picker: a sample icon drawn in it, with the shape's name under it.
    component ShapeTile: RippleButton {
        id: tile

        required property var shape
        readonly property bool selected: Config.options.appearance.icons.iiPack.shape === tile.shape.key
        readonly property string preview: IiIconPack.previews[tile.shape.key] ?? ""

        implicitWidth: 96
        implicitHeight: 96
        buttonRadius: Appearance.rounding.normal
        // The previews are painted in primary container, so the picked tile sits on primary.
        colBackground: tile.selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
        colBackgroundHover: tile.selected ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover
        colRipple: tile.selected ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active
        Accessible.name: tile.shape.name
        Accessible.role: Accessible.RadioButton
        Accessible.checked: tile.selected

        onClicked: {
            if (tile.selected) return;
            Config.options.appearance.icons.iiPack.shape = tile.shape.key;
            IiIconPack.applyOptions();
        }

        contentItem: Item {
            anchors.fill: parent

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 10
                spacing: 6

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 52
                    implicitHeight: 52

                    Image {
                        anchors.fill: parent
                        visible: tile.preview !== ""
                        source: tile.preview !== "" ? `file://${tile.preview}` : ""
                        sourceSize.width: 104
                        sourceSize.height: 104
                        asynchronous: true
                        cache: false
                        smooth: true
                        mipmap: true
                    }

                    MaterialShape {
                        anchors.fill: parent
                        visible: tile.preview === "" && tile.shape.materialShape !== ""
                        shapeString: tile.shape.materialShape || "Circle"
                        color: Appearance.colors.colPrimaryContainer
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.shape.name
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: tile.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                }
            }
        }

        StyledToolTip {
            text: tile.shape.name
        }
    }
}
