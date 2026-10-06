import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.usage.limits

/**
 * The translation, as the one thing the tab is about.
 *
 * The pane takes the hue of its state — primary container while it waits, the primary
 * itself once a translation lands — and everything on it is tinted with the pane's own
 * content colour. The header shape becomes the loading indicator while `trans` runs; a
 * scalloped ornament parked off the top-right corner turns with every swap.
 */
Rectangle {
    id: root

    property string text: ""
    property string transliteration: ""
    property string targetName: ""
    property bool busy: false
    property int textSize: Appearance.font.pixelSize.huge
    property int turns: 0
    /// Whole-sentence alternatives (strings).
    property var alternatives: []
    /// Word alternatives by part of speech: [{ pos, words: [{ word, back: [...] }] }].
    property var dictionary: []
    /// The helper's error, "" when fine.
    property string error: ""
    property bool canSpeak: false
    property bool speaking: false
    property bool speakFailed: false
    property string emptyHint: Translation.tr("Type or paste text above — press / from anywhere in the tab to start")

    signal speakRequested()
    signal retryRequested()

    readonly property bool hasResult: root.text.length > 0
    readonly property bool failed: root.error.length > 0 && !root.busy
    readonly property bool hasAlternatives: root.alternatives.length > 0 || root.dictionary.length > 0
    readonly property color colPane: root.failed ? ClockStyle.colErrorContainer
        : root.hasResult ? ClockStyle.colPrimary : ClockStyle.colPrimaryContainer
    readonly property color colContent: root.failed ? ClockStyle.colOnErrorContainer
        : root.hasResult ? ClockStyle.colOnPrimary : ClockStyle.colOnPrimaryContainer
    /// The alternative just copied, so its chip can say so.
    property string copiedValue: ""

    readonly property string errorTitle: root.error === "missing-trans" ? Translation.tr("translate-shell is missing")
        : Translation.tr("Couldn't translate")
    readonly property string errorDetail: root.error === "missing-trans" ? Translation.tr("Install the trans command (translate-shell) to use the translator")
        : root.error === "timeout" ? Translation.tr("The translation service took too long to answer")
        : Translation.tr("Check your connection and try again")

    radius: ClockStyle.radiusCard
    color: root.colPane
    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    property real ornamentAngle: root.turns * 45
    Behavior on ornamentAngle {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
    }

    function copy(value: string) {
        Quickshell.clipboardText = value;
        root.copiedValue = "";
        copiedTimer.restart();
    }

    function copyAlternative(value: string) {
        Quickshell.clipboardText = value;
        root.copiedValue = value;
        copiedTimer.stop();
        alternativeTimer.restart();
    }

    Timer {
        id: copiedTimer
        interval: 1600
    }

    Timer {
        id: alternativeTimer
        interval: 1600
        onTriggered: root.copiedValue = ""
    }

    // ── Ornament ────────────────────────────────────────────────────────
    // A plain clip would square off the rounded corners, so the arc is cut by a mask of
    // the pane itself (kept in the tree, so the window can die safely).
    Item {
        id: ornament
        anchors.fill: parent
        visible: false

        MaterialShape {
            readonly property real size: Math.round(Math.max(root.width * 0.86, 220))
            width: size
            height: size
            x: root.width - size * 0.52
            y: -size * 0.42
            shapeString: "Cookie12Sided"
            color: root.colContent
            rotation: root.ornamentAngle
        }
    }

    Rectangle {
        id: ornamentMask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: ornament
        maskEnabled: true
        maskSource: ornamentMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        opacity: 0.1
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
            topMargin: ClockStyle.cardPadding - 4
        }
        spacing: ClockStyle.gap

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall + 2

            Item {
                implicitWidth: 40
                implicitHeight: 40

                MaterialShapeWrappedMaterialSymbol {
                    anchors.centerIn: parent
                    text: "translate"
                    iconSize: 20
                    padding: 10
                    shape: MaterialShape.Shape.Cookie7Sided
                    color: root.colContent
                    colSymbol: root.colPane
                    fill: 1
                    opacity: root.busy ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity {
                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                    }
                }

                Loader {
                    anchors.centerIn: parent
                    active: root.busy
                    sourceComponent: MaterialLoadingIndicator {
                        implicitSize: 40
                        loading: true
                        shapeColor: root.colContent
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Translation")
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: root.colContent
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.busy ? Translation.tr("Translating…") : root.failed ? root.errorTitle : root.targetName
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colContent
                    opacity: 0.8
                    elide: Text.ElideRight
                }
            }

            ClockCardAction {
                Layout.alignment: Qt.AlignTop
                visible: root.canSpeak && root.hasResult && !root.failed
                symbol: root.speakFailed ? "volume_off" : root.speaking ? "stop" : "volume_up"
                tip: root.speakFailed ? Translation.tr("Couldn't play the audio") : root.speaking ? Translation.tr("Stop") : Translation.tr("Listen")
                colContent: root.colContent
                onClicked: root.speakRequested()
            }
        }

        // ── Result ──────────────────────────────────────────────────────
        StyledFlickable {
            id: resultFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.hasResult && !root.failed
            clip: true
            contentHeight: resultColumn.implicitHeight

            ColumnLayout {
                id: resultColumn
                width: resultFlick.width
                spacing: ClockStyle.gap

                StyledText {
                    Layout.fillWidth: true
                    text: root.text
                    wrapMode: Text.Wrap
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: root.textSize
                    color: root.colContent
                }

                // Transliteration: the same words in the reader's script.
                Rectangle {
                    id: transliterationBlock
                    Layout.fillWidth: true
                    visible: root.transliteration.length > 0
                    implicitHeight: transliterationRow.implicitHeight + ClockStyle.gap * 2
                    radius: Appearance.rounding.large
                    color: ColorUtils.applyAlpha(root.colContent, 0.1)

                    RowLayout {
                        id: transliterationRow
                        anchors {
                            fill: parent
                            margins: ClockStyle.gap
                            leftMargin: ClockStyle.gapLarge
                        }
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: root.transliteration
                            wrapMode: Text.Wrap
                            font.pixelSize: ClockStyle.textNormal
                            font.italic: true
                            color: root.colContent
                            opacity: 0.9
                        }

                        ClockCardAction {
                            Layout.alignment: Qt.AlignTop
                            symbol: "content_copy"
                            tip: Translation.tr("Copy transliteration")
                            colContent: root.colContent
                            onClicked: root.copy(root.transliteration)
                        }
                    }
                }

                // ── Alternatives ────────────────────────────────────────
                // Other ways to say it: word senses by part of speech, or whole
                // rephrasings for a sentence. A chip copies itself.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: ClockStyle.gapSmall
                    visible: root.hasAlternatives
                    spacing: ClockStyle.gap

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Alternatives")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: root.colContent
                        opacity: 0.72
                    }

                    Repeater {
                        model: root.dictionary

                        delegate: ColumnLayout {
                            id: posGroup
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                Layout.fillWidth: true
                                text: posGroup.modelData.pos
                                font.family: ClockStyle.fontTitle
                                font.variableAxes: ClockStyle.axesTitle
                                font.pixelSize: ClockStyle.textNormal + 1
                                color: root.colContent
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: ClockStyle.gapTiny + 2

                                Repeater {
                                    model: posGroup.modelData.words

                                    delegate: AlternativeChip {
                                        required property var modelData
                                        value: modelData.word
                                        tip: modelData.back.join(", ")
                                        maxWidth: posGroup.width
                                    }
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        visible: root.alternatives.length > 0
                        spacing: ClockStyle.gapTiny + 2

                        Repeater {
                            model: root.alternatives

                            delegate: AlternativeChip {
                                required property string modelData
                                value: modelData
                                maxWidth: resultColumn.width
                            }
                        }
                    }
                }
            }
        }

        // ── Empty state ─────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.hasResult && !root.failed

            ColumnLayout {
                id: emptyState
                anchors.centerIn: parent
                width: Math.min(parent.width, 300)
                spacing: ClockStyle.gapSmall

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: ClockStyle.gapSmall
                    text: "forum"
                    iconSize: 40
                    padding: 22
                    shape: MaterialShape.Shape.SoftBurst
                    color: ColorUtils.applyAlpha(root.colContent, 0.14)
                    colSymbol: root.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Nothing to translate yet")
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textTitle
                    color: root.colContent
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.emptyHint
                    font.pixelSize: ClockStyle.textNormal
                    color: root.colContent
                    opacity: 0.8
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── Error state ─────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.failed

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, 300)
                spacing: ClockStyle.gapSmall

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: ClockStyle.gapSmall
                    text: root.error === "missing-trans" ? "extension_off" : "cloud_off"
                    iconSize: 36
                    padding: 20
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: ColorUtils.applyAlpha(root.colContent, 0.14)
                    colSymbol: root.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.errorTitle
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textTitle
                    color: root.colContent
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.errorDetail
                    font.pixelSize: ClockStyle.textNormal
                    color: root.colContent
                    opacity: 0.8
                    wrapMode: Text.Wrap
                }

                LimitsTintButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: ClockStyle.gapSmall
                    visible: root.error !== "missing-trans"
                    solid: true
                    colContent: root.colContent
                    colSolidContent: root.colPane
                    symbol: "refresh"
                    label: Translation.tr("Try again")
                    onClicked: root.retryRequested()
                }
            }
        }

        // ── Actions ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasResult && !root.failed
            spacing: ClockStyle.gapSmall

            LimitsTintButton {
                solid: true
                colContent: root.colContent
                colSolidContent: root.colPane
                symbol: copiedTimer.running ? "check" : "content_copy"
                label: copiedTimer.running ? Translation.tr("Copied") : Translation.tr("Copy")
                onClicked: root.copy(root.text)
            }

            LimitsTintButton {
                colContent: root.colContent
                symbol: "travel_explore"
                label: Translation.tr("Search")
                onClicked: {
                    let url = Config.options.search.engineBaseUrl + encodeURIComponent(root.text);
                    for (let site of Config.options.search.excludedSites)
                        url += ` -site:${site}`;
                    Qt.openUrlExternally(url);
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }

    /// A tinted chip on the pane: copies its text, says so for a moment.
    component AlternativeChip: RippleButton {
        id: chip
        property string value: ""
        property string tip: ""
        property real maxWidth: 200
        readonly property bool copied: root.copiedValue === chip.value

        leftPadding: 0
        rightPadding: 0
        implicitHeight: Math.max(ClockStyle.chipHeight - 2, chipRow.implicitHeight + ClockStyle.gapSmall * 2)
        implicitWidth: Math.min(chip.maxWidth, chipRow.implicitWidth + ClockStyle.gap * 2)
        buttonRadius: ClockStyle.pill(ClockStyle.chipHeight - 2)
        buttonRadiusPressed: ClockStyle.radiusSmall
        colBackground: chip.copied ? root.colContent : ColorUtils.applyAlpha(root.colContent, 0.12)
        colBackgroundHover: chip.copied ? root.colContent : ColorUtils.applyAlpha(root.colContent, 0.2)
        colRipple: ColorUtils.applyAlpha(root.colContent, 0.28)
        onClicked: root.copyAlternative(chip.value)

        contentItem: Item {
            RowLayout {
                id: chipRow
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    right: parent.right
                    leftMargin: ClockStyle.gap
                    rightMargin: ClockStyle.gap
                }
                spacing: ClockStyle.gapTiny

                MaterialSymbol {
                    visible: chip.copied
                    text: "check"
                    iconSize: ClockStyle.iconSmall
                    color: root.colPane
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: chip.maxWidth - ClockStyle.gap * 2 - (chip.copied ? ClockStyle.iconSmall + ClockStyle.gapTiny : 0)
                    text: chip.value
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    color: chip.copied ? root.colPane : root.colContent
                    wrapMode: Text.Wrap
                }
            }
        }

        StyledToolTip {
            text: chip.tip.length > 0 ? chip.tip : Translation.tr("Copy")
        }
    }
}
