import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool isMaterial: true // Forced expressive

    implicitWidth: loader.implicitWidth
    implicitHeight: loader.implicitHeight

    Loader {
        id: loader
        anchors.fill: parent
        sourceComponent: materialStyle // Forced expressive
    }

    Component {
        id: materialStyle
        RippleButton {
            implicitWidth: Appearance.sizes.barHeight - 8
            implicitHeight: Appearance.sizes.barHeight - 8
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onPressed: {
                GlobalStates.sessionOpen = !GlobalStates.sessionOpen
            }

            MaterialShapeWrappedMaterialSymbol {
                anchors.centerIn: parent
                text: "power_settings_new"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnPrimary
                colSymbol: Appearance.colors.colPrimary
                shape: MaterialShape.Shape.Cookie12Sided
                padding: 2
            }
        }
    }
}
