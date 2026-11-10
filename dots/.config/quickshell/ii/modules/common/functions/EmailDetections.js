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

// Letters as JS sees them, plus Latin-1 accents (\b and \w are ASCII-only).
var WORD_CHAR = "A-Za-z0-9\\u00C0-\\u00FF";

// Labels that name the code itself: matched anywhere near a candidate.
var STRONG_LABEL = new RegExp(
    "(?:^|[^" + WORD_CHAR + "])("
    + "c[óo]digos?|codes?|passcodes?|otp|pin|tokens?|senha|2fa|mfa|"
    + "one[ -]?time|uso [úu]nico|steam guard"
    + ")(?![" + WORD_CHAR + "])", "gi");

// Words that only hint at a code ("verify your login"): a short reach.
var WEAK_LABEL = new RegExp(
    "(?:^|[^" + WORD_CHAR + "])("
    + "verifica(?:tion|r|ção|cao)|verify|confirma(?:tion|r|ção|cao)|confirm|"
    + "autentica(?:tion|ção|cao)|authentication|authenticate|"
    + "sign[ -]?in|log[ -]?in|entrar|acesso|access|"
    + "insira|digite|informe|enter|type|use|utilize|copie|copy"
    + ")(?![" + WORD_CHAR + "])", "gi");

// Candidate shapes, most specific first:
//  - single digits split by spaces (table cells per digit): 4 8 2 9 1 3
//  - digit groups split by a space or dash: 492 018, 384-219
//  - one alphanumeric token, optionally dashed: 482913, F4K9X, XK2-9PL
var CANDIDATE = new RegExp(
    "(^|[^" + WORD_CHAR + "])("
    + "\\d(?:[ \\t]{1,4}\\d){3,7}"
    + "|\\d{2,4}(?:(?:[ \\t]|[-–—])\\d{2,4}){1,2}"
    + "|[A-Za-z0-9]{3,12}(?:[-–—][A-Za-z0-9]{2,8})?"
    + ")(?![" + WORD_CHAR + "]|[-–—.,/:]\\d)", "g");

var COMMON_WORDS = /^(?:CODE|CODES|TOKEN|PIN|OTP|PASSCODE|PASSWORD|SENHA|CODIGO|LOGIN|EMAIL|HTML|HTTP|HTTPS|HELLO|IMPORTANT|NOTICE|URGENT|ALERT|WARNING|ATTENTION|SECURITY|ACCOUNT|VERIFY|CONFIRM|GOOGLE|APPLE|MICROSOFT|STEAM|DISCORD|NETFLIX|AMAZON|UBER|NUBANK|PIX|CPF|CNPJ|CEP|USD|BRL|EUR|OK)$/;

function codeLabels(text, regex) {
    var labels = [];
    var m;
    regex.lastIndex = 0;
    while ((m = regex.exec(text)) !== null) {
        var start = m.index + m[0].length - m[1].length;
        labels.push({ start: start, end: start + m[1].length });
        regex.lastIndex = start + m[1].length;
    }
    return labels;
}

// Characters between the candidate and the nearest label, before or after.
function labelDistance(labels, start, end) {
    var best = -1;
    for (var i = 0; i < labels.length; i++) {
        var d = -1;
        if (labels[i].end <= start)
            d = start - labels[i].end;
        else if (labels[i].start >= end)
            d = labels[i].start - end;
        if (d >= 0 && (best < 0 || d < best))
            best = d;
    }
    return best;
}

