import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services
import "FootballFormat.js" as Format

/**
 * The scoreboard hero, in a broadcast voice.
 *
 * Three equal columns, everything centred: each club on a Material shape that
 * morphs on hover (crest opens the club, the corner star follows it), its name
 * as a slanted condensed headline and its scorers; in the middle the score in
 * tall heavy digits — the trailing side drops to a light cut of the same face —
 * with the state under it. A live match takes the primary colour, the one state
 * the screen is about. A scalloped ornament, clipped by the card, turns one
 * full turn per hour of play; possession splits the foot of the card.
 */
Item {
    id: root

    property var match: null
    property var keyEvents: []
    property var stats: []
    property real layoutWidth: width
    signal teamActivated(var team)

    readonly property bool started: root.match ? root.match.state !== "pre" : false
    readonly property bool live: root.match?.state === "in"
    readonly property bool compact: root.layoutWidth < 820
    readonly property var locale: Qt.locale(Translation.languageCode)

    readonly property color colHero: root.live ? FootballStyle.colPrimary : FootballStyle.colPrimaryContainer
    readonly property color colOnHero: root.live ? FootballStyle.colOnPrimary : FootballStyle.colOnPrimaryContainer

    readonly property real homeGoals: parseFloat(root.match?.home?.score ?? "0") || 0
    readonly property real awayGoals: parseFloat(root.match?.away?.score ?? "0") || 0
    readonly property int scoreSize: Math.round(Math.max(72, Math.min(156, content.columnWidth * 0.44)))
    readonly property int nameSize: Math.round(Math.max(20, Math.min(38, content.columnWidth * 0.095)))
    readonly property var possession: root.stats.find(stat => stat.key === "possessionPct") ?? null
    // Minutes played, for the ornament's turn.
    readonly property real minute: {
        const value = parseInt(String(root.match?.clock ?? ""), 10);
        return isNaN(value) ? (root.match?.state === "post" ? 90 : 0) : value;
    }

    implicitHeight: content.implicitHeight + FootballStyle.gapHuge * 2 + (root.possession ? 34 : 0)

    function scorers(side) {
        return root.keyEvents.filter(event => (event.kind === "goal" || event.kind === "own") && event.side === side)
            .map(event => `${event.players[0] ?? ""} ${event.minute}${event.kind === "own" ? " (" + Translation.tr("OG") + ")" : ""}`);
    }

    // ── Surface with the clipped ornament ───────────────────────────────────
    Rectangle {
        id: heroMask
        width: surface.width
        height: surface.height
        radius: FootballStyle.radiusCard
        visible: false
        layer.enabled: true
    }

    Item {
        id: surface
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: heroMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Rectangle {
            anchors.fill: parent
            color: root.colHero
            Behavior on color {
                animation: FootballStyle.motionFast.colorAnimation.createObject(this)
            }
        }

        MaterialShape {
            implicitSize: root.height * 1.9
            x: root.width - implicitSize * 0.42
            y: (root.height - implicitSize) / 2
            shape: MaterialShape.Shape.SoftBurst
            color: root.colOnHero
            opacity: 0.08
            rotation: root.minute * 6
            Behavior on rotation {
                enabled: !FootballStyle.reducedMotion
                animation: FootballStyle.motionDefault.numberAnimation.createObject(this)
            }
        }
        MaterialShape {
            implicitSize: root.height * 1.3
            x: -implicitSize * 0.55
            y: root.height - implicitSize * 0.6
            shape: MaterialShape.Shape.Cookie12Sided
            color: root.colOnHero
            opacity: 0.06
        }

        // Possession across the foot of the card.
        Item {
            visible: root.possession !== null
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: FootballStyle.gapHuge
            anchors.rightMargin: FootballStyle.gapHuge
            anchors.bottomMargin: 14
            height: 22

            readonly property real share: root.possession ? root.possession.homeValue / Math.max(1, root.possession.homeValue + root.possession.awayValue) : 0.5

            StyledText {
                shouldUseNumberFont: false
                id: homePossession
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.possession?.home ?? ""
                font.pixelSize: FootballStyle.textNormal
                font.variableAxes: FootballStyle.axesScoreHeavy
                color: root.colOnHero
            }
            StyledText {
                shouldUseNumberFont: false
                id: awayPossession
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.possession?.away ?? ""
                font.pixelSize: FootballStyle.textNormal
                font.variableAxes: FootballStyle.axesScoreHeavy
                color: root.colOnHero
            }
            Item {
                anchors.left: homePossession.right
                anchors.right: awayPossession.left
                anchors.leftMargin: FootballStyle.gap
                anchors.rightMargin: FootballStyle.gap
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                Rectangle {
                    width: Math.max(height, parent.width * parent.parent.share - 2)
                    height: parent.height
                    radius: 3
                    color: root.colOnHero
                    Behavior on width {
                        enabled: !FootballStyle.reducedMotion
                        animation: FootballStyle.motionDefault.numberAnimation.createObject(this)
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    width: Math.max(height, parent.width * (1 - parent.parent.share) - 2)
                    height: parent.height
                    radius: 3
                    color: root.colOnHero
                    opacity: 0.35
                }
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.top
                text: (root.possession?.label ?? "").toUpperCase()
                font.pixelSize: FootballStyle.textSmallest
                font.variableAxes: FootballStyle.axesCaps
                font.letterSpacing: 1.5
                color: root.colOnHero
                opacity: 0.7
            }
        }
    }

    // ── Content ─────────────────────────────────────────────────────────────
    component TeamBlock: ColumnLayout {
        id: block
        property var team: null
        property string side: "home"
        readonly property bool leading: root.started && (block.side === "home" ? root.homeGoals > root.awayGoals : root.awayGoals > root.homeGoals)
        spacing: FootballStyle.gapSmall

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: crestButton.implicitWidth
            implicitHeight: crestButton.implicitHeight

            RippleButton {
                id: crestButton
                implicitWidth: root.compact ? 104 : 148
                implicitHeight: implicitWidth
                buttonRadius: implicitWidth / 2
                colBackground: "transparent"
                colBackgroundHover: "transparent"
                colRipple: "transparent"
                onClicked: if (block.team) root.teamActivated(Object.assign({ league: root.match?.league?.slug ?? "" }, block.team))
                contentItem: Item {
                    // Shape is state: hover morphs it into its sibling.
                    MaterialShape {
                        anchors.centerIn: parent
                        implicitSize: parent.width
                        shape: crestButton.hovered
                            ? (block.side === "home" ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Sunny)
                            : (block.side === "home" ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.VerySunny)
                        color: FootballStyle.colField
                    }
                    StyledImage {
                        anchors.centerIn: parent
                        width: Math.round(parent.width * 0.58)
                        height: width
                        source: block.team?.logo ?? ""
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                        cache: true
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Open %1").arg(block.team?.name ?? "")
                }
            }
            ClockIconButton {
                readonly property bool favorite: FootballService.isFavorite(block.team?.id)
                anchors.right: crestButton.right
                anchors.top: crestButton.top
                anchors.rightMargin: -6
                anchors.topMargin: -6
                size: 34
                iconSize: 18
                symbol: "star"
                filled: favorite
                colBackground: favorite ? FootballStyle.colTertiary : FootballStyle.colField
                colBackgroundHover: favorite ? FootballStyle.colTertiary : FootballStyle.colFieldHover
                colIcon: favorite ? FootballStyle.colOnTertiary : FootballStyle.colOnSurfaceVariant
                tooltip: favorite ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
                onClicked: FootballService.toggleFavorite(Object.assign({ league: root.match?.league?.slug ?? "" }, block.team))
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            horizontalAlignment: Text.AlignHCenter
            text: (block.team?.short || block.team?.name || "").toUpperCase()
            elide: Text.ElideRight
            font.pixelSize: root.nameSize
            font.variableAxes: FootballStyle.axesHeadline
            color: root.colOnHero
        }
        Repeater {
            model: root.scorers(block.side)
            delegate: RowLayout {
                required property string modelData
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: false
                Layout.maximumWidth: content.columnWidth
                spacing: 4
                MaterialSymbol {
                    text: "sports_soccer"
                    iconSize: 14
                    fill: 1
                    color: root.colOnHero
                    opacity: 0.8
                }
                StyledText {
                    Layout.maximumWidth: content.columnWidth - 20
                    text: modelData
                    elide: Text.ElideRight
                    font.pixelSize: FootballStyle.textSmall
                    font.weight: Font.DemiBold
                    color: root.colOnHero
                }
            }
        }
    }

    RowLayout {
        id: content
        x: FootballStyle.gapHuge
        y: FootballStyle.gapHuge
        width: root.width - FootballStyle.gapHuge * 2
        spacing: FootballStyle.gapLarge
        readonly property real columnWidth: Math.floor((width - spacing * 2) / 3)

        TeamBlock {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: content.columnWidth
            Layout.maximumWidth: content.columnWidth
            team: root.match?.home ?? null
            side: "home"
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: false
            Layout.preferredWidth: content.columnWidth
            Layout.maximumWidth: content.columnWidth
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: (root.match?.league?.name ?? "").toUpperCase()
                elide: Text.ElideRight
                font.pixelSize: FootballStyle.textSmaller
                font.variableAxes: FootballStyle.axesCaps
                font.letterSpacing: 2
                color: root.colOnHero
                opacity: 0.8
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Math.round(root.scoreSize * 0.12)
                StyledText {
                    shouldUseNumberFont: false
                    visible: root.started
                    text: root.match?.home?.score ?? ""
                    font.pixelSize: root.scoreSize
                    font.variableAxes: FootballStyle.axesScoreHeavy
                    color: root.colOnHero
                    opacity: root.homeGoals >= root.awayGoals ? 1 : 0.5
                }
                Rectangle {
                    visible: root.started
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Math.round(root.scoreSize * 0.18)
                    implicitHeight: Math.max(4, Math.round(root.scoreSize * 0.07))
                    radius: height / 2
                    color: root.colOnHero
                    opacity: 0.5
                }
                StyledText {
                    shouldUseNumberFont: false
                    visible: root.started
                    text: root.match?.away?.score ?? ""
                    font.pixelSize: root.scoreSize
                    font.variableAxes: FootballStyle.axesScoreHeavy
                    color: root.colOnHero
                    opacity: root.awayGoals >= root.homeGoals ? 1 : 0.5
                }
                StyledText {
                    shouldUseNumberFont: false
                    visible: !root.started
                    text: Format.kickoffTime(root.match?.date)
                    font.pixelSize: Math.round(root.scoreSize * 0.85)
                    font.variableAxes: FootballStyle.axesScoreHeavy
                    color: root.colOnHero
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: (root.match?.home?.shootout ?? "") !== ""
                text: Translation.tr("Penalties %1 – %2").arg(root.match?.home?.shootout ?? "").arg(root.match?.away?.shootout ?? "")
                font.pixelSize: FootballStyle.textSmall
                font.variableAxes: FootballStyle.axesCaps
                color: root.colOnHero
            }

            // State: a live minute in the tertiary voice, otherwise a caption.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                visible: root.live
                implicitHeight: 34
                implicitWidth: liveRow.implicitWidth + 28
                radius: 17
                color: FootballStyle.colTertiaryContainer
                RowLayout {
                    id: liveRow
                    anchors.centerIn: parent
                    spacing: 8
                    StyledText {
                        text: Translation.tr("LIVE")
                        font.pixelSize: FootballStyle.textSmaller
                        font.variableAxes: FootballStyle.axesCaps
                        font.letterSpacing: 1.5
                        color: FootballStyle.colOnTertiaryContainer
                    }
                    StyledText {
                        shouldUseNumberFont: false
                        text: root.match?.clock || root.match?.statusDetail || ""
                        font.pixelSize: FootballStyle.textLarge
                        font.variableAxes: FootballStyle.axesScoreHeavy
                        color: FootballStyle.colOnTertiaryContainer
                    }
                }
            }
            StyledText {
                shouldUseNumberFont: false
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !root.live
                horizontalAlignment: Text.AlignHCenter
                text: root.match?.state === "post"
                    ? (root.match?.statusDescription || root.match?.statusDetail || "").toUpperCase()
                    : Format.longDate(root.match?.date, root.locale)
                elide: Text.ElideRight
                font.pixelSize: root.match?.state === "post" ? FootballStyle.textSmall : FootballStyle.textNormal
                font.variableAxes: root.match?.state === "post" ? FootballStyle.axesCaps : FootballStyle.axesCondensed
                font.letterSpacing: root.match?.state === "post" ? 1.5 : 0
                color: root.colOnHero
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.started
                horizontalAlignment: Text.AlignHCenter
                text: [root.match?.venue ?? "", Format.shortDate(root.match?.date, root.locale)].filter(part => part !== "").join(" · ")
                elide: Text.ElideRight
                font.pixelSize: FootballStyle.textSmaller
                color: root.colOnHero
                opacity: 0.7
            }
        }

        TeamBlock {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: content.columnWidth
            Layout.maximumWidth: content.columnWidth
            team: root.match?.away ?? null
            side: "away"
        }
    }
}
