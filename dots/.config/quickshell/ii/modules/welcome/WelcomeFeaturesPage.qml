pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * A presentation list of apps the shell ships with, one page of the tour.
 *
 * The step is optional twice over: it can be skipped as a whole, and nothing
 * on it has to be opened. Each row only says what the app is, which key opens
 * it, and offers to open it now — the same shape as the shortcuts step, with
 * the explanation the shortcut cards have no room for.
 *
 * The rows come from `WelcomeFeatureRegistry`, filtered by `featurePage`; the
 * keys come from `WelcomeKeybindRegistry`, so a rebound key shows rebound.
 */
Item {
    id: root

    /** Which group of `WelcomeFeatureRegistry.features` this page lists. */
    property string featurePage: ""
    property bool nextButtonHovered: false
    readonly property string skipLabel: Translation.tr("Skip")

    readonly property var features: WelcomeFeatureRegistry.featuresFor(root.featurePage)

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.rounding.small

        Repeater {
            model: root.features

            delegate: WelcomeFeatureRow {
                required property var modelData

                Layout.fillWidth: true
                title: Translation.tr(modelData.titleKey)
                description: Translation.tr(modelData.descriptionKey)
                note: WelcomeFeatureRegistry.noteFor(modelData.id)
                materialIcon: modelData.icon
                shape: modelData.shape
                keys: WelcomeKeybindRegistry.keysFor(modelData.id)
                performed: WelcomeKeybindRegistry.hasPerformed(modelData.id)
                onActivated: WelcomeFeatureRegistry.open(modelData.id)
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Opening one leaves this guide right where it is. None of them is required.")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.smaller
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
}
