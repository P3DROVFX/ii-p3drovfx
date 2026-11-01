pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The tab's home: app bar (sync, add, import, account), the "Due today" hero with the
 * day's total in expressive digits and a one-tap start on the first deck with work,
 * sync banners, and the decks as one grouped list with their due counts.
 */
Item {
    id: root

    signal sheetRequested(string name)

    readonly property int dueTotal: Anki.totals.new + Anki.totals.learn + Anki.totals.review
    readonly property var nextDeck: Anki.decks.find(d => d.depth === 0 && d.new + d.learn + d.review > 0) ?? null
    readonly property bool empty: Anki.decksLoaded && Anki.cardCount === 0

    function minutesText(seconds: int): string {
        const m = Math.round(seconds / 60);
        return m < 1 ? Translation.tr("under a minute") : Translation.tr("%1 min").arg(m);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: ClockStyle.gapSmall

        // ── App bar ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapTiny

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: ClockStyle.gapTiny
                text: "Anki"
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: Appearance.font.pixelSize.huge + 4
                color: ClockStyle.colOnSurface
            }

            AnkiIconButton {
                symbol: Anki.loggedIn ? "sync" : "cloud_off"
                busy: Anki.syncing
                tooltip: Anki.loggedIn ? Translation.tr("Sync with AnkiWeb") : Translation.tr("Sign in to AnkiWeb")
                onClicked: Anki.loggedIn ? Anki.sync() : root.sheetRequested("login")
            }
            AnkiIconButton {
                symbol: "add"
                tooltip: Translation.tr("Add a card")
                onClicked: root.sheetRequested("add")
            }
            AnkiIconButton {
                symbol: "download"
                busy: Anki.importing
                tooltip: Translation.tr("Import a deck (.apkg)")
                onClicked: Anki.importPackage()
            }
            AnkiIconButton {
                visible: Anki.loggedIn
                symbol: "account_circle"
                tooltip: Anki.username
                onClicked: root.sheetRequested("account")
            }
        }

        StyledFlickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            visible: !root.empty

            ColumnLayout {
                id: body
                width: flick.width
                spacing: ClockStyle.gapSmall

                // ── Hero ────────────────────────────────────────────────
                Rectangle {
                    id: hero
                    Layout.fillWidth: true
                    implicitHeight: heroColumn.implicitHeight + ClockStyle.cardPadding * 2
                    radius: ClockStyle.radiusCard
                    color: root.dueTotal > 0 ? ClockStyle.colPrimaryContainer : ClockStyle.colPane
                    readonly property color colContent: root.dueTotal > 0 ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

                    Behavior on color {
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }

                    // Ornament: a big flower off the right edge, cut by the card's shape.
                    Item {
                        id: ornament
                        anchors.fill: parent
                        visible: false
                        MaterialShape {
                            readonly property real size: Math.round(hero.height * 1.9)
                            width: size
                            height: size
                            x: hero.width - size * 0.45
                            y: (hero.height - size) / 2
                            shapeString: "Flower"
                            color: hero.colContent
                        }
                    }
                    Rectangle {
                        id: ornamentMask
                        anchors.fill: parent
                        radius: hero.radius
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
                        opacity: 0.09
                    }

                    ColumnLayout {
                        id: heroColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: ClockStyle.cardPadding
                        }
                        spacing: 2

                        StyledText {
                            text: Translation.tr("Due today")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: hero.colContent
                            opacity: 0.8
                        }

                        StyledText {
                            text: root.dueTotal
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: 84
                            color: hero.colContent
                            Layout.topMargin: -6
                            Layout.bottomMargin: -8
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: root.dueTotal > 0
                                ? Translation.tr("%1 new · %2 learning · %3 review").arg(Anki.totals.new).arg(Anki.totals.learn).arg(Anki.totals.review)
                                : Translation.tr("Nothing due. Nice work.")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: hero.colContent
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: Anki.studiedToday.cards > 0
                            text: Translation.tr("%1 cards studied in %2 today").arg(Anki.studiedToday.cards).arg(root.minutesText(Anki.studiedToday.seconds))
                            font.pixelSize: ClockStyle.textSmall
                            color: hero.colContent
                            opacity: 0.75
                        }

                        RippleButton {
                            Layout.topMargin: ClockStyle.gap
                            Layout.fillWidth: true
                            visible: root.nextDeck !== null
                            implicitHeight: 52
                            buttonRadius: Appearance.rounding.full
                            buttonRadiusPressed: Appearance.rounding.normal
                            colBackground: ClockStyle.colPrimary
                            colBackgroundHover: ClockStyle.colPrimaryHover
                            colBackgroundActive: ClockStyle.colPrimaryActive
                            colRipple: ClockStyle.colPrimaryActive
                            onClicked: Anki.study(root.nextDeck)

                            contentItem: RowLayout {
                                spacing: ClockStyle.gapSmall
                                Item {
                                    Layout.fillWidth: true
                                }
                                MaterialSymbol {
                                    text: "play_arrow"
                                    iconSize: 24
                                    fill: 1
                                    color: ClockStyle.colOnPrimary
                                }
                                StyledText {
                                    Layout.maximumWidth: hero.width - 120
                                    elide: Text.ElideRight
                                    text: Translation.tr("Study %1").arg(root.nextDeck?.name ?? "")
                                    font.family: ClockStyle.fontTitle
                                    font.variableAxes: ClockStyle.axesTitle
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    color: ClockStyle.colOnPrimary
                                }
                                Item {
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                // ── Sync banners ────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    visible: Anki.syncConflict
                    implicitHeight: conflictColumn.implicitHeight + ClockStyle.gapLarge * 2
                    radius: Appearance.rounding.large
                    color: ClockStyle.colSecondaryContainer

                    ColumnLayout {
                        id: conflictColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: ClockStyle.gapLarge
                        }
                        spacing: ClockStyle.gapSmall
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("AnkiWeb and this computer both changed in ways that can't be merged. Keep which one?")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: ClockStyle.colOnSecondaryContainer
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapTiny
                            AnkiChip {
                                primary: true
                                symbol: "cloud_download"
                                label: Translation.tr("Keep AnkiWeb")
                                onClicked: Anki.resolveConflict(false)
                            }
                            AnkiChip {
                                symbol: "cloud_upload"
                                label: Translation.tr("Keep this computer")
                                onClicked: Anki.resolveConflict(true)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: Anki.syncError.length > 0
                    implicitHeight: errorRow.implicitHeight + ClockStyle.gap * 2
                    radius: Appearance.rounding.large
                    color: ClockStyle.colErrorContainer

                    RowLayout {
                        id: errorRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: ClockStyle.gapLarge
                            rightMargin: ClockStyle.gapSmall
                        }
                        MaterialSymbol {
                            text: "sync_problem"
                            iconSize: 20
                            color: ClockStyle.colOnErrorContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Anki.syncError
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: ClockStyle.colOnErrorContainer
                        }
                        AnkiIconButton {
                            symbol: "close"
                            onClicked: Anki.syncError = ""
                        }
                    }
                }

                // ── Decks ───────────────────────────────────────────────
                StyledText {
                    Layout.topMargin: ClockStyle.gapSmall
                    Layout.leftMargin: ClockStyle.gapTiny
                    visible: Anki.decks.length > 0
                    text: Translation.tr("Decks")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Repeater {
                        model: Anki.decks

                        AnkiDeckRow {
                            required property var modelData
                            Layout.fillWidth: true
                            deck: modelData
                            onClicked: Anki.study(modelData)
                        }
                    }
                }

                Item {
                    implicitHeight: ClockStyle.gap
                }
            }
        }

        // ── Empty collection ────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.empty

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, 320)
                spacing: ClockStyle.gapLarge

                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: "school"
                    shape: "Clover4Leaf"
                    colShape: ClockStyle.colTertiaryContainer
                    colIcon: ClockStyle.colOnTertiaryContainer
                    title: Translation.tr("No cards yet")
                    subtitle: Translation.tr("Bring your collection from AnkiWeb, import a shared deck, or write your first card.")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapTiny
                    ClockSheetAction {
                        primary: true
                        visible: !Anki.loggedIn
                        label: Translation.tr("Sign in to AnkiWeb")
                        symbol: "cloud"
                        onClicked: root.sheetRequested("login")
                    }
                    ClockSheetAction {
                        label: Translation.tr("Import a deck (.apkg)")
                        symbol: "download"
                        onClicked: Anki.importPackage()
                    }
                    ClockSheetAction {
                        label: Translation.tr("Create a card")
                        symbol: "add"
                        onClicked: root.sheetRequested("add")
                    }
                }
            }
        }
    }

    StaggeredEntrance { target: hero; index: 0; step: ClockStyle.staggerStep }
}
