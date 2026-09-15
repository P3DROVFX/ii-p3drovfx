import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

ColumnLayout {
    id: root
    property string query: ""
    implicitHeight: Math.min(600, appGridView.contentHeight + 30 + spacing + 20) // 30 is alphabet, 20 is padding
    implicitWidth: 500
    spacing: 10

    readonly property var allApps: Array.from(DesktopEntries.applications.values).sort((a, b) => a.name.localeCompare(b.name))

    readonly property var filteredApps: {
        if (query === "")
            return allApps;
        return Fuzzy.go(query, allApps, {
            key: "name"
        }).map(r => r.obj);
    }

    // Alphabet filter
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 30
        spacing: 2

        Flickable {
            Layout.fillWidth: true
            height: parent.height
            contentWidth: alphabetRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            RowLayout {
                id: alphabetRow
                spacing: 2
                Repeater {
                    model: ["#", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
                    delegate: RippleButton {
                        id: letterButton
                        required property string modelData
                        implicitWidth: 28
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.small
                        colBackgroundHover: Appearance.colors.colPrimaryContainer

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: letterButton.modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: letterButton.hovered ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                            opacity: letterButton.hovered ? 1 : 0.7
                        }

                        onClicked: {
                            const apps = root.filteredApps;
                            for (let i = 0; i < apps.length; i++) {
                                const app = apps[i];
                                if (letterButton.modelData === "#" && /^\d/.test(app.name)) {
                                    appGridView.positionViewAtIndex(i, GridView.Beginning);
                                    break;
                                }
                                if (app.name.toUpperCase().startsWith(letterButton.modelData)) {
                                    appGridView.positionViewAtIndex(i, GridView.Beginning);
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    GridView {
        id: appGridView
        Layout.fillWidth: true
        Layout.fillHeight: true
        cellWidth: 110
        cellHeight: 120
        model: root.filteredApps
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // Performance optimization
        cacheBuffer: 500

        Behavior on contentY {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
            }
        }

        delegate: RippleButton {
            id: appButton
            required property var modelData
            width: 100
            height: 110
            buttonRadius: Appearance.rounding.normal
            colBackgroundHover: Appearance.colors.colPrimaryContainer

            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                }
            }
            scale: hovered ? 1.05 : 1.0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                IconImage {
                    Layout.alignment: Qt.AlignHCenter
                    source: Quickshell.iconPath(AppSearch.guessIcon(modelData.id), "image-missing")
                    implicitSize: 48
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.name
                    font.pixelSize: Appearance.font.pixelSize.small
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    color: appButton.hovered ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface
                }
            }

            onClicked: {
                AppUsage.recordLaunch(modelData.id);
                modelData.execute();
                GlobalStates.overviewOpen = false;
            }
        }
    }
}
