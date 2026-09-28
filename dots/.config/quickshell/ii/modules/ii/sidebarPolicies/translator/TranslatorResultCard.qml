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

    readonly property bool hasResult: root.text.length > 0
    readonly property color colPane: root.hasResult ? ClockStyle.colPrimary : ClockStyle.colPrimaryContainer
    readonly property color colContent: root.hasResult ? ClockStyle.colOnPrimary : ClockStyle.colOnPrimaryContainer

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
        copiedTimer.restart();
    }

    Timer {
        id: copiedTimer
        interval: 1600
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
                    text: root.busy ? Translation.tr("Translating…") : root.targetName
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colContent
                    opacity: 0.8
                    elide: Text.ElideRight
                }
            }
        }

        // ── Result ──────────────────────────────────────────────────────
        StyledFlickable {
            id: resultFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.hasResult
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
            }
        }

        // ── Empty state ─────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.hasResult

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
                    text: Translation.tr("Type or paste text above — press / from anywhere in the tab to start")
                    font.pixelSize: ClockStyle.textNormal
                    color: root.colContent
                    opacity: 0.8
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── Actions ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasResult
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
                    let url = Config.options.search.engineBaseUrl + root.text;
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
}
