import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: searchPageRoot

    property string queryString: SearchRegistry.currentSearch
    property var results: []

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

    function buildResults() {
        for (var i = dynamicContainer.children.length - 1; i >= 0; i--) {
            dynamicContainer.children[i].destroy();
        }

        if (results.length === 0) {
            return;
        }

        for (let i = 0; i < results.length; i++) {
            let section = results[i];

            let qmlStr = section.fileImports + "\n";
            qmlStr += "import QtQuick; import QtQuick.Layouts; import qs.modules.common.widgets; import qs.services; import qs.modules.common; \n";
            qmlStr += "ContentSection { title: \"" + section.title.replace(/"/g, '\\"') + "\"; icon: \"" + section.icon + "\"; Layout.fillWidth: true; \n";

            for (let j = 0; j < section.items.length; j++) {
                qmlStr += section.items[j].full + "\n";
            }

            for (let k = 0; k < section.subsections.length; k++) {
                let sub = section.subsections[k];
                qmlStr += "ContentSubsection { title: \"" + sub.title.replace(/"/g, '\\"') + "\"; icon: \"" + sub.icon + "\"; Layout.fillWidth: true; \n";
                for (let j = 0; j < sub.items.length; j++) {
                    qmlStr += sub.items[j].full + "\n";
                }
                qmlStr += "}\n";
            }

            qmlStr += "}";
            
            try {
                Qt.createQmlObject(qmlStr, dynamicContainer, "dynamicSection_" + i);
            } catch (e) {
                console.log("[SearchPage] Failed to build section:", section.title, e, "\nQML String:", qmlStr);
            }
        }
    }
    
    Component.onCompleted: {
        if (queryString !== "") {
            results = SearchRegistry.getDynamicSearchResults(queryString);
            buildResults();
        }
    }
}
