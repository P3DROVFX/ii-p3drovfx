import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

Item {
    id: root
    anchors.fill: parent

    readonly property var activeJobs: ProgressService.jobs
    readonly property var activeJob: activeJobs.length > 0 ? activeJobs[0] : null

    // --- Contracted View (Icon + Rounded Rectangle filling the remaining space) ---
    Item {
        id: contractedLayout
        anchors.fill: parent

        // Left: Program/App Icon Container using SineCookie
        Item {
            id: iconWrapper
            width: 26
            height: 26
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter

            SineCookie {
                anchors.fill: parent
                implicitSize: 26
                sides: 14
                amplitude: 1.5
                color: Appearance.colors.colSurfaceContainer
                constantlyRotate: root.activeJob && root.activeJob.state === "running"
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: {
                    if (!root.activeJob)
                        return "sync";
                    if (root.activeJob.state === "completed")
                        return "check";
                    if (root.activeJob.state === "failed")
                        return "error";
                    // The shell's own jobs name their glyph: a download, a speed test.
                    if (root.activeJob.icon)
                        return root.activeJob.icon;
                    if (root.activeJob.source === "notification")
                        return "download";
                    return "sync";
                }
                iconSize: 14
                color: root.activeJob && root.activeJob.state === "completed" ? Appearance.m3colors.m3success : Appearance.colors.colPrimary
            }
        }

        // Right: Rounded Rectangle holding File Name, Percent, and Wavy ProgressBar
        // Spans completely from the icon's right edge to the notch right margin
        Rectangle {
            anchors.left: iconWrapper.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - 8 // Fills vertically leaving 4px margin top and bottom
            color: Appearance.colors.colSurfaceContainerHighest
            radius: Appearance.rounding.verysmall

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 2
                anchors.bottomMargin: 2
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                        text: {
                            if (!root.activeJob)
                                return "";
                            // A job may say how it ended: a speed test's result, say.
                            if (root.activeJob.state !== "running" && root.activeJob.doneText)
                                return root.activeJob.doneText;
                            if (root.activeJob.state === "completed") {
                                return Translation.tr("Transfer completed!");
                            }
                            return root.activeJob.message || root.activeJob.appName;
                        }
                        elide: Text.ElideRight
                    }

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.bold: true
                        color: root.activeJob && root.activeJob.state === "completed" ? Appearance.m3colors.m3success : Appearance.colors.colPrimary
                        text: root.activeJob ? root.activeJob.percent + "%" : ""
                    }
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 3
                    valueBarHeight: 3
                    value: root.activeJob ? root.activeJob.percent / 100 : 0
                    wavy: root.activeJob ? (root.activeJob.state === "running") : false
                    animateWave: true
                    highlightColor: root.activeJob && root.activeJob.state === "completed" ? Appearance.m3colors.m3success : Appearance.colors.colPrimary
                    trackColor: Appearance.colors.colSurfaceContainerLow
                }
            }
        }
    }
}
