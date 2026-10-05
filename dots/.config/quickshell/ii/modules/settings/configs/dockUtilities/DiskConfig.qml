import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Which disk the widget measures: every mounted filesystem (pseudo ones left
 * out) with how full it is. The choice is `resources.diskMount`, shared with
 * the bar's system monitor and the resources popup.
 */
UtilityConfigPage {
    id: page
    title: Translation.tr("Disk usage")

    property var mounts: []

    Process {
        running: true
        command: ["bash", "-c", "LANG=C LC_ALL=C df -B1 -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs --output=target,size,used,source | tail -n +2"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const out = [];
                for (const line of this.text.split("\n")) {
                    const parts = line.trim().split(/\s+/);
                    if (parts.length < 4 || seen[parts[0]])
                        continue;
                    seen[parts[0]] = true;
                    out.push({ target: parts[0], size: Number(parts[1]), used: Number(parts[2]), source: parts[3] });
                }
                page.mounts = out;
            }
        }
    }

    function bytes(value) {
        const units = ["B", "KB", "MB", "GB", "TB", "PB"];
        let v = Math.max(0, Number(value) || 0);
        let i = 0;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
    }

    ContentSection {
        title: Translation.tr("Disk")
        icon: "hard_drive"
        tooltip: Translation.tr("Shared with the system monitor and the resources popup")

        Repeater {
            model: page.mounts
            delegate: RippleButton {
                id: mountRow
                required property var modelData
                required property int index
                readonly property bool chosen: (Config.options.resources.diskMount ?? "/") === mountRow.modelData.target
                readonly property real fraction: mountRow.modelData.size > 0 ? mountRow.modelData.used / mountRow.modelData.size : 0
                Layout.fillWidth: true
                implicitHeight: 64
                buttonRadius: mountRow.index === 0 ? Appearance.rounding.normal : Appearance.rounding.small
                colBackground: mountRow.chosen ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: mountRow.chosen ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: Config.options.resources.diskMount = mountRow.modelData.target

                contentItem: Item {
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 16
                        spacing: 12
                        MaterialShapeWrappedMaterialSymbol {
                            text: mountRow.modelData.target === "/" ? "hard_drive" : "folder"
                            iconSize: 18
                            padding: 8
                            shape: mountRow.chosen ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                            color: mountRow.chosen ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                            colSymbol: mountRow.chosen ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: mountRow.modelData.target
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: mountRow.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                    elide: Text.ElideMiddle
                                }
                                StyledText {
                                    text: Translation.tr("%1 of %2").arg(page.bytes(mountRow.modelData.used)).arg(page.bytes(mountRow.modelData.size))
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: mountRow.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.12)
                                Rectangle {
                                    height: parent.height
                                    radius: 3
                                    width: Math.max(height, parent.width * mountRow.fraction)
                                    color: mountRow.fraction >= 0.9 ? Appearance.colors.colError : Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: page.mounts.length === 0
            text: Translation.tr("Looking for disks…")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
