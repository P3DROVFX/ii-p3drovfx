pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One helper, and where its build has got to.
 *
 * The row has four states and changes shape between them rather than only changing a
 * word: idle is a description and a button, building is cargo's own narration under a
 * wavy indicator, done is a filled check on the accent container, failed is the last
 * thing cargo said plus a way to try again. A build takes about a minute on a cold
 * cache, and a row that only said "Building…" for that minute would be
 * indistinguishable from a row that had hung.
 */
Rectangle {
    id: root

    property string symbol: ""
    property string title: ""
    property string description: ""
    property bool built: false
    property bool building: false
    property bool failed: false
    property string failureText: ""
    /// Cargo's narration: "Compiling wayland-backend".
    property string progressText: ""
    property int unitsCompiled: 0
    property int elapsedSeconds: 0
    /// 0..1, from the lockfile's package count. See RustHelperBuild.progress.
    property real progress: 0

    signal buildRequested()

    implicitHeight: layout.implicitHeight + 26
    radius: root.built ? Appearance.rounding.large : Appearance.rounding.normal
    // The finished row moves onto the accent container. M3 Expressive's own way of
    // marking a completed step, and it is the only colour change in the window — which
    // is what makes it read as an event rather than as decoration.
    color: root.built ? Appearance.colors.colSecondaryContainer
        : (root.failed ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2)

    readonly property color onColor: root.built ? Appearance.colors.colOnSecondaryContainer
        : (root.failed ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnLayer2)

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(root)
    }
    Behavior on radius {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: root.built ? "check_circle" : (root.failed ? "error" : root.symbol)
                iconSize: Appearance.font.pixelSize.larger
                fill: root.built ? 1 : 0
                color: root.built ? Appearance.colors.colPrimary : root.onColor

                // One turn as the check lands. A completed build is a moment worth
                // marking; it happens once and then stops, which is the difference
                // between an accent and a distraction.
                rotation: root.built ? 0 : -25
                opacity: root.built ? 1 : 0.9
                Behavior on rotation {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: root.built ? 600 : 400
                    color: root.onColor
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    // Each state answers with the most useful line it has: cargo's
                    // narration while building, cargo's complaint when it failed, and
                    // otherwise what the helper is for.
                    text: {
                        if (root.building)
                            return root.progressText;
                        if (root.failed && root.failureText.length > 0)
                            return root.failureText.split("\n").filter(l => l.trim().length > 0).slice(-1)[0];
                        if (root.built)
                            return Translation.tr("Built and running.");
                        return root.description;
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: root.building ? Appearance.font.family.monospace
                                               : Appearance.font.family.main
                    color: root.failed ? Appearance.m3colors.m3onErrorContainer
                                       : Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignVCenter
                visible: !root.built && !root.building
                buttonRadius: Appearance.rounding.small
                materialIcon: root.failed ? "refresh" : "build"
                mainText: root.failed ? Translation.tr("Retry") : Translation.tr("Build")
                onClicked: root.buildRequested()
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: root.building
                // Two true numbers, in place of a percentage cargo cannot supply: it
                // does not say how many units it will build before it starts, and the
                // count differs between a warm and a cold cache.
                text: root.unitsCompiled > 0
                    ? Translation.tr("%1 crates · %2s").arg(root.unitsCompiled).arg(root.elapsedSeconds)
                    : Translation.tr("%1s").arg(root.elapsedSeconds)
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // M3 Expressive's wavy indicator, running against a real denominator: the
        // lockfile says how many crates a cold build compiles.
        StyledProgressBar {
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.font.pixelSize.larger + 12
            visible: root.building
            value: root.progress
            wavy: true
            animateWave: true
            valueBarHeight: 5

            Behavior on value {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
    }
}
