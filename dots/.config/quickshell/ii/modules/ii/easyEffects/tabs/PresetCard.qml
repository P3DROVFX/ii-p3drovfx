pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.easyEffects.components

/**
 * One preset as a card: its badge, the tone curve its equalizers draw, its name and how
 * many effects it chains. The preset in use is a primary container, an idle one a plain
 * row. "In use" and "Default" sit where the card's own actions (edit, make default, more)
 * appear while the pointer is on it, so the corner never holds both.
 */
Rectangle {
    id: root

    required property string name
    required property var info
    property bool inUse: false
    property bool isDefault: false
    property string deviceName: ""

    signal chosen()
    signal editRequested()
    signal defaultToggled()
    signal moreRequested()

    readonly property bool engaged: cardHover.hovered || editAction.activeFocus || starAction.activeFocus || moreAction.activeFocus
    readonly property bool showActions: root.engaged
    readonly property color colContent: root.inUse ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colOnSurface
    readonly property color colSubContent: root.inUse ? EasyEffectsStyle.tint(EasyEffectsStyle.colOnPrimaryContainer, EasyEffectsStyle.tintSubtext) : EasyEffectsStyle.colSubtext
    /// Each card is drawn to its own scale, so a gentle preset still shows its shape.
    readonly property real curveRange: Math.max(EasyEffectsStyle.gapSmall - 2, root.info.curve.reduce((peak, db) => Math.max(peak, Math.abs(db)), 0) / 0.75)
    readonly property bool isFlat: root.info.known && root.info.hasEqualizer && root.info.curve.every(db => Math.abs(db) < 0.05)
    readonly property string family: EasyEffects.familyOf(root.name)
    readonly property string effects: root.info.count === 1 ? Translation.tr("1 effect") : Translation.tr("%1 effects").arg(root.info.count)

    implicitHeight: EasyEffectsStyle.presetCardHeight
    radius: EasyEffectsStyle.radiusCard
    color: root.inUse ? EasyEffectsStyle.colPrimaryContainer
        : root.engaged ? EasyEffectsStyle.colRow : EasyEffectsStyle.colPane

    Behavior on color {
        animation: EasyEffectsStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.chosen()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: EasyEffectsStyle.cardPadding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: EasyEffectsStyle.gapSmall

            EasyEffectsBadge {
                size: EasyEffectsStyle.presetBadge
                text: EasyEffects.iconFor(root.name)
                // A preset that leaves the tone alone is the absence of a shape: a circle.
                shape: root.isFlat ? MaterialShape.Shape.Circle : EasyEffectsStyle.shapeFor(root.name)
                color: root.inUse ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colSecondaryContainer
                colSymbol: root.inUse ? EasyEffectsStyle.colPrimaryContainer : EasyEffectsStyle.colOnSecondaryContainer
            }

            Item {
                Layout.fillWidth: true
            }

            // One slot for both: the state pills and the actions share it, so the header is as
            // wide as the wider of the two (never their sum, which pushed the whole card's
            // content past its edge) and the swap is a crossfade with a small slide.
            Item {
                id: trailing
                Layout.preferredWidth: Math.max(pills.implicitWidth, actions.implicitWidth)
                Layout.preferredHeight: Math.max(pills.implicitHeight, actions.implicitHeight)
                Layout.minimumWidth: 0

                RowLayout {
                    id: pills
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: EasyEffectsStyle.gapSmall
                    opacity: root.showActions ? 0 : 1
                    visible: opacity > 0
                    transform: Translate {
                        x: root.showActions ? EasyEffectsStyle.gapSmall : 0
                        Behavior on x {
                            enabled: !EasyEffectsStyle.reducedMotion
                            animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
                        }
                    }

                    Behavior on opacity {
                        animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
                    }

                    EasyEffectsPill {
                        visible: root.isDefault && !root.inUse
                        symbol: "star"
                        label: Translation.tr("Default")
                        colContent: EasyEffectsStyle.colOnTertiaryContainer
                        colFill: EasyEffectsStyle.colTertiaryContainer
                    }

                    EasyEffectsPill {
                        visible: root.inUse
                        symbol: root.isDefault ? "star" : "check"
                        filledSymbol: root.isDefault
                        label: root.isDefault ? Translation.tr("In use · device default") : Translation.tr("In use")
                        colContent: root.colContent
                    }
                }

                RowLayout {
                    id: actions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: EasyEffectsStyle.gapSmall
                    opacity: root.showActions ? 1 : 0
                    visible: opacity > 0
                    transform: Translate {
                        x: root.showActions ? 0 : -EasyEffectsStyle.gapSmall
                        Behavior on x {
                            enabled: !EasyEffectsStyle.reducedMotion
                            animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
                        }
                    }

                    Behavior on opacity {
                        animation: EasyEffectsStyle.motionFast.numberAnimation.createObject(this)
                    }

                    EasyEffectsCardAction {
                        id: editAction
                        symbol: "edit"
                        tip: Translation.tr("Edit effects")
                        colContent: root.colContent
                        onClicked: root.editRequested()
                    }

                    EasyEffectsCardAction {
                        id: starAction
                        symbol: "star"
                        filledSymbol: root.isDefault
                        tip: root.isDefault ? Translation.tr("Stop being the default for %1").arg(root.deviceName)
                            : Translation.tr("Make default for %1").arg(root.deviceName)
                        colContent: root.colContent
                        onClicked: root.defaultToggled()
                    }

                    EasyEffectsCardAction {
                        id: moreAction
                        symbol: "more_vert"
                        tip: Translation.tr("More")
                        colContent: root.colContent
                        onClicked: root.moreRequested()
                    }
                }
            }
        }

        // The tone curve when an equalizer shapes the sound; otherwise the app's wave, so a
        // preset without one doesn't show a bare line that looks like a mistake.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: EasyEffectsStyle.gapSmall
            Layout.bottomMargin: EasyEffectsStyle.gapSmall
            Layout.minimumHeight: EasyEffectsStyle.pillHeight
            opacity: root.inUse ? EasyEffectsStyle.opacityCurveActive : EasyEffectsStyle.opacityCurve

            ResponseCurve {
                anchors.fill: parent
                visible: root.info.hasEqualizer
                lineWidth: EasyEffectsStyle.gapTiny - 0.5
                fill: false
                range: root.curveRange
                values: root.info.curve
                colLine: root.inUse ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colPrimary
            }

            WavyLine {
                anchors.fill: parent
                visible: !root.info.hasEqualizer
                lineWidth: EasyEffectsStyle.gapTiny - 0.5
                amplitudeMultiplier: root.info.known && root.info.count > 0 ? 1.8 : 1
                color: root.inUse ? EasyEffectsStyle.colOnPrimaryContainer : EasyEffectsStyle.colPrimary
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: EasyEffectsStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: EasyEffects.shortName(root.name)
                elide: Text.ElideRight
                font.family: EasyEffectsStyle.fontTitle
                font.variableAxes: EasyEffectsStyle.axesName
                font.pixelSize: EasyEffectsStyle.textCardTitle
                color: root.colContent
            }

            StyledText {
                Layout.maximumWidth: root.width * 0.45
                text: root.family.length > 0 ? `${root.family} · ${root.effects}` : root.effects
                elide: Text.ElideRight
                font.pixelSize: EasyEffectsStyle.textSmall
                color: root.colSubContent
            }
        }
    }
}
