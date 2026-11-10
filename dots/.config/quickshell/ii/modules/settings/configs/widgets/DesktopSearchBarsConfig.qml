pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.utility
import qs.modules.settings.configs.widgets

/*
 * One page for the Pixel-style search bars - Pixel Search Bar and Search with
 * Shortcuts (both 2x0.5). The bar itself always opens the launcher's search;
 * every other key is picked here from the same list.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var pixel: Config.options.background.widgets.search_pixel
    readonly property var shortcuts: Config.options.background.widgets.search_shortcuts

    SearchActions {
        id: actions
    }
    // The bar already searches; its keys pick from everything else.
    readonly property var keyOptions: actions.catalog.filter(entry => entry.value !== "search")

    WidgetPageHeader {
        title: Translation.tr("Search Bar Widgets Options")
        onBack: root.goBack()
    }

    WidgetPreviewStage {
        columns: 2
        rows: 1

        WidgetPreviewSlot {
            columnSpan: 2
            height: 76
            PixelSearchBarWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            columnSpan: 2
            y: 96
            height: 124
            SearchShortcutsWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    component KeyPicker: ColumnLayout {
        id: picker
        property string label
        property var section
        property string key
        property string fallback
        Layout.fillWidth: true
        spacing: 2

        ContentSubsectionLabel { text: picker.label }
        ConfigSelectionArray {
            currentValue: picker.section?.[picker.key] ?? picker.fallback
            onSelected: newValue => picker.section[picker.key] = newValue
            options: root.keyOptions
        }
    }

    component HintField: ConfigTextField {
        id: hintField
        property var section
        text: Translation.tr("Hint text")
        icon: "short_text"
        placeholderText: Translation.tr("Leave empty for the default")
        Component.onCompleted: inputText = hintField.section?.hint ?? ""
        textField.onTextChanged: {
            if (textField.activeFocus)
                hintField.section.hint = textField.text.trim();
        }
    }

    ContentSection {
        title: Translation.tr("Pixel Search Bar (2x0.5)")
        icon: "search"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "search_pixel" }
            WidgetSizeSlider { options: root.pixel }

            ContentSubsectionLabel { text: Translation.tr("Logo") }
            ConfigSelectionArray {
                currentValue: root.pixel.logo ?? "google"
                onSelected: newValue => root.pixel.logo = newValue
                options: [
                    { displayName: "Google", icon: "g_mobiledata", value: "google" },
                    { displayName: Translation.tr("Distro"), icon: "computer", value: "distro" },
                    { displayName: Translation.tr("Search glyph"), icon: "search", value: "spark" }
                ]
            }

            HintField { section: root.pixel }

            KeyPicker { label: Translation.tr("First key in the bar"); section: root.pixel; key: "action1"; fallback: "lens" }
            KeyPicker { label: Translation.tr("Second key in the bar"); section: root.pixel; key: "action2"; fallback: "music_rec" }
            KeyPicker { label: Translation.tr("Circle beside the bar"); section: root.pixel; key: "action3"; fallback: "ai_chat" }
        }
    }

    ContentSection {
        title: Translation.tr("Search with Shortcuts (2x0.5)")
        icon: "manage_search"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            WidgetPlacementNote { widgetId: "search_shortcuts" }
            WidgetSizeSlider { options: root.shortcuts }

            HintField { section: root.shortcuts }

            KeyPicker { label: Translation.tr("Key in the bar"); section: root.shortcuts; key: "barAction"; fallback: "ai_chat" }
            KeyPicker { label: Translation.tr("Shortcut 1"); section: root.shortcuts; key: "shortcut1"; fallback: "clipboard" }
            KeyPicker { label: Translation.tr("Shortcut 2"); section: root.shortcuts; key: "shortcut2"; fallback: "emojis" }
            KeyPicker { label: Translation.tr("Shortcut 3"); section: root.shortcuts; key: "shortcut3"; fallback: "files" }
            KeyPicker { label: Translation.tr("Shortcut 4"); section: root.shortcuts; key: "shortcut4"; fallback: "lens" }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
