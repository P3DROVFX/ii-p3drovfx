pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.translator
import qs.modules.ii.background.widgets

/*
 * Translator (1x2), the Policies sidebar's translator on the desktop. On top,
 * the language pair as two tiles hinged by the swap shape (it turns half a
 * turn per swap); a tap on a tile steps through the quick languages set in
 * Settings. Below, the text to translate - typed after a click, or pasted -
 * and the translation as the hero pane, in the accent, with copy and listen.
 * Same engine, cache and language pair as the sidebar.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "translator_widget"
    designWidth: 240
    designHeight: 492

    readonly property real padding: 12
    readonly property real barHeight: 58
    readonly property real swapSize: 40
    readonly property real sourceHeight: 150
    // The text being translated, for callers that fill it (and the preview).
    property alias sourceText: field.text

    readonly property var quickLanguages: {
        const list = Array.from(root.options?.quickLanguages ?? []).map(String).filter(code => code.length > 0);
        return list.length > 0 ? list : ["en", "pt-BR", "es", "fr", "de", "ja"];
    }

    Component.onCompleted: TranslatorService.ensureLanguages()

    TranslatorSession {
        id: session
        text: root.isPreview ? "" : field.text
    }

    readonly property string sourceName: TranslatorService.sourceLanguage === "auto" && session.detected
        ? TranslatorService.displayName(session.detected)
        : TranslatorService.displayName(TranslatorService.sourceLanguage)
    readonly property string targetName: TranslatorService.displayName(TranslatorService.targetLanguage)

    function nextIn(list, current) {
        const codes = list.map(code => TranslatorService.codeOf(code).toLowerCase());
        const at = codes.indexOf(TranslatorService.codeOf(current).toLowerCase());
        return list[(at + 1) % list.length];
    }

    function cycleSource() {
        TranslatorService.setSource(root.nextIn(["auto"].concat(root.quickLanguages), TranslatorService.sourceLanguage));
    }

    function cycleTarget() {
        // Never onto the source itself.
        let next = root.nextIn(root.quickLanguages, TranslatorService.targetLanguage);
        if (TranslatorService.sameLanguage(next, TranslatorService.sourceLanguage) && root.quickLanguages.length > 1)
            next = root.nextIn(root.quickLanguages, next);
        TranslatorService.setTarget(next);
    }

    function swap() {
        const translation = session.translation;
        if (!TranslatorService.swap(session.detected))
            return;
        if (translation.length > 0 && !session.busy)
            field.text = translation;
    }

    // ── Language pair ──
    Item {
        id: bar
        x: root.padding
        y: root.padding
        width: root.designWidth - root.padding * 2
        height: root.barHeight

        readonly property real tileWidth: (width - root.swapSize + 12) / 2

        LanguageTile {
            anchors.left: parent.left
            width: bar.tileWidth
            height: parent.height
            caption: TranslatorService.sourceLanguage === "auto" && session.detected ? Translation.tr("Detected") : Translation.tr("From")
            language: root.sourceName
            innerSide: "right"
            onTapped: root.cycleSource()
        }

        LanguageTile {
            anchors.right: parent.right
            width: bar.tileWidth
            height: parent.height
            caption: Translation.tr("To")
            language: root.targetName
            innerSide: "left"
            onTapped: root.cycleTarget()
        }

        // The hinge: turns half a turn per swap, counted, so it never unwinds.
        Item {
            anchors.centerIn: parent
            width: root.swapSize
            height: root.swapSize

            MaterialShape {
                anchors.fill: parent
                shape: swapHover.hovered && swapButton.canSwap ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Cookie9Sided
                color: WidgetColorScheme.accentColor
                rotation: TranslatorService.swapTurns * 180

                Behavior on rotation {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "swap_horiz"
                iconSize: 20
                color: WidgetColorScheme.onAccentColor
                opacity: swapButton.canSwap ? 1 : 0.45
            }

            Item {
                id: swapButton
                anchors.fill: parent
                readonly property bool canSwap: root.actionsEnabled
                    && (TranslatorService.sourceLanguage !== "auto" || session.detected.length > 0)

                HoverHandler {
                    id: swapHover
                    cursorShape: swapButton.canSwap ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
                TapHandler {
                    enabled: swapButton.canSwap
                    onTapped: root.swap()
                }
            }
        }
    }

    // ── Source ──
    Rectangle {
        id: sourcePane
        x: root.padding
        anchors.top: bar.bottom
        anchors.topMargin: 8
        width: bar.width
        height: root.sourceHeight
        radius: Appearance.rounding.normal
        color: entry.holding ? ColorUtils.mix(WidgetColorScheme.accentColor, WidgetColorScheme.pillBgColor, 0.1) : WidgetColorScheme.pillBgColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Flickable {
            id: sourceFlick
            x: 14
            y: 12
            width: parent.width - 28
            height: parent.height - 12 - 44
            clip: true
            contentWidth: width
            contentHeight: field.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            TextEdit {
                id: field
                width: sourceFlick.width
                enabled: root.actionsEnabled
                wrapMode: TextEdit.Wrap
                color: WidgetColorScheme.textColorOnBg
                selectionColor: WidgetColorScheme.accentColor
                selectedTextColor: WidgetColorScheme.onAccentColor
                font.family: Appearance.font.family.main
                font.pixelSize: field.text.length > 60 ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
                cursorVisible: entry.holding

                Keys.onEscapePressed: entry.end()
                onCursorRectangleChanged: {
                    if (cursorRectangle.y + cursorRectangle.height > sourceFlick.contentY + sourceFlick.height)
                        sourceFlick.contentY = cursorRectangle.y + cursorRectangle.height - sourceFlick.height;
                }

                StyledText {
                    visible: field.text.length === 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: entry.holding ? Translation.tr("Type to translate") : Translation.tr("Click to type, or paste")
                    color: WidgetColorScheme.subtextColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
                }
            }
        }

        // Arms the keyboard on the first click; then clicks go to the text.
        MouseArea {
            anchors.fill: sourceFlick
            enabled: root.actionsEnabled && !entry.holding
            cursorShape: Qt.IBeamCursor
            onClicked: entry.begin()
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            spacing: 6

            WidgetButton {
                height: 32
                width: 88
                symbol: "content_paste"
                symbolSize: 16
                label: Translation.tr("Paste")
                labelSize: Appearance.font.pixelSize.smaller
                colFill: WidgetColorScheme.cardBgColor
                colContent: WidgetColorScheme.textColorOnBg
                onClicked: field.text = String(Quickshell.clipboardText ?? "").trim()
            }
        }

        WidgetButton {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: 32
            height: 32
            visible: field.text.length > 0
            symbol: "close"
            symbolSize: 16
            colFill: WidgetColorScheme.cardBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: {
                field.text = "";
                entry.end();
            }
        }
    }

    WidgetTextEntry {
        id: entry
        field: field
    }

    // ── Translation ──
    Rectangle {
        id: resultPane
        x: root.padding
        anchors.top: sourcePane.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        width: bar.width
        radius: Appearance.rounding.large
        color: session.error && session.hasInput ? WidgetColorScheme.warningColor : WidgetColorScheme.pillFillColor

        readonly property color contentColor: session.error && session.hasInput ? root.contentOn(WidgetColorScheme.warningColor) : WidgetColorScheme.textColorOnPillFill

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        StyledText {
            x: 16
            y: 14
            width: parent.width - 32
            elide: Text.ElideRight
            text: session.busy ? Translation.tr("Translating…") : root.targetName
            color: resultPane.contentColor
            opacity: 0.75
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.letterSpacing: 1
        }

        StyledText {
            id: resultText
            x: 16
            y: 36
            width: parent.width - 32
            height: parent.height - y - 56
            text: !session.hasInput ? Translation.tr("The translation shows here")
                : session.error ? Translation.tr("Couldn't translate. Check the connection or the translator setup.")
                : session.translation
            color: resultPane.contentColor
            opacity: session.hasInput && !session.error ? (session.busy ? 0.6 : 1) : 0.7
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            fontSizeMode: Text.Fit
            minimumPixelSize: 13
            font.family: Appearance.font.family.main
            font.pixelSize: session.hasInput && !session.error ? 30 : Appearance.font.pixelSize.larger
            font.variableAxes: ({ "wght": session.hasInput && !session.error ? 620 : 480, "wdth": 92, "ROND": 100, "opsz": 32 })

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            spacing: 6
            visible: session.translation.length > 0 && !session.error

            WidgetButton {
                width: 40
                height: 40
                readonly property bool speaking: TranslatorService.speakingKey === "widget:target"
                symbol: speaking ? "stop" : "volume_up"
                symbolSize: 20
                colFill: ColorUtils.applyAlpha(resultPane.contentColor, 0.14)
                colContent: resultPane.contentColor
                restRadius: speaking ? Appearance.rounding.small : root.pill(height)
                onClicked: TranslatorService.speak("widget:target", session.translation, session.targetCode)
            }

            WidgetButton {
                id: copyKey
                width: 40
                height: 40
                symbol: copiedTimer.running ? "check" : "content_copy"
                symbolSize: 20
                colFill: resultPane.contentColor
                colContent: resultPane.color
                restRadius: copiedTimer.running ? Appearance.rounding.small : root.pill(height)
                onClicked: {
                    Quickshell.clipboardText = session.translation;
                    copiedTimer.restart();
                }

                Timer {
                    id: copiedTimer
                    interval: 1600
                }
            }
        }
    }

    component LanguageTile: Rectangle {
        id: tile
        property string caption
        property string language
        property string innerSide: "right"
        signal tapped

        // Outer corners large, the corners facing the hinge small: one shape.
        readonly property real outer: Appearance.rounding.normal
        readonly property real inner: Appearance.rounding.verysmall
        topLeftRadius: tile.innerSide === "left" ? tile.inner : tile.outer
        bottomLeftRadius: tile.innerSide === "left" ? tile.inner : tile.outer
        topRightRadius: tile.innerSide === "right" ? tile.inner : tile.outer
        bottomRightRadius: tile.innerSide === "right" ? tile.inner : tile.outer
        color: tileHover.hovered && root.actionsEnabled ? ColorUtils.mix(WidgetColorScheme.textColorOnBg, WidgetColorScheme.pillBgColor, 0.08) : WidgetColorScheme.pillBgColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            x: tile.innerSide === "right" ? 12 : 12 + root.swapSize / 2 - 6
            width: parent.width - 24 - root.swapSize / 2 + 6
            spacing: 0

            StyledText {
                width: parent.width
                text: tile.caption
                elide: Text.ElideRight
                color: WidgetColorScheme.subtextColorOnBg
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
            }
            StyledText {
                width: parent.width
                text: tile.language
                elide: Text.ElideRight
                // Long endonyms narrow before they elide.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 12
                color: WidgetColorScheme.textColorOnBg
                font.pixelSize: Appearance.font.pixelSize.normal
                font.variableAxes: ({ "wght": 640, "wdth": 88, "ROND": 100 })
            }
        }

        HoverHandler {
            id: tileHover
            enabled: root.actionsEnabled
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: root.actionsEnabled
            onTapped: tile.tapped()
        }
    }
}
