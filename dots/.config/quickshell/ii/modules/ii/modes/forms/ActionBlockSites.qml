pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.modes
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `blockSites` action: browser windows whose title names one of
 * these sites get the block screen while the mode is on. `row` is the ActionRow
 * this form unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: form
    required property var row

    // Common distractions plus whatever is open in a browser right now.
    readonly property var siteSuggestions: {
        const names = ["YouTube", "Instagram", "TikTok", "Facebook", "Reddit", "X", "Twitch", "Netflix",
            "LinkedIn", "Pinterest", "Tumblr", "Threads", "Bluesky", "Kwai", "9GAG", "Prime Video", "Disney+"];
        const out = names.map(n => ({ label: n, value: n }));
        for (const w of ModeSchema.toArray(HyprlandData.windowList)) {
            if (!ScreenTimeLimits.isBrowserClass(String(w["class"] ?? "")))
                continue;
            const page = ScreenTimeLimits.pageTitle(w.title);
            const parts = page.split(/\s+[|—–\/•·-]\s+/);
            const site = parts[parts.length - 1]?.trim() ?? "";
            if (site.length > 0 && site.length <= 30 && !out.some(o => o.value === site))
                out.push({ label: site, value: site });
        }
        return out;
    }

    spacing: 8

    FormLabel {
        text: Translation.tr("Block")
    }

    ChipInput {
        Layout.fillWidth: true
        values: ModeSchema.stringList(row.obj.sites)
        placeholder: Translation.tr("Site name, or /regex/")
        suggestions: form.siteSuggestions
        pickTitle: Translation.tr("Sites")
        onChanged: list => row.patchValue({ sites: list })
    }

    FormLabel {
        text: Translation.tr("Always allow")
    }

    ChipInput {
        Layout.fillWidth: true
        values: ModeSchema.stringList(row.obj.allow)
        placeholder: Translation.tr("Title word that lets a page through")
        onChanged: list => row.patchValue({ allow: list })
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        StyledSwitch {
            checked: row.obj.strict === true
            onClicked: row.patchValue({ strict: checked })
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Translation.tr("Ask for the PIN to get through")
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnSurface
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !ScreenTimeLimits.hasPin
                text: Translation.tr("No PIN yet: set one in App usage → Daily limits.")
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colOnSurfaceVariant
            }
        }
    }

    FormHint {
        text: Translation.tr("Matched against the title of browser windows, so only the tab on show counts. A short name (X) must be a whole part of the title (\"Home / X\"); longer ones match as a word. For blocking inside the browser, add a Browser extension action too.")
    }
}
