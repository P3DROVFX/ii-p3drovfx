import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "LockLook.js" as LockLook

/**
 * The lock's look, adjusted under its preview: a header that names the current
 * look, and one slider per treatment whose zero is its old switch.
 */
Rectangle {
    id: root

    /// The saved look's preset name, "" when custom.
    property string presetName: ""
    /// A preset being tried on, named instead while the pointer is on it.
    property string tryingName: ""

    readonly property var lock: Config.options.lock
    readonly property int padding: 20
    readonly property int activeCount: LockLook.activeCount(root.lock)

    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1
    implicitHeight: column.implicitHeight + root.padding * 2

    ColumnLayout {
        id: column
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: "auto_awesome"
                iconSize: 22
                padding: 11
                fill: 1
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Effects")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.tryingName !== "" ? root.tryingName
                        : root.activeCount === 0 ? Translation.tr("Clear")
                        : `${root.presetName !== "" ? root.presetName : Translation.tr("Custom")} · ${root.activeCount === 1 ? Translation.tr("1 effect") : Translation.tr("%1 effects").arg(root.activeCount)}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        LockSliderRow {
            Layout.fillWidth: true
            symbol: "blur_on"
            label: Translation.tr("Blur")
            activeShape: MaterialShape.Shape.Cookie12Sided
            from: 0
            to: 50
            stepSize: 5
            format: v => `${Math.round(v)} px`
            value: LockLook.valueOf(root.lock, "blur")
            onMoved: value => LockLook.setValue(root.lock, "blur", value)
        }
        LockSliderRow {
            Layout.fillWidth: true
            symbol: "filter_b_and_w"
            label: Translation.tr("Desaturate")
            activeShape: MaterialShape.Shape.Sunny
            value: LockLook.valueOf(root.lock, "desaturate")
            onMoved: value => LockLook.setValue(root.lock, "desaturate", value)
        }
        LockSliderRow {
            Layout.fillWidth: true
            symbol: "format_color_fill"
            label: Translation.tr("Color wash")
            activeShape: MaterialShape.Shape.Flower
            value: LockLook.valueOf(root.lock, "colorWash")
            onMoved: value => LockLook.setValue(root.lock, "colorWash", value)
        }
        LockSliderRow {
            Layout.fillWidth: true
            symbol: "vignette"
            label: Translation.tr("Vignette")
            activeShape: MaterialShape.Shape.SoftBurst
            value: LockLook.valueOf(root.lock, "vignette")
            onMoved: value => LockLook.setValue(root.lock, "vignette", value)
        }
    }
}
