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
    property bool isExpanded: false

    readonly property var activeJobs: ProgressService.jobs
    readonly property var activeJob: activeJobs.length > 0 ? activeJobs[0] : null

    // --- Contracted View (Icon + Rounded Rectangle filling the remaining space) ---
    Item {
        id: contractedLayout
        anchors.fill: parent
        opacity: !root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

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

    // --- Expanded View (Optimized detailed view or list depending on job count) ---
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        opacity: root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        // --- Case A: Single Job (Highly detailed pro-dashboard layout utilizing vertical space) ---
        ColumnLayout {
            visible: root.activeJobs.length === 1
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SineCookie {
                    width: 24
                    height: 24
                    implicitSize: 24
                    sides: 12
                    amplitude: 1.5
                    color: Appearance.colors.colSurfaceContainerHighest
                    constantlyRotate: root.activeJob && root.activeJob.state === "running"
                }

                StyledText {
                    text: root.activeJob ? root.activeJob.appName : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.bold: true
                    color: Appearance.colors.colPrimary
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: root.activeJob ? root.activeJob.percent + "%" : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.bold: true
                    color: root.activeJob && root.activeJob.state === "completed" ? Appearance.m3colors.m3success : Appearance.colors.colPrimary
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.activeJob ? (root.activeJob.message || Translation.tr("Processing transaction...")) : ""
                font.pixelSize: Appearance.font.pixelSize.normal
                font.bold: true
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                valueBarHeight: 6
                value: root.activeJob ? root.activeJob.percent / 100 : 0
                wavy: root.activeJob ? (root.activeJob.state === "running") : false
                animateWave: true
                highlightColor: root.activeJob && root.activeJob.state === "completed" ? Appearance.m3colors.m3success : Appearance.colors.colPrimary
                trackColor: Appearance.colors.colSurfaceContainerHigh
            }

            // Stats grid layout below progress bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    StyledText {
                        text: Translation.tr("Speed")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: (root.activeJob && root.activeJob.speedText) || "---"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    StyledText {
                        text: Translation.tr("Progress")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: (root.activeJob && root.activeJob.progressText) || "---"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    StyledText {
                        text: Translation.tr("Time Remaining")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: (root.activeJob && root.activeJob.etaText) || "---"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }

        // --- Case B: Multiple Jobs (Standard compact list view) ---
        ColumnLayout {
            visible: root.activeJobs.length > 1
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.activeJobs.slice(0, 2)
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: modelData.source === "notification" ? "download" : "sync"
                            iconSize: 16
                            color: modelData.state === "completed" ? Appearance.m3colors.m3success : Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: true
                            color: Appearance.colors.colOnSurface
                            text: modelData.message || (modelData.state === "completed" ? Translation.tr("Done") : Translation.tr("Processing..."))
                            elide: Text.ElideRight
                        }

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: true
                            color: modelData.state === "completed" ? Appearance.m3colors.m3success : Appearance.colors.colPrimary
                            text: modelData.percent + "%"
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 5
                        color: Appearance.colors.colSurfaceContainerHigh
                        radius: 2.5

                        Rectangle {
                            height: parent.height
                            width: parent.width * (modelData.percent / 100)
                            color: modelData.state === "completed" ? Appearance.m3colors.m3success : Appearance.colors.colPrimary
                            radius: 2.5

                            Behavior on width {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            text: modelData.progressText || ""
                            elide: Text.ElideRight
                        }

                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.bold: true
                            color: Appearance.colors.colPrimary
                            text: {
                                let parts = [];
                                if (modelData.speedText)
                                    parts.push(modelData.speedText);
                                if (modelData.etaText)
                                    parts.push(modelData.etaText);
                                return parts.join(" • ");
                            }
                        }
                    }
                }
            }
        }

        // Footer for additional jobs overflow indicator
        StyledText {
            visible: root.activeJobs.length > 2
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.italic: true
            color: Appearance.colors.colSubtext
            text: Translation.tr("+ %1 other processes active").arg(root.activeJobs.length - 2)
        }
    }
}
