import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

SectionCard {
    title: Translation.tr("Current Transfer")
    icon: "devices"
    shapeColor: Appearance.colors.colPrimaryContainer
    symbolColor: Appearance.colors.colOnPrimaryContainer

    ColumnLayout {
        spacing: 8

        StyledText {
            text: Translation.tr("Sender: %1").arg(LocalSend.currentTransfer?.sender || "Unknown")
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideMiddle
        }

        Repeater {
            model: {
                const files = LocalSend.currentTransfer?.files || []
                return files.slice(0, 3) // first 3
            }

            delegate: RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: "description"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        var size = modelData.size || 0
                        var sizeStr = size + " B"
                        if (size >= 1024 && size < 1024 * 1024) {
                            sizeStr = (size / 1024).toFixed(1) + " KB"
                        } else if (size >= 1024 * 1024) {
                            sizeStr = (size / (1024 * 1024)).toFixed(1) + " MB"
                        }
                        return modelData.name + " (" + sizeStr + ")"
                    }
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.normal
                    elide: Text.ElideMiddle
                }
            }
        }

        StyledText {
            visible: (LocalSend.currentTransfer?.files?.length || 0) > 3
            text: Translation.tr("... and %1 more files").arg((LocalSend.currentTransfer?.files?.length || 0) - 3)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        RowLayout {
            spacing: 8

            RippleButton {
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: LocalSend.acceptTransfer()
                contentItem: RowLayout {
                    spacing: 18
                    anchors.centerIn: parent
                    MaterialSymbol {
                        text: "check_circle"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: Translation.tr("Accept")
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                onClicked: LocalSend.denyTransfer()
                contentItem: RowLayout {
                    spacing: 18
                    anchors.centerIn: parent
                    MaterialSymbol {
                        text: "cancel"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: Translation.tr("Deny")
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
            }
        }
    }
}
