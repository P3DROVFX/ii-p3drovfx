// EmailDetections.js

function decodeHtmlEntities(text) {
    var namedEntities = {
        nbsp: " ",
        amp: "&",
        lt: "<",
        gt: ">",
        quot: '"',
        apos: "'",
        '#39': "'"
    };

    return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]+);/gi, function(full, entity) {
        var lower = entity.toLowerCase();
        if (namedEntities[lower] !== undefined)
            return namedEntities[lower];

        if (lower.indexOf("#x") === 0) {
            var hexCode = parseInt(lower.slice(2), 16);
            return isNaN(hexCode) ? full : String.fromCharCode(hexCode);
        }

        if (lower.indexOf("#") === 0) {
            var decimalCode = parseInt(lower.slice(1), 10);
            return isNaN(decimalCode) ? full : String.fromCharCode(decimalCode);
        }

        return full;
    });
}

function extractCodes(text) {
    var codes = [];
    var codeTerms = "(?:código|codigo|code|token|pin|senha|password|passcode|otp)";
    var bridgeWords = "(?:is|are|equals|é|e|your|seu|the|o|a|de|do|da|para|for|use|using|below|abaixo|confirmation|confirmação|confirmacao|confirm|verification|verificação|verificacao|security|segurança|seguranca|login|authentication|autenticação|autenticacao|one|time|temporary|access|acesso)";

    // Keep the label explicit, but allow the natural-language glue used by
    // real emails: "verification code is", "código de confirmação é", etc.
    var codeBeforeCandidate = new RegExp(
        "\\b" + codeTerms + "\\b(?:(?:\\s+" + bridgeWords + ")|(?:\\s*[:=\\-–—])){0,5}\\s*$",
        "i"
    );
    var codeAfterCandidate = new RegExp(
        "^\\s*(?:(?:" + bridgeWords + ")\\s*){0,5}" + codeTerms + "\\b",
        "i"
    );
    var instructionBeforeCandidate = /\b(?:use|enter|type|input|insira|digite|informe)\s*$/i;
    var instructionAfterCandidate = /^\s*(?:to|para)\s+(?:verify|verificar|confirm|confirmar|validate|validar|continue|continuar|sign\s+in|login)\b/i;
    var candidateRegex = /(^|[^A-Za-z0-9])([0-9]{2,4}(?:(?:[ \t]+|[-–—])[0-9]{2,4})+|[A-Za-z0-9]{4,10}(?:[-–—][A-Za-z0-9]{2,10})?)(?![A-Za-z0-9])/g;
    var commonWords = /^(?:your|you|the|this|that|code|token|pin|passcode|password|access|account|login|verify|verification|confirmation|security|use|enter|here|now|please|email|mail|from|with|for|one|time|is|are|and|to|of|a|an)$/i;
    var m;

    function addCandidate(candidate) {
        var value = candidate.trim().replace(/[ \t]+/g, " ");
        var compact = value.replace(/[ \t\-–—]/g, "");

        if (compact.length < 4 || compact.length > 20)
            return;

        // Numeric and mixed codes are the common OTP formats. Letter-only
        // values are accepted only when visibly uppercase and not a normal
        // email word, so "your" can never become a key by accident.
        if (!/\d/.test(compact) && (!/^[A-Z]+$/.test(compact) || commonWords.test(compact)))
            return;

        if (codes.indexOf(value) === -1)
            codes.push(value);
    }

    while ((m = candidateRegex.exec(text)) !== null) {
        var candidate = m[2];
        var candidateStart = m.index + m[1].length;
        var before = text.slice(Math.max(0, candidateStart - 140), candidateStart);
        var after = text.slice(candidateStart + candidate.length, candidateStart + candidate.length + 100);

        if (codeBeforeCandidate.test(before)
                || codeAfterCandidate.test(after)
                || (instructionBeforeCandidate.test(before) && instructionAfterCandidate.test(after)))
            addCandidate(candidate);
    }

    return codes;
}

function detectAll(bodyRaw) {
    if (!bodyRaw) {
        return {
            meetings: [],
            phones: [],
            codes: []
        };
    }

    var clean = bodyRaw.replace(/<style[\s\S]*?<\/style>/gi, '')
                       .replace(/<script[\s\S]*?<\/script>/gi, '')
                       .replace(/<br\s*\/?>/gi, '\n')
                       .replace(/<\/p>/gi, '\n')
                       .replace(/<\/div>/gi, '\n')
                       .replace(/<[^>]*>?/gm, ' ');
    var textNoUrls = decodeHtmlEntities(clean)
        .replace(/\u00a0/g, ' ')
        .replace(/https?:\/\/[^\s]+/gi, ' ');

    var meetings = [];
    var m;

    // Meet
    var meetRegex = /https?:\/\/meet\.google\.com\/[a-z0-9-]+/gi;
    while ((m = meetRegex.exec(bodyRaw)) !== null) {
        meetings.push({
            type: "Meet",
            url: m[0],
            icon: "video_chat"
        });
    }

    // Teams
    var teamsRegex1 = /https?:\/\/teams\.microsoft\.com\/l\/meetup-join\/[^\s"<>'{}|\\^`[\]]+/gi;
    while ((m = teamsRegex1.exec(bodyRaw)) !== null) {
        meetings.push({
            type: "Teams",
            url: m[0],
            icon: "groups"
        });
    }

    var teamsRegex2 = /https?:\/\/teams\.microsoft\.com\/v2\/\?meetingjoin=true#\/meet\/[^\s"<>'{}|\\^`[\]]+/gi;
    while ((m = teamsRegex2.exec(bodyRaw)) !== null) {
        meetings.push({
            type: "Teams",
            url: m[0],
            icon: "groups"
        });
    }

    // Zoom
    var zoomRegex = /https?:\/\/zoom\.us\/j\/[0-9]+(?:\?pwd=[a-zA-Z0-9]+)?/gi;
    while ((m = zoomRegex.exec(bodyRaw)) !== null) {
        meetings.push({
            type: "Zoom",
            url: m[0],
            icon: "video_call"
        });
    }

    // Filter duplicate meetings
    var uniqueMeetings = meetings.filter(function(v, i, a) {
        return a.findIndex(function(t) { return t.url === v.url; }) === i;
    });

    // Phones
    var phones = [];
    var phoneRegex = /(?:\+?55\s*)?(?:\(\d{2}\)\s*|\d{2}\s+)?(?:9\s*)?\d{4}[-.\s]?\d{4}/g;
    var phoneKeywords = /(?:tel|phone|celular|whatsapp|contato|ligar|fone|mobile|contatos|telefones)/i;
    while ((m = phoneRegex.exec(clean)) !== null) {
        var p = m[0].trim();
        if (p.length >= 8) {
            var hasPlus55 = p.indexOf("+55") !== -1 || p.indexOf("55") === 0;
            var hasDDDInParens = /\(\d{2}\)/.test(p);
            if (hasPlus55 || hasDDDInParens) {
                if (phones.indexOf(p) === -1) {
                    phones.push(p);
                }
            } else {
                var start = Math.max(0, m.index - 30);
                var end = Math.min(clean.length, m.index + p.length + 30);
                var context = clean.slice(start, end);
                if (phoneKeywords.test(context)) {
                    if (phones.indexOf(p) === -1) {
                        phones.push(p);
                    }
                }
            }
        }
    }

    // Codes (OTP): only return candidates attached to an explicit code label.
    var codes = extractCodes(textNoUrls);

    return {
        meetings: uniqueMeetings,
        phones: phones,
        codes: codes
    };
}
