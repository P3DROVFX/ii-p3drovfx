import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property bool nextButtonHovered: false

    readonly property var layoutOptions: {
        // The same shortlist the Hyprland settings page offers, kept in XkbCatalog so the two
        // cannot drift apart.
        const options = Array.from(XkbCatalog.commonLayouts).map(entry => ({
            "code": entry.code, "label": entry.label
        }));
        const current = HyprlandXkb.layoutCodes.length > 0 ? HyprlandXkb.layoutCodes[0] : "";
        if (current.length > 0 && options.findIndex(option => option.code === current) < 0)
            options.unshift({ "code": current, "label": Translation.tr("Current (%1)").arg(current) });
        return options;
    }

    property string selectedLayoutCode: HyprlandXkb.layoutCodes.length > 0
        ? HyprlandXkb.layoutCodes[0]
        : "us"
    property bool manualEntry: false
    property bool statusIsError: false
    property string statusText: ""
    property bool persistencePending: false
    readonly property bool navigationLocked: root.persistencePending
    signal advanceRequested()

    readonly property string desiredLayoutValue: root.manualEntry
        ? root.normalizeValue(manualLayoutField.text, false)
        : root.selectedLayoutCode
    readonly property string desiredVariantValue: root.manualEntry
        ? root.normalizeValue(manualVariantField.text, true)
        : ""
    readonly property bool inputInvalid: root.manualEntry
        && (root.desiredLayoutValue.length === 0
            || (manualVariantField.text.trim().length > 0 && root.desiredVariantValue.length === 0))
    readonly property bool hasChanges: root.inputInvalid
        || root.desiredLayoutValue !== HyprlandXkb.layoutCodes.join(",")
        || root.desiredVariantValue !== HyprlandXkb.layoutVariants.join(",")
    readonly property string nextLabel: root.hasChanges
        ? Translation.tr("Save to Hyprland")
        : Translation.tr("Next")
    readonly property string nextIcon: root.hasChanges ? "save" : "keyboard"

    Timer {
        id: feedbackTimer
        interval: 2400
        onTriggered: root.statusText = ""
    }

    function normalizeValue(value, allowEmpty): string {
        const parts = String(value ?? "").split(",").map(part => part.trim());
        if (!allowEmpty && parts.some(part => part.length === 0))
            return "";
        for (const part of parts) {
            if (!/^[A-Za-z0-9_-]*$/.test(part))
                return "";
        }
        return parts.join(",");
    }

    function applyKeyboardLayout(): bool {
        if (root.persistencePending)
            return false;

        const layoutValue = root.desiredLayoutValue;
        const variantValue = root.desiredVariantValue;
        if (layoutValue.length === 0) {
            root.statusIsError = true;
            root.statusText = Translation.tr("Enter at least one valid XKB layout code, such as us or br.");
            feedbackTimer.restart();
            return false;
        }
        if (root.manualEntry && variantValue.length === 0 && manualVariantField.text.trim().length > 0) {
            root.statusIsError = true;
            root.statusText = Translation.tr("Use only letters, numbers, underscores and hyphens in variants.");
            feedbackTimer.restart();
            return false;
        }

        if (!HyprlandConfig.persistWelcomeKeyboardLayout(layoutValue, variantValue))
            return false;

        root.persistencePending = true;
        root.statusIsError = false;
        root.statusText = Translation.tr("Applying and saving keyboard layout…");
        feedbackTimer.restart();
        return false;
    }

    function prepareNext(): bool {
        return !root.hasChanges || root.applyKeyboardLayout();
    }

    function syncManualFields() {
        if (!manualLayoutField.activeFocus)
            manualLayoutField.text = HyprlandXkb.layoutCodes.join(",");
        if (!manualVariantField.activeFocus)
            manualVariantField.text = HyprlandXkb.layoutVariants.join(",");
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.large
        anchors.rightMargin: Appearance.rounding.large
        anchors.topMargin: Appearance.rounding.small
        spacing: Appearance.rounding.small

        ListView {
            id: layoutList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Appearance.rounding.large * 12
            // Let the hover scale breathe past the list viewport. The
            // Welcome window remains the outer clipping boundary.
            clip: false
            spacing: Appearance.rounding.verysmall
            boundsBehavior: Flickable.StopAtBounds
            model: root.layoutOptions

            delegate: RippleButton {
                id: layoutButton
                required property var modelData
                width: layoutList.width
                implicitHeight: Appearance.rounding.large * 2.5
                buttonRadius: Appearance.rounding.normal
                toggled: !root.manualEntry && root.selectedLayoutCode === modelData.code
                colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                colBackgroundHover: toggled ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
                colBackgroundActive: toggled ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active
                colRipple: toggled ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active
                opacity: root.manualEntry ? 0.55 : 1
                Accessible.name: modelData.label

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Appearance.rounding.normal
                    anchors.rightMargin: Appearance.rounding.normal
                    spacing: Appearance.rounding.small

                    MaterialSymbol {
                        text: "keyboard"
                        iconSize: Appearance.font.pixelSize.large
                        color: layoutButton.toggled
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: layoutButton.modelData.label
                        color: layoutButton.toggled
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer1
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: layoutButton.toggled ? Font.Bold : Font.DemiBold
                    }

                    MaterialSymbol {
                        visible: layoutButton.toggled
                        text: "check"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimary
                    }
                }

                onClicked: root.selectedLayoutCode = layoutButton.modelData.code
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            forceUniformRadius: true
            buttonIcon: "edit"
            text: Translation.tr("Enter a custom layout manually")
            checked: root.manualEntry
            onCheckedChanged: {
                if (root.manualEntry !== checked)
                    root.manualEntry = checked;
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.manualEntry
            spacing: Appearance.rounding.verysmall

            MaterialTextField {
                id: manualLayoutField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Layout codes, for example us,br")
                text: HyprlandXkb.layoutCodes.join(",")
            }

            MaterialTextField {
                id: manualVariantField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Variants, optional; for example ,abnt2")
                text: HyprlandXkb.layoutVariants.join(",")
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: statusLabel.implicitHeight
            visible: root.statusText.length > 0

            StyledText {
                id: statusLabel
                anchors.fill: parent
                text: root.statusText
                color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
        }

    }

    Connections {
        target: HyprlandConfig
        function onWelcomeKeyboardLayoutPersisted(success, message) {
            if (!root.persistencePending)
                return;

            root.persistencePending = false;
            root.statusIsError = !success;
            root.statusText = success
                ? Translation.tr("Keyboard layout saved to Hyprland.")
                : Translation.tr("Could not save keyboard layout. %1").arg(message || Translation.tr("Try again."));
            feedbackTimer.restart();
            if (success)
                root.advanceRequested();
        }
    }

    Connections {
        target: HyprlandXkb
        function onLayoutCodesChanged() {
            root.syncManualFields();
        }
        function onLayoutVariantsChanged() {
            root.syncManualFields();
        }
    }
}
