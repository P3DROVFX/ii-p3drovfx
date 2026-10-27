import QtQuick
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * A person as a round picture: the contact's photo, or their initials on a
 * colour the name always picks the same way from the widget scheme.
 */
ClippingRectangle {
    id: avatar

    property string name: ""
    property string source: ""
    readonly property var tones: [WidgetColorScheme.accentColor, WidgetColorScheme.pillFillColor,
        WidgetColorScheme.highlightCircleColor, WidgetColorScheme.innerShapeColor]
    readonly property var inks: [WidgetColorScheme.onAccentColor, WidgetColorScheme.textColorOnPillFill,
        WidgetColorScheme.highlightTextColor, WidgetColorScheme.textColorOnBg]
    readonly property int tone: {
        let hash = 0;
        for (let i = 0; i < avatar.name.length; i++)
            hash = (hash * 31 + avatar.name.charCodeAt(i)) | 0;
        return Math.abs(hash) % 4;
    }
    readonly property string initials: avatar.name.split(/\s+/).filter(part => part.length > 0)
        .slice(0, 2).map(part => part.charAt(0).toUpperCase()).join("")

    radius: width / 2
    color: avatar.tones[avatar.tone]

    StyledText {
        anchors.centerIn: parent
        visible: picture.status !== Image.Ready
        text: avatar.initials
        color: avatar.inks[avatar.tone]
        font.family: Appearance.font.family.main
        font.pixelSize: Math.round(avatar.height * 0.4)
        font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
    }

    Image {
        id: picture
        anchors.fill: parent
        visible: status === Image.Ready
        source: avatar.source.length > 0 ? (avatar.source.startsWith("/") ? "file://" + avatar.source : avatar.source) : ""
        sourceSize: Qt.size(Math.ceil(avatar.width * 2), Math.ceil(avatar.height * 2))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }
}
