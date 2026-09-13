import QtQuick
import QtTest
import "../../services/notes/NotesSearchIndex.js" as Search

TestCase {
    name: "NotesSearchIndex"

    function test_accents_are_normalized() {
        compare(Search.normalizeText("Reunião"), "reuniao");
        compare(Search.normalizeText("Árvore de Maçã"), "arvore de maca");
        compare(Search.normalizeText("Crédito & Débito"), "credito & debito");
    }

    function test_tokenization_splits_words_and_strips_punctuation() {
        const tokens = Search.tokenize("Olá, mundo! Isto é um teste (2026).");
        verify(tokens.indexOf("ola") !== -1);
        verify(tokens.indexOf("mundo") !== -1);
        verify(tokens.indexOf("isto") !== -1);
        verify(tokens.indexOf("teste") !== -1);
        verify(tokens.indexOf("2026") !== -1);
    }

    function test_wikilinks_extraction() {
        const links = Search.extractWikilinks("Veja [[Minha Nota]] e também [[Outra Nota|Rótulo]].");
        compare(links.length, 2);
        compare(links[0], "Minha Nota");
        compare(links[1], "Outra Nota");
    }

    function test_backlinks_discovery() {
        const notes = [
            { id: "n1", title: "Target Note", preview: "Some text" },
            { id: "n2", title: "Source Note A", preview: "Contains [[Target Note]] reference" },
            { id: "n3", title: "Source Note B", preview: "No links here" },
        ];
        const backlinks = Search.findBacklinks("n1", "Target Note", notes, null);
        compare(backlinks.length, 1);
        compare(backlinks[0].id, "n2");
    }

    function test_query_parser_extracts_terms_and_operators() {
        const parsed = Search.parseQuery("reunião tag:trabalho tem:imagem tem:tinta is:favorite criada:>2026-01-01");
        verify(parsed.terms.indexOf("reuniao") !== -1);
        verify(parsed.filters.tags.indexOf("trabalho") !== -1);
        verify(parsed.filters.has.indexOf("image") !== -1);
        verify(parsed.filters.has.indexOf("ink") !== -1);
        verify(parsed.filters.is.indexOf("favorite") !== -1);
        compare(parsed.filters.dates.length, 1);
        compare(parsed.filters.dates[0].field, "created");
        compare(parsed.filters.dates[0].op, ">");
    }

    function test_search_ranks_title_higher_than_body() {
        const idx = Search.createIndex();
        const noteTitleMatch = {
            id: "n_title",
            title: "Reunião de Alinhamento",
            preview: "Outro assunto qualquer",
            modified: 1000
        };
        const noteBodyMatch = {
            id: "n_body",
            title: "Notas Diversas",
            preview: "Foi falado sobre a reunião com a equipe",
            modified: 2000
        };

        idx.build([noteBodyMatch, noteTitleMatch], null);
        const results = idx.search("reunião", [noteBodyMatch, noteTitleMatch], null, null);

        compare(results.length, 2);
        compare(results[0].id, "n_title");
        compare(results[1].id, "n_body");
    }

    function test_search_filters_by_tag() {
        const idx = Search.createIndex();
        const note1 = { id: "n1", title: "Nota 1", tags: ["trabalho", "urgente"], modified: 100 };
        const note2 = { id: "n2", title: "Nota 2", tags: ["pessoal"], modified: 200 };

        idx.build([note1, note2], null);
        const results = idx.search("tag:trabalho", [note1, note2], null, null);

        compare(results.length, 1);
        compare(results[0].id, "n1");
    }

    function test_search_filters_by_has_image_and_ink() {
        const idx = Search.createIndex();
        const noteWithImg = { id: "n_img", title: "Imagens", hasImages: true, hasInk: false, modified: 100 };
        const noteWithInk = { id: "n_ink", title: "Desenho", hasImages: false, hasInk: true, modified: 200 };

        idx.build([noteWithImg, noteWithInk], null);

        const imgResults = idx.search("tem:imagem", [noteWithImg, noteWithInk], null, null);
        compare(imgResults.length, 1);
        compare(imgResults[0].id, "n_img");

        const inkResults = idx.search("tem:tinta", [noteWithImg, noteWithInk], null, null);
        compare(inkResults.length, 1);
        compare(inkResults[0].id, "n_ink");
    }

    function test_search_filters_by_is_favorite() {
        const idx = Search.createIndex();
        const favNote = { id: "n_fav", title: "Favorita", favorite: true, modified: 100 };
        const normalNote = { id: "n_norm", title: "Normal", favorite: false, modified: 200 };

        idx.build([favNote, normalNote], null);
        const results = idx.search("is:favorite", [favNote, normalNote], null, null);

        compare(results.length, 1);
        compare(results[0].id, "n_fav");
    }

    function test_incremental_indexing_and_removal() {
        const idx = Search.createIndex();
        const note = { id: "n_dyn", title: "Original Title", preview: "Initial content", modified: 100 };

        idx.build([note], null);
        compare(idx.search("Original", [note], null, null).length, 1);

        // Update note title
        const updated = { id: "n_dyn", title: "Brand New Title", preview: "Initial content", modified: 150 };
        idx.indexNote(updated, null);

        compare(idx.search("Original", [updated], null, null).length, 0);
        compare(idx.search("Brand", [updated], null, null).length, 1);

        // Remove note
        idx.removeNote("n_dyn");
        compare(idx.search("Brand", [], null, null).length, 0);
    }

    function test_highlight_snippet() {
        const text = "No primeiro semestre de 2026 realizamos um grande planejamento estratégico para o setor.";
        const snippet = Search.highlightSnippet(text, ["planejamento"], 50);
        verify(snippet.indexOf("planejamento") !== -1);
    }
}
