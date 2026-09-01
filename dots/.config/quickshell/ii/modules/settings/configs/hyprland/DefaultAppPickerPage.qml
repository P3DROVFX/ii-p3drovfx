pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Installed-app picker for one XDG default association.
 *
 * Every desktop entry is offered deliberately. XDG associations are user intent, and some
 * desktop files omit a MimeType declaration even though their command handles the file well.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false
    property string rawQuery: ""

    readonly property var category: DefaultApps.category(DefaultApps.editCategory)
    readonly property string categoryId: String(category?.id ?? "")
    readonly property string currentId: DefaultApps.defaultId(categoryId)
    readonly property string query: rawQuery.trim()
    readonly property var apps: query === "" ? AppSearch.list : AppSearch.fuzzyQuery(query)

    function pick(entry: var) {
        if (!DefaultApps.setDefault(categoryId, String(entry.id ?? "")))
            return;
        subPageRoot.goBack();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            IconImage {
                Layout.alignment: Qt.AlignVCenter
                visible: DefaultApps.appIcon(subPageRoot.categoryId) !== ""
                implicitSize: 32
                source: Quickshell.iconPath(DefaultApps.appIcon(subPageRoot.categoryId), "application-x-executable")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: subPageRoot.category?.label ?? Translation.tr("Default application")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: subPageRoot.currentId === ""
                        ? Translation.tr("No default application is set")
                        : Translation.tr("Now using %1").arg(DefaultApps.appName(subPageRoot.categoryId))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search installed applications")
            onTextChanged: subPageRoot.rawQuery = text
        }

        StyledText {
            Layout.fillWidth: true
            visible: subPageRoot.apps.length === 0
            text: Translation.tr("No installed applications match that search.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        StyledListView {
            id: appList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            animateAppearance: false
            model: subPageRoot.apps

            delegate: RippleButton {
                id: appRow

                required property var modelData

                readonly property bool current: String(modelData.id ?? "") === subPageRoot.currentId

                width: appList.width
                implicitHeight: 56
                buttonRadius: Appearance.rounding.normal
                colBackground: current ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                colBackgroundHover: current ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
                colRipple: current ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active
                onClicked: subPageRoot.pick(modelData)

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    IconImage {
                        Layout.alignment: Qt.AlignVCenter
                        implicitSize: 28
                        source: Quickshell.iconPath(String(appRow.modelData.icon ?? ""), "application-x-executable")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: String(appRow.modelData.name ?? appRow.modelData.id ?? "")
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: appRow.current ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: String(appRow.modelData.id ?? "") !== ""
                            text: String(appRow.modelData.id ?? "")
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: appRow.current ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colSubtext
                        }
                    }

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        visible: appRow.current
                        text: "check"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }
        }
    }
}
