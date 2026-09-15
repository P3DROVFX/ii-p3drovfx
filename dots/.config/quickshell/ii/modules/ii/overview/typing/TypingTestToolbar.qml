pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * One row of grouped pills over the typing stage: modifiers, mode, and the
 * presets for the selected mode, with the panel's own settings and history
 * entries kept apart on the right so the mode controls stay centred.
 *
 * The whole row de-emphasises while a test runs — the words are the hero and
 * changing a parameter mid-test is not allowed anyway.
 */
Item {
    id: root

    required property var engine
    property bool settingsOpen: false
    property bool historyOpen: false
    property bool statsOpen: false
    readonly property bool controlsEnabled: root.engine?.state !== "running"

    signal requestMode(string mode)
    signal requestZenGuided(bool guided)
    signal requestTime(int seconds)
    signal requestWords(int count)
    signal requestTogglePunctuation
    signal requestToggleNumbers
    signal requestSettings
    signal requestHistory
    signal requestStats

    readonly property real pillHeight: 36
    /** Gap between the group track and the shape sitting inside it. */
    readonly property real trackPadding: 4
    readonly property var presets: root.engine?.mode === "time" ? [15, 30, 60, 120] : [10, 25, 50, 100]

    implicitHeight: root.pillHeight
    opacity: root.engine?.state === "running" ? 0.4 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // Two surfaces, the way a tab bar reads: a tonal track for the whole group
    // and a filled shape on the one that is selected. Colouring the label alone
    // was not enough to tell the active mode apart at a glance.
    component PillGroup: Rectangle {
        id: pillGroup
        default property alias groupContent: pillRow.data
        implicitWidth: pillRow.implicitWidth + root.trackPadding * 2
        implicitHeight: root.pillHeight
        radius: Appearance.rounding.full
        color: Appearance.colors.colSurfaceContainerHigh

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 2
        }
    }

    component PillButton: RippleButton {
        id: pillButton
        property string pillIcon: ""
        property string pillLabel: ""
        property bool active: false
        readonly property color contentColor: pillButton.active
            ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant

        implicitWidth: pillContent.implicitWidth + (pillButton.pillLabel.length > 0 ? 22 : 14)
        implicitHeight: root.pillHeight - root.trackPadding * 2
        buttonRadius: Appearance.rounding.full
        colBackground: pillButton.active ? Appearance.colors.colPrimary : "transparent"
        colBackgroundHover: pillButton.active
            ? Appearance.colors.colPrimaryHover : Appearance.colors.colSurfaceContainerHighestHover
        colRipple: pillButton.active
            ? Appearance.colors.colPrimaryActive : Appearance.colors.colSurfaceContainerHighestActive

        RowLayout {
            id: pillContent
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                visible: pillButton.pillIcon.length > 0
                text: pillButton.pillIcon
                iconSize: Appearance.font.pixelSize.normal
                fill: pillButton.active ? 1 : 0
                color: pillButton.contentColor

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
            }

            StyledText {
                visible: pillButton.pillLabel.length > 0
                text: pillButton.pillLabel
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: pillButton.active ? Font.DemiBold : Font.Normal
                color: pillButton.contentColor

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
            }
        }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: 10

        PillGroup {
            // Both modifiers decorate the generated target, so they follow the
            // target rather than the mode: free zen has nothing to decorate,
            // guided zen has exactly what the other modes have.
            visible: Boolean(root.engine?.hasTarget)

            PillButton {
                pillIcon: "format_quote"
                pillLabel: Translation.tr("punctuation")
                active: Boolean(root.engine?.punctuation)
                enabled: root.controlsEnabled
                onClicked: root.requestTogglePunctuation()
            }
            PillButton {
                pillIcon: "tag"
                pillLabel: Translation.tr("numbers")
                active: Boolean(root.engine?.numbers)
                enabled: root.controlsEnabled
                onClicked: root.requestToggleNumbers()
            }
        }

        PillGroup {
            Repeater {
                model: [
                    { id: "time", icon: "schedule", label: Translation.tr("time") },
                    { id: "words", icon: "text_fields", label: Translation.tr("words") },
                    { id: "zen", icon: "air", label: Translation.tr("zen") }
                ]

                delegate: PillButton {
                    required property var modelData
                    pillIcon: modelData.icon
                    pillLabel: modelData.label
                    active: root.engine?.mode === modelData.id
                    enabled: root.controlsEnabled
                    onClicked: root.requestMode(modelData.id)
                }
            }
        }

        // Zen's own pair, standing in for the presets the other modes get:
        // free typing, or the same generated words with no limit on them.
        PillGroup {
            visible: root.engine?.mode === "zen"

            PillButton {
                pillIcon: "air"
                pillLabel: Translation.tr("free")
                active: !root.engine?.zenGuided
                enabled: root.controlsEnabled
                onClicked: root.requestZenGuided(false)
            }
            PillButton {
                pillIcon: "match_case"
                pillLabel: Translation.tr("guided")
                active: Boolean(root.engine?.zenGuided)
                enabled: root.controlsEnabled
                onClicked: root.requestZenGuided(true)
            }
        }

        PillGroup {
            visible: root.engine?.mode !== "zen"

            Repeater {
                model: root.presets

                delegate: PillButton {
                    required property int modelData
                    pillLabel: String(modelData)
                    active: root.engine?.mode === "time"
                        ? root.engine?.timeLimitSeconds === modelData
                        : root.engine?.wordLimit === modelData
                    enabled: root.controlsEnabled
                    onClicked: root.engine?.mode === "time"
                        ? root.requestTime(modelData) : root.requestWords(modelData)
                }
            }
        }

        // Panel-level entries rather than test parameters, so they get their
        // own group at the end instead of sitting among the presets.
        PillGroup {
            Repeater {
                model: [
                    { id: "stats", icon: "monitoring", tip: Translation.tr("Statistics") },
                    { id: "history", icon: "history", tip: Translation.tr("Score history") },
                    { id: "settings", icon: "tune", tip: Translation.tr("Typing test settings") }
                ]

                delegate: PillButton {
                    id: circleButton
                    required property var modelData

                    pillIcon: circleButton.modelData.icon
                    active: circleButton.modelData.id === "settings" ? root.settingsOpen
                        : (circleButton.modelData.id === "history" ? root.historyOpen : root.statsOpen)
                    onClicked: {
                        if (circleButton.modelData.id === "settings")
                            root.requestSettings();
                        else if (circleButton.modelData.id === "history")
                            root.requestHistory();
                        else
                            root.requestStats();
                    }

                    StyledToolTip { text: circleButton.modelData.tip }
                }
            }
        }
    }
}
