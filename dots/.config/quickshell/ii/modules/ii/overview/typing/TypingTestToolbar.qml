pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    property var engine: null
    property var languages: []
    property bool controlsEnabled: engine?.state === "ready" || engine?.state === "finished"
    signal requestMode(string mode)
    signal requestTime(int seconds)
    signal requestWords(int count)
    signal requestLanguage(string languageId)
    signal requestTogglePunctuation()
    signal requestToggleNumbers()

    function cycleLanguage() {
        if (root.languages.length === 0)
            return;
        const current = root.languages.findIndex(language => language.id === root.engine?.languagePack?.id);
        const next = root.languages[(current + 1 + root.languages.length) % root.languages.length];
        root.requestLanguage(next.id);
    }

    Layout.fillWidth: true
    spacing: Appearance.sizes.elevationMargin / 2
    opacity: engine?.state === "running" ? 0.58 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.sizes.elevationMargin / 2

        Repeater {
            model: [
                { id: "time", label: qsTr("time") },
                { id: "words", label: qsTr("words") },
                { id: "zen", label: qsTr("zen") }
            ]

            delegate: RippleButton {
                id: modeBtn
                required property var modelData
                enabled: root.controlsEnabled
                implicitWidth: modeLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: Appearance.sizes.elevationMargin * 3
                buttonRadius: Appearance.rounding.full
                colBackground: root.engine?.mode === modeBtn.modelData.id
                    ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: root.engine?.mode === modeBtn.modelData.id
                    ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                colRipple: root.engine?.mode === modeBtn.modelData.id
                    ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.requestMode(modeBtn.modelData.id)

                StyledText {
                    id: modeLabel
                    anchors.centerIn: parent
                    text: modeBtn.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: root.engine?.mode === modeBtn.modelData.id ? Font.DemiBold : Font.Normal
                    color: root.engine?.mode === modeBtn.modelData.id
                        ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        Item { Layout.fillWidth: true }

        Repeater {
            model: [
                { property: "punctuation", icon: "format_quote", label: qsTr("Punctuation") },
                { property: "numbers", icon: "123", label: qsTr("Numbers") }
            ]

            delegate: RippleButton {
                id: toggleBtn
                required property var modelData
                readonly property bool active: Boolean(root.engine?.[toggleBtn.modelData.property])
                enabled: root.controlsEnabled
                implicitWidth: Appearance.sizes.elevationMargin * 3
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: toggleBtn.active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: toggleBtn.active ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                colRipple: toggleBtn.active ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                onClicked: toggleBtn.modelData.property === "punctuation"
                    ? root.requestTogglePunctuation() : root.requestToggleNumbers()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: toggleBtn.modelData.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: toggleBtn.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                }
                StyledToolTip { text: toggleBtn.modelData.label }
            }
        }

        RippleButton {
            id: languageButton
            enabled: root.controlsEnabled
            implicitWidth: languageText.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: Appearance.sizes.elevationMargin * 3
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSurfaceContainerHigh
            colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
            colRipple: Appearance.colors.colSurfaceContainerHighestActive
            onClicked: root.cycleLanguage()

            RowLayout {
                anchors.centerIn: parent
                spacing: Appearance.sizes.elevationMargin / 3
                MaterialSymbol {
                    text: "language"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    id: languageText
                    text: root.languages.find(language => language.id === root.engine?.languagePack?.id)?.label
                        ?? root.engine?.languagePack?.name ?? qsTr("Language")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                }
            }

            StyledToolTip { text: qsTr("Change language") }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.engine?.mode !== "zen"
        spacing: Appearance.sizes.elevationMargin / 3

        Repeater {
            model: root.engine?.mode === "time" ? [15, 30, 60, 120] : [10, 25, 50, 100]

            delegate: RippleButton {
                id: presetBtn
                required property int modelData
                readonly property bool selected: root.engine?.mode === "time"
                    ? root.engine?.timeLimitSeconds === presetBtn.modelData
                    : root.engine?.wordLimit === presetBtn.modelData
                enabled: root.controlsEnabled
                implicitWidth: presetText.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: Appearance.sizes.elevationMargin * 3
                buttonRadius: Appearance.rounding.full
                colBackground: selected ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSurfaceContainerLow
                colBackgroundHover: selected ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colSurfaceContainerHigh
                colRipple: selected ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.engine?.mode === "time"
                    ? root.requestTime(presetBtn.modelData) : root.requestWords(presetBtn.modelData)
                StyledText {
                    id: presetText
                    anchors.centerIn: parent
                    text: root.engine?.mode === "time" ? presetBtn.modelData + "s" : String(presetBtn.modelData)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: presetBtn.selected ? Font.DemiBold : Font.Normal
                    color: presetBtn.selected ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurfaceVariant
                }
            }
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: root.engine?.mode === "zen" ? qsTr("Shift+Enter to finish") : qsTr("Ctrl+R to restart")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
