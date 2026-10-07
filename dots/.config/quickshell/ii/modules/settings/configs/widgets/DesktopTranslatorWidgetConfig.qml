pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets.productivity
import qs.modules.settings.configs.widgets

/*
 * The Translator widget (1x2): live beside the languages its tiles step
 * through. A tap on the widget's "To" tile moves to the next chosen language;
 * the "From" tile adds Detect language in front of them.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var options: Config.options.background.widgets.translator_widget
    readonly property var commonLanguages: ["en", "pt-BR", "pt-PT", "es", "fr", "de", "it", "nl", "pl", "ru", "uk", "tr", "ar", "hi", "ja", "ko", "zh-CN"]
    readonly property var chosen: Array.from(root.options.quickLanguages ?? [])

    function toggle(code) {
        const next = root.chosen.slice();
        const at = next.indexOf(code);
        if (at >= 0) {
            // Keep at least two: the tiles need somewhere to go.
            if (next.length <= 2)
                return;
            next.splice(at, 1);
        } else {
            next.push(code);
        }
        root.options.quickLanguages = next;
    }

    Component.onCompleted: TranslatorService.ensureLanguages()

    WidgetPageHeader {
        title: Translation.tr("Translator Widget Options")
        onBack: root.goBack()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        WidgetPreviewStage {
            Layout.fillWidth: false
            Layout.preferredWidth: 240 * 0.7 + 40
            Layout.alignment: Qt.AlignTop
            columns: 1
            rows: 2
            // A fixed scale: the stage is narrow by design.
            boardScaleOverride: 0.7

            WidgetPreviewSlot {
                rowSpan: 2
                TranslatorWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.height / Math.max(1, implicitHeight)
                }
            }
        }

        // ── Quick languages ──
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                RowLayout {
                    spacing: 12

                    MaterialShapeWrappedMaterialSymbol {
                        text: "translate"
                        iconSize: 24
                        padding: 12
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Quick languages")
                            font.family: Appearance.font.family.title
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("%1 chosen · the tiles step through them in this order").arg(root.chosen.length)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.commonLanguages

                        delegate: RippleButton {
                            id: chip
                            required property string modelData
                            readonly property int order: root.chosen.indexOf(chip.modelData)
                            readonly property bool selected: chip.order >= 0
                            implicitHeight: 36
                            implicitWidth: chipRow.implicitWidth + 28
                            buttonRadius: chip.selected ? Appearance.rounding.small : Appearance.rounding.full
                            colBackground: chip.selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                            colBackgroundHover: chip.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                            colRipple: chip.selected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer2Active
                            onClicked: root.toggle(chip.modelData)

                            contentItem: Item {
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: chip.selected
                                        text: String(chip.order + 1)
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: TranslatorService.displayName(chip.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: chip.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("The engine and the default pair are the translator's own, in Settings → Language & Time.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Translator (1x2)")
        icon: "translate"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            WidgetPlacementNote { widgetId: "translator_widget" }
            WidgetSizeSlider { options: root.options }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
