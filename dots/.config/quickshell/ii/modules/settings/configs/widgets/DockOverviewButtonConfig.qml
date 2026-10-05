import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.dockUtilities
import "../../../ii/dock"

/**
 * Dock → Overview button: its icon (the `apps` symbol or any picture in
 * assets/icons), the shape of its plate, and whether the plate stays up or
 * only shows while the overview is open. The hero is the real button, at rest
 * and with the overview open.
 */
UtilityConfigPage {
    id: page
    title: Translation.tr("Overview button")

    readonly property var cfg: Config.options.dock.overviewButton
    readonly property string iconFolder: FileUtils.trimFileProtocol(Directories.assetsPath) + "/icons"

    // An icon from assets/icons. Black-and-white ones (any grey, any file
    // name) are drawn in the theme's colour; coloured ones as they are. The
    // tone is measured on the pixels, since few files say so in their name.
    // QtQuick.Effects, not Qt5Compat: the Settings window is destroyed on
    // close and a Qt5Compat effect would keep a reference to it.
    component AssetIcon: Item {
        id: assetIcon
        property string file: ""
        property color tint: Appearance.colors.colOnLayer1
        readonly property string url: assetIcon.file.length > 0 ? ("file://" + page.iconFolder + "/" + assetIcon.file) : ""
        property bool measured: false
        property bool monochrome: assetIcon.file.indexOf("symbolic") >= 0
        signal toneMeasured()

        IconImage {
            id: image
            anchors.fill: parent
            source: assetIcon.url
            implicitSize: assetIcon.width
            visible: !assetIcon.monochrome
        }
        MultiEffect {
            anchors.fill: image
            visible: assetIcon.monochrome
            source: image
            brightness: 1.0
            colorization: 1.0
            colorizationColor: assetIcon.tint
        }

        // Painted once, never shown (opacity, not visible: a hidden canvas
        // does not paint).
        Canvas {
            id: probe
            width: 24
            height: 24
            opacity: 0
            onAvailableChanged: if (probe.available && assetIcon.url.length > 0) probe.loadImage(assetIcon.url)
            onImageLoaded: probe.requestPaint()
            onPaint: {
                if (!probe.isImageLoaded(assetIcon.url))
                    return;
                const ctx = probe.getContext("2d");
                ctx.clearRect(0, 0, probe.width, probe.height);
                ctx.drawImage(assetIcon.url, 0, 0, probe.width, probe.height);
                const d = ctx.getImageData(0, 0, probe.width, probe.height).data;
                let solid = 0;
                let coloured = 0;
                let dark = 0;
                let light = 0;
                for (let i = 0; i < d.length; i += 4) {
                    if (d[i + 3] < 80)
                        continue;
                    solid++;
                    const hi = Math.max(d[i], d[i + 1], d[i + 2]);
                    if (hi - Math.min(d[i], d[i + 1], d[i + 2]) > 48)
                        coloured++;
                    if (d[i + 3] > 200) {
                        if (hi < 90)
                            dark++;
                        else if (hi > 170)
                            light++;
                    }
                }
                // A few tinted pixels are antialiasing, not colour. Black and
                // white together (a letter on a white tile, a photo) would
                // flatten into one blob, so only one-tone pictures are tinted.
                const twoTone = Math.min(dark, light) / Math.max(1, solid) > 0.08;
                assetIcon.monochrome = solid > 0 && coloured / solid < 0.04 && !twoTone;
                assetIcon.measured = true;
                assetIcon.toneMeasured();
            }
        }
    }

    // ── The real button ─────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 132
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        RowLayout {
            anchors.centerIn: parent
            spacing: 40
            Repeater {
                model: [false, true]
                delegate: ColumnLayout {
                    required property bool modelData
                    spacing: 8
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 84
                        implicitHeight: 72
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        DockActionButton {
                            anchors.centerIn: parent
                            actionId: "overview"
                            toggled: modelData
                            normalShape: MaterialShape.Shape.SoftBurst
                            activeShape: MaterialShape.Shape.SoftBurst
                            symbolSize: Math.round(Appearance.sizes.dockButtonSize * 0.5)
                            symbolName: page.cfg.symbol.trim().length > 0 ? page.cfg.symbol.trim() : "apps"
                            customIconSource: page.cfg.iconFile.length > 0 ? ("file://" + page.iconFolder + "/" + page.cfg.iconFile) : ""
                            tintCustomIcon: page.cfg.iconTint
                            shapeName: page.cfg.shape
                            alwaysShowShape: page.cfg.alwaysShowShape
                        }
                        // A picture of the button, not a button: no click reaches it.
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData ? Translation.tr("Overview open") : Translation.tr("At rest")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Plate")
        icon: "category"

        ConfigSwitch {
            buttonIcon: "visibility"
            text: Translation.tr("Keep the shape visible")
            checked: page.cfg.alwaysShowShape
            onCheckedChanged: page.cfg.alwaysShowShape = checked
            StyledToolTip {
                text: Translation.tr("Off: the shape only shows while the overview is open")
            }
        }
        ShapePicker {
            Layout.fillWidth: true
            current: page.cfg.shape
            onPicked: name => page.cfg.shape = name
        }
    }

    ContentSection {
        title: Translation.tr("Icon")
        icon: "image"
        tooltip: Translation.tr("A Material Symbol by name, or any picture in assets/icons; black-and-white ones take the theme's colours")

        ConfigTextField {
            id: symbolField
            text: Translation.tr("Material Symbol")
            icon: "emoji_symbols"
            placeholderText: Translation.tr("A symbol's name, e.g. grid_view or rocket_launch")
            inputText: page.cfg.symbol
            textField.onEditingFinished: {
                const name = textField.text.trim();
                page.cfg.symbol = name;
                if (name.length > 0)
                    page.cfg.iconFile = "";
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            // The default: the `apps` symbol.
            RippleButton {
                id: defaultIcon
                readonly property bool chosen: page.cfg.iconFile.length === 0 && page.cfg.symbol.trim().length === 0
                implicitWidth: 52
                implicitHeight: 52
                buttonRadius: Appearance.rounding.normal
                colBackground: defaultIcon.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: defaultIcon.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: {
                    page.cfg.iconFile = "";
                    page.cfg.symbol = "";
                }
                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "apps"
                        iconSize: 26
                        color: defaultIcon.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Default symbol")
                }
            }

            Repeater {
                model: FolderListModel {
                    folder: "file://" + page.iconFolder
                    nameFilters: ["*.svg", "*.png"]
                    showDirs: false
                    sortField: FolderListModel.Name
                }
                delegate: RippleButton {
                    id: iconOption
                    required property string fileName
                    readonly property bool chosen: page.cfg.iconFile === iconOption.fileName
                    implicitWidth: 52
                    implicitHeight: 52
                    buttonRadius: Appearance.rounding.normal
                    colBackground: iconOption.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                    colBackgroundHover: iconOption.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: {
                        page.cfg.iconFile = iconOption.fileName;
                        page.cfg.symbol = "";
                        if (optionIcon.measured)
                            page.cfg.iconTint = optionIcon.monochrome;
                    }
                    contentItem: Item {
                        AssetIcon {
                            id: optionIcon
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            file: iconOption.fileName
                            tint: iconOption.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                            // Keeps a hand-edited or older choice in step.
                            onToneMeasured: if (iconOption.chosen) page.cfg.iconTint = optionIcon.monochrome
                        }
                    }
                    StyledToolTip {
                        text: iconOption.fileName.replace(/\.(svg|png)$/i, "").replace(/[-_]/g, " ")
                    }
                }
            }
        }
    }
}
