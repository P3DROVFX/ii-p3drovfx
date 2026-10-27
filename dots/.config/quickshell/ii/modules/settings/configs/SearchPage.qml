import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: searchPageRoot

    property string queryString: SearchRegistry.query
    property var results: []
    // Sections are live QML compiled from source, so a broad query ("show":
    // 69 sections, 156 controls) blocked the window for ~1 s when built in one
    // pass. They are built best-first in slices of at most `buildBudgetMs`,
    // letting frames render between slices.
    readonly property int buildBudgetMs: 12
    // One slot per result, in rank order, and the slots by result key. Results
    // follow typing, and one more letter mostly re-ranks the same cards: a
    // slot whose result is still there is moved, not compiled again.
    property var slots: []
    property var slotsByKey: ({})

    onQueryStringChanged: {
        results = SearchRegistry.getDynamicSearchResults(queryString);
        buildResults();
    }

    ColumnLayout {
        id: dynamicContainer
        Layout.fillWidth: true
        spacing: 12
    }

    // Slots wait here while the container is put back in rank order.
    Item {
        id: slotParking
        visible: false
    }

    Component {
        id: slotComponent
        ColumnLayout {
            property string resultKey: ""
            property var result: null
            property bool built: false
            // An empty slot would still take the container's spacing.
            visible: built
            Layout.fillWidth: true
            spacing: 0
        }
    }

    // A page the query names, as one row that opens it.
    Component {
        id: pageLinkComponent

        ContentSection {
            id: pageLink
            searchResult: true
            Layout.fillWidth: true

            ConfigSubpageRow {
                title: Translation.tr("Open %1").arg(pageLink.title)
                onOpenSubPage: pageLink.navigateToPage("")
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: searchPageRoot.queryString !== "" && searchPageRoot.results.length === 0

        PagePlaceholder {
            anchors.fill: parent
            icon: "search_off"
            shape: MaterialShape.Shape.Circle
            title: Translation.tr("No results")
            description: Translation.tr("No settings match your search.")
        }
    }

    Timer {
        id: buildSliceTimer
        interval: 1
        onTriggered: searchPageRoot.buildSlice()
    }

    function resultKey(r) {
        if (r.page)
            return "page|" + r.pageId;
        const base = r.pageId + "|" + (r.subPage || "") + "|" + r.title + "|" + (r.sourceKey || "") + "|";
        if (r.landmarks)
            return base + "L|" + (r.components || []).join(",") + "|" + r.landmarks.map(l => l.text).join(",");
        return base + "S|" + r.items.map(i => i.sourceStart).join(",") + "|"
            + r.subsections.map(s => s.title + ":" + s.items.map(i => i.sourceStart).join(",")).join(";");
    }

    function buildResults() {
        buildSliceTimer.stop();
        let next = [];
        let nextByKey = {};
        for (let r of results) {
            const key = resultKey(r);
            if (nextByKey[key])
                continue;
            let slot = slotsByKey[key];
            if (!slot)
                slot = slotComponent.createObject(slotParking, { resultKey: key, result: r });
            nextByKey[key] = slot;
            next.push(slot);
        }
        for (let slot of slots)
            if (nextByKey[slot.resultKey] !== slot)
                slot.destroy();
        // Re-adding every slot in order is what orders a layout's children.
        for (let slot of next)
            slot.parent = slotParking;
        for (let slot of next)
            slot.parent = dynamicContainer;
        slots = next;
        slotsByKey = nextByKey;

        // Let deferred destroy() calls finish before compiling new results;
        // otherwise both queries coexist at peak memory.
        if (next.some(slot => !slot.built))
            buildSliceTimer.restart();
    }

    function buildSlice() {
        const deadline = Date.now() + buildBudgetMs;
        for (let i = 0; i < slots.length; i++) {
            const slot = slots[i];
            if (slot.built)
                continue;
            buildSection(slot.result, i, slot);
            slot.built = true;
            if (Date.now() >= deadline)
                break;
        }
        if (slots.some(slot => !slot.built))
            buildSliceTimer.restart();
    }

    // Headings of redesigned pages (hero cards, panes, chips) are not
    // cloneable: each is a row that opens its page and flashes it there.
    Component {
        id: landmarkGroupComponent

        ContentSection {
            id: landmarkGroup
            property var landmarks: []
            searchResult: true
            Layout.fillWidth: true

            Repeater {
                model: landmarkGroup.landmarks
                delegate: ConfigSubpageRow {
                    required property var modelData
                    title: modelData.text
                    onOpenSubPage: landmarkGroup.navigateToLandmark(modelData.text)
                }
            }
        }
    }

    // A landmark group with components: the components are cloned from the
    // page source, with its imports and from its directory, like the controls
    // below. A page-root id the block names (`page.activeSubPage = …`) gets a
    // stand-in that opens that sub-page instead.
    function buildComponentGroup(section, i, slot) {
        const blocks = section.components.map(id => SearchRegistry.landmarkBlocks[id]).filter(b => !!b);
        let imports = [];
        for (let b of blocks)
            for (let line of b.imports.split("\n"))
                if (line && imports.indexOf(line) === -1)
                    imports.push(line);
        let qmlStr = imports.join("\n") + "\n";
        qmlStr += "import QtQuick; import QtQuick.Layouts; import qs.modules.common.widgets; import qs.services; import qs.modules.common; \n";
        qmlStr += "ContentSection { id: __searchSection; searchResult: true; Layout.fillWidth: true; title: " + JSON.stringify(section.title)
            + "; icon: " + JSON.stringify(section.icon) + "; pageId: " + JSON.stringify(section.pageId)
            + "; subPage: " + JSON.stringify(section.subPage || "") + "\n";
        let rootIds = [];
        for (let b of blocks) {
            if (b.rootId && rootIds.indexOf(b.rootId) === -1) {
                rootIds.push(b.rootId);
                qmlStr += "QtObject { id: " + b.rootId + "; property var activeSubPage; onActiveSubPageChanged: if (activeSubPage) "
                    + "__searchSection.navigateToPage(String(activeSubPage).replace(/^.*\\/modules\\/settings\\/configs\\//, \"\")) }\n";
            }
        }
        for (let b of blocks)
            qmlStr += b.source + "\n";
        for (let l of section.landmarks)
            qmlStr += "ConfigSubpageRow { title: " + JSON.stringify(l.text)
                + "; onOpenSubPage: __searchSection.navigateToLandmark(" + JSON.stringify(l.text) + ") }\n";
        qmlStr += "}";

        try {
            Qt.createQmlObject(qmlStr, slot, "file://" + blocks[0].dir + "landmarkSection_" + i);
        } catch (e) {
            console.warn("[SearchPage] Failed to build landmark component:", section.title, e, "\nQML String:", qmlStr);
            // The links still lead there.
            landmarkGroupComponent.createObject(slot, {
                title: section.title,
                icon: section.icon,
                pageId: section.pageId,
                subPage: section.subPage,
                landmarks: section.landmarks.concat(section.coveredLandmarks ?? [])
            });
        }
    }

    function buildSection(section, i, slot) {
        if (section.page) {
            pageLinkComponent.createObject(slot, {
                title: section.title,
                icon: section.icon,
                pageId: section.pageId
            });
            return;
        }
        if (section.components && section.components.length > 0
                && section.components.some(id => !!SearchRegistry.landmarkBlocks[id])) {
            buildComponentGroup(section, i, slot);
            return;
        }
        if (section.landmarks) {
            landmarkGroupComponent.createObject(slot, {
                title: section.title,
                icon: section.icon,
                pageId: section.pageId,
                subPage: section.subPage,
                landmarks: section.landmarks
            });
            return;
        }
        let qmlStr = section.fileImports + "\n";
        qmlStr += "import QtQuick; import QtQuick.Layouts; import qs.modules.common.widgets; import qs.services; import qs.modules.common; \n";
        qmlStr += "ContentSection { searchResult: true; title: \"" + section.title.replace(/"/g, '\\"') + "\"; icon: \"" + section.icon + "\"; pageId: \"" + (section.pageId ? section.pageId.replace(/"/g, '\\"') : "") + "\"; subPage: \"" + (section.subPage ? section.subPage.replace(/"/g, '\\"') : "") + "\"; Layout.fillWidth: true; \n";

        for (let j = 0; j < section.items.length; j++) {
            qmlStr += SearchRegistry.getBlockSource(section.items[j]) + "\n";
        }

        for (let k = 0; k < section.subsections.length; k++) {
            let sub = section.subsections[k];
            qmlStr += "ContentSubsection { title: \"" + sub.title.replace(/"/g, '\\"') + "\"; icon: \"" + sub.icon + "\"; Layout.fillWidth: true; \n";
            for (let j = 0; j < sub.items.length; j++) {
                qmlStr += SearchRegistry.getBlockSource(sub.items[j]) + "\n";
            }
            qmlStr += "}\n";
        }

        qmlStr += "}";

        // The clone carries its source file's imports, so relative ones
        // ("../../../ii/recordingToolbar", `import "."`) must resolve from that
        // file's directory, not this page's: a sub-page in widgets/ otherwise
        // failed to compile and its matches were counted but never shown.
        const sourceDir = section.sourceKey.substring(0, section.sourceKey.lastIndexOf("/") + 1);
        const cloneUrl = "file://" + sourceDir + "dynamicSection_" + i;

        try {
            Qt.createQmlObject(qmlStr, slot, cloneUrl);
        } catch (e) {
            console.log("[SearchPage] Failed to build section:", section.title, e, "\nQML String:", qmlStr);
        }
    }
    
    Component.onCompleted: {
        if (queryString !== "") {
            results = SearchRegistry.getDynamicSearchResults(queryString);
            buildResults();
        }
    }
}
