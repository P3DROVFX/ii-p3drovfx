pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_ios"

    // The box hugs the rendered text instead of a fixed 240x240 slot — the
    // grip still scales the whole item, but there is no dead space around it.
    resizeMaxScale: 5

    implicitWidth: Math.max(clockRow.implicitWidth, dateText.visible ? dateText.implicitWidth : 0) + root.padding * 2
    implicitHeight: root.padding * 2 + clockRow.implicitHeight
        + (dateText.visible ? Math.max(0, dateText.implicitHeight + root.dateSpacing) : 0)

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    // ── Config ────────────────────────────────────────────────────────────────
    readonly property var opts: Config.options.background.widgets.clock_ios
    readonly property bool showDate: opts.showDate ?? true
    readonly property real dateSpacing: opts.dateSpacing ?? 0
    readonly property string clockVariant: opts.clockFontVariant ?? "bold"
    readonly property string dateVariant: opts.dateFontVariant ?? "medium"

    // ── SF Pro font variants ──────────────────────────────────────────────────
    // Every file in the folder registers the SAME family name ("SF Pro Display"),
    // so picking a face requires the matching weight/italic alongside the loaded
    // file — family alone resolves to whichever face fontconfig saw first. The
    // italic cut is all some weights ship with in this folder.
    readonly property var fontVariantMeta: ({
            "regular": { file: "SFPRODISPLAYREGULAR.OTF", weight: Font.Normal, italic: false },
            "medium": { file: "SFPRODISPLAYMEDIUM.OTF", weight: Font.Medium, italic: false },
            "semibold": { file: "SFPRODISPLAYSEMIBOLDITALIC.OTF", weight: Font.DemiBold, italic: true },
            "bold": { file: "SFPRODISPLAYBOLD.OTF", weight: Font.Bold, italic: false },
            "heavy": { file: "SFPRODISPLAYHEAVYITALIC.OTF", weight: Font.ExtraBold, italic: true },
            "black": { file: "SFPRODISPLAYBLACKITALIC.OTF", weight: Font.Black, italic: true },
            "light": { file: "SFPRODISPLAYLIGHTITALIC.OTF", weight: Font.Light, italic: true },
            "thin": { file: "SFPRODISPLAYTHINITALIC.OTF", weight: Font.Thin, italic: true },
            "ultralight": { file: "SFPRODISPLAYULTRALIGHTITALIC.OTF", weight: Font.ExtraLight, italic: true }
        })

    function variantMeta(variant) {
        return root.fontVariantMeta[variant] ?? root.fontVariantMeta["bold"];
    }

    FontLoader {
        id: clockLoader
        source: "file://" + Directories.assetsPath + "/fonts/sf-pro-display/" + root.variantMeta(root.clockVariant).file
    }
    FontLoader {
        id: dateLoader
        source: "file://" + Directories.assetsPath + "/fonts/sf-pro-display/" + root.variantMeta(root.dateVariant).file
    }

    readonly property var clockMeta: root.variantMeta(root.clockVariant)
    readonly property var dateMeta: root.variantMeta(root.dateVariant)
    readonly property string clockFamily: clockLoader.status === FontLoader.Ready && clockLoader.name ? clockLoader.name : Appearance.font.family.main
    readonly property string dateFamily: dateLoader.status === FontLoader.Ready && dateLoader.name ? dateLoader.name : Appearance.font.family.main

    // ── Time & date (respect the user's shell-wide format flags) ─────────────
    readonly property bool use12h: DateTime.use12HourClock
    readonly property string timeString: DateTime.hours + ":" + DateTime.minutes
    readonly property string meridiemString: use12h ? DateTime.meridiem : ""
    readonly property string dateString: DateTime.longDate

    // Fit: measure at a fixed reference size and shrink only when the current
    // text would overflow the design width, so "9:41" and "10:24" render at
    // the same size. Font sizes are design constants, never derived from the
    // widget box — that would make the implicit sizes a binding loop.
    readonly property real referencePixelSize: 100
    readonly property real clockBasePixelSize: 72
    readonly property real designContentWidth: 208
    readonly property real fittedPixelSize: {
        const target = Math.max(1, designContentWidth * (meridiemString !== "" ? 0.86 : 1));
        const refWidth = Math.max(1, sfProMetrics.advanceWidth);
        return Math.min(clockBasePixelSize, referencePixelSize * target / refWidth);
    }
    readonly property real datePixelSize: 20
    readonly property int padding: 12

    TextMetrics {
        id: sfProMetrics
        font.family: root.clockFamily
        font.pixelSize: root.referencePixelSize
        font.letterSpacing: -0.02 * root.referencePixelSize
        font.weight: root.clockMeta.weight
        font.italic: root.clockMeta.italic
        text: root.timeString
    }

    // ── Colors (widget color scheme, not the shell theme) ────────────────────
    // The widget transparency system (tintOpacityEnabled / tintOpacity) only
    // multiplies surface alpha, so the text applies the same factor itself —
    // otherwise the clock stays fully opaque on translucent setups.
    function tintedText(c) {
        const t = WidgetColorScheme.backgroundTintOpacity;
        return t === 1 ? c : Qt.rgba(c.r, c.g, c.b, c.a * t);
    }
    readonly property color colMainText: root.tintedText(WidgetColorScheme.textColorOnBg)
    readonly property color colSubText: root.tintedText(WidgetColorScheme.subtextColorOnBg)

    // ── Content ───────────────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: root.dateSpacing

        StyledText {
            id: dateText
            visible: root.showDate && root.dateString.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateString
            color: root.colSubText
            font.family: root.dateFamily
            font.pixelSize: root.datePixelSize
            font.weight: root.dateMeta.weight
            font.italic: root.dateMeta.italic
        }

        Item {
            id: clockRow
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real meridiemGap: Math.round(root.fittedPixelSize * 0.12)
            implicitWidth: timeText.implicitWidth + (meridiemText.visible ? meridiemGap + meridiemText.implicitWidth : 0)
            implicitHeight: timeText.implicitHeight
            width: implicitWidth
            height: implicitHeight

            Text {
                id: timeText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.timeString
                color: root.colMainText
                font.family: root.clockFamily
                font.pixelSize: root.fittedPixelSize
                font.weight: root.clockMeta.weight
                font.italic: root.clockMeta.italic
                font.letterSpacing: -0.02 * root.fittedPixelSize
                renderType: Text.QtRendering
            }

            Text {
                id: meridiemText
                visible: root.meridiemString !== ""
                anchors.left: timeText.right
                anchors.leftMargin: clockRow.meridiemGap
                anchors.baseline: timeText.baseline
                text: root.meridiemString
                color: root.colSubText
                font.family: root.clockFamily
                font.pixelSize: root.fittedPixelSize * 0.38
                font.weight: root.clockMeta.weight
                font.italic: root.clockMeta.italic
                font.letterSpacing: 0.06 * root.fittedPixelSize
                renderType: Text.QtRendering
            }
        }
    }

    StyledDropShadow {
        target: clockRow
        visible: Config.options.background.widgets.enableShadows ?? false
    }
}
