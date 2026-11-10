pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import qs.modules.ii.clock.components
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

            // The chosen app as a filled chip with its own remove button.
            Rectangle {
                visible: (row.obj.app ?? "").length > 0
                implicitWidth: chosenRow.implicitWidth + ClockStyle.gap + ClockStyle.gapTiny
                implicitHeight: 40
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colSecondaryContainer

                RowLayout {
                    id: chosenRow
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapTiny + 2

                    StyledText {
                        Layout.leftMargin: 2
                        text: DesktopEntries.byId(row.obj.app ?? "")?.name ?? (row.obj.app ?? "")
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSecondaryContainer
                    }

                    RippleButton {
                        implicitWidth: 24
                        implicitHeight: 24
                        buttonRadius: 12
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.applyAlpha(ClockStyle.colOnSecondaryContainer, 0.12)
                        colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSecondaryContainer, 0.2)
                        onClicked: row.patchValue({ app: "" })

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 16
                            color: ClockStyle.colOnSecondaryContainer
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: ClockStyle.radiusSmall
                color: appSearch.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: ClockStyle.gap
                        rightMargin: ClockStyle.gap + 2
                    }
                    spacing: ClockStyle.gapSmall

                    MaterialSymbol {
                        text: "search"
                        iconSize: ClockStyle.iconSmall + 2
                        color: ClockStyle.colOnSurfaceVariant
                    }

                    StyledTextInput {
                        id: appSearch
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: ClockStyle.colOnSurface
                        font.pixelSize: ClockStyle.textNormal
                        clip: true
                        onTextChanged: launchCol.appQuery = text

                        StyledText {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !appSearch.text.length
                            text: (row.obj.app ?? "").length ? Translation.tr("Search to replace")
                                                              : Translation.tr("Search apps")
                            font.pixelSize: ClockStyle.textNormal
                            color: Appearance.colors.colOnLayer1Inactive
                        }
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
                implicitHeight: 44
                buttonRadius: ClockStyle.radiusSmall
                colBackground: ClockStyle.colField
                colBackgroundHover: ClockStyle.colFieldHover
                colRipple: ClockStyle.colSurfaceActive
                onClicked: {
                    row.patchValue({ app: appResult.modelData.id, command: "" });
                    appSearch.text = "";
                }

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: ClockStyle.gap
                        rightMargin: ClockStyle.gap
                    }
                    spacing: ClockStyle.gapSmall

                    MaterialSymbol {
                        text: "add"
                        iconSize: ClockStyle.iconSmall
                        color: ClockStyle.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: appResult.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSurface
                    }

                    StyledText {
                        text: appResult.modelData.id
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
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
