import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings > About > Optional features.
 *
 * The packages this fork uses on top of the base install (FeatureDeps), one
 * row per feature, each with a way to install it through the setup script's
 * `deps` command in a terminal. A sub-page, because the list is long and About
 * is opened for updates.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    property alias contentY: page.contentY

    Component.onCompleted: FeatureDeps.refresh()

    // One optional feature: what it is, whether it is here, and a way to get it.
    component FeatureRow: Rectangle {
        id: featureRow
        property var feature: ({})
        property bool first: false
        property bool last: false
        readonly property string status: feature.status ?? "missing"
        readonly property bool canInstall: status !== "installed" && (feature.installable ?? false)
        readonly property var missingNames: Array.from(feature.packages ?? []).filter(p => !p.present).map(p => p.name)
        readonly property bool needsHelper: Array.from(feature.packages ?? []).some(p => !p.present && p.aur && !p.installable)

        implicitHeight: featureLayout.implicitHeight + 20
        color: Appearance.colors.colLayer2
        topLeftRadius: first ? Appearance.rounding.normal : Appearance.rounding.unsharpen
        topRightRadius: topLeftRadius
        bottomLeftRadius: last ? Appearance.rounding.normal : Appearance.rounding.unsharpen
        bottomRightRadius: bottomLeftRadius

        RowLayout {
            id: featureLayout
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 14
                rightMargin: 10
            }
            spacing: 12

            MaterialSymbol {
                text: {
                    switch (featureRow.status) {
                    case "installed":
                        return "check_circle";
                    case "partial":
                        return "incomplete_circle";
                    case "unavailable":
                        return "block";
                    default:
                        return "radio_button_unchecked";
                    }
                }
                iconSize: Appearance.font.pixelSize.larger
                color: featureRow.status === "installed" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: featureRow.feature.label ?? ""
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: {
                        const description = featureRow.feature.description ?? "";
                        if (featureRow.status === "installed")
                            return description;
                        if (featureRow.status === "unavailable")
                            return Translation.tr("%1 Not packaged for %2.").arg(description).arg(FeatureDeps.distro);
                        if (featureRow.needsHelper)
                            return Translation.tr("%1 Needs %2, from the AUR: install yay or paru first.").arg(description).arg(featureRow.missingNames.join(", "));
                        return Translation.tr("%1 Needs %2.").arg(description).arg(featureRow.missingNames.join(", "));
                    }
                }
            }

            RippleButtonWithIcon {
                visible: featureRow.canInstall
                Layout.preferredHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                materialIcon: "download"
                mainText: Translation.tr("Install")
                onClicked: FeatureDeps.install([featureRow.feature.id])

                StyledToolTip {
                    text: Translation.tr("Opens a terminal that installs %1 after asking").arg(featureRow.missingNames.join(", "))
                }
            }
        }
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Optional features")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "extension"
            title: Translation.tr("Optional features")
            tooltip: Translation.tr("Some features need a package the base install does not bring. Install opens a terminal running 'II-P3DROVFX deps', which asks before installing anything. 'II-P3DROVFX deps remove <id>' takes back only what it installed.")

            Rectangle {
                visible: FeatureDeps.requiredMissing.length > 0
                Layout.fillWidth: true
                implicitHeight: coreRow.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colErrorContainer

                RowLayout {
                    id: coreRow
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 12

                    MaterialSymbol {
                        text: "warning"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnErrorContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnErrorContainer
                        text: Translation.tr("Core packages missing: %1. Parts of the shell do not work without them.")
                            .arg(FeatureDeps.requiredMissing.map(f => f.label).join(", "))
                    }

                    RippleButtonWithIcon {
                        visible: FeatureDeps.requiredMissing.some(f => f.installable)
                        Layout.preferredHeight: 40
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colError
                        colBackgroundHover: Appearance.colors.colErrorHover
                        colRipple: Appearance.colors.colErrorActive
                        colText: Appearance.colors.colOnError
                        materialIcon: "download"
                        mainText: Translation.tr("Install")
                        onClicked: FeatureDeps.install(["core"])
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.Wrap
                    text: {
                        if (FeatureDeps.error !== "")
                            return FeatureDeps.error;
                        if (!FeatureDeps.loaded)
                            return Translation.tr("Checking installed packages…");
                        return Translation.tr("%1 of %2 installed").arg(FeatureDeps.optionalInstalled).arg(FeatureDeps.optionalFeatures.length);
                    }
                }

                RippleButtonWithIcon {
                    Layout.preferredHeight: 36
                    buttonRadius: Appearance.rounding.full
                    materialIcon: "refresh"
                    mainText: Translation.tr("Refresh")
                    enabled: !FeatureDeps.loading
                    onClicked: FeatureDeps.refresh()

                    StyledToolTip {
                        text: Translation.tr("Check again after installing something in the terminal")
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: FeatureDeps.optionalFeatures

                    delegate: FeatureRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        feature: modelData
                        first: index === 0
                        last: index === FeatureDeps.optionalFeatures.length - 1
                    }
                }
            }
        }
    }
}
