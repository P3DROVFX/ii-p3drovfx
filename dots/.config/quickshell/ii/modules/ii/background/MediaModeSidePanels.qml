pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

// Classic frontend's right column: Lyrics Studio above the local queue.
Item {
    id: panel
    required property var context
    ColumnLayout {
        anchors.fill: parent
        spacing: panel.context.rightPanelLayout.gap

        Item {
            id: lyricsPanel
            Layout.fillWidth: true
            Layout.fillHeight: false
            property real targetHeight: panel.context.rightPanelLayout.lyricsHeight
            Layout.preferredHeight: targetHeight
            visible: panel.context.lyricsPanelVisible

            Behavior on targetHeight {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Rectangle {
                id: lyricsContainer
                anchors.fill: parent
                radius: Appearance.rounding.verylarge
                color: panel.context.videoActive ? ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.80) :
                                                   ColorUtils.transparentize(Appearance.colors.colLayer1Base, 0.65)

                Behavior on color {
                    ColorAnimation {
                        duration: 400
                        easing.type: Easing.InOutQuad
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    // Lyrics Studio Header Toolbar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        MaterialSymbol {
                            iconSize: 22
                            color: panel.context.dynamicAccentColor
                            text: "lyrics"
                        }

                        StyledText {
                            text: Translation.tr("Lyrics Studio")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnLayer0
                        }

                        // Status Chip
                        Rectangle {
                            implicitWidth: statusText.implicitWidth + 16
                            implicitHeight: 24
                            radius: Appearance.rounding.full
                            color: ColorUtils.transparentize(panel.context.dynamicAccentContainer, 0.4)

                            StyledText {
                                id: statusText
                                anchors.centerIn: parent
                                text: lyricsItem.statusLabel
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: ColorUtils.contrastRatio(panel.context.dynamicAccentColor,
                                                                Appearance.colors.colLayer1Base) >= 3.0
                                       ? panel.context.dynamicAccentColor : Appearance.colors.colOnLayer0
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        RippleButton {
                            visible: panel.context.queueEligible
                            implicitWidth: Appearance.sizes.minimumTouchTarget
                                           - Appearance.sizes.elevationMargin
                            implicitHeight: implicitWidth
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundActive: Appearance.colors.colLayer2Active
                            onClicked: {
                                if (panel.context.localLyricsExpanded) {
                                    panel.context.localLyricsPreference = "collapsed";
                                    panel.context.localQueueExpanded = true;
                                } else {
                                    panel.context.localLyricsPreference = "expanded";
                                }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: panel.context.localLyricsExpanded ? "keyboard_arrow_up" :
                                                                          "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }

                            PopupToolTip {
                                text: panel.context.localLyricsExpanded ? Translation.tr("Collapse lyrics") :
                                                                          Translation.tr("Expand lyrics")
                            }
                        }

                        MediaModeLyricsProviderRow {
                            accentColor: panel.context.dynamicAccentColor
                        }

                        // Font Zoom Controls
                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundActive: Appearance.colors.colLayer2Active

                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 16
                                color: Appearance.colors.colOnLayer2
                                text: "remove"
                            }
                            onClicked: panel.context.lyricsScaleMultiplier = Math.max(0.7,
                                                                                      panel.context.lyricsScaleMultiplier
                                                                                      - 0.15)
                            StyledToolTip {
                                text: Translation.tr("Decrease Lyrics Size")
                            }
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundActive: Appearance.colors.colLayer2Active

                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 16
                                color: Appearance.colors.colOnLayer2
                                text: "add"
                            }
                            onClicked: panel.context.lyricsScaleMultiplier = Math.min(1.8,
                                                                                      panel.context.lyricsScaleMultiplier
                                                                                      + 0.15)
                            StyledToolTip {
                                text: Translation.tr("Increase Lyrics Size")
                            }
                        }

                        // Refresh Lyrics Button
                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.5)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundActive: Appearance.colors.colLayer2Active

                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: 16
                                color: Appearance.colors.colOnLayer2
                                text: "refresh"
                            }
                            onClicked: LyricsService.initiliazeLyrics()
                            StyledToolTip {
                                text: Translation.tr("Reload Lyrics")
                            }
                        }
                    }

                    // Lyrics Content Area
                    MediaModeLyricsContent {
                        id: lyricsItem
                        context: panel.context
                        Layout.fillWidth: true
                        Layout.fillHeight: panel.context.lyricsContentVisible
                        visible: panel.context.lyricsContentVisible || opacity > 0
                        opacity: panel.context.lyricsContentVisible ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }
                }
            }
        }

        MediaModeQueue {
            id: queuePanel
            property real targetHeight: panel.context.rightPanelLayout.queueHeight
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: targetHeight
            visible: panel.context.queueEligible
            expanded: panel.context.localQueueExpanded
            lyricsExpanded: panel.context.localLyricsExpanded
            lyricsToggleAvailable: panel.context.showLyricsPanel
            queueSnapshot: LocalMediaService.queueSnapshot
            accentColor: panel.context.dynamicAccentColor
            accentContainerColor: panel.context.dynamicAccentContainer
            onAccentContainerColor: panel.context.dynamicOnAccentContainer
            onOpenFileBrowserRequested: audioOnly => panel.context.openFileBrowser(audioOnly)
            onExpandedToggled: {
                if (panel.context.localQueueExpanded) {
                    panel.context.localQueueExpanded = false;
                    panel.context.localLyricsPreference = "expanded";
                } else {
                    panel.context.localQueueExpanded = true;
                }
            }
            onLyricsExpandedToggled: {
                if (panel.context.localLyricsExpanded) {
                    panel.context.localLyricsPreference = "collapsed";
                    panel.context.localQueueExpanded = true;
                } else {
                    panel.context.localLyricsPreference = "expanded";
                }
            }

            Behavior on targetHeight {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }
        }
    }
}
