import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: searchPageRoot

    property string queryString: SearchRegistry.currentSearch
    property var results: []
    // Next result section to build. Sections are live QML compiled from source,
    // so a broad query ("show": 69 sections, 156 controls) blocked the window
    // for ~1 s when built in one pass. They are built best-first in slices of
    // at most `buildBudgetMs`, letting frames render between slices.
    property int buildIndex: 0
    readonly property int buildBudgetMs: 12

    onQueryStringChanged: {
        results = SearchRegistry.getDynamicSearchResults(queryString);
        buildResults();
    }

    ColumnLayout {
        id: dynamicContainer
        Layout.fillWidth: true
        spacing: 12
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

    function buildResults() {
        buildSliceTimer.stop();
        buildIndex = 0;
        for (var i = dynamicContainer.children.length - 1; i >= 0; i--) {
            dynamicContainer.children[i].destroy();
        }

        if (results.length === 0) {
            return;
        }

        // Let deferred destroy() calls finish before compiling replacement
        // results; otherwise both queries coexist at peak memory.
        buildSliceTimer.restart();
    }

    function buildSlice() {
        const deadline = Date.now() + buildBudgetMs;
        while (buildIndex < results.length) {
            buildSection(results[buildIndex], buildIndex);
            buildIndex++;
            if (Date.now() >= deadline)
                break;
        }
        if (buildIndex < results.length)
            buildSliceTimer.restart();
    }

    function buildSection(section, i) {
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
            Qt.createQmlObject(qmlStr, dynamicContainer, cloneUrl);
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
