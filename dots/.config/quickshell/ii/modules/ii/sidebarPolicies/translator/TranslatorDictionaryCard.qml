pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The source word as a dictionary entry: definitions, examples in context and synonyms.
 *
 * The other panes speak through shapes and hue; this one is carried by type alone — a
 * wide, heavy headword, condensed tertiary numerals, examples in italics — like the
 * page of a printed dictionary. A synonym looks itself up.
 */
Rectangle {
    id: root

    property string headword: ""
    property string phonetic: ""
    property string languageName: ""
    /// [{ pos, items: [{ text, example }] }]
    property var definitions: []
    /// Example sentences, as StyledText with the word in <b>.
    property var examples: []
    /// [{ pos, words: [...] }]
    property var synonyms: []

    signal lookupRequested(string word)

    readonly property color colContent: ClockStyle.colOnSurface
    readonly property color colAccent: ClockStyle.colTertiary

    color: ClockStyle.colSurfaceHigh
    radius: ClockStyle.radiusCard

    StyledFlickable {
        id: flick
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
            topMargin: ClockStyle.cardPadding - 4
            rightMargin: ClockStyle.cardPadding - 6
        }
        clip: true
        contentHeight: column.implicitHeight

        ColumnLayout {
            id: column
            width: flick.width - 6
            spacing: ClockStyle.gapLarge

            // ── Headword ────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.languageName.length > 0 ? Translation.tr("Dictionary · %1").arg(root.languageName) : Translation.tr("Dictionary")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurfaceVariant
                    elide: Text.ElideRight
                }

                StyledText {
                    id: headwordText
                    Layout.fillWidth: true
                    text: root.headword
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ({ "wght": 780, "wdth": 125, "ROND": 0 })
                    font.pixelSize: Math.round(ClockStyle.textTitle * 1.25)
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: ClockStyle.textLarge
                    color: root.colContent
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.phonetic.length > 0
                    text: `/${root.phonetic}/`
                    font.pixelSize: ClockStyle.textNormal
                    font.italic: true
                    color: ClockStyle.colSubtext
                    elide: Text.ElideRight
                }
            }

            // ── Definitions ─────────────────────────────────────────────
            Repeater {
                model: root.definitions

                delegate: ColumnLayout {
                    id: sense
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    PosLabel {
                        text: sense.modelData.pos
                    }

                    Repeater {
                        model: sense.modelData.items

                        delegate: RowLayout {
                            id: definitionRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: ClockStyle.gap

                            StyledText {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: 18
                                text: definitionRow.index + 1
                                horizontalAlignment: Text.AlignRight
                                font.family: ClockStyle.fontMain
                                font.variableAxes: ClockStyle.axesDigitsBold
                                font.pixelSize: ClockStyle.textLarge + 2
                                color: root.colAccent
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: definitionRow.modelData.text
                                    font.pixelSize: ClockStyle.textNormal + 1
                                    color: root.colContent
                                    wrapMode: Text.Wrap
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: definitionRow.modelData.example.length > 0
                                    text: `“${definitionRow.modelData.example}”`
                                    font.pixelSize: ClockStyle.textNormal
                                    font.italic: true
                                    color: ClockStyle.colSubtext
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }

            // ── Examples ────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.examples.length > 0
                spacing: ClockStyle.gapSmall

                PosLabel {
                    text: Translation.tr("Examples")
                }

                Repeater {
                    model: root.examples

                    delegate: StyledText {
                        required property string modelData
                        Layout.fillWidth: true
                        text: `“${modelData}”`
                        textFormat: Text.StyledText
                        font.pixelSize: ClockStyle.textNormal + 1
                        font.italic: true
                        color: ClockStyle.colOnSurfaceVariant
                        wrapMode: Text.Wrap
                    }
                }
            }

            // ── Synonyms ────────────────────────────────────────────────
            Repeater {
                model: root.synonyms

                delegate: ColumnLayout {
                    id: synonymGroup
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    PosLabel {
                        text: Translation.tr("Synonyms · %1").arg(synonymGroup.modelData.pos)
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapTiny + 2

                        Repeater {
                            model: synonymGroup.modelData.words

                            delegate: RippleButton {
                                id: synonym
                                required property string modelData
                                leftPadding: 0
                                rightPadding: 0
                                implicitHeight: ClockStyle.chipHeight - 4
                                implicitWidth: Math.min(synonymGroup.width, synonymText.implicitWidth + ClockStyle.gap * 2)
                                buttonRadius: ClockStyle.radiusSmall
                                buttonRadiusPressed: ClockStyle.pill(ClockStyle.chipHeight - 4)
                                colBackground: ClockStyle.colSecondaryContainer
                                colBackgroundHover: ClockStyle.colSecondaryContainerHover
                                colRipple: ClockStyle.colSecondaryContainerActive
                                onClicked: root.lookupRequested(synonym.modelData)

                                contentItem: Item {
                                    StyledText {
                                        id: synonymText
                                        anchors {
                                            verticalCenter: parent.verticalCenter
                                            left: parent.left
                                            right: parent.right
                                            leftMargin: ClockStyle.gap
                                            rightMargin: ClockStyle.gap
                                        }
                                        text: synonym.modelData
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: ClockStyle.textNormal
                                        color: ClockStyle.colOnSecondaryContainer
                                        elide: Text.ElideRight
                                    }
                                }

                                StyledToolTip {
                                    text: Translation.tr("Look up “%1”").arg(synonym.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Part of speech and section captions: small, wide, spaced, in the accent.
    component PosLabel: StyledText {
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.variableAxes: ({ "wght": 700, "wdth": 120 })
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
        color: root.colAccent
        elide: Text.ElideRight
    }
}
