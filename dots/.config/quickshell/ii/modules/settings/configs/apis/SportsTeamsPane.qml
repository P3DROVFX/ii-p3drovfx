import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Teams: narrow your competitions down to the clubs you care about. Empty means
 * every match of the followed competitions; picking teams shows only theirs.
 * Search covers every sport ESPN knows; picked teams are crest chips.
 */
Rectangle {
    id: root

    property var model: null
    property var catalog: null

    readonly property var terms: root.model?.teamTerms ?? []
    readonly property bool searching: field.text.trim().length >= 2

    implicitHeight: column.implicitHeight + 40
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    Timer {
        id: debounce
        interval: 350
        onTriggered: root.catalog?.searchTeams(field.text)
    }

    ColumnLayout {
        id: column
        x: 20
        y: 20
        width: root.width - 40
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            MaterialShapeWrappedMaterialSymbol {
                text: "shield"
                iconSize: 24
                padding: 12
                shape: MaterialShape.Shape.Clover4Leaf
                color: Appearance.colors.colTertiaryContainer
                colSymbol: Appearance.colors.colOnTertiaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Teams")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.terms.length === 0
                        ? Translation.tr("Showing every match of your competitions. Pick teams to see only theirs.")
                        : Translation.tr("Showing only matches with these teams.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
            RippleButtonWithIcon {
                visible: root.terms.length > 0
                materialIcon: "clear_all"
                mainText: Translation.tr("Show all teams")
                onClicked: root.model?.clearTeams()
            }
        }

        // Picked teams
        Flow {
            Layout.fillWidth: true
            spacing: 8
            visible: root.terms.length > 0
            Repeater {
                model: root.terms
                delegate: Rectangle {
                    id: chip
                    required property string modelData
                    readonly property var detail: root.model?.teamDetail(chip.modelData) ?? null
                    implicitHeight: 44
                    implicitWidth: chipRow.implicitWidth + 12
                    radius: 22
                    color: Appearance.colors.colSecondaryContainer
                    RowLayout {
                        id: chipRow
                        anchors.verticalCenter: parent.verticalCenter
                        x: 4
                        spacing: 8
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: Appearance.m3colors.m3surfaceContainerHighest
                            CrestImage {
                                anchors.centerIn: parent
                                width: 24
                                height: 24
                                visible: (chip.detail?.logo ?? "") !== ""
                                url: chip.detail?.logo
                                fillMode: Image.PreserveAspectFit
                                mipmap: true
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: (chip.detail?.logo ?? "") === ""
                                text: "shield"
                                iconSize: 18
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                        StyledText {
                            text: chip.modelData
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        RippleButton {
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: 14
                            colBackground: "transparent"
                            colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnSecondaryContainer, 0.12)
                            onClicked: root.model?.unfollowTeam(chip.modelData)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 16
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledToolTip {
                                text: Translation.tr("Stop following %1").arg(chip.modelData)
                            }
                        }
                    }
                }
            }
        }

        // Search
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: field.activeFocus ? Appearance.rounding.large : height / 2
            color: field.activeFocus ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.colors.colLayer2
            Behavior on radius {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 10
                spacing: 8
                MaterialShapeWrappedMaterialSymbol {
                    text: "person_search"
                    iconSize: 18
                    padding: 8
                    shape: field.activeFocus ? MaterialShape.Shape.VerySunny : MaterialShape.Shape.Cookie7Sided
                    color: Appearance.colors.colSecondaryContainer
                    colSymbol: Appearance.colors.colOnSecondaryContainer
                }
                ToolbarTextField {
                    id: field
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    colBackground: "transparent"
                    placeholderText: Translation.tr("Search a team, e.g. Flamengo, Lakers, Ferrari")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    onTextChanged: debounce.restart()
                }
            }
        }

        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: root.catalog?.teamLoading === true
        }

        // Results
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            visible: root.searching
            Repeater {
                model: root.searching ? (root.catalog?.teamResults ?? []).slice(0, 10) : []
                delegate: RippleButton {
                    id: result
                    required property var modelData
                    required property int index
                    readonly property bool followed: root.model?.isTeamFollowed(result.modelData.name) ?? false
                    readonly property int count: Math.min(10, (root.catalog?.teamResults ?? []).length)
                    Layout.fillWidth: true
                    implicitHeight: 56
                    toggled: result.followed
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    topLeftRadius: result.index === 0 ? Appearance.rounding.large : Appearance.rounding.verysmall
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: result.index === result.count - 1 ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomRightRadius: bottomLeftRadius
                    onClicked: result.followed ? root.model?.unfollowTeam(result.modelData.name) : root.model?.followTeam(result.modelData)

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 14
                        spacing: 12
                        Rectangle {
                            implicitWidth: 38
                            implicitHeight: 38
                            radius: 19
                            color: Appearance.m3colors.m3surfaceContainerHighest
                            CrestImage {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                url: result.modelData.logo
                                fillMode: Image.PreserveAspectFit
                                mipmap: true
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: result.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: result.followed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                            }
                            RowLayout {
                                spacing: 4
                                MaterialSymbol {
                                    text: root.catalog?.sportById(result.modelData.sport)?.icon ?? "sports"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: [root.catalog?.sportById(result.modelData.sport)?.label ?? "", result.modelData.league].filter(part => part !== "").join(" · ")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: result.followed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }
                            }
                        }
                        MaterialSymbol {
                            text: result.followed ? "check_circle" : "add_circle"
                            fill: result.followed ? 1 : 0
                            iconSize: 24
                            color: result.followed ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                        }
                    }
                }
            }
            StyledText {
                visible: !(root.catalog?.teamLoading) && (root.catalog?.teamResults ?? []).length === 0
                text: Translation.tr("No team with that name")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }
}
