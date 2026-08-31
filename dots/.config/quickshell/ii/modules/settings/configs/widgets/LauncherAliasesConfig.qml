import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
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

            StyledText {
                text: Translation.tr("Search aliases")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "label"
            title: Translation.tr("Configured Aliases")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                NoticeBox {
                    visible: !((Persistent.ready ? Persistent.states.search.aliases : Config.options.search.aliases) && (Persistent.ready ? Persistent.states.search.aliases : Config.options.search.aliases).length > 0)
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("No aliases configured yet. Use the form below to create shortcuts for apps, folders, commands, and Search panels.")
                }

                Repeater {
                    model: (Persistent.ready ? Persistent.states.search.aliases : null) || Config.options.search.aliases || []

                    delegate: Rectangle {
                        id: aliasDelegate

                        property bool isEditing: false

                        Layout.fillWidth: true
                        height: 60
                        color: Appearance.colors.colSurfaceContainerLow
                        topLeftRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
                        topRightRadius: index === 0 ? Appearance.rounding.small : Appearance.rounding.verysmall
                        bottomLeftRadius: index === ((Persistent.ready ? Persistent.states.search.aliases : Config.options.search.aliases).length - 1) ? Appearance.rounding.small : Appearance.rounding.verysmall
                        bottomRightRadius: index === ((Persistent.ready ? Persistent.states.search.aliases : Config.options.search.aliases).length - 1) ? Appearance.rounding.small : Appearance.rounding.verysmall

                        ScrollAnimate {}

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Rectangle {
                                width: 36
                                height: 36
                                radius: 18
                                color: modelData.type === "app" ? Appearance.colors.colPrimaryContainer : modelData.type === "folder" ? Appearance.colors.colSecondaryContainer : Appearance.colors.colTertiaryContainer

                                Loader {
                                    anchors.centerIn: parent
                                    sourceComponent: modelData.type === "app" ? appIconComp : fallbackIconComp
                                }

                                Component {
                                    id: appIconComp

                                    WAppIcon {
                                        iconName: modelData.target.replace(".desktop", "")
                                        implicitSize: 20
                                        tryCustomIcon: false
                                    }
                                }

                                Component {
                                    id: fallbackIconComp

                                    MaterialSymbol {
                                        iconSize: 20
                                        text: modelData.type === "folder" ? "folder" : modelData.type === "builtin" ? "explore" : "terminal"
                                        color: modelData.type === "folder" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnTertiaryContainer
                                    }
                                }
                            }

                            Rectangle {
                                color: Appearance.colors.colSurfaceContainerHigh
                                radius: Appearance.rounding.verysmall
                                implicitWidth: Math.max(40, aliasDelegate.isEditing ? aliasEditInput.implicitWidth + 16 : aliasText.implicitWidth + 16)
                                implicitHeight: 26

                                StyledText {
                                    id: aliasText

                                    visible: !aliasDelegate.isEditing
                                    anchors.centerIn: parent
                                    text: modelData.alias
                                    font.bold: true
                                    color: Appearance.colors.colPrimary
                                }

                                TextField {
                                    id: aliasEditInput

                                    visible: aliasDelegate.isEditing
                                    anchors.fill: parent
                                    text: modelData.alias
                                    color: Appearance.colors.colPrimary
                                    font.bold: true
                                    background: null
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.small

                                    StyledTextContextMenu {
                                        id: aliasEditContextMenu
                                        targetField: aliasEditInput
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.IBeamCursor
                                        acceptedButtons: Qt.RightButton
                                        onPressed: mouse => {
                                            if (mouse.button === Qt.RightButton) {
                                                aliasEditInput.forceActiveFocus();
                                                aliasEditContextMenu.popup(mouse.x, mouse.y);
                                            }
                                        }
                                    }
                                }
                            }

                            StyledText {
                                text: modelData.target
                                color: Appearance.colors.colOnSurface
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: 18
                                colBackground: Appearance.colors.colSurfaceContainerHigh
                                colBackgroundHover: aliasDelegate.isEditing ? Appearance.colors.colSuccessContainer : Appearance.colors.colPrimaryContainer
                                onClicked: {
                                    if (aliasDelegate.isEditing) {
                                        let newAlias = aliasEditInput.text.trim();
                                        if (newAlias === "") {
                                            aliasDelegate.isEditing = false;
                                            return;
                                        }
                                        let newAliases = Array.from((Persistent.ready ? Persistent.states.search.aliases : null) || Config.options.search.aliases || []);
                                        let exists = newAliases.some((a, idx) => {
                                            return a.alias === newAlias && idx !== index;
                                        });
                                        if (!exists) {
                                            newAliases[index].alias = newAlias;
                                            if (Persistent.ready) {
                                                Persistent.states.search.aliases = newAliases;
                                            }
                                            if (Config.ready) {
                                                Config.options.search.aliases = newAliases;
                                            }
                                        }
                                        aliasDelegate.isEditing = false;
                                    } else {
                                        aliasDelegate.isEditing = true;
                                        aliasEditInput.forceActiveFocus();
                                    }
                                }

                                contentItem: Item {
                                    anchors.fill: parent

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: 18
                                        text: aliasDelegate.isEditing ? "check" : "edit"
                                        color: parent.parent.parent.hovered ? (aliasDelegate.isEditing ? Appearance.colors.colOnSuccessContainer : Appearance.colors.colOnPrimaryContainer) : (aliasDelegate.isEditing ? Appearance.colors.colSuccess : Appearance.colors.colPrimary)
                                    }
                                }
                            }

                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: 18
                                colBackground: Appearance.colors.colSurfaceContainerHigh
                                colBackgroundHover: Appearance.colors.colErrorContainer
                                onClicked: {
                                    let newAliases = Array.from((Persistent.ready ? Persistent.states.search.aliases : null) || Config.options.search.aliases || []);
                                    newAliases.splice(index, 1);
                                    if (Persistent.ready) {
                                        Persistent.states.search.aliases = newAliases;
                                    }
                                    if (Config.ready) {
                                        Config.options.search.aliases = newAliases;
                                    }
                                }

                                contentItem: Item {
                                    anchors.fill: parent

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: 18
                                        text: "delete"
                                        color: parent.parent.parent.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colError
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "add_circle"
            title: Translation.tr("Add New Alias")

            ColumnLayout {
                id: addAliasArea

                property string selectedType: "app"
                property string appFilter: ""
                property var sortedApps: AppSearch.list.length > 0 ? AppSearch.frecencyQuery("") : []
                readonly property var filteredApps: {
                    let list = sortedApps;
                    if (appFilter.trim() !== "") {
                        let f = appFilter.toLowerCase();
                        let res = list.filter(app => {
                            return app.name.toLowerCase().includes(f) || app.id.toLowerCase().includes(f);
                        });
                        return res.slice(0, 12);
                    }
                    return list.slice(0, 8);
                }

                Layout.fillWidth: true
                spacing: 12

                Item {
                    Layout.fillWidth: true
                    implicitHeight: typeSection.implicitHeight

                    ContentSubsection {
                        id: typeSection

                        title: Translation.tr("Alias Target Type")
                        icon: "my_location"
                        anchors.fill: parent

                        ConfigSelectionArray {
                            currentValue: addAliasArea.selectedType
                            onSelected: newValue => {
                                addAliasArea.selectedType = newValue;
                            }
                            options: [
                                {
                                    "displayName": Translation.tr("App"),
                                    "icon": "apps",
                                    "value": "app"
                                },
                                {
                                    "displayName": Translation.tr("Folder"),
                                    "icon": "folder",
                                    "value": "folder"
                                },
                                {
                                    "displayName": Translation.tr("Command"),
                                    "icon": "terminal",
                                    "value": "command"
                                },
                                {
                                    "displayName": Translation.tr("Built-in"),
                                    "icon": "explore",
                                    "value": "builtin"
                                }
                            ]
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        color: Appearance.colors.colSecondaryContainer
                        topLeftRadius: Appearance.rounding.full
                        bottomLeftRadius: Appearance.rounding.full
                        topRightRadius: Appearance.rounding.verysmall
                        bottomRightRadius: Appearance.rounding.verysmall

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 12

                            TextField {
                                id: newAliasInput

                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Alias (e.g. i)")
                                placeholderTextColor: Qt.rgba(Appearance.colors.colOnSecondaryContainer.r, Appearance.colors.colOnSecondaryContainer.g, Appearance.colors.colOnSecondaryContainer.b, 0.5)
                                color: Appearance.colors.colOnSecondaryContainer
                                background: null
                                font.pixelSize: Appearance.font.pixelSize.small

                                StyledTextContextMenu {
                                    id: newAliasContextMenu
                                    targetField: newAliasInput
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    acceptedButtons: Qt.RightButton
                                    onPressed: mouse => {
                                        if (mouse.button === Qt.RightButton) {
                                            newAliasInput.forceActiveFocus();
                                            newAliasContextMenu.popup(mouse.x, mouse.y);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        color: Appearance.colors.colSecondaryContainer
                        radius: Appearance.rounding.verysmall

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16

                            TextField {
                                id: newTargetInput

                                Layout.fillWidth: true
                                placeholderText: addAliasArea.selectedType === "builtin" ? Translation.tr("Select target below...") : Translation.tr("Target (e.g. app-id, path)")
                                enabled: addAliasArea.selectedType !== "builtin"
                                placeholderTextColor: Qt.rgba(Appearance.colors.colOnSecondaryContainer.r, Appearance.colors.colOnSecondaryContainer.g, Appearance.colors.colOnSecondaryContainer.b, 0.5)
                                color: Appearance.colors.colOnSecondaryContainer
                                background: null
                                font.pixelSize: Appearance.font.pixelSize.small

                                StyledTextContextMenu {
                                    id: newTargetContextMenu
                                    targetField: newTargetInput
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    acceptedButtons: Qt.RightButton
                                    onPressed: mouse => {
                                        if (mouse.button === Qt.RightButton) {
                                            newTargetInput.forceActiveFocus();
                                            newTargetContextMenu.popup(mouse.x, mouse.y);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RippleButton {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 48
                        topLeftRadius: Appearance.rounding.verysmall
                        bottomLeftRadius: Appearance.rounding.verysmall
                        topRightRadius: Appearance.rounding.full
                        bottomRightRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        rippleColor: Appearance.colors.colSecondaryContainerActive
                        onClicked: {
                            if (newAliasInput.text.trim() === "" || newTargetInput.text.trim() === "")
                                return;

                            let newAliases = Array.from((Persistent.ready ? Persistent.states.search.aliases : null) || Config.options.search.aliases || []);
                            let exists = newAliases.some(a => {
                                return a.alias === newAliasInput.text.trim();
                            });
                            if (exists)
                                return;

                            newAliases.push({
                                "alias": newAliasInput.text.trim(),
                                "type": addAliasArea.selectedType,
                                "target": newTargetInput.text.trim()
                            });
                            if (Persistent.ready) {
                                Persistent.states.search.aliases = newAliases;
                            }
                            if (Config.ready) {
                                Config.options.search.aliases = newAliases;
                            }
                            newAliasInput.text = "";
                            newTargetInput.text = "";
                        }

                        contentItem: Item {
                            anchors.fill: parent

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "add"
                                iconSize: 24
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: appsSection.implicitHeight

                    ContentSubsection {
                        id: appsSection

                        title: addAliasArea.selectedType === "app" ? Translation.tr("Search frequent apps for alias target") : (addAliasArea.selectedType === "builtin" ? Translation.tr("Select available built-in target") : Translation.tr("Enter path or command directly above"))
                        icon: "search"
                        anchors.fill: parent

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            visible: addAliasArea.selectedType === "app"

                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                color: Appearance.colors.colSurfaceContainerHigh
                                radius: 22

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "search"
                                        iconSize: 18
                                        color: appFilterInput.focus ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                    }

                                    TextField {
                                        id: appFilterInput

                                        Layout.fillWidth: true
                                        placeholderText: Translation.tr("Type application name...")
                                        placeholderTextColor: Appearance.colors.colOnSurfaceVariant
                                        color: Appearance.colors.colOnSurface
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        background: null
                                        clip: true
                                        onTextChanged: addAliasArea.appFilter = text

                                        StyledTextContextMenu {
                                            id: appFilterContextMenu
                                            targetField: appFilterInput
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.IBeamCursor
                                            acceptedButtons: Qt.RightButton
                                            onPressed: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    appFilterInput.forceActiveFocus();
                                                    appFilterContextMenu.popup(mouse.x, mouse.y);
                                                }
                                            }
                                        }
                                    }

                                    IconToolbarButton {
                                        visible: appFilterInput.text !== ""
                                        text: "close"
                                        implicitHeight: 28
                                        implicitWidth: 28
                                        colText: Appearance.colors.colOnSurfaceVariant
                                        onClicked: appFilterInput.text = ""
                                    }
                                }
                            }

                            Flow {
                                id: appTargetFlow
                                Layout.fillWidth: true
                                Layout.preferredHeight: appTargetFlow.implicitHeight
                                spacing: 8

                                Repeater {
                                    model: addAliasArea.filteredApps

                                    delegate: Rectangle {
                                        id: chip

                                        color: chipMouse.containsMouse ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                                        radius: 18
                                        width: appLayout.implicitWidth + 24
                                        height: 36

                                        RowLayout {
                                            id: appLayout

                                            anchors.centerIn: parent
                                            spacing: 6

                                            WAppIcon {
                                                iconName: modelData.icon
                                                implicitSize: 16
                                                tryCustomIcon: false
                                            }

                                            StyledText {
                                                text: modelData.name
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.bold: chipMouse.containsMouse
                                                color: chipMouse.containsMouse ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                            }
                                        }

                                        MouseArea {
                                            id: chipMouse

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                newTargetInput.text = modelData.id;
                                                addAliasArea.selectedType = "app";
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Flow {
                            id: builtinFlow
                            property var builtins: SearchPanelRegistry.aliasTargets.concat([
                                { "id": "math", "name": Translation.tr("Calculator Mode"), "icon": "calculate" }
                            ])

                            Layout.fillWidth: true
                            Layout.preferredHeight: builtinFlow.implicitHeight
                            spacing: 8
                            visible: addAliasArea.selectedType === "builtin"

                            Repeater {
                                model: parent.builtins

                                delegate: Rectangle {
                                    id: builtinChip

                                    property bool selected: newTargetInput.text === modelData.id

                                    color: selected ? Appearance.colors.colPrimaryContainer : (builtinMouse.containsMouse ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh)
                                    radius: 18
                                    width: builtinLayout.implicitWidth + 24
                                    height: 36

                                    RowLayout {
                                        id: builtinLayout

                                        anchors.centerIn: parent
                                        spacing: 6

                                        MaterialSymbol {
                                            text: modelData.icon
                                            iconSize: 16
                                            color: builtinChip.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                        }

                                        StyledText {
                                            text: modelData.name + (modelData.enabled === false
                                                ? " · " + Translation.tr("Disabled")
                                                : "")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: builtinChip.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                            font.bold: builtinChip.selected
                                        }
                                    }

                                    MouseArea {
                                        id: builtinMouse

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            newTargetInput.text = modelData.id;
                                            newAliasInput.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
