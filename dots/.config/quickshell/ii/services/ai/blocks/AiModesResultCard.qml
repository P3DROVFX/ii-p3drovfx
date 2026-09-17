import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * What a modes tool actually wrote: the definition's name, what happened to
 * it, and the one hop that opens it in the Modes & Routines editor. The card
 * is a record of a finished write, not an approval — deletions use their own
 * preview card — so the button is always safe to press.
 */
Rectangle {
    id: root

    property var messageData: null
    property var card: null
    // `payload`, not `data`: the latter is QtObject's own read-only property
    // and declaring it breaks the type.
    readonly property var payload: root.card?.data ?? ({})

    implicitHeight: contentRow.implicitHeight + Appearance.rounding.normal
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSecondaryContainer

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.unsharpenmore
        anchors.rightMargin: Appearance.rounding.small
        spacing: Appearance.rounding.unsharpenmore

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            // The definition's own icon when the engine still holds it, so
            // the card and the list row read as the same object.
            text: String(root.payload.icon ?? (root.payload.kind === "routine" ? "bolt" : "tune"))
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.m3colors.m3onSecondaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: {
                    switch (String(root.payload.operation ?? "")) {
                    case "update":
                        return Translation.tr("Rewrote “%1”").arg(String(root.payload.name ?? ""));
                    case "start":
                        return Translation.tr("Started “%1”").arg(String(root.payload.name ?? ""));
                    case "stop":
                        return Translation.tr("Stopped “%1”").arg(String(root.payload.name ?? ""));
                    case "delete":
                        return Translation.tr("Deleted “%1”").arg(String(root.payload.name ?? ""));
                    }
                    return Translation.tr("Created “%1”").arg(String(root.payload.name ?? ""));
                }
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.m3colors.m3onSecondaryContainer
            }

            StyledText {
                Layout.fillWidth: true
                text: String(root.payload.detail ?? "")
                visible: text.length > 0
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3onSecondaryContainer
            }
        }

        // Deletions leave nothing to open.
        RippleButton {
            visible: String(root.payload.operation ?? "") !== "delete"
                && String(root.payload.id ?? "").length > 0
            leftPadding: Appearance.rounding.small
            rightPadding: Appearance.rounding.small
            topPadding: Appearance.rounding.unsharpenmore / 2
            bottomPadding: Appearance.rounding.unsharpenmore / 2
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: Modes.openAndReveal(String(root.payload.kind ?? "mode"), String(root.payload.id ?? ""))

            contentItem: StyledText {
                text: Translation.tr("Open")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3onSecondaryContainer
            }
        }
    }
}
