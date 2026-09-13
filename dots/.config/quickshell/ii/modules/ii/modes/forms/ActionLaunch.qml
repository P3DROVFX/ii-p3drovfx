pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Parameters of the `launch` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: launchCol
    required property var row

    spacing: 10

    property string appQuery: ""
    readonly property var appResults: {
        const q = appQuery.trim();
        if (!q.length)
            return [];
        return Array.from(AppSearch.fuzzyQuery(q)).slice(0, 6);
    }
    readonly property bool useCommand: (row.obj.command ?? "").length > 0 && !(row.obj.app ?? "").length

    FormChoice {
        current: launchCol.useCommand ? "command" : "app"
        onPicked: v => row.patchValue(v === "command" ? { app: "", command: row.obj.command || "" }
                                                        : { command: "", app: row.obj.app || "" })
        options: [
            { displayName: Translation.tr("An app"), value: "app" },
            { displayName: Translation.tr("A command"), value: "command" }
        ]
    }

    // App: the chosen entry, or a search to choose one.
    ColumnLayout {
        id: appPicker
        Layout.fillWidth: true
        visible: !launchCol.useCommand
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                visible: (row.obj.app ?? "").length > 0
                implicitWidth: chosenRow.implicitWidth + 20
                implicitHeight: 32
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: chosenRow
                    anchors.centerIn: parent
                    spacing: 6

                    StyledText {
                        text: DesktopEntries.byId(row.obj.app ?? "")?.name ?? (row.obj.app ?? "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    MouseArea {
                        implicitWidth: 18
                        implicitHeight: 18
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.patchValue({ app: "" })

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer3
                border.width: appSearch.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary

                StyledTextInput {
                    id: appSearch
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 14
                    }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.colors.colOnLayer3
                    clip: true
                    onTextChanged: launchCol.appQuery = text

                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !appSearch.text.length
                        text: (row.obj.app ?? "").length ? Translation.tr("Search to replace")
                                                          : Translation.tr("Search apps")
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        Repeater {
            model: launchCol.appResults

            delegate: RippleButton {
                id: appResult
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: {
                    row.patchValue({ app: appResult.modelData.id, command: "" });
                    appSearch.text = "";
                }

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 10
                    }
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: appResult.modelData.name
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        text: appResult.modelData.id
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    PlainField {
        Layout.fillWidth: true
        visible: launchCol.useCommand
        monospace: true
        value: String(row.obj.command ?? "")
        placeholder: Translation.tr("Command line, run with sh -c")
        onCommitted: v => row.patchValue({ command: v, app: "" })
    }

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("When it ends")
        }

        FormChoice {
            current: row.obj.onEnd ?? "keep"
            onPicked: v => row.patchValue({ onEnd: v })
            options: [
                { displayName: Translation.tr("Leave it open"), value: "keep" },
                { displayName: Translation.tr("Close it"), value: "close" }
            ]
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: (row.obj.onEnd ?? "keep") === "close"
        spacing: 10

        FormLabel {
            text: Translation.tr("Window class")
        }

        PlainField {
            Layout.fillWidth: true
            value: String(row.obj["class"] ?? "")
            placeholder: Translation.tr("Only if it differs from the app's own")
            onCommitted: v => row.patchValue({ "class": v })
        }
    }
}