function extractCodes(text) {
    var strong = codeLabels(text, STRONG_LABEL);
    var weak = codeLabels(text, WEAK_LABEL);
    var found = [];
    var m;

    if (strong.length === 0 && weak.length === 0)
        return [];

    CANDIDATE.lastIndex = 0;
    while ((m = CANDIDATE.exec(text)) !== null) {
        var raw = m[2];
        var start = m.index + m[1].length;
        var end = start + raw.length;
        var compact = raw.replace(/[ \t]/g, "");
        var digitsOnly = /^[\d\-–—]+$/.test(compact);
        var digits = compact.replace(/\D/g, "");
        var lineStart = text.lastIndexOf("\n", start - 1) + 1;
        var lineEnd = text.indexOf("\n", end);
        // Context filters stay on the candidate's line: "sua conta:" ending
        // the previous paragraph must not veto the code below it.
        var before = text.slice(Math.max(lineStart, start - 24), start);
        var after = text.slice(end, Math.min(lineEnd === -1 ? text.length : lineEnd, end + 24));
        var line = text.slice(lineStart, lineEnd === -1 ? text.length : lineEnd).trim();
        var alone = line === raw.trim();
        var value;

        if (digitsOnly) {
            if (digits.length < 3 || digits.length > 10)
                continue;
            // Pure digit codes are typed digit by digit: copy them without separators.
            value = digits;
        } else {
            if (/[-–—]/.test(compact) && !/\d/.test(compact))
                continue;
            if (!/\d/.test(compact)) {
                // Letter-only codes must look like a code, not a shouted word.
                if (!/^[A-Z]{5,8}$/.test(compact) || COMMON_WORDS.test(compact))
                    continue;
            } else if (!/[A-Z]/.test(compact) || /[a-z]/.test(compact)) {
                // Mixed codes are uppercase (AB12CD); lowercase mixes are ids/hashes.
                continue;
            }
            if (compact.replace(/[-–—]/g, "").length < 4)
                continue;
            value = compact;
        }

        // Money, order/ticket numbers, percentages, units, times and phone numbers.
        if (/(?:R\$|US\$|\$|€|£|#|n[º°o]\.?|nr\.?)\s*$/i.test(before))
            continue;
        if (/(?:pedido|order|protocolo|protocol|ticket|fatura|invoice|nota|cpf|cnpj|cep|zip|tel|telefone|phone|celular|whatsapp|ramal|conta|account|ag[êe]ncia|cart[ãa]o|card|room|sala|ref)\b\.?:?\s*$/i.test(before))
            continue;
        if (/^\s*(?:%|[,.]\d|reais|real|d[óo]lares|usd|brl|eur|kb|mb|gb|km|kg|min\b|minutos|minutes|horas|hours|segundos|seconds|dias|days|h\b|x\b)/i.test(after))
            continue;
        if (/\(\d{2}\)\s*$/.test(before) || /\d[:/]\s*$/.test(before) || /^\s*[:/]\d/.test(after))
            continue;

        var dStrong = labelDistance(strong, start, end);
        var dWeak = labelDistance(weak, start, end);
        var score = -1;
        if (dStrong >= 0 && dStrong <= 160)
            score = 100 - dStrong / 2;
        if (dWeak >= 0 && dWeak <= 60)
            score = Math.max(score, 70 - dWeak);
        if (score < 0)
            continue;

        if (alone)
            score += 25;
        if (digitsOnly && digits.length >= 4 && digits.length <= 8)
            score += 10;
        if (digitsOnly && digits.length === 4 && /^(?:19|20)\d\d$/.test(digits))
            score -= 45; // a year
        if (digitsOnly && digits.length === 3)
            score -= 15; // short codes need a closer label
        if (!/\d/.test(compact))
            score -= 30;
        // "1500 examples", "3 itens": a quantity, unless the next word is the
        // glue of a code sentence ("482913 is your code", "é o seu código").
        var nextWord = /^[ \t]+([a-zà-ÿ]{2,})/.exec(after);
        if (digitsOnly && nextWord && !/^(?:is|are|was|as|to|and|or|for|use|é|e|ou|para|como|seu|sua|o|a|expires|expira|vence|valid|válido|valido)$/.test(nextWord[1]))
            score -= 50;

        if (score < 55)
            continue;

        var existing = -1;
        for (var i = 0; i < found.length; i++) {
            if (found[i].value === value)
                existing = i;
        }
        if (existing === -1)
            found.push({ value: value, score: score, start: start });
        else if (score > found[existing].score)
            found[existing].score = score;
    }

    found.sort(function(a, b) {
        return b.score - a.score || a.start - b.start;
    });

    // An OTP mail carries one code; keep close runners-up (backup codes),
    // drop footer noise that only scraped past the threshold.
    var codes = [];
    for (var j = 0; j < found.length && codes.length < 3; j++) {
        if (found[j].score >= found[0].score - 30)
            codes.push(found[j].value);
    }
    return codes;
}

function detectAll(bodyRaw, subject) {
    if (!bodyRaw && !subject) {
        return {
            meetings: [],
            phones: [],
            codes: []
        };
    }

    bodyRaw = bodyRaw || "";
    var clean = bodyRaw.replace(/<style[\s\S]*?<\/style>/gi, '')
                       .replace(/<script[\s\S]*?<\/script>/gi, '')
                       .replace(/<br\s*\/?>/gi, '\n')
                       .replace(/<\/p>/gi, '\n')
                       .replace(/<\/div>/gi, '\n')
                       .replace(/<\/(?:center|h[1-6]|tr|li|table)>/gi, '\n')
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

    // Codes (OTP): candidates near a code label, best first. The subject often
    // carries the code alone ("482913 is your verification code").
    var codes = extractCodes((subject ? subject + "\n" : "") + textNoUrls);

    return {
        meetings: uniqueMeetings,
        phones: phones,
        codes: codes
    };
}
