import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Results & Layout")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "stars"
            title: Translation.tr("Best match configuration")
            tooltip: Translation.tr("Customize how the top result is presented and how its quick actions appear.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "stars"
                    text: Translation.tr("Best match row")
                    description: Translation.tr("Renders the top result as one prominent row carrying its own actions, and the rest as a single uniform list. You read one line instead of scanning seven groups.")
                    checked: Config.options.search.bestMatch.enable
                    onCheckedChanged: Config.options.search.bestMatch.enable = checked
                }

                ConfigSpinBox {
                    icon: "bolt"
                    text: Translation.tr("Actions shown on the best match")
                    value: Config.options.search.bestMatch.secondaryActions
                    from: 0
                    to: 6
                    stepSize: 1
                    enabled: Config.options.search.bestMatch.enable
                    onValueChanged: Config.options.search.bestMatch.secondaryActions = value
                    StyledToolTip {
                        text: Translation.tr("Actions from the result itself, placed on the row and reachable with Alt+1…n. The action panel (Ctrl+K) still holds every one of them.")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "reorder"
                    text: Translation.tr("Hide group captions in best match mode")
                    description: Translation.tr("With one answer at the top, the remaining results read better as one list. Turn this off to keep the category groups underneath it.")
                    checked: Config.options.search.bestMatch.uniformList
                    enabled: Config.options.search.bestMatch.enable
                    onCheckedChanged: Config.options.search.bestMatch.uniformList = checked
                }
            }
        }

        ContentSection {
            id: resultPrioritySection
            icon: "low_priority"
            title: Translation.tr("Result priority")
            tooltip: Translation.tr("Order the groups results are shown in, and choose which ones appear at all.")

            readonly property var orderedIds: {
                const list = Array.from(Config.options.search.sectionOrder ?? []);
                return list.map(entry => String((entry && entry.id) ? entry.id : (entry || ""))).filter(id => id.length > 0);
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "reorder"
                    text: Translation.tr("Drag a group to change where its results appear. Removing one hides its results entirely — add it back from the selector below.")
                }

                ConfigListView {
                    barSection: -1
                    listModel: Config.options.search.sectionOrder
                    availableComponents: SearchResultSectionRegistry.getAvailableComponents(resultPrioritySection.orderedIds)
                    addButtonText: Translation.tr("Add group")
                    infoProvider: id => SearchResultSectionRegistry.getComponent(id)
                    normalizeEntry: entry => ({
                        id: entry.id
                    })
                    onUpdated: newList => {
                        Config.options.search.sectionOrder = newList;
                    }
                }
            }
        }
    }
}
