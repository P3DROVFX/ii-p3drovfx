import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import "TimetableHelpers.js" as H

/**
 * Two mutually exclusive colour vocabularies.
 *
 * Theme tokens follow the wallpaper, which is what a local event wants. A Google
 * event instead has a colour the user already picked over there, so for those we
 * offer Google's own eleven colours and write the `colorId` back — otherwise the
 * two sides would disagree on every sync.
 */
Flow {
    id: root

    property string currentToken: ""
    property bool includeCalendarDefault: true

    /** Offer Google's palette instead of theme tokens. */
    property bool googleMode: false
    property string currentColorId: ""

    signal tokenSelected(string token)
    signal googleColorSelected(string colorId)

    readonly property var options: [
        { token: "", label: Translation.tr("Calendar") },
        { token: "primary", label: Translation.tr("Primary") },
        { token: "secondary", label: Translation.tr("Secondary") },
        { token: "tertiary", label: Translation.tr("Tertiary") },
        { token: "error", label: Translation.tr("Error") },
        { token: "primaryContainer", label: Translation.tr("Primary container") },
        { token: "secondaryContainer", label: Translation.tr("Secondary container") },
        { token: "tertiaryContainer", label: Translation.tr("Tertiary container") },
        { token: "errorContainer", label: Translation.tr("Error container") }
    ]

    readonly property var googleOptions: {
        const entries = [{ id: "", background: "", label: Translation.tr("Calendar") }];
        for (const option of GoogleCalendarService.colorOptions)
            entries.push({ id: option.id, background: option.background, label: Translation.tr("Google colour %1").arg(option.id) });
        return entries;
    }

    spacing: 6

    Repeater {
        model: root.googleMode ? [] : (root.includeCalendarDefault ? root.options : root.options.slice(1))

        delegate: RippleButton {
            id: colorButton
            required property var modelData

            readonly property bool selected: root.currentToken === modelData.token
            readonly property color tokenColor: modelData.token
                ? H.themeColorForToken(modelData.token, Appearance.colors)
                : Appearance.colors.colSurfaceContainerHighest

            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackground: tokenColor
            colBackgroundHover: H.themeHoverColorForToken(modelData.token, Appearance.colors)
            onClicked: root.tokenSelected(modelData.token)

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                visible: colorButton.selected
                text: "check"
                iconSize: Appearance.font.pixelSize.small
                color: ColorUtils.getContrastingTextColor(colorButton.tokenColor)
            }

            StyledToolTip {
                extraVisibleCondition: colorButton.hovered
                text: modelData.label
            }
        }
    }

    Repeater {
        model: root.googleMode ? root.googleOptions : []

        delegate: RippleButton {
            id: googleButton
            required property var modelData

            readonly property bool selected: root.currentColorId === modelData.id
            readonly property color swatch: String(modelData.background).length > 0
                ? modelData.background
                : Appearance.colors.colSurfaceContainerHighest

            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackground: googleButton.swatch
            colBackgroundHover: ColorUtils.mix(googleButton.swatch, Appearance.colors.colOnSurface, 0.88)
            onClicked: root.googleColorSelected(modelData.id)

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                visible: googleButton.selected
                text: "check"
                iconSize: Appearance.font.pixelSize.small
                color: ColorUtils.getContrastingTextColor(googleButton.swatch)
            }

            StyledToolTip {
                extraVisibleCondition: googleButton.hovered
                text: modelData.label
            }
        }
    }
}
