pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import "KeybindTokenizer.js" as Tokenizer

Singleton {
    id: root

    function tokenize(input: string): var {
        return Tokenizer.tokenize(input);
    }

    function canonical(input: string): string {
        return Tokenizer.tokenize(input).canonical;
    }

    function spokenDescription(input: string): string {
        return Tokenizer.spokenDescription(input);
    }

    function matchQuery(shortcutStr: string, query: string): bool {
        return Tokenizer.matchQuery(shortcutStr, query);
    }

    function parseSingleChord(chordStr: string): var {
        return Tokenizer.parseSingleChord(chordStr);
    }

    function keyEventToString(event: var): string {
        return Tokenizer.keyEventToString(event, Qt);
    }
}
