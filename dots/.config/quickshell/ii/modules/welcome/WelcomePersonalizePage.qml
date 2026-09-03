import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * "Make it yours" — the two ways to have a desktop that looks like yours.
 *
 * The page used to offer one: a wallpaper and a palette, which is where the
 * shell's own defaults end. Everything past that - the bar's layout, the dock,
 * which widgets are on the desktop, the hundreds of settings behind them - was
 * reachable only by someone who already knew Settings, and a person on their
 * first day does not. A preset from the store carries all of it, so the store
 * belongs HERE, in the minute the user is actually deciding what their shell
 * looks like, rather than three menus away.
 *
 * The two are alternatives, not halves, so they are two tabs rather than a
 * third column: a preset REPLACES the wallpaper and palette you would have
 * picked by hand. The page still opens on the wallpaper, which is the choice
 * that always works and never needs the network; the looks are one tab away,
 * and the store's own failures point back here rather than dead-ending.
 */
Item {
    id: root

    // 0 wallpaper and palette, by hand · 1 the store's looks
    readonly property int mode: tabBar.currentIndex

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.small

        // The shell's own navigation tab bar, the same one the Preset Manager
        // in Settings is split with - a pair of filled pills read as two
        // buttons that happen to be exclusive, which is not what switching
        // between two halves of a page is.
        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true

            SecondaryTabButton {
                buttonIcon: "palette"
                buttonText: Translation.tr("Wallpaper & colours")
            }

            SecondaryTabButton {
                buttonIcon: "auto_awesome"
                buttonText: Translation.tr("Ready-made looks")
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.mode

            RowLayout {
                spacing: Appearance.rounding.small

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 430
                    Layout.preferredWidth: 3
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1
                    clip: true

                    ConfigWallpaperSelector {
                        anchors.fill: parent
                        anchors.margins: Appearance.rounding.small
                        text: Translation.tr("Wallpaper")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 360
                    Layout.preferredWidth: 2
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Appearance.rounding.normal
                        spacing: Appearance.rounding.small

                        WelcomeLightDarkToggle {
                            Layout.fillWidth: true
                            Layout.minimumHeight: toggleHeight
                            Layout.preferredHeight: toggleHeight
                            Layout.maximumHeight: toggleHeight
                        }

                        StyledFlickable {
                            id: colorSchemesFlickable
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: colorSchemesContent.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: colorSchemesContent
                                width: colorSchemesFlickable.width
                                spacing: Appearance.rounding.small

                                ContentSubsectionLabel {
                                    text: Translation.tr("Generated palettes")
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                                    font.weight: Font.Bold
                                }

                                WelcomeColorPreviewGrid {
                                    id: generatedColorGrid
                                    Layout.fillWidth: true
                                    columns: 3
                                    customTheme: false
                                    builtInTheme: false
                                }

                                ContentSubsectionLabel {
                                    text: Translation.tr("Built-in palettes")
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                                    font.weight: Font.Bold
                                }

                                WelcomeColorPreviewGrid {
                                    id: builtInColorGrid
                                    Layout.fillWidth: true
                                    columns: 3
                                    customTheme: false
                                    builtInTheme: true
                                }

                                ContentSubsectionLabel {
                                    visible: Config.options.appearance.customColorSchemes.length > 0
                                    text: Translation.tr("Custom palettes")
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.family: Appearance.font.family.title
                                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                                    font.weight: Font.Bold
                                }

                                WelcomeColorPreviewGrid {
                                    id: customColorGrid
                                    Layout.fillWidth: true
                                    columns: 3
                                    customTheme: true
                                    builtInTheme: false
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Appearance.font.pixelSize.larger + Appearance.rounding.small

                            StyledText {
                                id: paletteLabel
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: Appearance.rounding.small
                                text: generatedColorGrid.hoveredColorSchemeDisplayName
                                    || builtInColorGrid.hoveredColorSchemeDisplayName
                                    || customColorGrid.hoveredColorSchemeDisplayName
                                    || generatedColorGrid.selectedColorSchemeDisplayName
                                    || builtInColorGrid.selectedColorSchemeDisplayName
                                    || customColorGrid.selectedColorSchemeDisplayName
                                color: Appearance.colors.colOnLayer1
                                font.family: Appearance.font.family.title
                                font.variableAxes: Appearance.font.variableAxes.titleRounded
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                                opacity: text !== "" ? 1 : 0
                                y: text !== "" ? 0 : Appearance.rounding.verysmall

                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on y {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }
            }

            // The same rounded card the wallpaper and palette sit in, so the
            // two tabs read as two fillings of one page rather than two pages.
            Rectangle {
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                clip: true

                WelcomePresetStorePane {
                    anchors.fill: parent
                    anchors.margins: Appearance.rounding.normal
                    // The first listing is a live GitHub search, so it waits
                    // for someone to actually be looking at this tab.
                    active: root.mode === 1
                    onPickYourOwnRequested: tabBar.currentIndex = 0
                }
            }
        }
    }
}
