import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.welcome
import qs.modules.welcome.tutorials

Item {
    id: root

    property var tutorial: null
    readonly property var content: WelcomeTutorialContent.contentFor(root.tutorial ? root.tutorial.contentId : "")
    readonly property var integrationState: WelcomeTutorialRegistry.stateFor(root.tutorial)

    signal backRequested()
    signal openSettingsTarget(string pageId, string subPageId, string sectionId)

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.normal

        Rectangle {
            id: tutorialHero
            Layout.fillWidth: true
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.large
            implicitHeight: heroContent.implicitHeight + Appearance.rounding.small * 2

            RowLayout {
                id: heroContent
                anchors.fill: parent
                anchors.margins: Appearance.rounding.small
                spacing: Appearance.rounding.normal

                RippleButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: Appearance.rounding.verylarge
                    implicitHeight: Appearance.rounding.verylarge
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colBackgroundActive: Appearance.colors.colSecondaryContainerActive
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    Accessible.name: Translation.tr("Back to tutorials")
                    onClicked: root.backRequested()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_back"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                MaterialShapeWrappedMaterialSymbol {
                    id: heroShape
                    Layout.alignment: Qt.AlignTop
                    text: root.tutorial ? root.tutorial.icon : "school"
                    shape: MaterialShape.Shape.SoftBurst
                    iconSize: Appearance.font.pixelSize.hugeass
                    padding: Appearance.rounding.normal
                    fill: 1
                    color: Appearance.colors.colTertiaryContainer
                    colSymbol: Appearance.colors.colOnTertiaryContainer
                }

                ColumnLayout {
                    id: heroCopy
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Appearance.rounding.verysmall

                    StyledText {
                        Layout.fillWidth: true
                        text: root.tutorial
                            ? Translation.tr(root.tutorial.titleKey)
                            : Translation.tr("Tutorial")
                        color: Appearance.colors.colOnLayer1
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.hugeass
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.weight: Font.Bold
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.tutorial
                            ? Translation.tr(root.tutorial.descriptionKey)
                            : Translation.tr("Choose a tutorial from the catalog.")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.rounding.small

                        StyledText {
                            text: root.tutorial
                                ? WelcomeTutorialRegistry.statusTextFor(root.tutorial)
                                : ""
                            color: root.integrationState.error
                                ? Appearance.colors.colOnErrorContainer
                                : Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            text: root.tutorial
                                ? WelcomeTutorialRegistry.estimatedTimeFor(root.tutorial)
                                : ""
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }

                        Repeater {
                            model: root.tutorial && root.tutorial.usedInChips
                                ? root.tutorial.usedInChips
                                : []

                            delegate: Rectangle {
                                required property string modelData
                                radius: Appearance.rounding.full
                                implicitHeight: Appearance.rounding.large
                                implicitWidth: chipLabel.implicitWidth + Appearance.rounding.normal
                                color: Appearance.colors.colTertiaryContainer

                                StyledText {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    text: Translation.tr(modelData)
                                    color: Appearance.colors.colOnTertiaryContainer
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.large
            implicitHeight: introColumn.implicitHeight + Appearance.rounding.normal * 2

            ColumnLayout {
                id: introColumn
                anchors.fill: parent
                anchors.margins: Appearance.rounding.normal
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: root.tutorial
                        ? Translation.tr(root.content.intro)
                        : Translation.tr("Choose a tutorial from the catalog.")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.content.prerequisites && root.content.prerequisites.length > 0
                    text: Translation.tr("What you need: ") + root.content.prerequisites.join(Translation.tr(" · "))
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        Flickable {
            id: flickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentContainer.implicitHeight + Appearance.rounding.normal
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: contentContainer
                width: flickable.width - Appearance.rounding.small
                spacing: Appearance.rounding.small

                Repeater {
                    model: root.content.steps || []

                    delegate: WelcomeTutorialStep {
                        required property var modelData
                        required property int index
                        title: Translation.tr(modelData.title)
                        supportingText: Translation.tr(modelData.body)
                        stepNumber: String(index + 1)
                        stateKind: index === 0 ? "current" : "pending"
                        isLast: index === (root.content.steps || []).length - 1
                    }
                }

                RippleButtonWithIcon {
                    Layout.alignment: Qt.AlignLeft
                    visible: root.content.actionPage && root.content.actionPage.length > 0
                    materialIcon: "open_in_new"
                    mainText: root.content.actionLabel
                        ? Translation.tr(root.content.actionLabel)
                        : Translation.tr("Open guide")
                    onClicked: root.openSettingsTarget(
                        root.content.actionPage || "",
                        root.content.actionSubPage || "",
                        root.content.actionSection || "")
                }
            }

            TouchpadScrollHandler {
                flickable: flickable
            }
        }
    }
}
