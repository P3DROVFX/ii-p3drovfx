import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A systemd unit as a row. The leading shape says the state at a glance — running is a
 * primary cookie, failed an error burst, stopped a plain circle — and the line under the
 * name says it in words. Start/stop is a round action, "at boot" the switch; the row
 * itself opens the unit's page (file, log, details).
 */
Rectangle {
    id: root

    required property var unit
    property string scope: "user"
    signal openRequested()

    readonly property bool running: root.unit.active === "active" || root.unit.active === "activating" || root.unit.active === "reloading"
    readonly property bool failed: root.unit.active === "failed"
    readonly property bool isTimer: root.unit.type === "timer"
    readonly property string fileState: root.unit.fileState ?? ""
    readonly property bool canToggleBoot: ["enabled", "disabled", "enabled-runtime"].includes(root.fileState)
    readonly property bool bootOn: root.fileState === "enabled" || root.fileState === "enabled-runtime"
    readonly property bool engaged: rowHover.hovered || rowTap.pressed

    implicitHeight: 76
    radius: Appearance.rounding.large
    color: root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    HoverHandler {
        id: rowHover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: rowTap
        onTapped: root.openRequested()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        MaterialShapeWrappedMaterialSymbol {
            text: root.failed ? "error" : root.isTimer ? "schedule" : root.running ? "play_arrow" : "stop"
            iconSize: 20
            padding: 11
            fill: 1
            shape: root.failed ? MaterialShape.Shape.SoftBurst
                : root.running ? (root.isTimer ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie7Sided)
                : MaterialShape.Shape.Circle
            color: root.failed ? Appearance.colors.colErrorContainer
                : root.running ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colSurfaceContainerHighest
            colSymbol: root.failed ? Appearance.colors.colOnErrorContainer
                : root.running ? Appearance.colors.colOnPrimaryContainer
                : Appearance.colors.colOnSurfaceVariant
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            RowLayout {
                id: nameRow
                Layout.fillWidth: true
                spacing: 6
                StyledText {
                    Layout.maximumWidth: nameRow.width - (badge.visible ? badge.width + nameRow.spacing : 0)
                    // systemd escapes "-" as \x2d in generated names (app-foo\x2dbar@autostart)
                    text: root.unit.name.replace(/\.service$/, "").replace(/\\x([0-9a-fA-F]{2})/g, (m, h) => String.fromCharCode(parseInt(h, 16)))
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: badge
                    visible: root.unit.mine || root.unit.overridden
                    implicitHeight: 18
                    implicitWidth: mineText.implicitWidth + 12
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colTertiaryContainer
                    StyledText {
                        id: mineText
                        anchors.centerIn: parent
                        text: root.unit.mine ? Translation.tr("Yours") : Translation.tr("Override")
                        font.pixelSize: Appearance.font.pixelSize.smallest - 1
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnTertiaryContainer
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: {
                    const state = root.failed ? Translation.tr("Failed")
                        : root.running ? (root.isTimer ? Translation.tr("Waiting") : Translation.tr("Running"))
                        : Translation.tr("Stopped");
                    const boot = root.fileState === "masked" ? Translation.tr("masked")
                        : root.bootOn ? (root.scope === "user" ? Translation.tr("starts at login") : Translation.tr("starts at boot"))
                        : root.fileState === "static" ? Translation.tr("started by others")
                        : "";
                    const desc = root.unit.description ?? "";
                    return [state + (boot ? " · " + boot : ""), desc].filter(s => s).join("  —  ");
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        CircleAction {
            symbol: root.running ? "stop" : "play_arrow"
            tip: root.running ? Translation.tr("Stop") : Translation.tr("Start")
            visible: root.unit.load !== "masked" && root.fileState !== "masked"
            enabled: !StartupManager.busy
            onClicked: StartupManager.unitAction(root.scope, root.unit.name, root.running ? "stop" : "start")
        }

        StyledSwitch {
            sizeScale: 0.8
            visible: root.canToggleBoot
            checked: root.bootOn
            enabled: !StartupManager.busy
            onToggled: StartupManager.unitAction(root.scope, root.unit.name, checked ? "enable" : "disable")
            StyledToolTip {
                text: root.scope === "user" ? Translation.tr("Start at login") : Translation.tr("Start at boot")
            }
        }
    }
}
