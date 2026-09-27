import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One city: day or night as a shape, its name and how far it is from here, and its time.
 *
 * Hover works like the dashboard's to-do rows: the actions slide in from the right on one
 * animated extent that also elides the name, so nothing jumps and a long city name gets
 * its tooltip instead of pushing the time off the card. The time never hides.
 */
Rectangle {
    id: root

    required property int clockIndex
    property date now: new Date()
    property bool showSeconds: false
    property int count: 1

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real timeSize: Math.round(Math.max(30, Math.min(root.height * 0.52, root.width * 0.1)))

    readonly property var entry: WorldClockService.clocks[root.clockIndex] ?? ({})
    readonly property string tz: String(root.entry.tz ?? "")
    readonly property bool night: WorldClockService.isNight(root.tz, root.now)
    readonly property string offsetText: WorldClockService.relativeOffsetLabel(root.tz, root.now)
    readonly property bool engaged: cardHover.hovered || renameButton.activeFocus || deleteButton.activeFocus

    signal renameRequested()

    implicitHeight: ClockStyle.worldCardHeight
    radius: ClockStyle.radiusCard
    color: root.engaged ? ClockStyle.colIdleCardHover : ClockStyle.colIdleCard

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: ClockStyle.cardPadding
            rightMargin: ClockStyle.cardPadding + 4
        }
        spacing: ClockStyle.gapLarge

        MaterialShapeWrappedMaterialSymbol {
            text: root.night ? "dark_mode" : "light_mode"
            iconSize: 28
            padding: 18
            fill: 1
            shape: root.night ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Sunny
            color: root.night ? ClockStyle.colSecondaryContainer : ClockStyle.colTertiaryContainer
            colSymbol: root.night ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnTertiaryContainer
            rotation: root.engaged ? 30 : 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                id: nameText
                Layout.fillWidth: true
                text: WorldClockService.displayName(root.entry)
                elide: Text.ElideRight
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textTitle
                color: ClockStyle.colOnSurface

                HoverHandler {
                    id: nameHover
                }
                StyledToolTip {
                    extraVisibleCondition: nameHover.hovered && nameText.truncated
                    text: nameText.text
                }
            }

            StyledText {
                id: detailText
                Layout.fillWidth: true
                text: {
                    const parts = [WorldClockService.dayRelationLabel(root.tz, root.now)];
                    parts.push(root.offsetText.length > 0 ? root.offsetText : Translation.tr("Same time"));
                    const abbreviation = WorldClockService.abbreviation(root.tz);
                    if (abbreviation.length > 0 && !/^[+-]/.test(abbreviation))
                        parts.push(abbreviation);
                    return parts.join(" · ");
                }
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: WorldClockService.formatDate(root.tz, root.now, "dddd, d MMMM")
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
                opacity: 0.8
            }
        }

        // One animated extent: the actions' reveal and the name's elision move together.
        Item {
            id: actionSlot
            property real revealProgress: root.engaged ? 1 : 0

            Layout.preferredWidth: (actionRow.implicitWidth + 4) * actionSlot.revealProgress
            Layout.preferredHeight: actionRow.implicitHeight
            clip: true

            Behavior on revealProgress {
                animation: ClockStyle.motionFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: actionRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                opacity: actionSlot.revealProgress
                enabled: root.engaged

                ClockCardAction {
                    symbol: "arrow_upward"
                    tip: Translation.tr("Move up")
                    enabled: root.engaged && root.clockIndex > 0
                    onClicked: WorldClockService.moveClock(root.clockIndex, root.clockIndex - 1)
                }
                ClockCardAction {
                    symbol: "arrow_downward"
                    tip: Translation.tr("Move down")
                    enabled: root.engaged && root.clockIndex < root.count - 1
                    onClicked: WorldClockService.moveClock(root.clockIndex, root.clockIndex + 1)
                }
                ClockCardAction {
                    id: renameButton
                    symbol: "edit"
                    tip: Translation.tr("Rename")
                    onClicked: root.renameRequested()
                }
                ClockCardAction {
                    id: deleteButton
                    symbol: "delete"
                    tip: Translation.tr("Remove")
                    danger: true
                    onClicked: WorldClockService.removeClock(root.clockIndex)
                }
            }
        }

        RowLayout {
            spacing: 0

            StyledText {
                text: WorldClockService.formatHourMinute(root.tz, root.now)
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: root.timeSize
                color: ClockStyle.colOnSurface
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignBottom
                Layout.leftMargin: 3
                Layout.bottomMargin: root.timeSize * 0.12
                spacing: -2

                StyledText {
                    visible: text.length > 0
                    text: WorldClockService.meridiem(root.tz, root.now)
                    font.pixelSize: root.timeSize * 0.3
                    color: ClockStyle.colSubtext
                }

                StyledText {
                    visible: root.showSeconds
                    text: WorldClockService.formatDate(root.tz, root.now, "ss")
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: root.timeSize * 0.4
                    color: ClockStyle.colPrimary
                }
            }
        }
    }
}
